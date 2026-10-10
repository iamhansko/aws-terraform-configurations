output "instance_id" {
  value       = aws_instance.vscode_ec2.id
  description = "ID of the workbench instance, which is what every SSM association in the root targets"
}
output "public_ip" {
  value       = aws_instance.vscode_ec2.public_ip
  description = "Public IP address of the workbench instance"
}
output "vscode_url" {
  value       = "http://${aws_instance.vscode_ec2.public_ip}:${var.code_server_port}"
  description = "URL of the code-server web UI"
}
output "security_group_id" {
  value       = aws_security_group.vscode_ec2_security_group.id
  description = "ID of the workbench instance's security group, for other modules to admit as an ingress source"
}
output "iam_role_arn" {
  value       = aws_iam_role.vscode_ec2_iam_role.arn
  description = "ARN of the workbench instance's IAM role"
}
output "marker_file_path" {
  value       = var.marker_file_path
  description = "Directory the bootstrap marker is written to, or null when marker_file_path was not set. Handed back so the root's until loops and this module cannot disagree about the path (rules.md B-5)"
}
