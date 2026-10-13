# A KakaoTalk chatbot skill on Lambda: a skill function behind a REST API at /<stage>/kakao, which answers Kakao
# within its five-second limit by asking for a callback and invokes a callback function asynchronously. The
# callback function echoes the utterance back after five seconds, and posts the answer to the callback URL Kakao
# sent.
#
# The _monolithic conversion of the SAM template (_monolithic/template.yaml) could not have worked. It dropped
# the template's Globals - the timeout, the memory and every environment variable, including the
# CALLBACK_LAMBDA_FUNCTION_NAME the skill function invokes - and pointed both functions' filename at the source
# directory, which Lambda cannot take. Its API had no resource, method, deployment or stage: the Skill event was
# not converted, and StageName and OpenApiVersion became TODO comments. And its layer pointed at a layer.zip
# that is not in the repository. Each is fixed in the module that now owns it.
#
# Also not reproduced: the text-to-image bucket, which the SAM template declared - public, with a public-read
# policy - in every top-level variant whether its code drew anything or not. This one does not draw, so it has
# no bucket.
data "aws_caller_identity" "current" {}
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
  # Nothing beyond its logs: callback.py sleeps and posts the utterance back. The SAM template granted it
  # lambda:InvokeFunction on every function in the account, and bedrock:*, translate:* and s3:* on "*" -
  # none of which it calls.
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
# The skill URL Kakao calls: ANY /<stage>/<skill_path>, as the SAM template's Skill event declared it.
module "skill_api" {
  source = "./modules/lambda_rest_api"

  name        = "${var.project_name}-api"
  description = "Kakao chatbot skill for ${var.project_name}"
  stage_name  = var.api_stage_name
  routes = {
    skill = {
      path        = var.skill_path
      http_method = "ANY"
    }
  }
  function_name       = module.chatbot_function.function_name
  function_invoke_arn = module.chatbot_function.invoke_arn
  api_key_required    = false
}
locals {
  skill_url = module.skill_api.route_urls["skill"]
}
