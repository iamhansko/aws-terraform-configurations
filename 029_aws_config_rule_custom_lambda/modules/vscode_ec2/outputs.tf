output "instance_id" {
  value       = aws_instance.vscode_ec2.id
  description = "ID of the instance, for targeting SSM associations and sessions at it"
}
output "public_ip" {
  value       = aws_instance.vscode_ec2.public_ip
  description = "Public IP address, empty when associate_public_ip_address is false"
}
output "private_ip" {
  value       = aws_instance.vscode_ec2.private_ip
  description = "Private IP address"
}
output "vscode_url" {
  value       = "http://${aws_instance.vscode_ec2.public_ip}:${var.code_server_port}"
  description = "code-server over the instance's public IP. Built from the same port variable that configures the listener and opens the security group rule, so the three cannot disagree (rules.md B-5)"
}
output "code_server_port" {
  value       = var.code_server_port
  description = "Port code-server listens on, re-exposed so a caller building a port forwarding command uses the configured value rather than a restated literal (rules.md B-5)"
}
output "instance_name" {
  value       = var.name
  description = "Name tag the instance carries, re-exposed because the Config rule's handler keys its exemption off this exact string (rules.md B-5)"
}
output "iam_role_arn" {
  value       = aws_iam_role.vscode_ec2_iam_role.arn
  description = "ARN of the instance's role"
}
output "iam_role_name" {
  value       = aws_iam_role.vscode_ec2_iam_role.name
  description = "Generated name of that role, for attaching anything extra from the caller and for seeing what the Config rule would have stripped off it had the Name tag exemption not been there"
}
output "instance_profile_name" {
  value       = aws_iam_instance_profile.vscode_ec2_instance_profile.name
  description = "Generated name of the instance profile. The third of the three in this project, and the one the rule skips"
}
output "security_group_id" {
  value       = aws_security_group.vscode_ec2_security_group.id
  description = "ID of the instance's security group, for other modules to name as an ingress source"
}
output "marker_file_path" {
  value       = var.marker_file_path
  description = "Directory the bootstrap drops its completion marker in, or null when no marker was requested. Re-exposed so the caller's association waits on the path it passed in rather than on a second copy of the literal (rules.md B-5)"
}
