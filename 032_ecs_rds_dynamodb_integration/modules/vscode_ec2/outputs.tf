output "instance_id" {
  value       = aws_instance.vscode_ec2.id
  description = "ID of the instance, which is what every SSM association in the root targets"
}
output "public_ip" {
  value       = aws_instance.vscode_ec2.public_ip
  description = "Public IPv4 address of the instance"
}
output "private_ip" {
  value       = aws_instance.vscode_ec2.private_ip
  description = "Private IPv4 address of the instance"
}
output "vscode_url" {
  value       = "http://${aws_instance.vscode_ec2.public_ip}:${var.code_server_port}"
  description = "URL of the code-server web UI. Plain http and no authentication - see the allow_inbound_from_anywhere variable"
}
output "code_server_port" {
  value       = var.code_server_port
  description = "Port code-server listens on, handed back out so a caller builds the URL from one value (rules.md B-5)"
}
output "iam_role_arn" {
  value       = aws_iam_role.vscode_ec2_iam_role.arn
  description = "ARN of the instance role"
}
output "iam_role_name" {
  value       = aws_iam_role.vscode_ec2_iam_role.name
  description = "Name of the instance role, for attaching further policies from the root"
}
output "security_group_id" {
  value       = aws_security_group.vscode_ec2_security_group.id
  description = "ID of the instance's security group. The database and the task security groups both name this as an ingress source, so the workbench can reach MySQL and curl the services"
}
output "marker_file_path" {
  value       = var.marker_file_path
  description = "Directory the completion marker is created in, or null. Handed back out so the associations in the root reference the same value that was passed in rather than keeping their own copy (rules.md B-5)"
}
output "cloud_init_log_command" {
  value       = "aws ssm start-session --target ${aws_instance.vscode_ec2.id} --document-name AWS-StartInteractiveCommand --parameters command='sudo tail -n 200 /var/log/cloud-init-output.log'"
  description = "The bootstrap's own output. First place to look when code-server does not answer or when an association is still waiting on the userdata marker"
}
