##############################################################################
# Outputs — OpenClaw POC
##############################################################################

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.openclaw.id
}

output "public_ip" {
  description = "Public IP of the OpenClaw instance"
  value       = aws_instance.openclaw.public_ip
}

output "public_dns" {
  description = "Public DNS of the OpenClaw instance"
  value       = aws_instance.openclaw.public_dns
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i openclaw-key.pem ubuntu@${aws_instance.openclaw.public_ip}"
}

output "openclaw_dashboard_url" {
  description = "OpenClaw dashboard URL (after bootstrap completes)"
  value       = "http://${aws_instance.openclaw.public_ip}:18789"
}

output "ssh_tunnel_command" {
  description = "SSH tunnel for secure dashboard access (recommended over direct exposure)"
  value       = "ssh -i openclaw-key.pem -L 18789:127.0.0.1:18789 ubuntu@${aws_instance.openclaw.public_ip}"
}

output "ssm_session_command" {
  description = "SSM Session Manager command (if SSM enabled)"
  value       = var.enable_ssm ? "aws ssm start-session --target ${aws_instance.openclaw.id} --region ${var.aws_region}" : "SSM not enabled"
}

output "iam_role_arn" {
  description = "IAM role ARN attached to the instance"
  value       = aws_iam_role.openclaw_ec2.arn
}

output "private_key_path" {
  description = "Path to the generated SSH private key"
  value       = local_file.private_key.filename
}

output "ami_id" {
  description = "AMI ID used for the instance"
  value       = data.aws_ami.ubuntu.id
}

output "bedrock_region" {
  description = "AWS region for Bedrock API calls"
  value       = var.aws_region
}
