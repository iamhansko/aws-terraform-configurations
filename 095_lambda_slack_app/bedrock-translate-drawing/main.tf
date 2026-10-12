# A Slack app on Lambda, written with Bolt for Python: one function behind a REST API that serves Slack's event
# subscription, the OAuth install page and the OAuth redirect, with the OAuth state and the installations kept
# in two S3 buckets. It acknowledges an app mention immediately, translates its prompt to English, draws it
# with Stable Image Core on Bedrock and posts the image in the original thread through a lazy invocation.
#
# The _monolithic conversion of the SAM template (_monolithic/template.yaml) could not have worked. It dropped
# the template's Globals - the timeout, the memory and every environment variable, the Slack credentials and the
# bucket names included - and the function's three Api events, so there was no API at all; it pointed filename
# at the source directory, which Lambda cannot take; and its layer pointed at a layer.zip that is not in the
# repository. Each is fixed in the module that now owns it.
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
locals {
  region        = data.aws_region.current.region
  function_name = "${var.project_name}-function"
  # Bucket names are capped at 63 characters and the generated suffix takes 26, so the prefixes are cut from a
  # stem rather than from the whole project name.
  bucket_stem = substr(var.project_name, 0, 24)
}
module "layer" {
  source = "./modules/python_lambda_layer"

  layer_name            = "${var.project_name}-layer"
  description           = "Python packages for the ${var.project_name} Slack app"
  requirements          = var.layer_requirements
  runtime               = var.lambda_runtime
  log_retention_in_days = var.log_retention_in_days
}
# Bolt's LambdaS3OAuthFlow keeps the state of each install in progress in one bucket and every completed
# installation - bot token included - in the other.
module "oauth_state_bucket" {
  source = "./modules/private_bucket"

  bucket_prefix = "${local.bucket_stem}-state-"
}
module "installation_bucket" {
  source = "./modules/private_bucket"

  bucket_prefix = "${local.bucket_stem}-install-"
}
# Where the generated images go, public so Slack can show them by URL (see the module).
module "image_bucket" {
  source = "./modules/public_image_bucket"

  bucket_prefix   = "${local.bucket_stem}-images-"
  expiration_days = var.image_expiration_days
}
module "slack_app_function" {
  source = "./modules/python_lambda_function"

  function_name         = local.function_name
  description           = "Slack App Function"
  source_dir            = "${path.root}/src"
  handler               = "app.lambda_handler"
  runtime               = var.lambda_runtime
  timeout               = var.function_timeout
  memory_size           = var.function_memory_size
  layers                = [module.layer.layer_version_arn]
  log_retention_in_days = var.log_retention_in_days
  environment = {
    SLACK_CLIENT_ID              = var.slack_client_id
    SLACK_CLIENT_SECRET          = var.slack_client_secret
    SLACK_SIGNING_SECRET         = var.slack_signing_secret
    OAUTH_STATE_S3_BUCKET_NAME   = module.oauth_state_bucket.bucket_name
    INSTALLATION_S3_BUCKET_NAME  = module.installation_bucket.bucket_name
    BEDROCK_MODEL_ID             = var.bedrock_model_id
    BEDROCK_REGION               = var.bedrock_region
    TEXT_TO_IMAGE_S3_BUCKET_NAME = module.image_bucket.bucket_name
    # AWS_REGION_NAME rather than AWS_REGION, which Lambda reserves; app.py builds the image URL from the S3
    # bucket's deployment region, independently of BEDROCK_REGION.
    AWS_REGION_NAME = local.region
  }
  inline_policies = {
    # The two OAuth buckets, bucket and objects, and nothing else. The SAM template listed seven actions,
    # among them GetObjectAcl, PutObjectAcl and ReplicateObject, which Bolt never calls - the buckets enforce
    # bucket ownership, so ACLs do not apply.
    #
    # Its ListBucket was granted on the objects only, where ListBucket does not apply, so a missing
    # installation read as AccessDenied rather than NoSuchKey.
    oauth_storage = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid      = "ListOAuthBuckets"
          Effect   = "Allow"
          Action   = "s3:ListBucket"
          Resource = [module.oauth_state_bucket.bucket_arn, module.installation_bucket.bucket_arn]
        },
        {
          Sid      = "ReadWriteOAuthObjects"
          Effect   = "Allow"
          Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
          Resource = ["${module.oauth_state_bucket.bucket_arn}/*", "${module.installation_bucket.bucket_arn}/*"]
        },
      ]
    })
    invoke_model = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid    = "InvokeModel"
        Effect = "Allow"
        Action = "bedrock:InvokeModel"
        # The function directly invokes only the tested Stable Image Core model in its pinned Bedrock region;
        # no inference profile, cross-region wildcard or additional Bedrock action is needed.
        Resource = "arn:${data.aws_partition.current.partition}:bedrock:${var.bedrock_region}::foundation-model/${var.bedrock_model_id}"
      }]
    })
    # Bolt's lazy listeners on Lambda: the function acknowledges Slack within its three seconds, then invokes
    # itself asynchronously to run the handler. Itself only, where the SAM template allowed invoking every
    # function in the account. The ARN is built from the name because the function cannot reference its own
    # attribute.
    invoke_self = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid      = "InvokeSelfForLazyListeners"
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = "arn:${data.aws_partition.current.partition}:lambda:${local.region}:${data.aws_caller_identity.current.account_id}:function:${local.function_name}"
      }]
    })
    # Korean to English before the image model sees the prompt. TranslateText has no resource-level scoping.
    translate_text = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid      = "TranslateText"
        Effect   = "Allow"
        Action   = "translate:TranslateText"
        Resource = "*"
      }]
    })
    # The one write the function makes, into the one bucket - where the SAM template granted s3:* on "*", which
    # reached every bucket in the account.
    put_image = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid      = "PutImage"
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "${module.image_bucket.bucket_arn}/*"
      }]
    })
  }
}
# The three endpoints the SAM template's Api events declared on its implicit API: Slack posts events to
# /slack/events, and the OAuth install flow starts at /slack/install and returns to /slack/oauth_redirect.
module "slack_api" {
  source = "./modules/lambda_rest_api"

  name        = "${var.project_name}-api"
  description = "Slack app endpoints for ${var.project_name}"
  stage_name  = var.api_stage_name
  routes = {
    events = {
      path        = "slack/events"
      http_method = "POST"
    }
    oauth_redirect = {
      path        = "slack/oauth_redirect"
      http_method = "GET"
    }
    install = {
      path        = "slack/install"
      http_method = "GET"
    }
  }
  function_name       = module.slack_app_function.function_name
  function_invoke_arn = module.slack_app_function.invoke_arn
}
