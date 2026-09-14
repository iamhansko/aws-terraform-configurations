output "instance_id" {
  value       = aws_instance.vscode_ec2.id
  description = "ID of the VS Code EC2 instance, for targeting SSM associations at it"
}
output "public_ip" {
  value       = aws_instance.vscode_ec2.public_ip
  description = "Public IP address of the VS Code EC2 instance"
}
output "public_dns" {
  value       = aws_instance.vscode_ec2.public_dns
  description = "Public DNS name of the VS Code EC2 instance, for use as a CloudFront custom origin"
}
output "private_ip" {
  value       = aws_instance.vscode_ec2.private_ip
  description = "Private IP address of the VS Code EC2 instance"
}
output "vscode_url" {
  value       = "http://${aws_instance.vscode_ec2.public_ip}:${var.code_server_port}"
  description = "URL to access the code-server web UI directly over the instance's public IP"
}
output "code_server_port" {
  value       = var.code_server_port
  description = "Port code-server listens on, re-exposed so a CloudFront origin or load balancer in the root module references one source of truth (rules.md #5)"
}
output "iam_role_arn" {
  value       = aws_iam_role.vscode_ec2_iam_role.arn
  description = "ARN of the VS Code EC2 instance's IAM role, for granting EKS access entries at the root module"
}
output "iam_role_name" {
  value       = aws_iam_role.vscode_ec2_iam_role.name
  description = "Name of the VS Code EC2 instance's IAM role, for attaching extra policies from the root module"
}
output "security_group_id" {
  value       = aws_security_group.vscode_ec2_security_group.id
  description = "ID of the VS Code EC2 instance's security group, for other modules to reference as an ingress source"
}
output "marker_file_path" {
  value       = var.marker_file_path
  description = "Directory where the userdata completion marker file is created, or null if marker_file_path was not set (rules.md #5)"
}
