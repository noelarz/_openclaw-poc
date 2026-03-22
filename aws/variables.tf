##############################################################################
# Variables — OpenClaw POC
##############################################################################

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used as prefix for all resources"
  type        = string
  default     = "openclaw-poc"
}

variable "owner_tag" {
  description = "Owner tag for resource identification"
  type        = string
  default     = "NaaS"
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the POC VPC"
  type        = string
  default     = "10.100.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR for the public subnet"
  type        = string
  default     = "10.100.1.0/24"
}

variable "allowed_cidrs" {
  description = "CIDR blocks allowed to reach SSH and OpenClaw dashboard (your IP)"
  type        = list(string)

  validation {
    condition     = length(var.allowed_cidrs) > 0
    error_message = "You must provide at least one allowed CIDR. Use your public IP/32."
  }
}

# ---------------------------------------------------------------------------
# Compute
# ---------------------------------------------------------------------------

variable "instance_type" {
  description = "EC2 instance type (4 GB RAM minimum recommended)"
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 30
}

variable "enable_ssm" {
  description = "Attach SSM managed policy for Session Manager access (no SSH key needed)"
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# OpenClaw Configuration
# ---------------------------------------------------------------------------

variable "openclaw_model" {
  description = "Default LLM model for OpenClaw agent (Bedrock model path)"
  type        = string
  default     = "anthropic/claude-sonnet-4-6"
}

variable "gateway_token" {
  description = "Auth token for the OpenClaw gateway (generate a strong random string)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.gateway_token) >= 24
    error_message = "Gateway token must be at least 24 characters for security."
  }
}

variable "node_major_version" {
  description = "Node.js major version to install"
  type        = number
  default     = 22
}
