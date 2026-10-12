# The account guard. Postconditions on the identity lookup rather than check blocks, and the difference is the
# whole point of having a guard: a failed check assertion is a warning - plan prints it and carries on to a
# successful apply - while a failed postcondition stops the plan before anything is created (rules.md I-2).
# The earlier version of this root used check blocks, and its comment said they failed in plan. They did not.
data "aws_caller_identity" "current" {
  lifecycle {
    # Always on, because source_account_id is required: the common mistake with two roots is running this one
    # with the other root's credentials, and those are exactly the source account's.
    postcondition {
      condition     = self.account_id != var.source_account_id
      error_message = "These credentials belong to source_account_id (${var.source_account_id}). This is the destination account's root - applying it here would create the destination bucket in the source account and a bucket policy trusting a role in its own account. Switch to the destination account's credentials."
    }
    # Optional, for pinning the root to one account explicitly.
    postcondition {
      condition     = var.expected_account_id == null || self.account_id == var.expected_account_id
      error_message = "These credentials belong to account ${self.account_id}, but expected_account_id is ${coalesce(var.expected_account_id, "unset")}."
    }
  }
}
# Apply this root first, into the destination account.
#
# The ordering is forced and worth stating: S3 validates a replication configuration when it is created,
# including that the destination bucket exists and is versioned - and the bucket's name is generated here, so
# the source root cannot even be filled in until this one has run. Because the two accounts have separate
# state files, nothing in Terraform can express that. This comment and the order notes in both roots' outputs
# are the whole mechanism (rules.md I-1/I-4).
#
# The dependency only runs this way because the destination policy can be written knowing just the source
# account id and the agreed role name. Its Principal is the always-existing source account root so S3 accepts
# this first apply before the role exists, while an aws:PrincipalArn condition limits access to that exact
# future role. The agreed name is still what breaks the cross-state reference circle (rules.md I-2).
module "destination_bucket" {
  source = "./modules/replication_destination_bucket"

  name_prefix                        = "${var.project_name}-destination-"
  source_account_id                  = var.source_account_id
  replication_role_name              = var.replication_role_name
  allow_owner_override               = var.allow_owner_override
  noncurrent_version_expiration_days = var.noncurrent_version_expiration_days
  force_destroy                      = var.force_destroy
}
