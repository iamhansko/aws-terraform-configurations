# An S3 bucket configured as a website, serving the escape-room game directly to a browser.
#
# Started from the reviewed module in 097_cloudfront_s3_static_website and then diverged, because the two
# projects put different things in front of the bucket (rules.md A-1 - the copy evolves on its own). What
# carried over is the reasoning about the website endpoint and about public access; what did not is
# everything that only makes sense with a distribution in front:
#
#   - no required_referer. In 097 that secret header is what stops a caller bypassing CloudFront. Here
#     there is no CloudFront to bypass - the website endpoint *is* the site - so a referer condition would
#     lock out the browser it is meant to serve.
#   - no objects/content_types inputs. In 097 Terraform writes the two pages. Here the content is a zip
#     released on GitHub, unpacked onto the bucket by the seeder instance at boot, so the objects are not
#     Terraform's and the module does not pretend otherwise.
#
# The website endpoint rather than the REST endpoint, and that choice drives everything awkward below. The
# website endpoint is the only one that resolves a request for / to /index.html; the REST endpoint returns
# a 404 for it. The cost is that it speaks HTTP only and has no authentication of any kind, so serving
# through it means the objects are readable by anyone who knows the hostname. For this project that is the
# intent - it is a public game - but it is a consequence of the origin type, not an oversight.
resource "aws_s3_bucket" "website" {
  # A prefix rather than a fixed name. Bucket names are globally unique, so a literal name collides with a
  # second copy of this project and with everyone else in the world. The _monolithic template sidestepped
  # this by declaring `resource "aws_s3_bucket" "s3_bucket" {}` with no name at all and letting the
  # provider invent one - which works, and produces a bucket called terraform-<hex> that tells nobody what
  # it holds.
  bucket_prefix = var.name_prefix
  force_destroy = var.force_destroy
}
resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.website.id
  index_document {
    suffix = var.index_document
  }
  dynamic "error_document" {
    for_each = var.error_document == null ? [] : [var.error_document]
    content {
      key = error_document.value
    }
  }
}
# The one place in this repository where some of these are deliberately false.
#
# block_public_policy has to be off because the policy below names Principal "*" - S3 rejects the
# PutBucketPolicy call outright otherwise, with AccessDenied, which looks like a credentials problem rather
# than a setting. restrict_public_buckets has to be off for the same underlying reason: with it on, S3
# ignores the public statement at request time and every anonymous GET returns 403 while the policy still
# reads as allowing it.
#
# The two ACL switches are true here and were false in the _monolithic template, which set all four to
# false. Nothing in this project uses an ACL: the seeder calls put_object with no ACL argument, and object
# ownership below removes ACLs from the bucket entirely. Leaving the ACL path open as well would mean two
# mechanisms could grant access and only one of them is written down.
resource "aws_s3_bucket_public_access_block" "website" {
  bucket                  = aws_s3_bucket.website.id
  block_public_acls       = true
  block_public_policy     = false
  ignore_public_acls      = true
  restrict_public_buckets = false
}
# Object ownership enforced, so the bucket has no ACLs at all and the only thing granting access is the
# policy below. The _monolithic template left this at the provider default and relied on the policy too,
# but silently.
resource "aws_s3_bucket_ownership_controls" "website" {
  bucket = aws_s3_bucket.website.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}
# Encryption at rest, which the _monolithic template did not configure. S3 applies SSE-S3 to new buckets by
# default now, so this changes nothing about the stored bytes - it states the setting so a plan shows it
# rather than leaving a reader to know the account-level default.
resource "aws_s3_bucket_server_side_encryption_configuration" "website" {
  bucket = aws_s3_bucket.website.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = var.sse_algorithm
    }
  }
}
# Anonymous read on every object, which is what makes the website endpoint serve anything at all.
#
# This is the _monolithic template's policy with its Sid and Id preserved in spirit; the statement is the
# same one. It grants s3:GetObject to Principal "*" on the whole bucket, which is as public as it sounds -
# the game, its images and the password hints are all readable by anyone who finds the hostname. The
# website endpoint cannot authenticate, so there is no narrower principal available.
resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id
  policy = jsonencode({
    Id      = var.policy_id
    Version = "2012-10-17"
    Statement = [{
      Sid       = var.policy_statement_id
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.website.arn}/*"
    }]
  })

  # The policy is public, so it cannot be written while block_public_policy is still true. Referencing the
  # bucket id orders this after the bucket but not after that setting, and the two creates otherwise race:
  # losing the race fails the apply with AccessDenied on PutBucketPolicy (rules.md D-1).
  depends_on = [aws_s3_bucket_public_access_block.website]
}
