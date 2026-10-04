output "instance_id" {
  value       = aws_instance.vscode_ec2.id
  description = "ID of the VS Code EC2 instance, for targeting SSM associations at it"
}
output "public_ip" {
  value       = aws_instance.vscode_ec2.public_ip
  description = "Public IP address of the VS Code EC2 instance"
}
output "private_ip" {
  value       = aws_instance.vscode_ec2.private_ip
  description = "Private IP address of the VS Code EC2 instance"
}
output "vscode_url" {
  value       = "http://${aws_instance.vscode_ec2.public_ip}:${var.code_server_port}"
  description = "URL to access the code-server web UI over the instance's public IP, which is the output the _monolithic template exposed"
}
output "code_server_port" {
  value       = var.code_server_port
  description = "Port code-server listens on, re-exposed so anything fronting the instance references one source of truth (rules.md B-5)"
}
output "iam_role_arn" {
  value       = aws_iam_role.vscode_ec2_iam_role.arn
  description = "ARN of the VS Code EC2 instance's IAM role, for granting EKS access entries at the root module (rules.md C-1)"
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
  description = "Directory where the userdata completion marker file is created, or null if marker_file_path was not set. Re-exposed so the SSM associations that wait on it read the same value the instance was given (rules.md B-5)"
}
