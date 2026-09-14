module "s3_bucket" {
  source = "./modules/s3_bucket"

  bucket_name        = var.bucket_name
  bucket_name_prefix = var.bucket_name_prefix
  force_destroy      = var.force_destroy
}

module "lambda_s3_sync" {
  source            = "./modules/lambda_s3_sync"
  bucket            = module.s3_bucket.bucket
  bucket_arn        = module.s3_bucket.bucket_arn
  source_dir        = "${path.root}/${var.source_dir}"
  key_prefix        = var.key_prefix
  function_name     = var.function_name
  delete_removed    = var.delete_removed
  delete_on_destroy = var.delete_on_destroy
  exclude_patterns  = var.exclude_patterns

  depends_on = [module.s3_bucket]
}
