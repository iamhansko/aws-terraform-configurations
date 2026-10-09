# The bucket the demo uploads into, and the event source for the masking function.
#
# What is deliberately NOT here is the notification configuration that points at the function. It lives in
# the root module, for two reasons.
#
# The first is a cycle. aws_s3_bucket_notification needs the function's ARN, and the function's
# aws_lambda_permission needs the bucket's ARN as its source_arn. If this module owned the notification it
# would consume the lambda module's output while the lambda module consumed this one's, which Terraform
# rejects with "Cycle: module.event_source_bucket -> module.lambda_function -> module.event_source_bucket".
# The _monolithic template broke that cycle by not referencing the bucket at all - it wrote the permission's
# source_arn as the literal string "arn:aws:s3:::sensitive-${random_string}", assembled from the same name
# expression as the bucket. That works, and it means the bucket name exists twice in the configuration with
# nothing checking that the two copies agree.
#
# The second is that the notification is the wiring between two modules that have no business knowing about
# each other, and joining two modules' outputs is the root's job (rules.md C-1). A bucket module that takes
# a function ARN is a bucket module that only works when there is a function.
#
# One consequence worth knowing: aws_s3_bucket_notification is authoritative over the bucket's entire
# notification configuration, the same way an inline security group rule block is authoritative over a group
# (rules.md F-2). A second notification resource pointing at this bucket does not add a configuration, it
# replaces the first one on every apply.
resource "aws_s3_bucket" "event_source" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy
}
resource "aws_s3_bucket_versioning" "event_source" {
  bucket = aws_s3_bucket.event_source.id
  versioning_configuration {
    status = var.versioning_status
  }
}
# Not in the _monolithic template, which left public access to the account-level default.
#
# This bucket holds the unmasked input: the demo's sample data is names, emails, phone numbers, card numbers
# and national identity numbers. The account default has blocked public access for new buckets since 2023, so
# the original was not actually open - it was relying on a setting declared somewhere else, which no plan for
# this project would ever show. Declaring it here means the four blocks are part of this bucket's state and
# turning one off is a visible change.
#
# This is the opposite call from a bucket serving a website, where block_public_policy has to be off for an
# anonymous read policy to be accepted at all. Nothing reads this bucket anonymously; the function reads it
# with its role.
resource "aws_s3_bucket_public_access_block" "event_source" {
  count = var.block_public_access ? 1 : 0

  bucket                  = aws_s3_bucket.event_source.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
