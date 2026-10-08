output "id" {
  value       = aws_cloudfront_distribution.distribution.id
  description = "Distribution id, which is what an invalidation names"
}
output "arn" {
  value       = aws_cloudfront_distribution.distribution.arn
  description = "ARN of the distribution"
}
output "domain_name" {
  value       = aws_cloudfront_distribution.distribution.domain_name
  description = "The distribution's own hostname under cloudfront.net"
}
output "url" {
  value       = "https://${aws_cloudfront_distribution.distribution.domain_name}"
  description = "The site. https because viewer_protocol_policy redirects plain HTTP by default - the origin hop is still HTTP, which a website endpoint cannot avoid"
}
output "hosted_zone_id" {
  value       = aws_cloudfront_distribution.distribution.hosted_zone_id
  description = "CloudFront's zone id, which a Route 53 alias record pointing at this distribution needs. The same constant for every distribution, exposed here so a caller does not hardcode it"
}
output "invalidate_command" {
  value       = "aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.distribution.id} --paths '/*'"
  description = "Clears the edge caches. Needed after changing an object, because the managed caching policy keeps a hit for a day - an updated page that still shows the old content is this, not a failed upload"
}
output "status_command" {
  value       = "aws cloudfront get-distribution --id ${aws_cloudfront_distribution.distribution.id} --query 'Distribution.Status' --output text"
  description = "Whether the distribution has finished deploying. A newly created distribution answers requests only once this reads Deployed, which takes several minutes after apply returns - a 403 or a DNS failure straight after apply is usually just this"
}
