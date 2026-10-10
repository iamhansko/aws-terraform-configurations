output "instance_id" {
  value       = aws_instance.vscode_ec2.id
  description = "Instance ID, which the SSM associations in the root target"
}
output "public_ip" {
  value       = aws_instance.vscode_ec2.public_ip
  description = "Public address assigned at launch, as the _monolithic template used it. It changes if the instance is stopped and started"
}
output "vscode_url" {
  value       = "http://${aws_instance.vscode_ec2.public_ip}:${var.code_server_port}"
  description = "URL of the code-server web UI. code-server runs with authentication disabled, so this URL is the credential"
}
output "ssh_command" {
  value       = "ssh -i key.pem -p ${var.ssh_port} ec2-user@${aws_instance.vscode_ec2.public_ip}"
  description = "SSH command for the instance, assuming the private key has been fetched to key.pem. Works only once ssh_ingress_cidr_blocks admits the caller"
}
output "session_command" {
  value       = "aws ssm start-session --target ${aws_instance.vscode_ec2.id}"
  description = "A shell on the instance through Session Manager, which needs no inbound rule and no key"
}
output "security_group_id" {
  value       = aws_security_group.vscode_ec2_security_group.id
  description = "ID of the instance's security group, for another module to name as an ingress source (rules.md B-6)"
}
output "iam_role_arn" {
  value       = aws_iam_role.vscode_ec2_iam_role.arn
  description = "ARN of the instance role"
}
output "marker_file_path" {
  value       = var.marker_file_path
  description = "Directory holding the bootstrap completion marker, or null when none was requested. Handed back out so the root's association chain reads one value rather than restating the path (rules.md B-5)"
}
