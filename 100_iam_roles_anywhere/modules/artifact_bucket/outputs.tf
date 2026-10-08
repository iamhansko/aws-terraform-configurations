output "bucket_name" {
  value       = aws_s3_bucket.artifacts.id
  description = "Generated name of the bucket. The bootstrap uploads into it, the association verifies the objects landed in it, and the vended role is allowed to read it - so this one value reaches three places and is defined once (rules.md B-5)"
}
output "bucket_arn" {
  value       = aws_s3_bucket.artifacts.arn
  description = "ARN of the bucket, for an IAM policy that has to name the objects inside it as <arn>/*"
}
# No output returns an object's contents, and that is the rule rather than an oversight: one of
# them is an unencrypted private key, and a terraform output - or a CI log capturing one - is not
# where it should end up (rules.md H-2 for the repository's preference for commands over values).
output "list_objects_command" {
  value       = "aws s3api list-objects-v2 --bucket ${aws_s3_bucket.artifacts.id} --query 'Contents[].{Key:Key,Size:Size,Modified:LastModified}'"
  description = "What is actually in the bucket. Four objects is the expected answer; an empty list means the bootstrap never got as far as uploading, which the apply should already have failed on"
}
