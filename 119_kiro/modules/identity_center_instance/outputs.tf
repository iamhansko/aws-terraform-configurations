output "instance_arn" {
  value       = local.instance_arn
  description = "ARN of the existing or newly created IAM Identity Center instance"
}

output "identity_store_id" {
  value       = local.identity_store_id
  description = "Identity Store ID associated with the existing or newly created instance"
}

output "created_by_this_root" {
  value       = terraform_data.creation_decision.input
  description = "Whether this root created and therefore owns the IAM Identity Center instance lifecycle"
}
