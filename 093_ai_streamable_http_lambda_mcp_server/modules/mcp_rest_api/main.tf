# The REST API in front of the MCP server: ANY /mcp, proxied to the server function, behind a TOKEN authorizer.
#
# This is the whole of what the _monolithic template's API was missing. The conversion produced the
# aws_api_gateway_rest_api and left the SAM properties that described everything else - StageName, Auth, and
# the function's Api event - as TODO comments, so it built an API with no resource, no method, no authorizer,
# no deployment and no stage. Its MCPServerApi output pointed at a Prod stage that did not exist, and both
# functions lacked the permission that lets API Gateway invoke them.
#
# Written as the resources SAM expanded AWS::Serverless::Api and the Api event into. SAM's second stage, named
# Stage, which an AWS::Serverless::Api carries when the template does not set OpenApiVersion, is not
# reproduced: it served the same API at a URL nothing used.
resource "aws_api_gateway_rest_api" "api" {
  name        = var.name
  description = var.description
  endpoint_configuration {
    types = [var.endpoint_type]
  }
}
# The SAM template's TokenAuthorizer: a TOKEN authorizer reading the Authorization header, with results
# cached for ReauthorizeEvery seconds.
resource "aws_api_gateway_authorizer" "token" {
  name                             = "TokenAuthorizer"
  rest_api_id                      = aws_api_gateway_rest_api.api.id
  type                             = "TOKEN"
  authorizer_uri                   = var.authorizer_invoke_arn
  identity_source                  = "method.request.header.${var.authorization_header}"
  identity_validation_expression   = var.identity_validation_expression
  authorizer_result_ttl_in_seconds = var.authorizer_result_ttl_in_seconds
}
# The permission SAM adds for an authorizer function, scoped to this one authorizer. Without it API Gateway
# answers every request 500 with AuthorizerConfigurationException, before the token is even looked at.
resource "aws_lambda_permission" "authorizer" {
  statement_id  = "AllowApiGatewayInvokeAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = var.authorizer_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/authorizers/${aws_api_gateway_authorizer.token.id}"
}
resource "aws_api_gateway_resource" "mcp" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = var.path_part
}
# ANY, as the SAM event declared it: streamable HTTP uses POST for every JSON-RPC message and DELETE to end a
# session, and the handler answers both.
resource "aws_api_gateway_method" "any" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.mcp.id
  http_method   = "ANY"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.token.id
}
# A Lambda proxy integration, which Lambda is always called through with POST whatever the client's method.
resource "aws_api_gateway_integration" "server" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.mcp.id
  http_method             = aws_api_gateway_method.any.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = var.server_invoke_arn
}
# Any stage and any method on this one path - the console's test invocations included, which run outside the
# stage.
resource "aws_lambda_permission" "server" {
  statement_id  = "AllowApiGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.server_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*/${var.path_part}"
}
resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  # A deployment is a snapshot, so a change to the method, the integration or the authorizer reaches the stage
  # only through a new one - a deployment without triggers is created once and keeps serving the API as it was
  # then. New function code does not need one: the integration names the function, not a version.
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.mcp,
      aws_api_gateway_method.any,
      aws_api_gateway_integration.server,
      aws_api_gateway_authorizer.token,
    ]))
  }
  lifecycle {
    create_before_destroy = true
  }
  # The integration, not only the method: a deployment of a method with no integration yet is rejected with
  # "No integration defined for method".
  depends_on = [aws_api_gateway_integration.server]
}
resource "aws_api_gateway_stage" "stage" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = var.stage_name
  deployment_id = aws_api_gateway_deployment.deployment.id
}
