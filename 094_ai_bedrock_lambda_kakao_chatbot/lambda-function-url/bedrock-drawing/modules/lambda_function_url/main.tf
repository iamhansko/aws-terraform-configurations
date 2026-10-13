# A public function URL, and the resource policy that makes it public.
#
# The SAM template's FunctionUrlConfig expanded into the URL and an AWS::Lambda::Permission granting
# lambda:InvokeFunctionUrl to everyone. The _monolithic conversion kept the URL, dropped the permission and the
# CORS block, and so produced a URL that answers every request with 403 Forbidden: with AuthType NONE Lambda
# skips IAM authentication, but the resource policy still has to allow the call.
#
# Two statements rather than SAM's one. Since October 2025 a new function URL needs lambda:InvokeFunction as
# well as lambda:InvokeFunctionUrl, the former restricted to calls arriving through the URL - which is what
# invoked_via_function_url adds - so granting it opens nothing but the URL.
resource "aws_lambda_function_url" "url" {
  function_name      = var.function_name
  authorization_type = "NONE"
  invoke_mode        = var.invoke_mode
  dynamic "cors" {
    for_each = var.cors == null ? [] : [var.cors]
    content {
      allow_origins = cors.value.allow_origins
      allow_methods = cors.value.allow_methods
    }
  }
}
resource "aws_lambda_permission" "invoke_function_url" {
  statement_id           = "FunctionUrlAllowPublicAccess"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = var.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}
resource "aws_lambda_permission" "invoke_function" {
  statement_id             = "FunctionUrlAllowInvokeFunction"
  action                   = "lambda:InvokeFunction"
  function_name            = var.function_name
  principal                = "*"
  invoked_via_function_url = true
}
