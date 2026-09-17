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
