# Every value here is a projection of local.outputs in main.tf, which the README written onto the workbench
# renders from the same map - so no value expression exists twice, and an output cannot be added without also
# appearing in that README (rules.md B-5/H-2).
#
# description is the one thing that cannot be projected: Terraform rejects an expression in an output's
# description ("Variables not allowed"), so the wording is a literal on both sides.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "The workbench. The commands below run from its terminal, with its instance role"
}
output "presigned_url" {
  value       = local.outputs.presigned_url.value
  description = "A GET for the template, signed by the Lambda function's role. It works from anywhere without credentials, for at most presigned_url_expires_in seconds - and less if the role session that signed it expires first, which is when S3 answers Request has expired"
}
output "fetch_presigned_url_command" {
  value       = local.outputs.fetch_presigned_url_command.value
  description = "No credentials involved. 200 while the URL is valid, 403 with Request has expired once it is not"
}
output "create_stack_command" {
  value       = local.outputs.create_stack_command.value
  description = "CloudFormation fetches the template through the URL, so this works from any account. Run it after the URL has expired to see the error in the screenshots"
}
output "workbench_presign_command" {
  value       = local.outputs.workbench_presign_command.value
  description = "The same operation as the Lambda function, signed with this instance's role session instead. Those credentials rotate every few hours, so the same rule applies: the URL lasts as long as the shorter of --expires-in and the session"
}
output "workbench_update_stack_command" {
  value       = local.outputs.workbench_update_stack_command.value
  description = "The _monolithic README's last step. update-stack reports No updates are to be performed when the template is unchanged, which still proves CloudFormation could read it"
}
output "regenerate_command" {
  value       = local.outputs.regenerate_command.value
  description = "Run from where terraform runs, not from the workbench. The invocation runs once at create and its result is kept in state, so an expired URL stays expired until it is replaced"
}
output "template_s3_uri" {
  value       = local.outputs.template_s3_uri.value
  description = "Where the template is stored. The bucket is private; the URL is the only way in from outside the account"
}
output "signer_role_arn" {
  value       = local.outputs.signer_role_arn.value
  description = "S3 checks this role's permissions when the URL is used. It may read this one object and nothing else, so a URL it signs can do nothing else either"
}
output "delete_stack_command" {
  value       = local.outputs.delete_stack_command.value
  description = "The stack is created by hand, so terraform destroy does not know about it. Delete it here or it outlives the project - the VPC it made stays behind"
}
output "private_key_command" {
  value       = local.outputs.private_key_command.value
  description = "Retrieves the generated private key from Parameter Store. No security group opens port 22; this is for the case where the SSM agent is what is broken"
}
