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
output "http_port" {
  value       = local.listen_port
  description = "Port the instance answers HTTP on - 80 behind nginx, code_server_port otherwise. A CloudFront custom origin's http_port has to be this (rules.md B-5)"
}
output "path_prefix" {
  value       = var.path_prefix
  description = "URL path code-server is served under, or null. Re-exposed so a distribution's cache behaviours name the same path nginx proxies (rules.md B-5)"
}
output "code_server_port" {
  value       = var.code_server_port
  description = "Port code-server itself listens on, which behind nginx is reachable only from the instance (rules.md B-5)"
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
  description = "Directory where the userdata completion marker file is created, or null if marker_file_path was not set (rules.md B-5)"
}
