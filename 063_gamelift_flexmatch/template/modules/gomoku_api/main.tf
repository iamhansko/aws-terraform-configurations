resource "aws_api_gateway_rest_api" "api" {
  name = var.name
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}
resource "aws_api_gateway_resource" "route" {
  for_each    = var.routes
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = each.value.path_part
}
# --- The Lambda methods -------------------------------------------------------------------------------------
#
# Non-proxy (type AWS) integrations, as the _monolithic template had them: the request body is passed through as
# the event, which is what the handlers read (event['PlayerName'], event['TicketId']), and the function's return
# value is passed back as the body.
#
# The integration responses below are new, and without them none of the three methods worked. A non-proxy
# integration has no default mapping from the backend's reply to a method response; with none declared, API
# Gateway answers every call with 500 "Internal server error" and logs "No match for output mapping and no
# default output mapping". The _monolithic template declared the method responses and stopped there.
resource "aws_api_gateway_method" "route" {
  for_each      = var.routes
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.route[each.key].id
  http_method   = each.value.http_method
  authorization = "NONE"
}
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
# The default (empty selection pattern) response, carrying the CORS header the leaderboard page needs: it is
# served from the S3 website endpoint, a different origin, and the browser discards a cross-origin response
# without Access-Control-Allow-Origin. The two game clients are native programs and do not care.
resource "aws_api_gateway_integration_response" "route" {
  for_each    = var.routes
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.route[each.key].id
  http_method = aws_api_gateway_method.route[each.key].http_method
  status_code = aws_api_gateway_method_response.route[each.key].status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'${var.cors_allow_origin}'"
  }
  # An integration response is rejected for a method that has no integration yet, and nothing above references
  # the integration (rules.md D-1).
  depends_on = [aws_api_gateway_integration.route]
}
resource "aws_lambda_permission" "route" {
  for_each      = var.routes
  action        = "lambda:InvokeFunction"
  function_name = each.value.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/${each.value.http_method}/${each.value.path_part}"
}
# --- CORS preflight -----------------------------------------------------------------------------------------
#
# The _monolithic template's OPTIONS methods had a MOCK integration and a bare 200 method response, and nothing
# else: no integration response (so the mock returned 500 like the methods above) and no Access-Control-Allow-*
# headers (so even a 200 would not have satisfied a preflight). integration_http_method is dropped as well - it
# means nothing on a MOCK integration.
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
    "method.response.header.Access-Control-Allow-Headers" = "'${var.cors_allow_headers}'"
    "method.response.header.Access-Control-Allow-Methods" = "'${each.value.http_method},OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'${var.cors_allow_origin}'"
  }
  depends_on = [aws_api_gateway_integration.options]
}
# --- Deployment and stage -----------------------------------------------------------------------------------
#
# The _monolithic template had a deployment and no stage, and with AWS provider v6 a deployment no longer takes
# stage_name - so nothing was ever published. Every URL the clients and the page were given ends in /prod, and
# every one of them was answered by API Gateway's own error for a stage that does not exist, never by a function.
#
# triggers is what makes a later change reach the stage: a deployment is a snapshot taken when it is created, so
# an edited integration is not served until a new one is made. create_before_destroy lets the stage move to the
# new snapshot before the old one is deleted, which API Gateway would otherwise refuse while the stage points
# at it.
resource "aws_api_gateway_deployment" "deployment" {
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
  # The references in triggers already order this after everything listed. depends_on is kept, as the
  # _monolithic template had it for the methods, so the requirement is visible here rather than implied by a
  # hash: CreateDeployment fails with "No integration defined for method" if a method has no integration yet -
  # which the original's methods-only list allowed to happen.
  depends_on = [
    aws_api_gateway_method.route,
    aws_api_gateway_method.options,
    aws_api_gateway_integration.route,
    aws_api_gateway_integration.options,
    aws_api_gateway_integration_response.route,
    aws_api_gateway_integration_response.options,
  ]
}
resource "aws_api_gateway_stage" "stage" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.deployment.id
  stage_name    = var.stage_name
}
