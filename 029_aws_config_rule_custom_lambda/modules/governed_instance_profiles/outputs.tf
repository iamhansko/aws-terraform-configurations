output "instance_profile_names" {
  value       = { for key, profile in aws_iam_instance_profile.governed_instance_profile : key => profile.name }
  description = "Instance profile name per fixture key. This is the value that goes into run-instances as --iam-instance-profile Name=<this>"
}
output "instance_profile_arns" {
  value       = { for key, profile in aws_iam_instance_profile.governed_instance_profile : key => profile.arn }
  description = "Instance profile ARN per fixture key. The handler reads this ARN off the instance's configuration item and takes the part after the last slash as the profile name"
}
output "role_names" {
  value       = { for key, role in aws_iam_role.governed_role : key => role.name }
  description = "Role name per fixture key, for listing what is currently attached to it - which is how the remediation becomes visible, since Terraform's state does not record policies the handler attached"
}
output "demonstrates" {
  value       = { for key, profile in var.profiles : key => profile.demonstrates }
  description = "What each fixture is supposed to show, re-exposed so the caller's outputs and the workbench README describe the fixtures from the same place they are defined (rules.md B-5)"
}
output "initial_policy_arns" {
  value       = { for key, profile in var.profiles : key => profile.policy_arns }
  description = "Policies each fixture started with, re-exposed for the same reason. Worth keeping separate from the live state: by the time anyone reads this, the handler may have detached them (rules.md B-5)"
}
