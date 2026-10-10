output "instance_id" {
  value       = aws_instance.vscode_ec2.id
  description = "ID of the instance, for targeting SSM associations at it"
}
output "public_ip" {
  value       = aws_eip.vscode_ec2_elastic_ip.public_ip
  description = "Elastic IP associated with the instance. Taken from the elastic IP rather than the instance's public_ip attribute, which is the launch-time address and changes on a stop and start"
}
output "private_ip" {
  value       = aws_instance.vscode_ec2.private_ip
  description = "Private IP address of the instance"
}
output "vscode_url" {
  value       = "http://${aws_eip.vscode_ec2_elastic_ip.public_ip}:${var.code_server_port}"
  description = "URL of the code-server web UI. code-server runs with authentication disabled, so while allow_inbound_from_anywhere is true this URL is the credential"
}
output "code_server_port" {
  value       = var.code_server_port
  description = "Port code-server listens on, re-exposed so a caller building a URL or a security group rule reads one source of truth (rules.md B-5)"
}
output "iam_role_arn" {
  value       = aws_iam_role.vscode_ec2_iam_role.arn
  description = "ARN of the instance's IAM role"
}
output "iam_role_name" {
  value       = aws_iam_role.vscode_ec2_iam_role.name
  description = "Name of the instance's IAM role, for attaching extra policies from the root module"
}
output "security_group_id" {
  value       = aws_security_group.vscode_ec2_security_group.id
  description = "ID of the instance's security group, for other modules to reference as an ingress source"
}
output "marker_file_path" {
  value       = var.marker_file_path
  description = "Directory where the userdata completion marker file is created, or null if marker_file_path was not set. Handed back out so the root's associations poll the path they passed in rather than keeping their own copy of it (rules.md B-5)"
}
