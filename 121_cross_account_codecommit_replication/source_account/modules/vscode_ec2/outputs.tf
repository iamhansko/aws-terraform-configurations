output "instance_id" {
  value       = aws_instance.workbench.id
  description = "ID of the code-server workbench instance."
}

output "public_ip" {
  value       = aws_instance.workbench.public_ip
  description = "Public IPv4 address of the workbench."
}

output "vscode_url" {
  value       = "http://${aws_instance.workbench.public_ip}:${var.code_server_port}"
  description = "Public code-server URL, reachable from my_ip_cidr by default, from every IPv4 source when allow_inbound_from_anywhere is true, and from any additional managed prefix lists."
}

output "iam_role_arn" {
  value       = aws_iam_role.workbench.arn
  description = "ARN of the generated workbench role."
}

output "iam_role_name" {
  value       = aws_iam_role.workbench.name
  description = "Name of the generated workbench role."
}

output "security_group_id" {
  value       = aws_security_group.workbench.id
  description = "ID of the workbench security group."
}

output "marker_file_path" {
  value       = var.marker_file_path
  description = "Completion-marker directory re-exposed to the root (rules.md B-5)."
}
