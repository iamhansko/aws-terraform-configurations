locals {
  # ** is required: a single * only matches entries at the top level of
  # source_dir, so a tree like src/1/1-1.txt would produce an empty set.
  # fileset returns paths relative to source_dir, which is exactly the shape
  # needed both for the S3 key and for the path inside the deployment package.
  matched  = fileset(var.source_dir, var.file_pattern)
  excluded = toset(flatten([for pattern in var.exclude_patterns : tolist(fileset(var.source_dir, pattern))]))
  selected = setsubtract(local.matched, local.excluded)

  # The manifest travels in the invocation payload rather than being baked into
  # the zip, so changing a content type re-invokes the function without
  # rebuilding (and re-uploading) the package.
  objects = [
    for relative_path in sort(tolist(local.selected)) : {
      key  = "${var.key_prefix}${relative_path}"
      path = relative_path
      # Without an explicit type S3 stores everything as binary/octet-stream,
      # which makes browsers download files instead of rendering them.
      content_type = lookup(var.content_types, lower(regex("[^.]*$", relative_path)), var.default_content_type)
    }
  ]

  # Read once into a local so the archive's source block and the tab precondition
  # below it both work from the same bytes.
  handler_source = file("${path.module}/lambda_src/lambda_function/index.py")

  # Re-invocation trigger. The archive's own hash would not be enough on its own,
  # because a file whose bytes change but whose base64 length stays identical
  # still has to be re-synced - hashing the source files directly is the direct
  # signal.
  payload_hash = sha256(join("", [for relative_path in sort(tolist(local.selected)) : filemd5("${var.source_dir}/${relative_path}")]))
}
# Bundles the handler and the whole source tree into one package, so the function
# has the directory on local disk and needs no staging bucket to fetch it from.
#
# Payload entries are base64-encoded because archive_file's `source` blocks take
# a string: passing raw file() output would corrupt any file that is not valid
# UTF-8, while base64 round-trips arbitrary bytes at a 33% size cost. The handler
# decodes each entry before uploading.
data "archive_file" "lambda_function" {
  type        = "zip"
  output_path = "${path.module}/build/lambda_function.zip"

  source {
    content  = local.handler_source
    filename = "index.py"
  }

  dynamic "source" {
    for_each = local.selected
    content {
      content  = filebase64("${var.source_dir}/${source.value}")
      filename = "${var.payload_directory_name}/${source.value}"
    }
  }

  lifecycle {
    # Terraform cannot compile the handler, but it can catch the one syntax
    # error that this packaging style hides until the very end: Python rejects a
    # file that mixes tabs and spaces for indentation, and that rejection happens
    # at import time inside Lambda. The failure therefore surfaces as a
    # Runtime.UserCodeSyntaxError from aws_lambda_invocation, after the function,
    # role, log group and bucket have all been created - an editor silently
    # reindenting part of the handler costs a whole apply cycle. Failing the plan
    # instead keeps that feedback immediate.
    precondition {
      condition     = !can(regex("\t", local.handler_source))
      error_message = "lambda_src/lambda_function/index.py contains a tab character. Python raises TabError (\"inconsistent use of tabs and spaces in indentation\") at import time, which Lambda reports as Runtime.UserCodeSyntaxError when the function is invoked. Indent the handler with two spaces throughout."
    }
  }
}
resource "aws_iam_role" "lambda_function_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_role_policy" "lambda_function_iam_role" {
  name = "S3Sync"
  role = aws_iam_role.lambda_function_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # ListBucket is on the bucket itself, not its contents, and is what makes
        # the sync a sync: without it the function cannot tell which objects
        # already exist and would re-upload everything on every invocation.
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = var.bucket_arn
        Condition = {
          StringLike = {
            "s3:prefix" = ["${var.key_prefix}*"]
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = "${var.bucket_arn}/${var.key_prefix}*"
      },
    ]
  })
}
resource "aws_iam_role_policy_attachment" "lambda_function_iam_role" {
  role       = aws_iam_role.lambda_function_iam_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
data "aws_partition" "current" {}
# Declared explicitly rather than letting Lambda create it on first invocation,
# so the retention is bounded and terraform destroy takes the logs with it.
resource "aws_cloudwatch_log_group" "lambda_function" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_in_days
}
resource "aws_lambda_function" "lambda_function" {
  function_name    = var.function_name
  runtime          = var.runtime
  handler          = "index.handler"
  role             = aws_iam_role.lambda_function_iam_role.arn
  timeout          = var.timeout
  memory_size      = var.memory_size
  filename         = data.archive_file.lambda_function.output_path
  source_code_hash = data.archive_file.lambda_function.output_base64sha256
  environment {
    variables = {
      PAYLOAD_DIRECTORY = var.payload_directory_name
    }
  }
  # The role must already carry its policies before the first invocation, and
  # role_arn alone does not order this after them. The log group has to exist
  # first too, or Lambda creates an unmanaged one that Terraform then fights
  # over.
  depends_on = [
    aws_iam_role_policy.lambda_function_iam_role,
    aws_iam_role_policy_attachment.lambda_function_iam_role,
    aws_cloudwatch_log_group.lambda_function,
  ]
}
resource "aws_lambda_invocation" "s3_sync" {
  function_name = aws_lambda_function.lambda_function.function_name

  # CRUD rather than the default CREATE_ONLY, so the function also runs on
  # update and on destroy. It makes the provider inject a "tf" key holding
  # action (create/update/delete) and prev_input, which is what lets the handler
  # clean the objects up on terraform destroy - the piece a plain
  # CREATE_ONLY invocation leaves orphaned in the bucket.
  lifecycle_scope = "CRUD"

  input = jsonencode({
    bucket            = var.bucket
    key_prefix        = var.key_prefix
    objects           = local.objects
    delete_removed    = var.delete_removed
    delete_on_destroy = var.delete_on_destroy
  })

  # input already changes whenever a file is added or removed, but not when an
  # existing file's contents change - the manifest carries no hash. These
  # triggers cover that, and cover the handler itself changing.
  triggers = {
    payload_hash  = local.payload_hash
    function_hash = data.archive_file.lambda_function.output_base64sha256
  }
}
