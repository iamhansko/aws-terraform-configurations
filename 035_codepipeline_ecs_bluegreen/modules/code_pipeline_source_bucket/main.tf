# The pipeline's source bucket, in a module of its own because four separate things read it: the
# bastion uploads the archive into it, the pipeline's source action reads one key out of it, the
# CloudTrail event selector records writes to that one object, and the EventBridge pattern matches the
# bucket and key. Three of those four would otherwise have to be ordered after whichever module owned
# the bucket, and the pipeline module cannot own it because the bastion has to exist before the
# pipeline does nothing useful - so a shared, upstream module is what keeps the graph acyclic.
resource "aws_s3_bucket" "source_bucket" {
  # A generated name. The _monolithic template declared this bucket with no arguments at all, so the
  # provider generated one anyway - a prefix at least says what it is in a bucket listing.
  bucket_prefix = var.bucket_prefix
  # force_destroy, which the _monolithic template did not set, and the decision is deliberate rather
  # than a default (rules.md I-4).
  #
  # This bucket accumulates objects nothing in this configuration created: the archive the bastion
  # uploads during the first apply, a new version of it on every re-upload, and a new version on every
  # re-apply. S3 refuses to delete a bucket that holds objects, so without this a destroy stops here
  # with BucketNotEmpty and leaves the rest of the project standing.
  #
  # Versioning below is on and required, which makes this irreversible: force_destroy deletes every
  # version, so destroying this project discards the archive and its whole history. For a demo that is
  # the right trade - the archive is rebuilt by the next apply - and the root's outputs say so where a
  # person would see it before running destroy.
  force_destroy = var.force_destroy
  tags = {
    Name = var.bucket_prefix
  }
}
# Required rather than optional: a CodePipeline S3 source action tracks a specific object version, and
# CreatePipeline rejects a source bucket that does not have versioning enabled.
resource "aws_s3_bucket_versioning" "source_bucket_versioning" {
  bucket = aws_s3_bucket.source_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}
