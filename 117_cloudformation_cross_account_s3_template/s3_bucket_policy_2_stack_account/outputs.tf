# These outputs carry their value expressions directly rather than projecting a local.outputs map, which
# applies only to roots declaring module "vscode_ec2" (rules.md H-2). There is no instance here.
#
# The stack itself is not a Terraform resource here: it is created by the command below, from the template the
# other account owns. That is the demo - so the order around it is written out as outputs (rules.md I-4).
output "apply_order" {
  value       = "1. ../s3_bucket_policy_1_bucket_account (bucket account)  2. this root (stack account)  3. create_stack_command below"
  description = "This root goes second. It needs the bucket account's template_url, and the bucket account needs nothing back"
}
output "cloudformation_role_arn" {
  value       = module.cloudformation_service_role.role_arn
  description = "Service role the stack is created with"
}
output "cloudformation_role_policies" {
  value       = module.cloudformation_service_role.policy_arns
  description = "What that role can do. AdministratorAccess, as the _monolithic template attached it, because the template comes from another account and this root cannot see what it will contain"
}
output "create_stack_command" {
  value       = "aws cloudformation create-stack --region ${data.aws_region.current.region} --stack-name ${var.stack_name} --template-url ${var.template_url} --role-arn ${module.cloudformation_service_role.role_arn}"
  description = "Creates the stack from the other account's bucket. The caller - not the service role - is what reads the template, so the caller needs s3:GetObject in its own IAM policy. The _monolithic template's version also passed CAPABILITY_NAMED_IAM and CAPABILITY_AUTO_EXPAND, which this template, one VPC, needs neither of"
}
output "stack_status_command" {
  value       = "aws cloudformation describe-stacks --region ${data.aws_region.current.region} --stack-name ${var.stack_name} --query 'Stacks[0].[StackStatus,StackStatusReason,RoleARN]' --output table"
  description = "Whether the stack was created, and with which role"
}
output "teardown_order" {
  value       = "aws cloudformation delete-stack --region ${data.aws_region.current.region} --stack-name ${var.stack_name} && aws cloudformation wait stack-delete-complete --region ${data.aws_region.current.region} --stack-name ${var.stack_name} && terraform destroy"
  description = "Delete the stack before destroying this root. CloudFormation deletes with the service role it created the stack with, and once terraform destroy has removed that role the stack can only end in DELETE_FAILED until a role of the same name is put back. Then destroy the bucket account root"
}
