# These outputs carry their value expressions directly rather than projecting a local.outputs map. That map
# keeps a root's outputs and a README written onto a VS Code instance in step, so it applies only to roots
# declaring module "vscode_ec2" (rules.md H-2). There is no instance here.
output "stack_set_name" {
  value       = module.stack_set.name
  description = "Name of the StackSet. Every stack it creates is called StackSet-<this>-<id>"
}
output "stack_set_id" {
  value       = module.stack_set.stack_set_id
  description = "The generated StackSet id. A stack found in a target account records this as its parent, so it is how the stack is traced back"
}
output "deployment_targets" {
  value       = module.stack_set.deployment_targets
  description = "Where the StackSet deploys and with what parameter values. This is what the _monolithic template was missing: StackInstancesGroup came through the conversion as a commented-out TODO, so it created a StackSet, deployed nothing, and succeeded"
}
output "administration_role_arn" {
  value       = module.stackset_roles.administration_role_arn
  description = "Role CloudFormation assumes to drive the StackSet"
}
output "execution_role_permissions" {
  value       = length(module.stackset_roles.execution_role_policy_arns) > 0 ? module.stackset_roles.execution_role_policy_arns : ["(inline policy scoped to iam:*Policy on ${var.managed_policy_name})"]
  description = "What the execution role can do in every target account. AdministratorAccess by default, which is what AWS's own setup template attaches and what a StackSet needs in general - it has to be able to create whatever the template contains. scope_execution_role_to_iam_policies narrows it to this template, and breaks as soon as the template changes"
}
output "deployed_policy_name" {
  value       = var.managed_policy_name
  description = "Name of the managed policy each stack creates"
}
output "deployed_policy_effect" {
  value       = "Denies every action for calls whose source address is not in ${join(", ", var.allowed_source_ip_addresses)}. It is created attached to nothing, so it has no effect until something is attached to it - attach it to yourself and you are locked out of everything except calls from those addresses"
  description = "What the deployed policy does, and why deploying it is safe. The addresses are documentation ranges and match nobody, so a policy that did apply to something would deny everything"
}
output "list_instances_command" {
  value       = module.stack_set.list_instances_command
  description = "1. Every stack the StackSet created and how it ended. This is the only place a per-account failure appears - the StackSet stays ACTIVE while an instance is OUTDATED or INOPERABLE"
}
output "last_operation_command" {
  value       = module.stack_set.last_operation_command
  description = "2. The most recent operation. A FAILED one with instances showing the old state is the usual shape of a rejected template or a missing execution role in a target account"
}
output "read_deployed_policy_command" {
  value       = "aws iam get-policy --policy-arn arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${var.managed_policy_name} --query 'Policy.[PolicyName,AttachmentCount,DefaultVersionId]' --output table"
  description = "3. The policy the stack created, read directly rather than through CloudFormation. AttachmentCount 0 is the expected and safe state"
}
output "read_deployed_policy_document_command" {
  value       = "aws iam get-policy-version --policy-arn arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${var.managed_policy_name} --version-id v1 --query 'PolicyVersion.Document' --output json"
  description = "4. The document, with the four addresses from the per-instance override rather than the two from the template's own default. That difference is the point of a parameter override"
}
output "describe_stack_set_command" {
  value       = module.stack_set.describe_command
  description = "5. The StackSet itself. ACTIVE here says nothing about whether any stack was created"
}
