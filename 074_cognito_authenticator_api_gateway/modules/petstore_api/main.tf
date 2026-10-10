# The PetStore REST API: one resource, /pets, whose GET is guarded by a Cognito user pool authorizer that checks
# OAuth scopes in the access token.
resource "aws_api_gateway_rest_api" "api" {
  name                         = var.name
  description                  = var.description
  disable_execute_api_endpoint = false
  endpoint_configuration {
    types           = ["REGIONAL"]
    ip_address_type = "ipv4"
  }
}
resource "aws_api_gateway_resource" "pets" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "pets"
}
# Validates the bearer token against the pool. With authorization_scopes on the method, the token has to be an
# access token carrying one of those scopes; an ID token is rejected.
resource "aws_api_gateway_authorizer" "cognito" {
  name            = var.authorizer_name
  rest_api_id     = aws_api_gateway_rest_api.api.id
  type            = "COGNITO_USER_POOLS"
  identity_source = "method.request.header.Authorization"
  provider_arns   = [var.user_pool_arn]
}
locals {
  cors = var.cors_allow_origin != null
  # The response headers a browser needs to read the result. Single-quoted, because in an integration
  # response mapping a quoted value is a literal and an unquoted one is a reference into the backend response.
  cors_headers = {
    "Access-Control-Allow-Origin"  = "'${coalesce(var.cors_allow_origin, "*")}'"
    "Access-Control-Allow-Headers" = "'Content-Type,Authorization,X-Amz-Date,X-Api-Key,X-Amz-Security-Token'"
    "Access-Control-Allow-Methods" = "'GET,OPTIONS'"
  }
}
# --- GET /pets --------------------------------------------------------------------------------------------
resource "aws_api_gateway_method" "get" {
  rest_api_id          = aws_api_gateway_rest_api.api.id
  resource_id          = aws_api_gateway_resource.pets.id
  http_method          = "GET"
  authorization        = "COGNITO_USER_POOLS"
  authorizer_id        = aws_api_gateway_authorizer.cognito.id
  authorization_scopes = var.authorization_scopes
  request_parameters   = { for name in var.optional_query_parameters : "method.request.querystring.${name}" => false }
}
resource "aws_api_gateway_integration" "get" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.pets.id
  http_method             = aws_api_gateway_method.get.http_method
  type                    = var.backend_url == null ? "MOCK" : "HTTP"
  integration_http_method = var.backend_url == null ? null : "GET"
  connection_type         = var.backend_url == null ? null : "INTERNET"
  uri                     = var.backend_url
  request_templates       = var.backend_url == null ? { "application/json" = "{\"statusCode\": 200}" } : null
  passthrough_behavior    = "WHEN_NO_MATCH"
  timeout_milliseconds    = 29000
}
resource "aws_api_gateway_method_response" "get" {
  rest_api_id         = aws_api_gateway_rest_api.api.id
  resource_id         = aws_api_gateway_resource.pets.id
  http_method         = aws_api_gateway_method.get.http_method
  status_code         = "200"
  response_parameters = local.cors ? { "method.response.header.Access-Control-Allow-Origin" = false } : {}
}
# The mapping from the backend's answer to the method response, which the _monolithic template did not have
# for either method. A non-proxy integration with no integration response has nothing to map a 200 to, so
# every call that got past the authorizer came back as 500 Internal server error - which reads like the
# backend failing rather than the API being incomplete.
resource "aws_api_gateway_integration_response" "get" {
  rest_api_id         = aws_api_gateway_rest_api.api.id
  resource_id         = aws_api_gateway_resource.pets.id
  http_method         = aws_api_gateway_method.get.http_method
  status_code         = aws_api_gateway_method_response.get.status_code
  response_parameters = local.cors ? { "method.response.header.Access-Control-Allow-Origin" = local.cors_headers["Access-Control-Allow-Origin"] } : {}
  depends_on          = [aws_api_gateway_integration.get]
}
# --- OPTIONS /pets: the CORS preflight ----------------------------------------------------------------------
#
# The browser sends this before the GET because the GET carries an Authorization header. A MOCK integration
# answers it inside API Gateway; with no authorizer, because a preflight carries no credentials.
resource "aws_api_gateway_method" "options" {
  count         = local.cors ? 1 : 0
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.pets.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "options" {
  count                = local.cors ? 1 : 0
  rest_api_id          = aws_api_gateway_rest_api.api.id
  resource_id          = aws_api_gateway_resource.pets.id
  http_method          = aws_api_gateway_method.options[0].http_method
  type                 = "MOCK"
  passthrough_behavior = "WHEN_NO_MATCH"
  request_templates    = { "application/json" = "{\"statusCode\": 200}" }
  timeout_milliseconds = 29000
}
resource "aws_api_gateway_method_response" "options" {
  count               = local.cors ? 1 : 0
  rest_api_id         = aws_api_gateway_rest_api.api.id
  resource_id         = aws_api_gateway_resource.pets.id
  http_method         = aws_api_gateway_method.options[0].http_method
  status_code         = "200"
  response_parameters = { for name in keys(local.cors_headers) : "method.response.header.${name}" => false }
}
resource "aws_api_gateway_integration_response" "options" {
  count               = local.cors ? 1 : 0
  rest_api_id         = aws_api_gateway_rest_api.api.id
  resource_id         = aws_api_gateway_resource.pets.id
  http_method         = aws_api_gateway_method.options[0].http_method
  status_code         = aws_api_gateway_method_response.options[0].status_code
  response_parameters = { for name, value in local.cors_headers : "method.response.header.${name}" => value }
  depends_on          = [aws_api_gateway_integration.options]
}
# --- Deployment ---------------------------------------------------------------------------------------------
resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  # A deployment is a snapshot taken when it is created, so a change to a method or an integration reaches the
  # stage only through a new one. The _monolithic template had no trigger, and its first deployment was the
  # last: editing the API afterwards changed nothing callers could see.
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.pets.id,
      aws_api_gateway_authorizer.cognito,
      aws_api_gateway_method.get,
      aws_api_gateway_integration.get,
      aws_api_gateway_integration_response.get,
      aws_api_gateway_method.options,
      aws_api_gateway_integration.options,
      aws_api_gateway_integration_response.options,
    ]))
  }
  lifecycle {
    create_before_destroy = true
  }
  # The integrations, not only the methods. A deployment of a method that has no integration yet is rejected
  # with "No integration defined for method", and the _monolithic template ordered this after the methods only.
  depends_on = [
    aws_api_gateway_integration_response.get,
    aws_api_gateway_integration_response.options,
  ]
}
resource "aws_api_gateway_stage" "stage" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = var.stage_name
  deployment_id = aws_api_gateway_deployment.deployment.id
}
