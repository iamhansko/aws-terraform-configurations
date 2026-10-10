output "instance_id" {
  value       = aws_instance.windows_ec2.id
  description = "ID of the instance, which the root's association targets and every SSM command below names"
}
output "public_ip" {
  value       = aws_instance.windows_ec2.public_ip
  description = "Public address of the instance, which is what the RDP client connects to"
}
output "security_group_id" {
  value       = aws_security_group.windows_ec2.id
  description = "ID of the instance's security group"
}
output "iam_role_arn" {
  value       = aws_iam_role.windows_ec2.arn
  description = "ARN of the instance role"
}
# Inputs handed back so the caller does not keep a second copy (rules.md B-5).
output "rdp_endpoint" {
  value       = "${aws_instance.windows_ec2.public_ip}:${var.rdp_port}"
  description = "Address and port for the RDP client"
}
output "workshop_username" {
  value       = var.workshop_username
  description = "Windows local account the RDP login uses"
}
output "marker_file" {
  value       = local.marker_file
  description = "File the setup creates as its very last action. The root's association waits for exactly this path, taken from here rather than rebuilt from workshop_dir (rules.md B-5)"
}
output "failure_marker_file" {
  value       = local.failure_marker_file
  description = "File the setup's catch block writes its error into"
}
output "setup_log_file" {
  value       = local.setup_log_file
  description = "Log the setup appends to as it goes"
}
output "user_data_byte_length" {
  value       = length(local.user_data)
  description = "Size of the rendered setup script against EC2's 16384 byte limit"
}
# Commands rather than values, because none of this is knowable to Terraform:
# apply returns when RunInstances does, and the setup runs for many minutes
# after that. All go through SSM, so a command that cannot find the instance is
# itself a finding - SSM Agent registers only once the instance has egress.
output "setup_log_command" {
  value       = "cid=$(aws ssm send-command --instance-ids ${aws_instance.windows_ec2.id} --document-name AWS-RunPowerShellScript --parameters 'commands=[\"Get-Content ${local.setup_log_file} -Tail 40\"]' --query Command.CommandId --output text) && sleep 8 && aws ssm get-command-invocation --command-id $cid --instance-id ${aws_instance.windows_ec2.id} --query StandardOutputContent --output text"
  description = "The last 40 lines of the setup log. The first thing to read when anything downstream is missing: every step runs inside one try block with ErrorActionPreference Continue, so a failure appears as an error line or as the log stopping, not as anything Terraform reported"
}
output "rdp_status_command" {
  value       = "cid=$(aws ssm send-command --instance-ids ${aws_instance.windows_ec2.id} --document-name AWS-RunPowerShellScript --parameters 'commands=[\"(Get-Service TermService).Status; (Get-LocalUser ${var.workshop_username}).Enabled; (Test-NetConnection -ComputerName localhost -Port ${var.rdp_port}).TcpTestSucceeded; Test-Path ${local.marker_file}; Get-Content ${local.setup_log_file} -Tail 5\"]' --query Command.CommandId --output text) && sleep 8 && aws ssm get-command-invocation --command-id $cid --instance-id ${aws_instance.windows_ec2.id} --query StandardOutputContent --output text"
  description = "Terminal Services state, whether the workshop account exists, whether the RDP port is listening, whether the setup has finished (its marker), and the last five log lines. Running, True, True, True is ready. An error on the second line with RDP up means the setup failed before New-LocalUser - port 3389 answers from first boot whatever the setup did"
}
