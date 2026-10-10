# image_uri comes back out of the invocation's result rather than straight from the input. That is what makes a
# function created from it wait for the invocation: while it is being created the result is unknown, so
# CreateFunction cannot be sent until this function has seen the tag in ECR (rules.md B-5).
output "image_uri" {
  value       = jsondecode(aws_lambda_invocation.wait.result).image_uri
  description = "The tagged image reference, known only once the function has seen the tag in the repository"
}
output "image_digest" {
  value       = jsondecode(aws_lambda_invocation.wait.result).image_digest
  description = "Digest the tag pointed at when the wait ended. A record of the first push only - every rebuild moves the tag"
}
output "function_name" {
  value       = aws_lambda_function.function.function_name
  description = "Name of the waiting function, whose log group shows each poll"
}
