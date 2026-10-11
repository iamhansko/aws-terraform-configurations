# A Lambda layer whose package is built somewhere Terraform does not run - on the workbench - and uploaded to
# the bucket here.
#
# The _monolithic template declared the layer with s3_key = "layer.zip" and nothing describing the package, so
# the layer version was created once and never again: a rebuilt package at the same key was invisible to every
# later plan. It also had nothing holding the layer until the upload had happened except a depends_on on an
# association whose 180 second budget had to cover a dnf update, and a bucket with no force_destroy that the
# uploaded object would have kept terraform destroy from deleting.
#
# Here the caller passes in the package's SHA-256 as S3 reports it. That value is what a new layer version is
# published for, and reading it is what waits for the upload - as long as the caller does not read it before
# the upload, which is the caller's wait to get right (the root waits on S3 itself, not on the build's SSM
# association).
resource "aws_s3_bucket" "package" {
  bucket_prefix = "${substr(lower(var.layer_name), 0, 30)}-pkg-"
  # The package is uploaded by the workbench, not by Terraform, so without this terraform destroy stops at
  # BucketNotEmpty.
  force_destroy = true
}
resource "aws_s3_bucket_public_access_block" "package" {
  bucket                  = aws_s3_bucket.package.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_ownership_controls" "package" {
  bucket = aws_s3_bucket.package.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}
resource "aws_lambda_layer_version" "layer" {
  layer_name  = var.layer_name
  description = var.description
  s3_bucket   = aws_s3_bucket.package.id
  s3_key      = var.package_key
  # Changing this publishes a new version, and the function that lists the layer moves to it. Lambda copies
  # the package when the version is published, so the bucket object is only needed at that moment.
  source_code_hash         = var.package_sha256
  compatible_runtimes      = var.compatible_runtimes
  compatible_architectures = var.compatible_architectures
  lifecycle {
    # Each version has its own ARN, so the new one can be published and the function moved to it before the
    # old one is deleted - rather than the function pointing at a deleted version in between.
    create_before_destroy = true
  }
}
