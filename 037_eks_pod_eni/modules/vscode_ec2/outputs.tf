output "public_ip" {
  value       = aws_instance.vscode_ec2.public_ip
  description = "Public IP address of the VS Code EC2 instance"
}

output "vscode_url" {
  value       = "http://${aws_instance.vscode_ec2.public_ip}:8000"
  description = "URL to access the code-server web UI"
}

output "iam_role_arn" {
  value       = aws_iam_role.vscode_ec2_iam_role.arn
  description = "ARN of the VS Code EC2 instance's IAM role, for granting EKS access entries at the root module"
}

output "security_group_id" {
  value       = aws_security_group.vscode_ec2_security_group.id
  description = "ID of the VS Code EC2 instance's security group"
}
