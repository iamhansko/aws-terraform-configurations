# These outputs carry their value expressions directly rather than projecting a local.outputs map. That map
# keeps a root's outputs and a README written onto a VS Code instance in step, so it applies only to roots
# declaring module "vscode_ec2" (rules.md H-2). There is no instance here.
#
# What these outputs are for instead: they are the interface to the other root. The two accounts have
# separate state files, so nothing can be referenced across them - these values have to be read here and
# typed into 2_source_account's variables (rules.md I-1).
output "destination_bucket_name" {
  value       = module.destination_bucket.bucket_name
  description = "Set this as destination_bucket_name in 2_source_account. It is the one value that root cannot work out for itself"
}
output "destination_account_id" {
  value       = data.aws_caller_identity.current.account_id
  description = "Set this as destination_account_id in 2_source_account. Taken from the credentials this root ran with rather than from a variable, so it is the account the bucket is actually in"
}
output "destination_bucket_arn" {
  value       = module.destination_bucket.bucket_arn
  description = "ARN of the destination bucket, which the source account's replication role policy needs in order to be scoped to this bucket rather than to every bucket"
}
output "replication_role_arn" {
  value       = module.destination_bucket.replication_role_arn
  description = "The exact role ARN this bucket policy permits through aws:PrincipalArn. The source root must create this ARN; otherwise both applies can succeed while replication is denied"
}
output "allow_owner_override" {
  value       = module.destination_bucket.allows_owner_override
  description = "Set replicate_owner_override to the same value in 2_source_account. The two halves are independent settings and either one alone does nothing"
}
output "source_account_variables" {
  value = {
    destination_bucket_name  = module.destination_bucket.bucket_name
    destination_account_id   = data.aws_caller_identity.current.account_id
    replication_role_name    = var.replication_role_name
    replicate_owner_override = module.destination_bucket.allows_owner_override
  }
  description = "Every variable 2_source_account needs, in one place. Copy this object into that root's tfvars - it is the closest thing to a reference across two state files"
}
output "list_replicated_objects_command" {
  value       = module.destination_bucket.list_replicated_objects_command
  description = "What has arrived in the destination. Run it with this account's credentials after writing into the source bucket"
}
output "apply_order_note" {
  value       = "1) apply this root into account ${data.aws_caller_identity.current.account_id}  2) copy source_account_variables into 2_source_account  3) apply 2_source_account with the source account's credentials"
  description = "The order is not optional: S3 validates a replication configuration on creation, including that the destination bucket and its policy exist. Applying the source root first fails on that validation"
}
output "teardown_order_note" {
  value       = "1) terraform destroy in 2_source_account with the source account's credentials  2) then terraform destroy here, in account ${data.aws_caller_identity.current.account_id}"
  description = "The exact reverse of the apply, and stated here as well as in the source root because whoever runs destroy may only have this root open (rules.md I-4). Destroying this bucket first leaves the source's replication rule pointing at a bucket that no longer exists, and every write to the source then records a FAILED replication status. force_destroy is on, so this deletes every replicated object and every version of it - the destination is versioned by necessity, and nothing here is recoverable afterwards"
}
