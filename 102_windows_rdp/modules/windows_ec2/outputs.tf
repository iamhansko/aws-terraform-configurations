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
# Three commands, because none of what matters here is knowable to Terraform.
# apply returns as soon as EC2 accepts the launch, and the script above then runs
# for several minutes - installing Chocolatey, Git, the AWS CLI, Node, Python,
# bun and the Kiro IDE, cloning the project, and finally rebooting. The instance
# is up and RDP answers long before any of that is true, so "can I connect" is a
# bad readiness test and these are the real ones.
#
# All three go through SSM rather than RDP, which also means a failed one tells
# you something: SSM Agent registers only once the instance has outbound
# internet, so a command that cannot find the instance is the egress symptom the
# security group comment describes.
output "setup_log_command" {
  value       = "cid=$(aws ssm send-command --instance-ids ${aws_instance.windows_ec2.id} --document-name AWS-RunPowerShellScript --parameters 'commands=[\"Get-Content ${var.workshop_dir}\\setup.log -Tail 40\"]' --query Command.CommandId --output text) && sleep 8 && aws ssm get-command-invocation --command-id $cid --instance-id ${aws_instance.windows_ec2.id} --query StandardOutputContent --output text"
  description = "The last 40 lines of the setup log the script writes as it goes. This is the first thing to read when RDP rejects the password: every step runs inside a try block, so a failure appears here as the log simply stopping rather than as anything Terraform reported"
}
output "rdp_status_command" {
  value       = "cid=$(aws ssm send-command --instance-ids ${aws_instance.windows_ec2.id} --document-name AWS-RunPowerShellScript --parameters 'commands=[\"(Get-Service TermService).Status; (Get-LocalUser ${var.workshop_username}).Enabled; (Test-NetConnection -ComputerName localhost -Port ${var.rdp_port}).TcpTestSucceeded\"]' --query Command.CommandId --output text) && sleep 8 && aws ssm get-command-invocation --command-id $cid --instance-id ${aws_instance.windows_ec2.id} --query StandardOutputContent --output text"
  description = "Three lines: the Terminal Services state, whether the workshop account exists, and whether 3389 is listening. Running, True, True is ready. Running plus an error on the second line is the case to recognise - RDP is up and the account was never created, which means the script failed before New-LocalUser"
}
output "app_status_command" {
  value       = "cid=$(aws ssm send-command --instance-ids ${aws_instance.windows_ec2.id} --document-name AWS-RunPowerShellScript --parameters 'commands=[\"Test-Path ${var.workshop_dir}\\temp\\server.ps1; Test-Path ${var.workshop_dir}\\${var.git_clone_branch}; (Test-NetConnection -ComputerName localhost -Port ${var.game_server_port}).TcpTestSucceeded; (Test-NetConnection -ComputerName localhost -Port ${var.client_dev_port}).TcpTestSucceeded\"]' --query Command.CommandId --output text) && sleep 8 && aws ssm get-command-invocation --command-id $cid --instance-id ${aws_instance.windows_ec2.id} --query StandardOutputContent --output text"
  description = "Whether the launcher scripts and the clone exist, and whether the game server and client are listening. The last two are False until a person logs in and runs the desktop shortcuts - nothing starts them automatically, so False there is the expected state and not a failure"
}
