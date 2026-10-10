output "arn" {
  value       = aws_cloudfront_function.function.arn
  description = "ARN of the function, which a distribution's function_association takes"
}
output "name" {
  value       = aws_cloudfront_function.function.name
  description = "Name of the function"
}
output "key_value_store_arn" {
  value       = one(aws_cloudfront_key_value_store.store[*].arn)
  description = "ARN of the associated key value store, or null when none was created"
}
output "describe_command" {
  value       = "aws cloudfront describe-function --name ${aws_cloudfront_function.function.name} --stage LIVE --query 'FunctionSummary.[Name,Status,FunctionConfig.Runtime,FunctionMetadata.Stage]' --output table"
  description = "The function's LIVE stage. Only LIVE runs at the edge"
}
output "test_command" {
  # --cli-binary-format raw-in-base64-out: --event-object is a blob, and AWS CLI v2 reads an inline blob as
  # base64 unless told otherwise. Its decoder skips the characters base64 does not use, so the JSON below did
  # not fail locally - it went out as the leftover letters, which CloudFront decodes into bytes that are not
  # an event. This command is printed into the workbench README and has to run there as written
  # (rules.md H-2).
  value       = "aws cloudfront test-function --name ${aws_cloudfront_function.function.name} --stage LIVE --if-match $(aws cloudfront describe-function --name ${aws_cloudfront_function.function.name} --stage LIVE --query ETag --output text) --cli-binary-format raw-in-base64-out --event-object '{\"version\":\"1.0\",\"context\":{\"eventType\":\"viewer-request\"},\"viewer\":{\"ip\":\"198.51.100.1\"},\"request\":{\"method\":\"GET\",\"uri\":\"/\",\"headers\":{},\"cookies\":{},\"querystring\":{}}}' --query 'TestResult.[ComputeUtilization,FunctionOutput]' --output text"
  description = "Runs the LIVE function against a sample viewer request without going through the distribution. ComputeUtilization above 100 is what makes CloudFront throttle it in production"
}
