##############################################################################
# OpenClaw POC — EC2 IaaS Deployment
# Author: Noel | Principal Cloud Architect
# Purpose: Standalone POC for OpenClaw AI Agent on AWS EC2
##############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "openclaw-poc"
      Environment = "dev"
      ManagedBy   = "terraform"
      Owner       = var.owner_tag
    }
  }
}

# ---------------------------------------------------------------------------
# Data Sources
# ---------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"
}

# Ubuntu 24.04 LTS — latest HVM-SSD AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Current caller identity (for tagging / reference)
data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# Networking — Dedicated VPC for POC isolation
# ---------------------------------------------------------------------------

resource "aws_vpc" "openclaw" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-vpc" }
}

resource "aws_internet_gateway" "openclaw" {
  vpc_id = aws_vpc.openclaw.id
  tags   = { Name = "${var.project_name}-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.openclaw.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = { Name = "${var.project_name}-public-subnet" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.openclaw.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.openclaw.id
  }

  tags = { Name = "${var.project_name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Security Group — Locked down to your IP
# ---------------------------------------------------------------------------

resource "aws_security_group" "openclaw" {
  name_prefix = "${var.project_name}-sg-"
  description = "OpenClaw POC — SSH + Dashboard access restricted to operator IP"
  vpc_id      = aws_vpc.openclaw.id

  # SSH
  ingress {
    description = "SSH from operator"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  # OpenClaw Gateway / Dashboard (default 18789)
  ingress {
    description = "OpenClaw Gateway from operator"
    from_port   = 18789
    to_port     = 18789
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  # HTTPS outbound (for Bedrock API, npm, apt, etc.)
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-sg" }

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# IAM — Instance Profile with Bedrock access
# ---------------------------------------------------------------------------

resource "aws_iam_role" "openclaw_ec2" {
  name_prefix = "${var.project_name}-ec2-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "bedrock_access" {
  name_prefix = "bedrock-invoke-"
  role        = aws_iam_role.openclaw_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BedrockInvoke"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock:ListFoundationModels",
          "bedrock:GetFoundationModel"
        ]
        Resource = "*"
      },
      {
        Sid    = "BedrockMarketplace"
        Effect = "Allow"
        Action = [
          "aws-marketplace:Subscribe",
          "aws-marketplace:ViewSubscriptions"
        ]
        Resource = "*"
      }
    ]
  })
}

# Optional: SSM access for Session Manager (no SSH key needed)
resource "aws_iam_role_policy_attachment" "ssm_managed" {
  count      = var.enable_ssm ? 1 : 0
  role       = aws_iam_role.openclaw_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "openclaw" {
  name_prefix = "${var.project_name}-profile-"
  role        = aws_iam_role.openclaw_ec2.name
}

# ---------------------------------------------------------------------------
# SSH Key Pair (generated locally — private key in tfstate, rotate for prod)
# ---------------------------------------------------------------------------

resource "tls_private_key" "openclaw" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "openclaw" {
  key_name_prefix = "${var.project_name}-key-"
  public_key      = tls_private_key.openclaw.public_key_openssh
}

# Write private key to local file for SSH access
resource "local_file" "private_key" {
  content         = tls_private_key.openclaw.private_key_openssh
  filename        = "${path.module}/openclaw-key.pem"
  file_permission = "0600"
}

# ---------------------------------------------------------------------------
# EC2 Instance
# ---------------------------------------------------------------------------

resource "aws_instance" "openclaw" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.openclaw.id]
  iam_instance_profile   = aws_iam_instance_profile.openclaw.name
  key_name               = aws_key_pair.openclaw.key_name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    iops                  = 3000
    throughput            = 125
    encrypted             = true
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/scripts/bootstrap.sh", {
    openclaw_model    = var.openclaw_model
    aws_region        = var.aws_region
    gateway_token     = var.gateway_token
    node_major        = var.node_major_version
  })

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"   # IMDSv2 enforced
    http_put_response_hop_limit = 1
  }

  tags = {
    Name = "${var.project_name}-instance"
  }

  lifecycle {
    ignore_changes = [ami] # Don't recreate on AMI refresh
  }
}
