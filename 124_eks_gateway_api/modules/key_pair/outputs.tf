output "key_name" {
  value       = aws_key_pair.key_pair.key_name
  description = "Name of the created EC2 key pair"
}
output "key_pair_id" {
  value       = aws_key_pair.key_pair.key_pair_id
  description = "ID of the created EC2 key pair, which is also the SSM parameter path the private key is stored under"
}
output "private_key_parameter_name" {
  value       = aws_ssm_parameter.key_pair_private_key.name
  description = "SSM Parameter Store path holding the private key as a SecureString, re-exposed so the caller does not restate /ec2/keypair/<id> (rules.md B-5)"
}
