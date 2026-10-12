output "bucket_name" {
  value       = aws_s3_bucket.destination.id
  description = "Generated name of the destination bucket. This is the one value the source root cannot derive on its own and has to be told (rules.md I-2)"
}
output "bucket_arn" {
  value       = aws_s3_bucket.destination.arn
  description = "ARN of the destination bucket"
}
output "bucket_region" {
  value       = aws_s3_bucket.destination.region
  description = "Region the bucket is in. Replication crosses accounts here rather than regions, but the two are independent and a source root pointed at a bucket in another region works the same way - worth having explicit rather than assumed"
}
output "replication_role_arn" {
  value       = local.replication_role_arn
  description = "The exact source role ARN this bucket policy permits through aws:PrincipalArn. Re-exposed so a mismatch with the role the source root creates is visible rather than as replication that silently never happens (rules.md B-5/I-2)"
}
output "allows_owner_override" {
  value       = var.allow_owner_override
  description = "Whether the policy permits the ownership translation, re-exposed because it has to match what the source root's replication configuration asks for - and a mismatch stops replication with an error recorded only on the objects (rules.md B-5)"
}
output "list_replicated_objects_command" {
  value       = "aws s3api list-object-versions --bucket ${aws_s3_bucket.destination.id} --query 'Versions[].[LastModified,Key,VersionId]' --output table"
  description = "What has arrived. Run this in the destination account after writing an object into the source bucket - replication is asynchronous, so an empty result immediately after is normal"
}
