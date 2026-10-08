output "instance_id" {
  value       = aws_instance.certificate_export_ec2.id
  description = "ID of the instance. The terminator Lambda is given it as input, waits for the export to land in S3, and only then terminates it"
}
output "security_group_id" {
  value       = aws_security_group.certificate_export_ec2_security_group.id
  description = "ID of the outbound-only security group created for the instance"
}
output "iam_role_arn" {
  value       = aws_iam_role.certificate_export_ec2_iam_role.arn
  description = "ARN of the instance role. Narrower than the _monolithic template's administrator role - see the policy comment in main.tf"
}
output "iam_role_name" {
  value       = aws_iam_role.certificate_export_ec2_iam_role.name
  description = "Generated name of that role"
}
output "exported_object_keys" {
  value       = local.exported_object_keys
  description = "The four object keys the bootstrap uploads, keyed by what each file is. Published because the caller waits for all four and downloads two of them, and a second list written out by hand is a list that can disagree with the script that produces the files (rules.md B-5)"
}
# Whether the instance was actually shut down is not visible in Terraform: it is terminated by a
# Lambda, so the state Terraform recorded is the running instance it created (rules.md B-5).
output "instance_state_command" {
  value       = "aws ec2 describe-instances --instance-ids ${aws_instance.certificate_export_ec2.id} --query 'Reservations[].Instances[].{State:State.Name,Launched:LaunchTime}'"
  description = "Whether the instance is gone. terminated is the expected answer after a successful apply; running means the terminator Lambda did not do its job, and the instance is still holding the private key it exported"
}
output "cloud_init_log_command" {
  value       = "aws ssm start-session --target ${aws_instance.certificate_export_ec2.id} --document-name AWS-StartInteractiveCommand --parameters command='sudo tail -n 200 /var/log/cloud-init-output.log'"
  description = "The bootstrap's own log, for the case where the apply fails at the terminator Lambda's wait. The Lambda does not terminate an instance whose export never arrived, so after that failure the instance is still running and this works until a later apply terminates it"
}
