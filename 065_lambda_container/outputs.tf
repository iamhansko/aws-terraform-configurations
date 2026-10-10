# Every value here is a projection of local.outputs in main.tf, which the README written onto the workbench
# renders from the same map - so no value expression exists twice, and an output cannot be added without also
# appearing in that README (rules.md B-5/H-2).
#
# description is the one thing that cannot be projected: Terraform rejects an expression in an output's
# description ("Variables not allowed"), so the wording is a literal on both sides. One description in the map
# interpolates the build directory; here it is spelled out.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "The workbench, and the _monolithic template's one output. Every command below is meant for its terminal. code-server runs without authentication, so this URL is the credential"
}
output "invoke_command" {
  value       = local.outputs.invoke_command.value
  description = "Runs it once and prints what it returned. statusCode 200 means the page was fetched and written; 500 carries the exception text in its body"
}
output "read_result_command" {
  value       = local.outputs.read_result_command.value
  description = "The page the function fetched, read back from the bucket. An error saying the key does not exist means the invocation above did not succeed"
}
output "presign_command" {
  value       = local.outputs.presign_command.value
  description = "A link valid for an hour. The bucket blocks public access, so this is how the page is viewed without making it public"
}
output "function_logs_command" {
  value       = local.outputs.function_logs_command.value
  description = "One START, END and REPORT line per invocation, and the traceback if the handler raised"
}
output "rebuild_command" {
  value       = local.outputs.rebuild_command.value
  description = "Edit /home/ec2-user/lambda/index.py, then run this. The push alone changes nothing: Lambda resolved the tag to a digest when the function was created and keeps running that digest, so the second command points it at the new one. Keep src/index.py in this repository in step - the next apply ships that file, not the edited copy"
}
output "resolved_image_command" {
  value       = local.outputs.resolved_image_command.value
  description = "The tag it was created from and the digest Lambda actually runs. Different digests in the repository and here mean the step above was only half done"
}
output "list_images_command" {
  value       = local.outputs.list_images_command.value
  description = "One image from the bootstrap, and one per rebuild. Empty means the bootstrap never got as far as pushing"
}
output "function_name" {
  value       = local.outputs.function_name.value
  description = "Name of the Lambda function"
}
output "ecr_repository_url" {
  value       = local.outputs.ecr_repository_url.value
  description = "Where the workbench pushes and the function's image comes from"
}
output "result_bucket_name" {
  value       = local.outputs.result_bucket_name.value
  description = "Where the function writes the page. Emptied by terraform destroy - see bucket_force_destroy"
}
output "log_group_name" {
  value       = local.outputs.log_group_name.value
  description = "The function's log group, declared with a retention rather than left for Lambda to create"
}
output "session_command" {
  value       = local.outputs.session_command.value
  description = "Session Manager, for when code-server is what is broken. Needs no inbound rule and no key"
}
output "private_key_command" {
  value       = local.outputs.private_key_command.value
  description = "Retrieves the generated private key from Parameter Store into key.pem. SSH also needs ssh_ingress_cidr_blocks, which is empty by default as the _monolithic template had it"
}
