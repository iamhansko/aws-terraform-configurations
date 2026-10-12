output "url" {
  value       = "https://${aws_cloudfront_distribution.code_server.domain_name}"
  description = "The IDE, through CloudFront. https because viewer_protocol_policy redirects plain HTTP - the edge-to-origin hop is still HTTP, which code-server with cert: false cannot avoid"
}
output "domain_name" {
  value       = aws_cloudfront_distribution.code_server.domain_name
  description = "The distribution's hostname under cloudfront.net"
}
output "id" {
  value       = aws_cloudfront_distribution.code_server.id
  description = "Distribution id, which an invalidation names"
}
output "cache_policy_id" {
  value       = aws_cloudfront_cache_policy.code_server.id
  description = "The cache policy in use. Re-exposed because the _monolithic template set both a cache policy and a legacy forwarded_values block on the same behaviour, which CloudFront rejects - seeing the policy here is the confirmation that only one is in play"
}
output "origin_request_policy_id" {
  value       = var.origin_request_policy_id
  description = "The origin request policy, re-exposed so it can be compared against what was intended - the original carried it as a bare uuid (rules.md B-5)"
}
output "status_command" {
  value       = "aws cloudfront get-distribution --id ${aws_cloudfront_distribution.code_server.id} --query 'Distribution.Status' --output text"
  description = "Whether the distribution has finished deploying. It has to read Deployed before the URL answers, which takes several minutes after apply returns - a 502 straight after apply is usually just this, or code-server not yet started"
}
output "invalidate_command" {
  value       = "aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.code_server.id} --paths '/*'"
  description = "Clears the edge caches. Needed after upgrading code-server, whose asset filenames are versioned but whose index is not"
}
