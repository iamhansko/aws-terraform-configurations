# Every value here is a projection of local.outputs in main.tf, which the README written onto the workbench
# renders from the same map - so no value expression exists twice, and an output cannot be added without also
# appearing in that README (rules.md B-5/H-2).
#
# description is the one thing that cannot be projected: Terraform rejects an expression in an output's
# description ("Variables not allowed"), so the wording is a literal on both sides.
output "distribution_domain_name" {
  value       = local.outputs.distribution_domain_name.value
  description = "The _monolithic template's DistributionDomainName output. The viewer-request function logs the request and passes it on, so this reaches code-server through CloudFront"
}
output "distribution_root_url" {
  value       = local.outputs.distribution_root_url.value
  description = "The default behaviour: the Hello World page in the bucket, after the S3 origin function has logged the request"
}
output "request_command" {
  value       = local.outputs.request_command.value
  description = "The function runs before the cache and the origin on every viewer request"
}
output "function_logs_command" {
  value       = local.outputs.function_logs_command.value
  description = "A Lambda@Edge replica logs to /aws/lambda/us-east-1.<function> in the region of the edge location that served the request - not in us-east-1, and not necessarily in this region. This lists the regions that have one"
}
output "function_versions" {
  value       = local.outputs.function_versions.value
  description = "The distribution runs these exact versions. A code change publishes a new version and the distribution is updated to it, which redeploys every edge location"
}
output "distribution_status_command" {
  value       = local.outputs.distribution_status_command.value
  description = "InProgress for several minutes after every change; the edge serves the previous version until it is Deployed"
}
output "teardown_note" {
  value       = local.outputs.teardown_note.value
  description = "The functions cannot be deleted until CloudFront has removed their edge replicas, which happens some time after the distribution is gone. Destroy waits up to lambda_delete_timeout for that; if it still fails with replicated function, run terraform destroy again later"
}
output "private_key_command" {
  value       = local.outputs.private_key_command.value
  description = "Retrieves the generated private key from Parameter Store. No security group opens port 22; this is for the case where the SSM agent is what is broken"
}
