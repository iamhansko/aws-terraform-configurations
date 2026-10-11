output "distribution_id" {
  value       = aws_cloudfront_distribution.distribution.id
  description = "ID of the CloudFront distribution"
}
output "domain_name" {
  value       = aws_cloudfront_distribution.distribution.domain_name
  description = "The distribution's *.cloudfront.net domain name"
}
output "url" {
  value       = "https://${aws_cloudfront_distribution.distribution.domain_name}"
  description = "HTTPS URL of ComfyUI through CloudFront"
}
output "vpc_origin_id" {
  value       = aws_cloudfront_vpc_origin.origin.id
  description = "ID of the VPC origin"
}
