# A KakaoTalk chatbot skill on Lambda: a skill function behind a public Lambda function URL, which answers Kakao
# within its five-second limit by asking for a callback and invokes a callback function asynchronously. The
# callback function translates the utterance to English and draws it with Stable Image Core on Bedrock, and
# posts the answer to the callback URL Kakao sent.
#
# The _monolithic conversion of the SAM template (_monolithic/template.yaml) could not have worked. It dropped
# the template's Globals - the timeout, the memory and every environment variable, including the
# CALLBACK_LAMBDA_FUNCTION_NAME the skill function invokes - and pointed both functions' filename at the source
# directory, which Lambda cannot take. Its function URL had no resource policy, so it answered every request
# with 403. And its layer pointed at a layer.zip that is not in the repository. Each is fixed in the module that
# now owns it.
data "aws_partition" "current" {}
data "aws_region" "current" {}
locals {
  region = data.aws_region.current.region
}
# The packages callback.py imports beyond the runtime, built inside AWS for the runtime it runs on (see the
# module). The skill function needs none: app.py imports json, os and boto3.
module "layer" {
  source = "./modules/python_lambda_layer"

  layer_name            = "${var.project_name}-layer"
  description           = "Python packages for the ${var.project_name} callback function"
  requirements          = var.layer_requirements
  runtime               = var.lambda_runtime
  log_retention_in_days = var.log_retention_in_days
}
# Where the generated images go, public so Kakao can show them by URL (see the module).
module "image_bucket" {
  source = "./modules/public_image_bucket"

  bucket_prefix   = "${substr(var.project_name, 0, 28)}-images-"
  expiration_days = var.image_expiration_days
}
# The function that does the work, invoked asynchronously by the skill function with the utterance and Kakao's
# callback URL.
module "callback_function" {
  source = "./modules/python_lambda_function"

  function_name         = "${var.project_name}-callback"
  description           = "Kakao Chatbot Callback Function"
  source_dir            = "${path.root}/src"
  handler               = "callback.lambda_handler"
  runtime               = var.lambda_runtime
  timeout               = var.function_timeout
  memory_size           = var.function_memory_size
  layers                = [module.layer.layer_version_arn]
  log_retention_in_days = var.log_retention_in_days
  environment = {
    BEDROCK_MODEL_ID             = var.bedrock_model_id
    BEDROCK_REGION               = var.bedrock_region
    TEXT_TO_IMAGE_S3_BUCKET_NAME = module.image_bucket.bucket_name
    # The S3 bucket remains in the stack's deployment Region, independently of the Bedrock model Region.
    AWS_REGION_NAME = local.region
  }
  inline_policies = {
    invoke_model = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid    = "InvokeModel"
        Effect = "Allow"
        Action = "bedrock:InvokeModel"
        # Stable Image Core is directly invoked in its tested us-west-2 Region. The Lambda and image bucket
        # remain in the deployment Region, and no inference-profile or model wildcard is needed.
        Resource = "arn:${data.aws_partition.current.partition}:bedrock:${var.bedrock_region}::foundation-model/${var.bedrock_model_id}"
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
# The skill: Kakao's chatbot calls it with the user's utterance and a callback URL, and it has five seconds to
# answer. It answers useCallback, invokes the callback function with InvocationType Event and returns.
module "chatbot_function" {
  source = "./modules/python_lambda_function"

  function_name         = "${var.project_name}-chatbot"
  description           = "Kakao Chatbot Function"
  source_dir            = "${path.root}/src"
  handler               = "app.lambda_handler"
  runtime               = var.lambda_runtime
  timeout               = var.function_timeout
  memory_size           = var.function_memory_size
  log_retention_in_days = var.log_retention_in_days
  # From the module that named the function, so the two cannot disagree (rules.md B-5).
  environment = {
    CALLBACK_LAMBDA_FUNCTION_NAME = module.callback_function.function_name
  }
  # The one function it invokes, where the SAM template granted lambda:InvokeFunction and the deprecated
  # lambda:InvokeAsync on every function in the account.
  inline_policies = {
    invoke_callback = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid      = "InvokeCallback"
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = module.callback_function.function_arn
      }]
    })
  }
}
# The skill URL Kakao calls: the skill function's own URL, with no authentication, as the SAM template's
# FunctionUrlConfig had it - and CORS for any origin and method, also as it had it, though Kakao's servers are
# not a browser and do not need it.
module "skill_url" {
  source = "./modules/lambda_function_url"

  function_name = module.chatbot_function.function_name
  invoke_mode   = "BUFFERED"
  cors = {
    allow_origins = ["*"]
    allow_methods = ["*"]
  }
}
locals {
  skill_url = module.skill_url.url
}
