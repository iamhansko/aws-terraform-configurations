output "instance_id" {
  value       = aws_instance.vscode_ec2.id
  description = "ID of the instance, which is what the README association targets and what every SSM command in the root's outputs names"
}
output "instance_arn" {
  value       = aws_instance.vscode_ec2.arn
  description = "ARN of the instance"
}
output "private_ip" {
  value       = aws_instance.vscode_ec2.private_ip
  description = "Private address of the instance. The only address it has - and the address that must NOT come back from the public-IP probe, because that would mean traffic is leaving somewhere other than the egress VPC's NAT gateways"
}
# No public_ip and no vscode_url output, which is the one place this module's interface differs from
# the vscode_ec2 modules elsewhere in this repository.
#
# The instance is in a private subnet of a VPC with no internet gateway, so aws_instance.public_ip is
# empty and a URL built from it would read as http://:8000 - an output that looks broken rather than
# one that explains why there is nothing to open. The port and the instance ID are exposed instead,
# and the root composes them into the SSM port-forwarding command that is the actual way in
# (rules.md B-5).
output "code_server_port" {
  value       = var.code_server_port
  description = "Port code-server listens on, re-exposed so the port-forwarding command in the root reads one source of truth rather than restating the number (rules.md B-5)"
}
output "security_group_id" {
  value       = aws_security_group.vscode_ec2.id
  description = "ID of the instance's own security group, for anything that needs to name it as a source"
}
output "iam_role_arn" {
  value       = aws_iam_role.vscode_ec2.arn
  description = "ARN of the instance role"
}
output "iam_role_name" {
  value       = aws_iam_role.vscode_ec2.name
  description = "Name of the instance role, for attaching further policies from the root"
}
output "marker_file_path" {
  value       = var.marker_file_path
  description = "Directory the userdata completion marker is created in, or null when no marker was requested. Re-exposed so the association that waits on it reads the same path the instance was given rather than a second copy of the variable (rules.md B-5)"
}
output "user_data" {
  value       = local.user_data
  description = "The rendered bootstrap script. Worth reading without launching anything: it contains three nested heredocs, so a single CR in these .tf files turns a terminator into EOF-carriage-return, the heredoc swallows the rest of the script and not one line runs - on a host with no inbound access, whose only symptom is the README association timing out (rules.md A-4)"
}
output "session_command" {
  value       = "aws ssm start-session --target ${aws_instance.vscode_ec2.id}"
  description = "A shell on the instance. Session Manager rather than SSH: there is no inbound rule, no public address and no route from outside the VPC, which is also why AmazonSSMManagedInstanceCore is on the instance role"
}
output "port_forward_command" {
  value = "aws ssm start-session --target ${aws_instance.vscode_ec2.id} --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"${var.code_server_port}\"],\"localPortNumber\":[\"${var.code_server_port}\"]}'"
  # The port is deliberately not interpolated into this description. An output's description takes a
  # literal only - Terraform rejects a reference there with "Variables not allowed" and "Unsuitable
  # value: value must be known", at init as well as validate. It is the same limit that forces the
  # root's descriptions to be restated alongside its local.outputs map (rules.md H-2).
  description = "Forwards code-server to localhost on the same port it listens on, which the value of this output names. The only way to reach the IDE - and note it runs with auth: none, so the forwarded port is the credential"
}
output "console_output_command" {
  value       = "aws ec2 get-console-output --instance-id ${aws_instance.vscode_ec2.id} --output text"
  description = "The boot log. The bootstrap runs with set -x, so this is the first place to look when the README association times out: a script that stopped at wget means the egress path is broken, and a script that never started means the user data itself failed to parse"
}
