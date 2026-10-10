# bucket and key come back out of the invocation's result rather than straight from the inputs. That is what
# makes a read named through them wait for the invocation: while it is being created or re-invoked the result
# is unknown, so the read is deferred to apply and runs after it; once it is in state the result is known and
# the read happens at plan, which is how a later deploy.sh upload is seen (rules.md B-5).
output "bucket" {
  value       = jsondecode(aws_lambda_invocation.wait.result).bucket
  description = "Bucket of the object, known only once the function has seen the object there"
}
output "key" {
  value       = jsondecode(aws_lambda_invocation.wait.result).key
  description = "Key of the object, known only once the function has seen the object there"
}
