##############################################################################
# Variables — NemoClaw POC
##############################################################################

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used as prefix for all resources"
  type        = string
  default     = "nemoclaw-poc"
}

variable "owner_tag" {
  description = "Owner tag for resource identification"
  type        = string
  default     = "noel"
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the NemoClaw VPC (separate from OpenClaw VPC)"
  type        = string
  default     = "10.200.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR for the public subnet"
  type        = string
  default     = "10.200.1.0/24"
}

variable "allowed_cidrs" {
  description = "CIDR blocks allowed to reach SSH and NemoClaw dashboard (your IP)"
  type        = list(string)

  validation {
    condition     = length(var.allowed_cidrs) > 0
    error_message = "You must provide at least one allowed CIDR. Use your public IP/32."
  }
}

variable "flow_log_retention_days" {
  description = "Days to retain VPC flow logs in CloudWatch (compliance/audit)"
  type        = number
  default     = 90
}

# ---------------------------------------------------------------------------
# Compute
# ---------------------------------------------------------------------------

variable "instance_type" {
  description = "EC2 instance type (8 GB RAM minimum required for NemoClaw)"
  type        = string
  default     = "t3.large"

  validation {
    condition     = can(regex("^(t3\\.large|t3\\.xlarge|t3\\.2xlarge|m5\\.large|m5\\.xlarge|m6i\\.large|m6i\\.xlarge|c5\\.xlarge|c6i\\.xlarge)", var.instance_type))
    error_message = "NemoClaw requires at least 8 GB RAM. Use t3.large or larger."
  }
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GB (NemoClaw sandbox image is ~2.4 GB + Docker layers)"
  type        = number
  default     = 40
}

variable "enable_ssm" {
  description = "Attach SSM managed policy for Session Manager access"
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# NemoClaw Configuration
# ---------------------------------------------------------------------------

variable "nvidia_api_key" {
  description = "NVIDIA API key for NemoClaw inference (get from build.nvidia.com)"
  type        = string
  sensitive   = true

  validation {
    condition     = startswith(var.nvidia_api_key, "nvapi-")
    error_message = "NVIDIA API key must start with 'nvapi-'. Get one at build.nvidia.com."
  }
}

variable "sandbox_name" {
  description = "Name for the NemoClaw sandbox instance"
  type        = string
  default     = "healthcare-agent"
}

variable "network_policy_preset" {
  description = "Comma-separated list of NemoClaw network policy presets to enable (empty = deny all)"
  type        = string
  default     = ""
}

variable "node_major_version" {
  description = "Node.js major version to install (22+ required)"
  type        = number
  default     = 22
}
