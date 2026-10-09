output "instance_id" {
  value       = aws_instance.vscode_ec2.id
  description = "ID of the instance, which is what the root's SSM association targets"
}
output "public_ip" {
  value       = var.associate_elastic_ip ? aws_eip.vscode_ec2[0].public_ip : aws_instance.vscode_ec2.public_ip
  description = "Address the browser connects to. The Elastic IP when one was allocated, so it survives a stop/start - the instance's own public_ip attribute does not"
}
output "private_ip" {
  value       = aws_instance.vscode_ec2.private_ip
  description = "Private address of the instance"
}
output "vscode_url" {
  value       = "http://${var.associate_elastic_ip ? aws_eip.vscode_ec2[0].public_ip : aws_instance.vscode_ec2.public_ip}:${var.code_server_port}"
  description = "The IDE. http rather than https because code-server is configured with cert: false, and no password because it is configured with auth: none - the address and ingress_cidr_blocks are the only things protecting it"
}
output "security_group_id" {
  value       = aws_security_group.vscode_ec2_security_group.id
  description = "ID of this instance's security group, for granting it anything further from the root"
}
output "iam_role_arn" {
  value       = aws_iam_role.vscode_ec2_iam_role.arn
  description = "ARN of the instance role, for granting it anything further from the root (rules.md C-1)"
}
output "iam_role_name" {
  value       = aws_iam_role.vscode_ec2_iam_role.name
  description = "Name of the instance role, for attaching further policies from the root without this module changing"
}
output "marker_file_path" {
  value       = var.marker_file_path
  description = "Directory the bootstrap writes its completion marker into, or null if no marker was requested. Handed straight back out so the root's association waits on a path defined in exactly one place (rules.md B-5)"
}
output "session_command" {
  value       = "aws ssm start-session --target ${aws_instance.vscode_ec2.id}"
  description = "A way onto this host that needs no key and no inbound rule. Useful precisely when the IDE did not come up, which is the case where the published URL is no help"
}
output "cloud_init_log_command" {
  value       = "sudo tail -n 200 /var/log/cloud-init-output.log"
  description = "Every line of the bootstrap, with set -x. First place to look when the IDE does not answer: connection timeouts against dnf and wget in here mean the security group lost its egress rule, which is the defect described in main.tf"
}
output "readme_path" {
  value       = "/home/ec2-user/README.md"
  description = "Where the root's SSM association writes the project's outputs. code-server opens /home/ec2-user, so this is the first file in the explorer - and if it is missing, the association is still waiting on the bootstrap marker or never ran at all (rules.md H-2)"
}
