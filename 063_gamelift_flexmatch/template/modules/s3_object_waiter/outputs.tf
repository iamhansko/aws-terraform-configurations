# bucket and key come back out of the invocation's result rather than straight from the inputs. That is what
# makes a resource named through them wait for the invocation: while it is being created the result is unknown,
# so the resource cannot be created until the function has seen the object (rules.md B-5).
output "bucket" {
  value       = jsondecode(aws_lambda_invocation.wait.result).bucket
  description = "Bucket of the object, known only once the function has seen the object there"
}
output "key" {
  value       = jsondecode(aws_lambda_invocation.wait.result).key
  description = "Key of the object, known only once the function has seen the object there"
}
output "function_name" {
  value       = aws_lambda_function.function.function_name
  description = "Name of the waiting function, whose log group shows each poll"
}
