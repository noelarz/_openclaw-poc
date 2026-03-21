##############################################################################
# NemoClaw POC — EC2 Enterprise-Grade OpenClaw Deployment
# Author: Noel | Principal Cloud Architect
# Purpose: OpenClaw + NVIDIA NemoClaw (OpenShell sandbox, kernel isolation,
#          network egress policy, inference routing) on AWS EC2
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
      Project     = "nemoclaw-poc"
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

# Ubuntu 24.04 LTS — required by NemoClaw
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

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# Networking — Dedicated VPC (isolated from existing aws/ deployment)
# ---------------------------------------------------------------------------

resource "aws_vpc" "nemoclaw" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-vpc" }
}

resource "aws_internet_gateway" "nemoclaw" {
  vpc_id = aws_vpc.nemoclaw.id
  tags   = { Name = "${var.project_name}-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.nemoclaw.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = { Name = "${var.project_name}-public-subnet" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.nemoclaw.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.nemoclaw.id
  }

  tags = { Name = "${var.project_name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# VPC Flow Logs — Audit trail for network activity (healthcare compliance)
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/vpc/${var.project_name}/flow-logs"
  retention_in_days = var.flow_log_retention_days

  tags = { Name = "${var.project_name}-flow-logs" }
}

resource "aws_iam_role" "flow_logs" {
  name_prefix = "${var.project_name}-flow-logs-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  name_prefix = "flow-logs-publish-"
  role        = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.flow_logs.arn}:*"
      }
    ]
  })
}

resource "aws_flow_log" "nemoclaw" {
  vpc_id               = aws_vpc.nemoclaw.id
  traffic_type         = "ALL"
  log_destination      = aws_cloudwatch_log_group.flow_logs.arn
  log_destination_type = "cloud-watch-logs"
  iam_role_arn         = aws_iam_role.flow_logs.arn

  tags = { Name = "${var.project_name}-flow-log" }
}

# ---------------------------------------------------------------------------
# Security Group — Tighter than base OpenClaw (enterprise posture)
# ---------------------------------------------------------------------------

resource "aws_security_group" "nemoclaw" {
  name_prefix = "${var.project_name}-sg-"
  description = "NemoClaw POC — SSH + Gateway restricted to operator IP"
  vpc_id      = aws_vpc.nemoclaw.id

  # SSH
  ingress {
    description = "SSH from operator"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  # NemoClaw Gateway / Dashboard
  ingress {
    description = "NemoClaw Gateway from operator"
    from_port   = 18789
    to_port     = 18789
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  # HTTPS outbound (NVIDIA API, apt, npm, Docker Hub)
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
# IAM — Instance Profile with Bedrock + CloudWatch access
# ---------------------------------------------------------------------------

resource "aws_iam_role" "nemoclaw_ec2" {
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
  role        = aws_iam_role.nemoclaw_ec2.id

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
      }
    ]
  })
}

resource "aws_iam_role_policy" "cloudwatch_logs" {
  name_prefix = "cw-logs-"
  role        = aws_iam_role.nemoclaw_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchAgentLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/nemoclaw/*"
      }
    ]
  })
}

# SSM Session Manager (recommended over SSH for enterprise)
resource "aws_iam_role_policy_attachment" "ssm_managed" {
  count      = var.enable_ssm ? 1 : 0
  role       = aws_iam_role.nemoclaw_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "nemoclaw" {
  name_prefix = "${var.project_name}-profile-"
  role        = aws_iam_role.nemoclaw_ec2.name
}

# ---------------------------------------------------------------------------
# SSH Key Pair
# ---------------------------------------------------------------------------

resource "tls_private_key" "nemoclaw" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "nemoclaw" {
  key_name_prefix = "${var.project_name}-key-"
  public_key      = tls_private_key.nemoclaw.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.nemoclaw.private_key_openssh
  filename        = "${path.module}/nemoclaw-key.pem"
  file_permission = "0600"
}

# ---------------------------------------------------------------------------
# EC2 Instance — Sized for NemoClaw (8 GB RAM minimum)
# ---------------------------------------------------------------------------

resource "aws_instance" "nemoclaw" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.nemoclaw.id]
  iam_instance_profile   = aws_iam_instance_profile.nemoclaw.name
  key_name               = aws_key_pair.nemoclaw.key_name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    iops                  = 3000
    throughput            = 125
    encrypted             = true
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/scripts/bootstrap-nemoclaw.sh", {
    aws_region     = var.aws_region
    nvidia_api_key = var.nvidia_api_key
    node_major     = var.node_major_version
    sandbox_name   = var.sandbox_name
    network_policy = var.network_policy_preset
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
    ignore_changes = [ami]
  }
}
