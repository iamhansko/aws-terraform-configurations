output "instance_id" {
  value       = aws_instance.vscode_ec2.id
  description = "Instance ID, which every SSM association in the root targets"
}
output "security_group_id" {
  value       = aws_security_group.vscode_ec2_security_group.id
  description = "The instance security group. Named as an allowed source on the ECS service and Aurora groups, which is how the _monolithic template let a person on this box reach both directly (rules.md B-6)"
}
output "iam_role_arn" {
  value       = aws_iam_role.vscode_ec2_iam_role.arn
  description = "ARN of the instance role"
}
output "iam_role_name" {
  value       = aws_iam_role.vscode_ec2_iam_role.name
  description = "Generated name of the instance role"
}
output "public_ip" {
  value       = aws_eip.vscode_ec2_elastic_ip.public_ip
  description = "Elastic IP associated with the instance. Taken from the Elastic IP rather than the instance's public_ip attribute, which is the launch-time address and changes on a stop and start"
}
output "vscode_url" {
  value       = "http://${aws_eip.vscode_ec2_elastic_ip.public_ip}:${var.code_server_port}"
  description = "URL of the code-server web UI. code-server runs with authentication disabled, so this URL is the credential"
}
output "ssh_command" {
  value       = "ssh -i key.pem -p ${var.ssh_port} ec2-user@${aws_eip.vscode_ec2_elastic_ip.public_ip}"
  description = "SSH command, with the port the bootstrap moved sshd to. Port 22 is closed in the security group, so the default port does not connect"
}
output "code_server_port" {
  value       = var.code_server_port
  description = "Port code-server listens on, re-exposed so a caller building a port-forward command does not restate it (rules.md B-5)"
}
output "marker_file_path" {
  value       = var.marker_file_path
  description = "Directory holding the bootstrap completion marker, or null when none was requested. Re-exposed from the input so the root's association chain reads one value (rules.md B-5)"
}
