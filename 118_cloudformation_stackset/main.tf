data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
locals {
  # Null means "here", which is what the _monolithic template's Ref to AWS::AccountId and AWS::Region did.
  target_account_ids = coalesce(var.stack_instance_account_ids, [data.aws_caller_identity.current.account_id])
  target_regions     = coalesce(var.stack_instance_regions, [data.aws_region.current.region])
  # The narrow alternative to AdministratorAccess on the execution role. Enough for the template in
  # templates/ and nothing more - which is the point and the problem: it is correct for this template only.
  scoped_execution_statements = [
    {
      Effect = "Allow"
      Action = [
        "iam:CreatePolicy",
        "iam:DeletePolicy",
        "iam:GetPolicy",
        "iam:ListPolicyVersions",
        "iam:CreatePolicyVersion",
        "iam:DeletePolicyVersion",
        "iam:TagPolicy",
        "iam:UntagPolicy",
      ]
      Resource = "arn:aws:iam::*:policy/${var.managed_policy_name}"
    },
    {
      # CloudFormation reads the stack's own state through the execution role. Without this the stack fails
      # to create with an access denied that names no resource.
      Effect   = "Allow"
      Action   = ["cloudformation:DescribeStacks", "cloudformation:DescribeStackEvents", "cloudformation:GetTemplate"]
      Resource = "*"
    },
  ]
}
module "stackset_roles" {
  source = "./modules/stackset_self_managed_roles"

  administration_role_name          = var.administration_role_name
  execution_role_name               = var.execution_role_name
  trusted_administrator_account_ids = [data.aws_caller_identity.current.account_id]
  # AdministratorAccess by default, as the original and AWS's own setup template have it. The narrow version
  # is opt-in because it is only correct for the template currently in templates/.
  execution_role_policy_arns              = var.scope_execution_role_to_iam_policies ? [] : ["arn:aws:iam::aws:policy/AdministratorAccess"]
  execution_role_inline_policy_statements = var.scope_execution_role_to_iam_policies ? local.scoped_execution_statements : []
}
module "stack_set" {
  source = "./modules/cloudformation_stack_set"

  name        = var.stack_set_name
  description = "Deploys ${var.managed_policy_name}, an IAM managed policy that denies calls from outside a list of source addresses"
  # Read from a file. The template stays CloudFormation on purpose: a StackSet distributes CloudFormation
  # stacks, so translating it to HCL would remove what the project demonstrates.
  template_body           = file("${path.root}/${var.template_path}")
  administration_role_arn = module.stackset_roles.administration_role_arn
  execution_role_name     = module.stackset_roles.execution_role_name
  # Only what this template needs. The original declared all three capabilities; this template creates a
  # named IAM resource and has no transforms.
  capabilities = ["CAPABILITY_NAMED_IAM"]
  # StackSet-level values, which every instance inherits unless it overrides them. The original left this
  # empty and put everything in the override, so the StackSet's own parameters were the template's defaults.
  parameters = {
    ManagedPolicyName = var.managed_policy_name
  }
  tags = var.stack_set_tags

  stack_instances = {
    # The one deployment target the _monolithic template described and never created: its
    # StackInstancesGroup came through the CloudFormation conversion as a commented-out TODO, so it built a
    # StackSet that deployed nowhere and reported success.
    current_account = {
      accounts = local.target_account_ids
      regions  = local.target_regions
      # The override is the interesting half: one template, a different address list per target. The
      # template's own default is two addresses and this replaces it with four.
      parameter_override = {
        AllowedSourceIpAddresses = join(",", var.allowed_source_ip_addresses)
      }
    }
  }

  failure_tolerance_count = var.failure_tolerance_count
  max_concurrent_count    = var.max_concurrent_count

  # The administration role's policy has to exist before the StackSet performs its first operation, and a
  # role ARN reference only orders this after the role (rules.md D-1/D-2). Without it the first stack
  # instance fails with an access denied that looks like a misconfigured StackSet.
  depends_on = [module.stackset_roles]
}
