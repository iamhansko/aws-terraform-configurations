output "distribution_id" {
  value       = aws_cloudfront_distribution.distribution.id
  description = "ID of the distribution"
}
output "domain_name" {
  value       = aws_cloudfront_distribution.distribution.domain_name
  description = "Domain name of the distribution"
}
output "url" {
  value       = "https://${aws_cloudfront_distribution.distribution.domain_name}"
  description = "Root URL of the distribution, which is the S3 origin's default behaviour"
}
output "ec2_url" {
  value       = "https://${aws_cloudfront_distribution.distribution.domain_name}${var.ec2_path_prefix}"
  description = "URL of the EC2 origin's behaviour through the distribution"
}
output "bucket_name" {
  value       = aws_s3_bucket.origin.id
  description = "Generated name of the S3 origin bucket"
}
output "status_command" {
  value       = "aws cloudfront get-distribution --id ${aws_cloudfront_distribution.distribution.id} --query 'Distribution.[Status,DomainName]' --output table"
  description = "Whether the distribution has finished deploying. InProgress for several minutes after every change; the edge serves the previous configuration until it is Deployed"
}
