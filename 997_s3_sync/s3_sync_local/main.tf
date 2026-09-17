module "s3_bucket" {
  source = "./modules/s3_bucket"

  bucket_name        = var.bucket_name
  bucket_name_prefix = var.bucket_name_prefix
  force_destroy      = var.force_destroy
}

module "s3_sync_local" {
  source = "./modules/s3_sync_local"

  bucket            = module.s3_bucket.bucket
  source_dir        = "${path.root}/${var.source_dir}"
  key_prefix        = var.key_prefix
  delete_removed    = var.delete_removed
  delete_on_destroy = var.delete_on_destroy
  exclude_patterns  = var.exclude_patterns
  aws_region        = var.aws_region

  # The bucket (and its encryption/ownership/public-access settings) must
  # exist before the local-exec provisioner's `aws s3 sync` call runs
  # against it; module.s3_bucket.bucket alone only orders this after the
  # aws_s3_bucket resource itself, not the bucket's other sub-resources
  # (rules.md D-3's reasoning applied to a bucket instead of network).
  depends_on = [module.s3_bucket]
}
