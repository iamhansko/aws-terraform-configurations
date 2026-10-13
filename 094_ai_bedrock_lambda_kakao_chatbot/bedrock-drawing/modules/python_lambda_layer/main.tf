# A Python Lambda layer built from pinned pip requirements, inside AWS, as part of terraform apply.
#
# The SAM template published ./layer.zip, a package its README said to build by hand (pip install into
# layer/python, zip it). The zip is not in this repository, so the _monolithic conversion pointed archive_file at
# a path that did not exist and could not plan. And the README's command would have built the wrong thing on
# most machines: pip install --platform manylinux2014_x86_64 without --python-version fetches wheels for the
# Python running pip, so a compiled dependency built for 3.13 or 3.14 fails to import on the function's 3.12.
#
# Here a small builder function, on the same runtime and architecture as the functions that use the layer,
# runs pip and uploads the package; aws_lambda_invocation runs it once, and again when the requirements change;
# the layer version is published from what it uploaded. Nothing has to be installed where terraform runs.
locals {
  # One name stem for everything the module creates.
  stem        = substr(var.layer_name, 0, 40)
  package_key = "layers/${var.layer_name}.zip"
}
# --- Package bucket -----------------------------------------------------------------------------------------
resource "aws_s3_bucket" "package" {
  # Bucket names take no uppercase letters or underscores, which a layer name can have. 32 characters and a
  # hyphen leave room for the 26 Terraform appends within the 63 S3 allows.
  bucket_prefix = "${replace(lower(substr(var.layer_name, 0, 32)), "_", "-")}-"
  # The package is written by the builder, not by Terraform, so without this terraform destroy stops at
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
# --- Builder ------------------------------------------------------------------------------------------------
data "archive_file" "builder" {
  type        = "zip"
  source_file = "${path.module}/builder/index.py"
  output_path = "${path.module}/build/${var.layer_name}-builder.zip"
}
resource "aws_iam_role" "builder" {
  name_prefix = "${substr(local.stem, 0, 29)}-builder-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "builder_basic_execution" {
  role       = aws_iam_role.builder.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
# Writes the one package object and nothing else.
resource "aws_iam_role_policy" "builder_upload" {
  name = "UploadLayerPackage"
  role = aws_iam_role.builder.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "s3:PutObject"
      Resource = "${aws_s3_bucket.package.arn}/${local.package_key}"
    }]
  })
}
resource "aws_cloudwatch_log_group" "builder" {
  name              = "/aws/lambda/${local.stem}-builder"
  retention_in_days = var.log_retention_in_days
}
resource "aws_lambda_function" "builder" {
  function_name    = "${local.stem}-builder"
  description      = "Builds the ${var.layer_name} layer package with pip"
  role             = aws_iam_role.builder.arn
  filename         = data.archive_file.builder.output_path
  source_code_hash = data.archive_file.builder.output_base64sha256
  handler          = "index.lambda_handler"
  runtime          = var.runtime
  architectures    = [var.architecture]
  # pip resolves and downloads the whole dependency tree in one invocation; langchain-aws and its
  # dependencies take most of a minute and a few hundred megabytes of /tmp.
  memory_size = var.builder_memory_size
  timeout     = var.builder_timeout
  ephemeral_storage {
    size = var.builder_ephemeral_storage_size
  }
  # The upload permission and the log group have to exist before the invocation below (rules.md D-1).
  depends_on = [
    aws_iam_role_policy_attachment.builder_basic_execution,
    aws_iam_role_policy.builder_upload,
    aws_cloudwatch_log_group.builder,
  ]
}
# The build. Runs on create and whenever the requirements or the builder change - input and triggers are what
# replace this resource - and not on an unchanged apply. A failed pip install fails the apply, with pip's own
# message.
resource "aws_lambda_invocation" "build" {
  function_name = aws_lambda_function.builder.function_name
  input = jsonencode({
    requirements = var.requirements
    bucket       = aws_s3_bucket.package.id
    key          = local.package_key
  })
  triggers = {
    builder = data.archive_file.builder.output_base64sha256
  }
  # The bucket's ownership controls and public access block are separate calls made after the bucket exists.
  # Ordering the upload after them means the package is written into the bucket as configured, which the bucket
  # name in the input does not imply (rules.md D-1).
  depends_on = [aws_s3_bucket_ownership_controls.package, aws_s3_bucket_public_access_block.package]
}
locals {
  build = jsondecode(aws_lambda_invocation.build.result)
}
resource "aws_lambda_layer_version" "layer" {
  layer_name               = var.layer_name
  description              = var.description
  s3_bucket                = local.build.bucket
  s3_key                   = local.build.key
  source_code_hash         = local.build.sha256
  compatible_runtimes      = [var.runtime]
  compatible_architectures = [var.architecture]
  lifecycle {
    # A new package publishes the next version before the old one is deleted, so the functions are moved to the
    # new ARN while the version they still name exists.
    create_before_destroy = true
  }
}
