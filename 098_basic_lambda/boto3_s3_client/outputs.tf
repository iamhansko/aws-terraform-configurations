# These outputs carry their value expressions directly rather than projecting a local.outputs map.
#
# That map exists to keep a root's outputs and the README written onto a VS Code instance from drifting
# apart, so it applies only to roots that declare module "vscode_ec2" (rules.md H-2). There is no instance in
# this root at all - the project is a bucket, a function and the notification between them, and everything is
# driven from the machine running Terraform - so there is no second copy of these values to keep in step. The
# boto3_sqs_client variant next door does declare such an instance, and does build the map.
output "bucket_name" {
  value       = module.event_source_bucket.bucket_name
  description = "Name of the bucket uploads go into. Globally unique, which is why random_string has no default"
}
output "bucket_arn" {
  value       = module.event_source_bucket.bucket_arn
  description = "ARN of the bucket"
}
output "notification_filter_prefix" {
  value       = var.notification_filter_prefix
  description = "Key prefix an upload has to carry to invoke the function. Null means every key invokes it, which is what the conversion left behind after dropping the template's Filter - a function invoked by its own output, surviving on the handler's own prefix check"
}
output "masked_object_prefix" {
  value       = var.masked_object_prefix
  description = "Prefix the handler writes masked copies under. Owned by index.py, restated here so the listing command and the handler cannot be read as disagreeing"
}
output "versioning_status" {
  value       = module.event_source_bucket.versioning_status
  description = "Versioning state of the bucket. Enabled, so re-uploading the same key keeps both the old and the new object - and so emptying the bucket on destroy means deleting versions, which is what force_destroy covers"
}
output "function_name" {
  value       = module.lambda_function.function_name
  description = "Name of the masking function"
}
output "function_arn" {
  value       = module.lambda_function.function_arn
  description = "ARN of the masking function, which is what the bucket notification points at"
}
output "function_role_arn" {
  value       = module.lambda_function.role_arn
  description = "ARN of the function's execution role"
}
output "permission_source_bucket_arn" {
  value       = module.lambda_function.source_bucket_arn
  description = "The bucket ARN the function's invoke permission was narrowed to, handed back out of the module (rules.md B-5). It should equal bucket_arn above; if it ever does not, the notification fires and the invocation is rejected, which looks exactly like a function that is never triggered"
}
output "upload_sample_command" {
  value       = module.event_source_bucket.upload_sample_command
  description = "1. Writes a sample file containing the kinds of data the handler masks and uploads it under the filtered prefix. This upload is the only thing in the project that invokes the function"
}
output "list_masked_command" {
  value       = module.event_source_bucket.list_masked_command
  description = "2. What the function produced. Allow a few seconds - the notification is asynchronous, so an empty listing immediately after the upload is normal"
}
output "diff_command" {
  value       = module.event_source_bucket.diff_command
  description = "3. The input and the masked copy printed one after the other, which is the result the project exists to show"
}
output "logs_command" {
  value       = module.lambda_function.logs_command
  description = "The function's own log output, and the first place to look when list_masked_command stays empty. A ResourceNotFoundException here means the group does not exist, which means the function was never invoked - look at the notification rather than at the handler"
}
output "invocation_metrics_command" {
  value       = module.lambda_function.invocation_metrics_command
  description = "How many times the function has run. Terraform has no way to know this and no resource attribute reports it, so it is a command rather than a value (rules.md H-2 takes the same position for values that only exist after an invocation)"
}
output "notification_config_command" {
  value       = "aws s3api get-bucket-notification-configuration --bucket ${module.event_source_bucket.bucket_name}"
  description = "What S3 believes it is configured to notify. Worth comparing against notification_filter_prefix above: this is the single authoritative configuration on the bucket, so anything that wrote it after this apply replaced the whole thing rather than adding to it"
}
