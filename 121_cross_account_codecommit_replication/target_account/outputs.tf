# This root has no vscode_ec2 module, so rules.md H-2 does not apply: there is no workbench README to
# render. Values are therefore exposed directly rather than routed through a local.outputs map.

output "apply_order" {
  value       = "Apply target_account first with target-account credentials, then apply source_account with source-account credentials and the source_root_handoff values below."
  description = "Required cross-account apply order, which Terraform cannot enforce across separate states."
}

output "destroy_order" {
  value       = "Destroy source_account first so no pipeline can assume this role, then destroy target_account."
  description = "Required cross-account destroy order, the reverse of apply order."
}

output "target_repository" {
  value       = module.codecommit_replication_target.repository_name
  description = "Name of the target CodeCommit repository."
}

output "target_repository_arn" {
  value       = module.codecommit_replication_target.repository_arn
  description = "ARN of the target CodeCommit repository."
}

output "target_role_arn" {
  value       = module.codecommit_replication_target.cross_account_role_arn
  description = "ARN of the narrowly trusted target role assumed by the source CodeBuild role."
}

output "target_region" {
  value       = data.aws_region.current.region
  description = "AWS region containing the target repository."
}

output "repository_verification_command" {
  value       = "aws codecommit get-repository --repository-name ${module.codecommit_replication_target.repository_name} --region ${data.aws_region.current.region}"
  description = "Command to verify the target repository while using target-account credentials."
}

output "role_verification_command" {
  value       = "aws iam get-role --role-name ${module.codecommit_replication_target.cross_account_role_name}"
  description = "Command to inspect the target cross-account role while using target-account credentials."
}

output "source_root_handoff" {
  value = {
    target_account_id         = var.target_account_id
    target_account_repository = module.codecommit_replication_target.repository_name
    target_region             = data.aws_region.current.region
    cross_account_role_name   = module.codecommit_replication_target.cross_account_role_name
  }
  description = "Values to pass to identically named source-root variables; fixed names break the cross-state cycle (rules.md I-2)."
}
