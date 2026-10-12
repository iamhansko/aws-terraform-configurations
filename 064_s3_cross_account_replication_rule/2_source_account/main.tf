# The account guard. Postconditions on the identity lookup rather than check blocks: a failed check assertion
# is only a warning, so plan prints it and the apply goes ahead anyway, while a failed postcondition stops the
# plan before anything is created (rules.md I-2). The earlier version of this root used check blocks and said
# they failed in plan; they did not. A variable validation cannot do this either, because it cannot read the
# running credentials.
data "aws_caller_identity" "current" {
  lifecycle {
    # Always on, because destination_account_id is required. Running this root with the destination root's
    # credentials is the mistake two roots make easy, and those credentials are exactly that account's. It
    # also catches destination_account_id copied from the wrong output, which would make the rule replicate
    # within one account - valid S3, but not what this project is for.
    postcondition {
      condition     = self.account_id != var.destination_account_id
      error_message = "These credentials belong to destination_account_id (${var.destination_account_id}). This is the source account's root: apply it with the source account's credentials, and read destination_account_id from 1_destination_account's outputs."
    }
    # Optional, for pinning the root to one account explicitly.
    postcondition {
      condition     = var.expected_account_id == null || self.account_id == var.expected_account_id
      error_message = "These credentials belong to account ${self.account_id}, but expected_account_id is ${coalesce(var.expected_account_id, "unset")}."
    }
  }
}
# Apply this root second, into the source account, with the values 1_destination_account printed.
#
# The order is forced by S3 rather than by Terraform: a replication configuration is validated when it is
# created, including that the destination bucket exists. Applying this first fails on that validation, and
# nothing here can express the dependency because the destination lives in another account's state file
# (rules.md I-1).
locals {
  destination_bucket_arn = "arn:aws:s3:::${var.destination_bucket_name}"
}
# The role S3 assumes. Its name is fixed because the other account's bucket policy limits its account-root
# Principal to this exact role ARN through aws:PrincipalArn. The name is the agreement between the two roots
# (rules.md I-2).
module "replication_role" {
  source = "./modules/s3_replication_role"

  role_name              = var.replication_role_name
  source_bucket_arn      = module.source_bucket.bucket_arn
  destination_bucket_arn = local.destination_bucket_arn
  allow_owner_override   = var.replicate_owner_override
}
# The source bucket and its replication rule.
#
# The two modules reference each other's outputs in opposite directions - the role's policy needs the bucket
# ARN, the bucket's configuration needs the role ARN - which reads like a cycle and is not one: the bucket
# ARN is derivable from the bucket resource, and the policy is a separate resource from the role. Terraform
# resolves it because the graph is over resources rather than modules.
module "source_bucket" {
  source = "./modules/replication_source_bucket"

  name_prefix                        = "${var.project_name}-source-"
  replication_role_arn               = module.replication_role.role_arn
  destination_bucket_arn             = local.destination_bucket_arn
  destination_account_id             = var.destination_account_id
  replicate_owner_override           = var.replicate_owner_override
  replication_time_minutes           = var.replication_time_minutes
  replicate_delete_markers           = var.replicate_delete_markers
  rule_prefix                        = var.rule_prefix
  noncurrent_version_expiration_days = var.noncurrent_version_expiration_days
  objects                            = var.demo_objects
  force_destroy                      = var.force_destroy
}
