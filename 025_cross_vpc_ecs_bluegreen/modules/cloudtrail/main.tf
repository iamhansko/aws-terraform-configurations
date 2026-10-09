# The trail exists for one reason: S3 does not publish data-plane events to EventBridge by itself,
# so without it the EventBridge rules in the application stacks never fire and nothing starts a
# pipeline. It is not here for auditing, which is why its event selector records write-only data
# events on exactly the objects that matter and nothing else.
resource "aws_s3_bucket" "logs_bucket" {
  # A generated name. The _monolithic template declared this bucket with no arguments at all, so
  # the provider generated one anyway - a prefix at least says what it is in a bucket listing.
  bucket_prefix = var.logs_bucket_prefix
  # CloudTrail writes a log file every few minutes whether or not anything happened, so this bucket
  # is never empty by the time a destroy reaches it. Without force_destroy that destroy stops with
  # BucketNotEmpty - which the _monolithic template would have hit, since it set nothing here.
  force_destroy = var.force_destroy
  tags = {
    Name = var.logs_bucket_prefix
  }
}
# The policy CloudTrail requires before it will accept the bucket. Both statements are necessary
# and they are not interchangeable: GetBucketAcl on the bucket is how CloudTrail checks it may
# write, and PutObject under the account prefix is the write itself.
#
# The aws:SourceArn conditions are what stop this bucket from being usable by a trail in another
# account - the confused deputy shape that CloudTrail's own documentation describes. They name the
# trail ARN, which is assembled from the trail name rather than taken from the resource below,
# because the trail depends on this policy and cannot also be referenced by it.
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
locals {
  trail_arn = "arn:${var.partition}:cloudtrail:${var.region}:${var.account_id}:trail/${var.trail_name}"
}
resource "aws_cloudtrail" "cloud_trail" {
  name           = var.trail_name
  s3_bucket_name = aws_s3_bucket.logs_bucket.id
  enable_logging = true
  # Management events off: nothing here reads them, and leaving them on means a log file for every
  # API call in the region. The _monolithic template left the default on, so this trail recorded
  # the whole account to pick up two PutObject calls.
  event_selector {
    read_write_type           = "WriteOnly"
    include_management_events = var.include_management_events
    data_resource {
      type = "AWS::S3::Object"
      # One entry per stack's artefact object, built in the stack module so the bucket and the key
      # stay together (rules.md B-5). An object-level ARN rather than a bucket-level one: a
      # bucket-level selector would record every write to the bucket, including the pipeline's own
      # artefacts, and each of those would start another pipeline run.
      values = var.data_resource_object_arns
    }
  }

  # The policy before the trail, and this one is not a precaution.
  #
  # CreateTrail validates the bucket policy synchronously and rejects a bucket it cannot write to
  # with InsufficientS3BucketPolicyException. The trail names the bucket by id, which orders it
  # after the bucket and not after the policy on it - two resources that Terraform is otherwise
  # free to create in either order. The _monolithic template had no edge here at all, so whether
  # its apply worked depended on which of the two the provider happened to start first
  # (rules.md D-1).
  depends_on = [aws_s3_bucket_policy.logs_bucket_policy]
}
