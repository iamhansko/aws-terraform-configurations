output "name" {
  value       = aws_cloudformation_stack_set.stack_set.name
  description = "Name of the StackSet"
}
output "id" {
  value       = aws_cloudformation_stack_set.stack_set.id
  description = "The StackSet's identifier, which for a self-managed StackSet is just its name"
}
output "stack_set_id" {
  value       = aws_cloudformation_stack_set.stack_set.stack_set_id
  description = "The generated StackSet id, name and uuid. This is what a stack instance records as its parent, so it is how a stack found in a target account is traced back"
}
output "instance_labels" {
  value       = sort(keys(aws_cloudformation_stack_instances.instances))
  description = "The deployment targets this StackSet has. An empty list means it deploys nowhere, which is valid and silent - and is what the _monolithic template produced (rules.md B-5)"
}
output "deployment_targets" {
  value = {
    for label, instance in var.stack_instances : label => {
      accounts            = instance.accounts
      regions             = instance.regions
      parameter_overrides = instance.parameter_override
    }
  }
  description = "Where each label deploys and with what parameter values, re-exposed because the overrides are the interesting half of a StackSet and are not visible from the StackSet itself (rules.md B-5)"
}
output "describe_command" {
  value       = "aws cloudformation describe-stack-set --stack-set-name ${aws_cloudformation_stack_set.stack_set.name} --query 'StackSet.[StackSetId,Status,PermissionModel]' --output table"
  description = "The StackSet itself. Status ACTIVE here says nothing about whether any stack was created - that is the instances below"
}
output "list_instances_command" {
  value       = "aws cloudformation list-stack-instances --stack-set-name ${aws_cloudformation_stack_set.stack_set.name} --query 'Summaries[].[Account,Region,Status,StatusReason]' --output table"
  description = "Every stack the StackSet created and how it ended. This is the only place a per-account failure is reported: the StackSet stays ACTIVE while an instance is OUTDATED or INOPERABLE"
}
output "last_operation_command" {
  value       = "aws cloudformation list-stack-set-operations --stack-set-name ${aws_cloudformation_stack_set.stack_set.name} --max-items 1 --query 'Summaries[].[OperationId,Action,Status]' --output table"
  description = "The most recent operation. A FAILED one here with instances still showing the old state is the usual shape of a rejected template or a missing execution role in a target account"
}
