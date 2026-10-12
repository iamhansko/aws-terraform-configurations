# These outputs carry their value expressions directly rather than projecting a local.outputs map. That map
# keeps a root's outputs and a README written onto a VS Code instance in step, so it applies only to roots
# declaring module "vscode_ec2" (rules.md H-2). There is no instance here.
#
# The apply and teardown order are outputs rather than README prose, because the two roots cannot order
# each other - they have separate states and separate credentials (rules.md I-4).
output "apply_order" {
  value       = "1. this root (bucket account)  2. ../s3_bucket_policy_2_stack_account with -var template_url=<template_url below>, using the stack account's credentials"
  description = "This root goes first: the stack account takes the template URL from it, and nothing here needs anything back from there"
}
output "bucket_name" {
  value       = module.template_bucket.bucket_name
  description = "Generated name of the template bucket. The _monolithic template's only output"
}
output "template_url" {
  value       = module.template_bucket.template_url
  description = "Pass this to the stack account root as template_url. It carries this bucket's region, so the stack account need not be applied in the same region"
}
output "granted_account_id" {
  value       = var.stack_account_id
  description = "The account the bucket policy grants s3:GetObject and s3:GetBucketLocation to, as its root principal. A principal there also needs s3:GetObject in its own IAM policy - the bucket policy is half of a cross-account grant"
}
output "bucket_policy_command" {
  value       = "aws s3api get-bucket-policy --bucket ${module.template_bucket.bucket_name} --query Policy --output text"
  description = "The cross-account grant as S3 holds it"
}
output "stack_account_read_check_command" {
  value       = "aws s3api head-object --bucket ${module.template_bucket.bucket_name} --key ${module.template_bucket.template_key}"
  description = "Run this with the stack account's credentials. A 403 means the read CloudFormation will attempt is denied - either this bucket policy or that caller's own IAM policy - and CreateStack will fail with S3 Access Denied for the same reason"
}
output "teardown_order" {
  value       = "1. delete the stack in the stack account  2. destroy ../s3_bucket_policy_2_stack_account  3. destroy this root"
  description = "Last to go. Deleting the bucket first does not break the existing stack - CloudFormation keeps its own copy of the template - but it breaks any update-stack that still points at this URL"
}
