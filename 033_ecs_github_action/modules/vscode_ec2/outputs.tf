output "instance_id" {
  value       = aws_instance.vscode_ec2.id
  description = "ID of the workbench instance, which is what every SSM association in the root targets"
}
output "public_ip" {
  value       = local.public_ip
  description = "Address the workbench answers on - the elastic IP when create_elastic_ip is true"
}
output "private_ip" {
  value       = aws_instance.vscode_ec2.private_ip
  description = "Private IP address of the workbench instance"
}
output "vscode_url" {
  value       = "http://${local.public_ip}:${var.code_server_port}"
  description = "URL of the code-server web UI"
}
output "ssh_command" {
  value       = "ssh -i key.pem -p ${var.ssh_port} ec2-user@${local.public_ip}"
  description = "SSH command with the relocated port, assembled from the same ssh_port the sshd drop-in was written with - the _monolithic template's comment said -p 10100 while its security group opened 2222 (rules.md B-5)"
}
output "code_server_port" {
  value       = var.code_server_port
  description = "Port code-server listens on, re-exposed so a caller putting a load balancer in front of it references one source of truth (rules.md B-5)"
}
output "iam_role_arn" {
  value       = aws_iam_role.vscode_ec2_iam_role.arn
  description = "ARN of the workbench instance's IAM role"
}
output "iam_role_name" {
  value       = aws_iam_role.vscode_ec2_iam_role.name
  description = "Name of the workbench instance's IAM role, for attaching extra policies from the root module"
}
output "security_group_id" {
  value       = aws_security_group.vscode_ec2_security_group.id
  description = "ID of the workbench instance's security group, for other modules to reference as an ingress source"
}
output "marker_file_path" {
  value       = var.marker_file_path
  description = "Directory the bootstrap marker is written to, or null when marker_file_path was not set. Handed back so the root's until loops and this module cannot disagree about the path (rules.md B-5)"
}
