output "key_id" {
  value       = aws_kms_key.kms_key.id
  description = "Key ID. The _monolithic template passed this where RDS and ECR expect a key identifier; both accept it, but kms_key_id on aws_rds_cluster is documented as an ARN and the API returns an ARN, so key_arn below is what this project passes instead"
}
output "key_arn" {
  value       = aws_kms_key.kms_key.arn
  description = "Key ARN. Used everywhere a key identifier is needed, because that is what the AWS APIs return - passing the bare ID to aws_rds_cluster.kms_key_id leaves a permanent diff between the configured ID and the ARN read back"
}
output "alias_name" {
  value       = aws_kms_alias.kms_key_alias.name
  description = "Alias of the key, re-exposed from the input so a caller referring to it in a command does not restate it (rules.md B-5)"
}
