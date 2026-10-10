# bucket and key come back out of the last round's result rather than straight from the inputs. That is what
# makes a resource named through them wait for the whole wait: until the last round has returned the result
# is unknown, so the resource cannot be created before (rules.md B-5).
output "bucket" {
  value       = local.final_result.bucket
  description = "Bucket of the object, known only once the function has seen the object there"
}
output "key" {
  value       = local.final_result.key
  description = "Key of the object, known only once the function has seen the object there"
}
output "function_name" {
  value       = aws_lambda_function.function.function_name
  description = "Name of the waiting function, whose log group shows each poll and each round"
}
output "rounds" {
  value       = local.rounds
  description = "How many invocations the wait is split into, each at most 900 seconds"
}
