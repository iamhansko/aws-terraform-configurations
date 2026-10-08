# An S3 bucket configured as a website, which is what this project puts CloudFront in front of.
#
# The website endpoint rather than the REST endpoint, and that choice drives everything awkward about this
# module, so it is worth stating plainly. The website endpoint is the only one that resolves a request for
# /docs/ to /docs/index.html; the REST endpoint returns a 404 for it. A static site with subdirectories
# therefore either uses the website endpoint or adds a CloudFront Function to rewrite the path.
#
# The cost is that the website endpoint speaks HTTP only and has no authentication. It cannot be paired with
# Origin Access Control, so the bucket policy has to allow anonymous reads - which means the distribution in
# front of it can be bypassed by asking the website endpoint directly. required_referer is the documented
# mitigation for that, and the root sets it by default.
resource "aws_s3_bucket" "website" {
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
# The one place in this repository where these are deliberately false.
#
# block_public_policy has to be off because the policy below names Principal "*" - S3 rejects the policy
# outright otherwise. The other three are off for the same underlying reason: the website endpoint serves
# anonymous requests or it serves nothing.
#
# This is the security consequence of the origin type, not an oversight, and it is why required_referer
# exists. A bucket that is not fronting a website endpoint should have all four of these true.
resource "aws_s3_bucket_public_access_block" "website" {
  bucket                  = aws_s3_bucket.website.id
  block_public_acls       = true
  block_public_policy     = false
  ignore_public_acls      = true
  restrict_public_buckets = false
}
# Object ownership enforced, so the bucket has no ACLs at all and the only thing granting access is the
# policy below. The _monolithic template left this at the provider default and relied on the policy too,
# but silently - with ACLs still available there were two mechanisms and only one of them was written down.
resource "aws_s3_bucket_ownership_controls" "website" {
  bucket = aws_s3_bucket.website.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "website" {
  bucket = aws_s3_bucket.website.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      merge(
        {
          Sid       = "PublicReadGetObject"
          Effect    = "Allow"
          Principal = "*"
          Action    = "s3:GetObject"
          Resource  = "${aws_s3_bucket.website.arn}/*"
        },
        # With a referer required, the statement still names Principal "*" - the website endpoint cannot
        # authenticate, so there is no principal to name - but it only applies to requests carrying the
        # secret. Without it, the statement is the _monolithic template's: anyone, any request.
        var.required_referer == null ? {} : {
          Condition = {
            StringEquals = {
              "aws:Referer" = var.required_referer
            }
          }
        },
      ),
    ]
  })

  # The policy is public, so it cannot be written while block_public_policy is still true. Referencing the
  # bucket id orders this after the bucket but not after that setting (rules.md D-1).
  depends_on = [aws_s3_bucket_public_access_block.website]
}
resource "aws_s3_object" "content" {
  for_each = var.objects

  bucket  = aws_s3_bucket.website.id
  key     = each.key
  content = each.value
  # Without an explicit type S3 stores application/octet-stream and a browser downloads the file instead of
  # rendering it, which looks like a broken site rather than a missing header. The lookup falls back to
  # text/plain rather than to octet-stream for the same reason.
  content_type = lookup(var.content_types, lower(reverse(split(".", each.key))[0]), "text/plain")
  # So that a changed body is a changed object rather than a no-op: without this the provider compares the
  # etag it recorded, and content set inline has none until it is uploaded.
  etag = md5(each.value)
}
