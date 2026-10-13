output "url" {
  value       = aws_lambda_function_url.url.function_url
  description = "The function URL, with a trailing slash"
  # The URL answers 403 until both permissions exist, so whatever reads it waits for them too.
  depends_on = [aws_lambda_permission.invoke_function_url, aws_lambda_permission.invoke_function]
}
