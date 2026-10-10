# GomokuAPI: three routes, each a non-proxy Lambda integration with a CORS
# preflight beside it.
#
#   GET  /ranking       game-rank-reader    the leaderboard page's $.get()
#   POST /matchrequest  game-match-request  the game client's match request
#   POST /matchstatus   game-match-status   the game client's poll for its match
#
# Three things differ from the _monolithic template, and each of them was a
# reason the API returned nothing useful.
#
# 1. There was no stage. The conversion produced an aws_api_gateway_deployment
#    and nothing else, and in provider v6 a deployment cannot create a stage at
#    all - the stage_name argument is gone from the resource. Every URL the
#    project hands out ends in /prod (both client config.ini files, the
#    leaderboard's main.js), so every one of them named a stage that did not
#    exist. The stage is aws_api_gateway_stage now.
#
# 2. There were no integration responses. A non-proxy (type = "AWS")
#    integration returns nothing to the caller until an integration response
#    maps the backend's reply onto a method response; without one, API Gateway
#    answers 500 and its execution log says "No match for output mapping and no
#    default output mapping specified". The conversion has method responses and
#    no integration responses at all, so all six methods, the three MOCK
#    preflights included, were in that state.
#
# 3. CORS headers are declared. The OPTIONS methods existed but answered
#    without a single Access-Control-Allow-* header, which a browser treats as
#    a failed preflight. More to the point, the one route a browser calls -
#    GET /ranking, cross-origin from the S3 website endpoint - is a simple
#    request that needs no preflight at all but does need
#    Access-Control-Allow-Origin on its own response, or the page's script
#    cannot read it. The game clients are native executables and ignore CORS
#    entirely; the headers are on every route because the template put a
#    preflight on every route.
resource "aws_api_gateway_rest_api" "api" {
  name = var.api_name
  endpoint_configuration {
    types = [var.endpoint_type]
  }
}
resource "aws_api_gateway_resource" "route" {
  for_each    = var.routes
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = each.value.path_part
}
# --- The routes themselves ---------------------------------------------------
resource "aws_api_gateway_method" "route" {
  for_each      = var.routes
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.route[each.key].id
  http_method   = each.value.http_method
  authorization = "NONE"
}
# Non-proxy, as the template had it: the request body is passed through as the
# event, which is why MatchRequest.py reads event['PlayerName'] directly rather
# than parsing event['body'], and the function's return value becomes the
# response body.
resource "aws_api_gateway_integration" "route" {
  for_each                = var.routes
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.route[each.key].id
  http_method             = aws_api_gateway_method.route[each.key].http_method
  type                    = "AWS"
  integration_http_method = "POST"
  uri                     = each.value.invoke_arn
}
resource "aws_api_gateway_method_response" "route" {
  for_each    = var.routes
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.route[each.key].id
  http_method = aws_api_gateway_method.route[each.key].http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}
resource "aws_api_gateway_integration_response" "route" {
  for_each    = var.routes
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.route[each.key].id
  http_method = aws_api_gateway_method.route[each.key].http_method
  status_code = aws_api_gateway_method_response.route[each.key].status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'${var.cors_allow_origin}'"
  }

  # PutIntegrationResponse on a method whose integration does not exist yet is a
  # NotFoundException; the method and method response references do not order
  # this after the integration (rules.md D-1).
  depends_on = [aws_api_gateway_integration.route]
}
# --- CORS preflights -----------------------------------------------------------
resource "aws_api_gateway_method" "options" {
  for_each      = var.routes
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.route[each.key].id
  http_method   = "OPTIONS"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "options" {
  for_each    = var.routes
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.route[each.key].id
  http_method = aws_api_gateway_method.options[each.key].http_method
  type        = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}
resource "aws_api_gateway_method_response" "options" {
  for_each    = var.routes
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.route[each.key].id
  http_method = aws_api_gateway_method.options[each.key].http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}
resource "aws_api_gateway_integration_response" "options" {
  for_each    = var.routes
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.route[each.key].id
  http_method = aws_api_gateway_method.options[each.key].http_method
  status_code = aws_api_gateway_method_response.options[each.key].status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'${join(",", var.cors_allow_headers)}'"
    "method.response.header.Access-Control-Allow-Methods" = "'${each.value.http_method},OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'${var.cors_allow_origin}'"
  }
  depends_on = [aws_api_gateway_integration.options]
}
# --- Invoke permissions -------------------------------------------------------
# Scoped to this API, any stage, this method and path - the template's shape,
# expressed through the API's execution_arn rather than reassembled from the
# account id and region.
resource "aws_lambda_permission" "route" {
  for_each      = var.routes
  action        = "lambda:InvokeFunction"
  function_name = each.value.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/${each.value.http_method}/${each.value.path_part}"
}
# --- Deployment and stage -----------------------------------------------------
# A deployment is a snapshot taken when it is created, so editing a method later
# changes nothing a caller sees until a new deployment is made. The trigger
# hashes everything the snapshot contains, which makes any change to the routes
# replace the deployment; create_before_destroy is what lets the stage move to
# the new one before the old one is deleted, since API Gateway refuses to delete
# a deployment a stage still points at.
resource "aws_api_gateway_deployment" "api" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.route,
      aws_api_gateway_method.route,
      aws_api_gateway_integration.route,
      aws_api_gateway_method_response.route,
      aws_api_gateway_integration_response.route,
      aws_api_gateway_method.options,
      aws_api_gateway_integration.options,
      aws_api_gateway_method_response.options,
      aws_api_gateway_integration_response.options,
    ]))
  }
  lifecycle {
    create_before_destroy = true
  }

  # CreateDeployment fails with "No integration defined for method" while any
  # method lacks one, and a snapshot taken before the integration responses
  # exist is the 500 described at the top of this file. The triggers hash reads
  # these values but a hash is not an ordering edge Terraform can rely on, so
  # the dependency is stated (rules.md D-1).
  depends_on = [
    aws_api_gateway_method.route,
    aws_api_gateway_method.options,
    aws_api_gateway_integration.route,
    aws_api_gateway_integration.options,
    aws_api_gateway_integration_response.route,
    aws_api_gateway_integration_response.options,
  ]
}
resource "aws_api_gateway_stage" "api" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.api.id
  stage_name    = var.stage_name
}
