output "instance_id" {
  value       = aws_instance.site_seeder_ec2.id
  description = "ID of the instance. The root passes this into the terminator Lambda's payload and scopes its ec2:TerminateInstances permission to this one instance, so it is the value that connects the two (rules.md B-5)"
}
output "instance_arn" {
  value       = aws_instance.site_seeder_ec2.arn
  description = "ARN of the instance, which is what an IAM statement naming it has to use - ec2:TerminateInstances takes a resource ARN, not an instance id"
}
output "public_ip" {
  value       = aws_instance.site_seeder_ec2.public_ip
  description = "Public address of the instance. Nothing listens on it: the group has no ingress rules and there is no key pair. Exposed because an empty value here means the instance has no route out, which is the first thing to check when the bucket stays empty"
}
output "security_group_id" {
  value       = aws_security_group.site_seeder_ec2.id
  description = "ID of the group this module created, for a caller referencing it as a source elsewhere"
}
output "iam_role_arn" {
  value       = aws_iam_role.site_seeder_ec2.arn
  description = "ARN of the instance's role"
}
output "iam_role_name" {
  value       = aws_iam_role.site_seeder_ec2.name
  description = "Generated name of the role, for a caller attaching anything further to it"
}
output "bucket_name" {
  value       = var.bucket_name
  description = "The bucket this instance was told to fill, re-exposed so a command checking the result reads the same value the script was given rather than restating it (rules.md B-5)"
}
output "completion_marker" {
  value       = var.completion_marker
  description = "The line the userdata echoes on success, re-exposed so the root's console-log check greps for exactly the string the script prints (rules.md B-5)"
}
output "failure_marker" {
  value       = var.failure_marker
  description = "The line the userdata echoes on failure, re-exposed for the same reason (rules.md B-5)"
}
output "console_output_command" {
  value       = "aws ec2 get-console-output --instance-id ${aws_instance.site_seeder_ec2.id} --output text --query Output | grep -E '${var.completion_marker}|${var.failure_marker}|Traceback'"
  description = "Whether the seed ran, and whether it finished. This is the project's main diagnostic: the upload happens minutes after apply returns, so a 404 from the website endpoint is either a seed that has not finished yet or one that failed, and only the console log tells them apart. Nothing at all here means the script never started - look at the dnf and pip lines instead"
}
output "session_command" {
  value       = "aws ssm start-session --target ${aws_instance.site_seeder_ec2.id}"
  description = "A shell on the instance, if it is still running. The only way in: there is no key pair and no inbound rule, which is why AmazonSSMManagedInstanceCore is on the role. Fails with TargetNotConnected once the terminator Lambda has run"
}
output "user_data" {
  value       = local.user_data
  description = "The rendered boot script. Worth being able to read without launching anything, because the whole upload is in here and the generated Python is nested inside a shell heredoc - a stray CRLF in the .tf files breaks the heredoc terminator and nothing in the script runs at all (rules.md A-4)"
}
