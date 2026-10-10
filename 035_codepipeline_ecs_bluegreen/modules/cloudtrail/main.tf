# The trail exists for one reason: S3 does not publish data-plane events to EventBridge by itself, so
# without it the EventBridge rule never fires and nothing starts the pipeline. It is not here for
# auditing, which is why its event selector records write-only data events on exactly the one object
# that matters and nothing else.
#
# There is a newer way to do this - turning on the bucket's own EventBridge notifications and matching
# detail-type "Object Created", which needs no trail at all - and a sibling project in this repository
# uses it. This one keeps the trail because that is what the _monolithic template declared, and because
# the two are not equivalent in what they record: the trail also captures who made the write.
resource "aws_s3_bucket" "logs_bucket" {
  # A generated name. The _monolithic template declared this bucket with no arguments at all, so the
  # provider generated one anyway - a prefix at least says what it is in a bucket listing.
  bucket_prefix = var.logs_bucket_prefix
  # force_destroy, which the _monolithic template did not set, decided rather than defaulted
  # (rules.md I-4).
  #
  # CloudTrail writes a digest file every few minutes whether or not anything happened, so this bucket
  # is never empty by the time a destroy reaches it, and S3 refuses to delete a bucket that holds
  # objects - so without this a destroy stops here with BucketNotEmpty.
  #
  # What it discards is the audit log: every recorded write to the source object, and with management
  # events enabled every API call in the region as well. For a demo whose trail exists only to make an
  # EventBridge rule fire that is the right trade, and the root's outputs say so where a person would
  # see it before running destroy. For anything kept, this is the bucket to set false.
  force_destroy = var.force_destroy
  tags = {
    Name = var.logs_bucket_prefix
  }
}
locals {
  # Assembled from the trail name rather than read from the trail below, which is forced: the trail
  # depends on this policy, so the policy cannot reference the trail.
  trail_arn = "arn:${var.partition}:cloudtrail:${var.region}:${var.account_id}:trail/${var.trail_name}"
}
# The policy CloudTrail requires before it will accept the bucket. Both statements are necessary and
# they are not interchangeable: GetBucketAcl on the bucket is how CloudTrail checks it may write, and
# PutObject under the account prefix is the write itself.
#
# The _monolithic template had this policy and had it right, which is worth recording because the same
# bucket in a sibling project had no policy at all and could therefore never apply. The only changes
# here are the two Sids, added because they are what appears in an access-denied message.
#
# The aws:SourceArn conditions are what stop this bucket from being usable by a trail in another
# account - the confused deputy shape CloudTrail's own documentation describes.
resource "aws_s3_bucket_policy" "logs_bucket_policy" {
  bucket = aws_s3_bucket.logs_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = ["s3:GetBucketAcl"]
        Resource = aws_s3_bucket.logs_bucket.arn
        Condition = {
          StringEquals = {
            "aws:SourceArn" = local.trail_arn
          }
        }
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.logs_bucket.arn}/AWSLogs/${var.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "aws:SourceArn" = local.trail_arn
          }
        }
      },
    ]
  })
}
resource "aws_cloudtrail" "cloud_trail" {
  name           = var.trail_name
  s3_bucket_name = aws_s3_bucket.logs_bucket.id
  enable_logging = true
  event_selector {
    read_write_type = "WriteOnly"
    # False, where the _monolithic template left this unset and the provider's default is true. That
    # default is why the template's trail recorded every API call in the region in order to notice two
    # PutObject calls, and it is the one setting here with a real running cost. Nothing in this project
    # reads a management event.
    include_management_events = var.include_management_events
    data_resource {
      type = "AWS::S3::Object"
      # Object-level ARNs rather than a bucket-level one, as the template had it, and the distinction
      # matters: a bucket-level selector would record every write to the source bucket, and because the
      # EventBridge rule below turns a recorded write into a pipeline execution, each one would start
      # another run.
      #
      # This is also the half of the chain that is easy to get wrong in the other direction. Management
      # events alone never see an object PUT, so a trail without a data_resource block produces an
      # EventBridge rule that is correct and never fires.
      values = var.data_resource_object_arns
    }
  }

  # The policy before the trail, and this one is not a precaution.
  #
  # CreateTrail validates the bucket policy synchronously and rejects a bucket it cannot write to with
  # InsufficientS3BucketPolicyException. The trail names the bucket by id, which orders it after the
  # bucket and not after the policy on it - two resources Terraform is otherwise free to create in
  # either order. The template had this edge; it is kept because it is load bearing (rules.md D-1).
  depends_on = [aws_s3_bucket_policy.logs_bucket_policy]
}
