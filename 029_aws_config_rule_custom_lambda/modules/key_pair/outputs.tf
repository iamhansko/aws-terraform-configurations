output "key_name" {
  value       = aws_key_pair.key_pair.key_name
  description = "Name of the created EC2 key pair"
}
output "key_pair_id" {
  value       = aws_key_pair.key_pair.key_pair_id
  description = "ID of the created key pair, which is the last segment of the SSM parameter holding the private key"
}
output "private_key_parameter_name" {
  value       = aws_ssm_parameter.key_pair_private_key.name
  description = "Full name of that SSM parameter, built here rather than reassembled by the caller from a prefix and the id (rules.md B-5)"
}
