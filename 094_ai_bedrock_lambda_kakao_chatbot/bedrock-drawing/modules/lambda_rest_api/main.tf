# A REST API whose routes are Lambda proxy integrations to one function, deployed to one stage, with an
# optional API key requirement.
#
# This is what an AWS::Serverless::Api and a function's Api events expand into under SAM. The _monolithic
# conversions kept the aws_api_gateway_rest_api and dropped the rest - StageName, OpenApiVersion and Auth became
# TODO comments, and the functions' Events were not converted at all - so they built an API with no resource,
# no method, no deployment and no stage, and a function nothing could call. The Lambda permission SAM adds
# for each event was missing too.
#
# One of SAM's implicit resources is not reproduced: the second stage named Stage that an API carries when the
# template does not set OpenApiVersion, as the Slack templates' implicit API did not. It served the same routes
# at a URL nothing used.
locals {
  # Each route's path split into its segments. One or two levels, which is what the projects here use - the
  # Kakao skill at /kakao, the Slack endpoints at /slack/events and its siblings (see the validation).
  segments = { for key, route in var.routes : key => split("/", route.path) }
  # One resource per distinct first segment, shared by every route under it.
  first_segments = toset([for key, parts in local.segments : parts[0]])
  # And one per distinct two-segment path.
  second_paths = toset([for key, parts in local.segments : join("/", parts) if length(parts) == 2])
}
resource "aws_api_gateway_rest_api" "api" {
  name        = var.name
  description = var.description
  # Edge-optimised, the endpoint type an AWS::Serverless::Api has when the template names none.
  endpoint_configuration {
    types = ["EDGE"]
  }
}
resource "aws_api_gateway_resource" "first" {
  for_each    = local.first_segments
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = each.value
}
resource "aws_api_gateway_resource" "second" {
  for_each    = local.second_paths
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.first[split("/", each.value)[0]].id
  path_part   = split("/", each.value)[1]
}
locals {
  # The resource each route's method hangs off.
  route_resource_ids = {
    for key, parts in local.segments : key => (
      length(parts) == 1 ? aws_api_gateway_resource.first[parts[0]].id : aws_api_gateway_resource.second[join("/", parts)].id
    )
  }
}
resource "aws_api_gateway_method" "route" {
  for_each         = var.routes
  rest_api_id      = aws_api_gateway_rest_api.api.id
  resource_id      = local.route_resource_ids[each.key]
  http_method      = each.value.http_method
  authorization    = "NONE"
  api_key_required = var.api_key_required
}
# Lambda proxy integrations, which API Gateway always calls Lambda through with POST whatever the client's method.
resource "aws_api_gateway_integration" "route" {
  for_each                = aws_api_gateway_method.route
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = each.value.resource_id
  http_method             = each.value.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = var.function_invoke_arn
}
# One permission for every route, where SAM added one per event: any stage, method and path of this API - the
# console's test invocations included, which run outside the stage. Without it API Gateway answers every
# request with 500 and the function never runs, which is what the _monolithic conversion would have done had
# its API had any routes.
resource "aws_lambda_permission" "api" {
  statement_id  = "AllowApiGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}
resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  # A deployment is a snapshot, so a change to a route reaches the stage only through a new one. New function
  # code does not need one: the integrations name the function, not a version.
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.first,
      aws_api_gateway_resource.second,
      aws_api_gateway_method.route,
      aws_api_gateway_integration.route,
    ]))
  }
  lifecycle {
    create_before_destroy = true
  }
  # The integrations, not only the methods: a deployment of a method with no integration yet is rejected with
  # "No integration defined for method".
  depends_on = [aws_api_gateway_integration.route]
}
resource "aws_api_gateway_stage" "stage" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = var.stage_name
  deployment_id = aws_api_gateway_deployment.deployment.id
}
# --- API key ------------------------------------------------------------------------------------------------
#
# What SAM's Auth { ApiKeyRequired: true, UsagePlan: { CreateUsagePlan: PER_API } } expands into: a usage
# plan for this API's stage, one API key, and the key's membership of the plan. API Gateway only accepts an
# x-api-key header whose key belongs to a usage plan that covers the stage, so all three are needed for the
# key to work - the key alone is rejected with 403 Forbidden.
resource "aws_api_gateway_usage_plan" "api" {
  count = var.api_key_required ? 1 : 0
  name  = "${trimsuffix(var.name, "-api")}-usage-plan"
  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_stage.stage.stage_name
  }
}
resource "aws_api_gateway_api_key" "api" {
  count = var.api_key_required ? 1 : 0
  name  = "${trimsuffix(var.name, "-api")}-api-key"
}
resource "aws_api_gateway_usage_plan_key" "api" {
  count         = var.api_key_required ? 1 : 0
  key_id        = aws_api_gateway_api_key.api[0].id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.api[0].id
}
