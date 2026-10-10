# Every value here is a projection of local.outputs in main.tf, which the README written onto the workbench
# renders from the same map - so no value expression exists twice, and an output cannot be added without also
# appearing in that README (rules.md B-5/H-2).
#
# description is the one thing that cannot be projected: Terraform rejects an expression in an output's
# description ("Variables not allowed"), so the wording is a literal on both sides.
output "distribution_domain_name" {
  value       = local.outputs.distribution_domain_name.value
  description = "The _monolithic template's DistributionDomainName output. The viewer-request function on this path answers every request itself with a 302 to aws.amazon.com/cloudfront, so code-server is never reached through it until the function is changed"
}
output "distribution_root_url" {
  value       = local.outputs.distribution_root_url.value
  description = "The default behaviour. Its function also answers with the 302, so the Hello World page in the bucket is never served until that function is changed"
}
output "function_redirect_command" {
  value       = local.outputs.function_redirect_command.value
  description = "The response comes from the edge, not from either origin: a 302 carrying the cloudfront-functions header the function sets"
}
output "s3_function_test_command" {
  value       = local.outputs.s3_function_test_command.value
  description = "test-function evaluates the LIVE code against a sample event and reports its compute utilization"
}
output "ec2_function_describe_command" {
  value       = local.outputs.ec2_function_describe_command.value
  description = "Edit functions/ec2_origin.js to return event.request instead of the 302, apply, and the code path reaches code-server through CloudFront"
}
output "key_value_stores" {
  value       = local.outputs.key_value_stores.value
  description = "The stores associated with each function, or none in the default variant. The functions here do not read them yet - a function reads its store through import cf from 'cloudfront' and cf.kvs()"
}
output "distribution_status_command" {
  value       = local.outputs.distribution_status_command.value
  description = "InProgress for several minutes after every change; the edge serves the previous configuration until it is Deployed"
}
output "private_key_command" {
  value       = local.outputs.private_key_command.value
  description = "Retrieves the generated private key from Parameter Store. No security group opens port 22; this is for the case where the SSM agent is what is broken"
}
