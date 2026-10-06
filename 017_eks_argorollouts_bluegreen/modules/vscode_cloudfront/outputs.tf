output "domain_name" {
  value       = aws_cloudfront_distribution.vscode_distribution.domain_name
  description = "CloudFront domain name serving the distribution"
}
output "url" {
  value       = "https://${aws_cloudfront_distribution.vscode_distribution.domain_name}"
  description = "HTTPS URL to reach code-server through CloudFront"
}
output "distribution_id" {
  value       = aws_cloudfront_distribution.vscode_distribution.id
  description = "ID of the CloudFront distribution"
}
output "cache_policy_id" {
  value       = aws_cloudfront_cache_policy.vscode_cache_policy.id
  description = "ID of the cache policy created for the distribution"
}
output "cache_policy_name" {
  value       = aws_cloudfront_cache_policy.vscode_cache_policy.name
  description = "The name the policy was actually created under, which is generated unless the caller pinned one. Re-exposed because the generated suffix is not predictable from the inputs, and this is the name to look for in the CloudFront console when more than one of these projects is deployed in the account (rules.md B-5)"
}
