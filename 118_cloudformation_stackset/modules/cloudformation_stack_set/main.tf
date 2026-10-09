# The StackSet and the stack instances it deploys.
#
# Both here rather than in separate modules, because a StackSet with no instances is inert: it is a template
# and a set of permissions, and nothing exists in any account until an instance names one. The _monolithic
# template is the demonstration of that - StackInstancesGroup came through the CloudFormation conversion as a
# commented-out TODO, so it created a StackSet, deployed nothing, and reported success.
resource "aws_cloudformation_stack_set" "stack_set" {
  name        = var.name
  description = var.description
  # SELF_MANAGED, as the original had it: the two roles are created by the caller rather than by
  # CloudFormation through Organizations. SERVICE_MANAGED needs an Organizations management account with
  # trusted access enabled, which a demo cannot assume.
  permission_model        = "SELF_MANAGED"
  administration_role_arn = var.administration_role_arn
  execution_role_name     = var.execution_role_name
  capabilities            = var.capabilities
  parameters              = var.parameters
  template_body           = var.template_body
  tags                    = var.tags
}
# Where it actually deploys. One resource per label rather than one per account, because
# aws_cloudformation_stack_instances takes lists of accounts and regions and creates the cross product -
# which is what CloudFormation's StackInstancesGroup did.
resource "aws_cloudformation_stack_instances" "instances" {
  for_each = var.stack_instances

  stack_set_name = aws_cloudformation_stack_set.stack_set.name
  accounts       = each.value.accounts
  regions        = each.value.regions
  # Per-instance parameter values, which override the StackSet's. This is where the original's
  # ParameterOverrides went - and it is the interesting half of the feature: one template, different values
  # per account.
  parameter_overrides = each.value.parameter_override
  retain_stacks       = var.retain_stacks_on_destroy

  operation_preferences {
    failure_tolerance_count = var.failure_tolerance_count
    max_concurrent_count    = var.max_concurrent_count
  }
}
