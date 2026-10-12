output "url" {
  value       = jsondecode(aws_lambda_invocation.presign.result)["Url"]
  description = "The presigned GET URL"
}
output "expires_in_seconds" {
  value       = var.expires_in_seconds
  description = "Lifetime that was requested for the URL (rules.md B-5)"
}
output "function_name" {
  value       = aws_lambda_function.presign.function_name
  description = "Name of the presigning function"
}
output "role_arn" {
  value       = aws_iam_role.presign.arn
  description = "Role the URL is signed with, which is also whose permissions S3 checks when the URL is used"
}
output "invocation_address" {
  value       = "aws_lambda_invocation.presign"
  description = "Address of the invocation inside this module, for the root to build a -replace command without restating it (rules.md B-5)"
}
