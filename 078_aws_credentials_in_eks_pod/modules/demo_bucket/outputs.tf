output "bucket_name" {
  value       = aws_s3_bucket.demo.id
  description = "Name of the bucket, generated unless one was given so that two deployments in one account do not collide on a globally unique name"
}
output "bucket_arn" {
  value       = aws_s3_bucket.demo.arn
  description = "ARN of the bucket. The caller scopes each pod identity's policy to this and to its objects rather than attaching AmazonS3FullAccess, which is what the _monolithic template did - a demo role with access to every bucket in the account (rules.md A-5)"
}
output "object_arn_pattern" {
  value       = "${aws_s3_bucket.demo.arn}/*"
  description = "ARN pattern for the bucket's objects, re-exposed because a policy granting s3:GetObject needs this form while s3:ListBucket needs the bucket ARN itself - getting the two the wrong way round produces a role that can list and not read, or read and not list, and neither failure names the cause"
}
output "object_keys" {
  value       = [for object in aws_s3_object.demo : object.key]
  description = "The objects written into the bucket, so a caller describing the demo can say what a successful listing should show"
}
output "list_command" {
  value       = "aws s3 ls s3://${aws_s3_bucket.demo.id}/"
  description = "Lists the bucket's contents. Run it inside each pod: it is the difference between an identity that has the permission and one that does not, and with an object in the bucket a success is distinguishable from a swallowed denial"
}
