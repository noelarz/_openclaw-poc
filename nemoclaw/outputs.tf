##############################################################################
# Outputs — NemoClaw POC
##############################################################################

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.nemoclaw.id
}

output "public_ip" {
  description = "Public IP of the NemoClaw instance"
  value       = aws_instance.nemoclaw.public_ip
}

output "public_dns" {
  description = "Public DNS of the NemoClaw instance"
  value       = aws_instance.nemoclaw.public_dns
}

output "ssh_command" {
  description = "SSH command to connect"
  value       = "ssh -i nemoclaw-key.pem ubuntu@${aws_instance.nemoclaw.public_ip}"
}

output "ssh_tunnel_command" {
  description = "SSH tunnel for secure dashboard access (recommended)"
  value       = "ssh -i nemoclaw-key.pem -L 18789:127.0.0.1:18789 ubuntu@${aws_instance.nemoclaw.public_ip}"
}

output "ssm_session_command" {
  description = "SSM Session Manager command"
  value       = var.enable_ssm ? "aws ssm start-session --target ${aws_instance.nemoclaw.id} --region ${var.aws_region}" : "SSM not enabled"
}

output "nemoclaw_connect_command" {
  description = "Command to connect to the NemoClaw sandbox (run after SSH-ing in)"
  value       = "nemoclaw ${var.sandbox_name} connect"
}

output "nemoclaw_status_command" {
  description = "Command to check NemoClaw sandbox status"
  value       = "nemoclaw ${var.sandbox_name} status"
}

output "nemoclaw_logs_command" {
  description = "Command to tail NemoClaw sandbox logs"
  value       = "nemoclaw ${var.sandbox_name} logs --follow"
}

output "iam_role_arn" {
  description = "IAM role ARN attached to the instance"
  value       = aws_iam_role.nemoclaw_ec2.arn
}

output "vpc_flow_log_group" {
  description = "CloudWatch log group for VPC flow logs (audit trail)"
  value       = aws_cloudwatch_log_group.flow_logs.name
}

output "private_key_path" {
  description = "Path to the generated SSH private key"
  value       = local_file.private_key.filename
}

output "ami_id" {
  description = "AMI ID used for the instance"
  value       = data.aws_ami.ubuntu.id
}
