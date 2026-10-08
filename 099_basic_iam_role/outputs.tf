# These outputs carry their value expressions directly rather than projecting a local.outputs map.
#
# That map exists to keep a root's outputs and the README written onto a VS Code instance from drifting
# apart, so it applies only to roots that declare module "vscode_ec2" (rules.md H-2). There is no instance
# in this root - the project is three IAM roles - so there is nothing to render a README onto and no second
# copy of these values to keep in step.
output "role_arns" {
  value = {
    hcl_object  = module.hcl_object_role.arn
    data_source = module.data_source_role.arn
    heredoc     = module.heredoc_role.arn
  }
  description = "The three roles, keyed by how their policy documents were written"
}
output "role_names" {
  value = {
    hcl_object  = module.hcl_object_role.name
    data_source = module.data_source_role.name
    heredoc     = module.heredoc_role.name
  }
  description = "Generated names of the three roles. Generated rather than fixed, so this project can be applied twice in one account"
}
output "stored_trust_policies" {
  value = {
    hcl_object  = module.hcl_object_role.assume_role_policy
    data_source = module.data_source_role.assume_role_policy
    heredoc     = module.heredoc_role.assume_role_policy
  }
  description = "The three trust policies as IAM stored them. This is the answer to the question the project asks: three documents authored three ways, and IAM holds the same thing for all of them"
}
output "compare_trust_policies_command" {
  value       = "for role in ${module.hcl_object_role.name} ${module.data_source_role.name} ${module.heredoc_role.name}; do echo \"== $role\"; aws iam get-role --role-name $role --query 'Role.AssumeRolePolicyDocument' --output json; done"
  description = "Reads all three trust policies back from IAM in one command. The three blocks should be identical apart from nothing at all - if one differs, the way it was written is not equivalent after all, which is exactly what this project exists to check"
}
output "compare_inline_policies_command" {
  value       = "for role in ${module.hcl_object_role.name} ${module.data_source_role.name} ${module.heredoc_role.name}; do echo \"== $role\"; aws iam get-role-policy --role-name $role --policy-name ${var.policy_name} --query 'PolicyDocument' --output json; done"
  description = "The same comparison for the permissions policies"
}
output "read_policies_commands" {
  value = {
    hcl_object  = module.hcl_object_role.read_policies_command
    data_source = module.data_source_role.read_policies_command
    heredoc     = module.heredoc_role.read_policies_command
  }
  description = "Per-role read commands, for looking at one of them on its own"
}
output "role_unique_ids" {
  value = {
    hcl_object  = module.hcl_object_role.unique_id
    data_source = module.data_source_role.unique_id
    heredoc     = module.heredoc_role.unique_id
  }
  description = "The roles' AROA identifiers, which are what CloudTrail records and what a resource policy resolves a principal to. A role recreated under the same name gets a new one, which is how a trust relationship that looks correct can still fail"
}
