output "instance_id" {
  value       = aws_instance.windows_ec2.id
  description = "ID of the instance, which ec2 get-password-data and every SSM command below name"
}
output "public_ip" {
  value       = aws_instance.windows_ec2.public_ip
  description = "Public address of the instance, which is what an RDP client connects to"
}
output "private_ip" {
  value       = aws_instance.windows_ec2.private_ip
  description = "Private address of the instance"
}
output "security_group_id" {
  value       = aws_security_group.windows_ec2_security_group.id
  description = "ID of the security group, so a caller can reference it as a source in another group"
}
output "iam_role_arn" {
  value       = aws_iam_role.windows_ec2_iam_role.arn
  description = "ARN of the instance role, for a caller that needs to grant this instance access to something it owns"
}
output "iam_role_name" {
  value       = aws_iam_role.windows_ec2_iam_role.name
  description = "Name of the instance role"
}
# Inputs handed back out, so the caller does not keep a second copy of them to
# build its own outputs from (rules.md B-5). The endpoint in particular is the
# port this module opened and the address it was given - assembling it in the
# root would mean the root restating the port.
output "rdp_endpoint" {
  value       = "${aws_instance.windows_ec2.public_ip}:${var.rdp_port}"
  description = "Address and port for the RDP client, reproducing the _monolithic template's 01RdpUrl output"
}
output "rdp_port" {
  value       = var.rdp_port
  description = "Port the security group opens for RDP"
}
output "workshop_username" {
  value       = var.workshop_username
  description = "Windows local account the RDP login uses, reproducing the _monolithic template's 02Username output"
}
output "dynamodb_table_names" {
  value       = var.dynamodb_table_names
  description = "The table names written into the game server's environment, handed back so the DYNAMODB_TABLE_* variables the server will see can be read off terraform output without logging in (rules.md B-5)"
}
# Nothing here carries the workshop password. The _monolithic template's
# 03Password output printed it in the clear; the root exposes the Secrets Manager
# retrieval command instead, and this module never receives the value at all - it
# only gets the secret id to read it by.
output "user_data_byte_length" {
  value       = length(local.user_data)
  description = "Size of the rendered setup script. EC2 rejects anything over 16384, and this reproduction of the _monolithic template's script already takes about 15 KB - so this is the headroom for anything added through additional_user_data. Watch it rather than discovering the limit during an apply"
}
# None of what matters here is knowable to Terraform. apply returns as soon as
# EC2 accepts the launch, and the script above then runs for several minutes -
# installing Chocolatey, Git, the AWS CLI, Node, Python, bun and the Kiro IDE,
# cloning the project, and finally rebooting. The instance is up and RDP answers
# long before any of that is true, so "can I connect" is a bad readiness test.
# The real ones are the setup_check associations in main.tf, which run on their
# own; these two outputs only say where their results are.
output "setup_check_association_ids" {
  value       = { for key, association in aws_ssm_association.setup_check : key => association.association_id }
  description = "ID of each readiness check association, keyed setup_log, rdp_status and app_status. For aws ssm start-associations-once, to run a check again"
}
# Three calls per check, because State Manager does not keep the output on the
# association itself: an execution points at execution targets, and each target
# points at the Run Command invocation that holds the output (the same chain
# rules.md A-4 walks when an association fails). The first execution is the
# newest. Joined with ";" rather than "&&" so a check that has not run yet does
# not hide the ones that have.
#
# Nothing here sends a command to the instance. An error from this before the
# instance registers with SSM - about a quarter of an hour after apply returns -
# means there is no execution yet, not that the setup failed; and a check that
# never runs at all is the egress symptom the security group comment describes,
# because SSM Agent registers only once the instance has outbound internet.
output "setup_check_results_command" {
  value = join(" ; ", [for check in local.setup_checks : join(" && ", [
    "echo '== ${check.key} =='",
    "eid=$(aws ssm describe-association-executions --association-id ${aws_ssm_association.setup_check[check.key].association_id} --query 'AssociationExecutions[0].ExecutionId' --output text)",
    "cid=$(aws ssm describe-association-execution-targets --association-id ${aws_ssm_association.setup_check[check.key].association_id} --execution-id $eid --query 'AssociationExecutionTargets[0].OutputSource.OutputSourceId' --output text)",
    "aws ssm get-command-invocation --command-id $cid --instance-id ${aws_instance.windows_ec2.id} --query '[Status,StandardOutputContent]' --output text",
  ])])
  description = "What each readiness check association printed, in order: setup_log, rdp_status, app_status. For each, the invocation status first - Success, Failed, or InProgress while it is still waiting for the setup to finish - then its output"
}
