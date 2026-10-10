# The workshop web app: an Express app on Lambda behind the Lambda Web Adapter, with a REST API that proxies
# every path to it - the static pages under public/ and the /callback page the user pool redirects to.
#
# This is the workshop's cognito-web SAM template, written as the resources SAM expanded it into: the
# AWS::Serverless::Function with its implicit execution role, and the implicit ServerlessRestApi its two Api
# events (RootPath, AnyPath) created, with its Prod stage and the invoke permission. Two of SAM's implicit
# resources are not reproduced. The second stage, named Stage, that an implicit API carries when the template
# does not set OpenApiVersion, served the same app at a URL nothing used; and the deployment bucket
# sam deploy --resolve-s3 kept in a shared stack (aws-sam-cli-managed-default) is this module's package
# bucket, deleted with everything else.
#
# What SAM did that Terraform cannot is the build - npm install, and the front-end bundle that has the user
# pool's IDs compiled into it. The workbench does that (cognito-web/deploy.sh) and uploads the package to the
# bucket here; the caller passes the package's checksum back in, which is also what holds the function until
# the package exists - as long as the caller does not read that checksum before the upload, which is the
# caller's wait to get right (the root waits on S3 itself, not on the build's SSM association).
data "aws_region" "current" {}
locals {
  # The name the SAM template gave the function, ${AWS::StackName}-CognitoWebApp, with the stack name now the
  # caller's.
  function_name = "${var.name}-CognitoWebApp"
}
# --- Package ------------------------------------------------------------------------------------------------
resource "aws_s3_bucket" "package" {
  bucket_prefix = "${substr(lower(var.name), 0, 30)}-pkg-"
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
# --- Function -----------------------------------------------------------------------------------------------
#
# The role SAM generates for a function that names none: Lambda may assume it, and it carries
# AWSLambdaBasicExecutionRole and nothing else.
resource "aws_iam_role" "function" {
  name_prefix = "${substr(local.function_name, 0, 37)}-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "function" {
  role       = aws_iam_role.function.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
# Terraform's, so it is deleted with the function. Under SAM, Lambda created it on the first invocation and
# deleting the stack left it behind.
resource "aws_cloudwatch_log_group" "function" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_in_days
}
resource "aws_lambda_function" "function" {
  function_name = local.function_name
  role          = aws_iam_role.function.arn
  s3_bucket     = aws_s3_bucket.package.id
  s3_key        = var.package_key
  # Compared with the CodeSha256 Lambda reports, so a deploy.sh run on the workbench, which points the function
  # at a new package in the same place, is what the next plan sees too - not drift to revert.
  code_sha256 = var.package_sha256
  # The Lambda Web Adapter's wrapper starts run.sh, which starts the Express app, and forwards each invocation
  # to it as an HTTP request. run.sh is the handler in name only.
  handler       = "run.sh"
  runtime       = var.runtime
  memory_size   = var.memory_size
  timeout       = var.timeout
  architectures = ["x86_64"]
  # Published by AWS from its own account in every commercial region, under the same version numbers. The x86
  # build, matching architectures.
  layers = ["arn:aws:lambda:${data.aws_region.current.region}:753240598075:layer:LambdaAdapterLayerX86:${var.lambda_adapter_layer_version}"]
  environment {
    variables = {
      AWS_LAMBDA_EXEC_WRAPPER = "/opt/bootstrap"
      RUST_LOG                = "info"
    }
  }
  # The role's policy and the log group have to exist before the first invocation (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.function, aws_cloudwatch_log_group.function]
}
# --- API ----------------------------------------------------------------------------------------------------
#
# Edge-optimised, the endpoint type SAM's implicit API has when the template does not name one.
resource "aws_api_gateway_rest_api" "api" {
  name        = var.name
  description = "Amazon Cognito Workshop web app"
  endpoint_configuration {
    types = ["EDGE"]
  }
}
resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "{proxy+}"
}
locals {
  # The SAM function's two Api events: ANY on / (RootPath) and ANY on everything below it (AnyPath). Literal
  # keys, so the methods below can for_each over resource IDs that are unknown until apply (rules.md B-8).
  resource_ids = {
    root  = aws_api_gateway_rest_api.api.root_resource_id
    proxy = aws_api_gateway_resource.proxy.id
  }
}
resource "aws_api_gateway_method" "any" {
  for_each      = local.resource_ids
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = each.value
  http_method   = "ANY"
  authorization = "NONE"
}
# Lambda proxy integrations, which Lambda is always called through with POST whatever the client's method.
resource "aws_api_gateway_integration" "function" {
  for_each                = aws_api_gateway_method.any
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = each.value.resource_id
  http_method             = each.value.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.function.invoke_arn
}
# One permission for both events, where SAM added one per event. Any stage, method and path of this API - the
# console's test invocations included, which run outside the stage.
resource "aws_lambda_permission" "api" {
  statement_id  = "AllowApiGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}
resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  # A deployment is a snapshot, so a change to a method or an integration reaches the stage only through a new
  # one. A new function package does not need one: the integrations name the function, not a version.
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.proxy.id,
      aws_api_gateway_method.any,
      aws_api_gateway_integration.function,
    ]))
  }
  lifecycle {
    create_before_destroy = true
  }
  # The integrations, not only the methods: a deployment of a method with no integration yet is rejected with
  # "No integration defined for method".
  depends_on = [aws_api_gateway_integration.function]
}
resource "aws_api_gateway_stage" "stage" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = var.stage_name
  deployment_id = aws_api_gateway_deployment.deployment.id
}
