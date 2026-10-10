output "key_name" {
  value       = aws_key_pair.key_pair.key_name
  description = "Generated name of the key pair"
}
output "key_pair_id" {
  value       = aws_key_pair.key_pair.key_pair_id
  description = "ID of the key pair, which is also the last element of the Parameter Store path holding the private key"
}
output "private_key_parameter_name" {
  value       = aws_ssm_parameter.key_pair_private_key.name
  description = "Parameter Store path holding the private key, re-exposed so the root can build the fetch command without reassembling /ec2/keypair/<id> itself (rules.md B-5)"
}
output "private_key_command" {
  value       = "aws ssm get-parameter --name ${aws_ssm_parameter.key_pair_private_key.name} --with-decryption --query Parameter.Value --output text > key.pem && chmod 600 key.pem"
  description = "Command that retrieves the private key into key.pem. A command rather than the key, so terraform output does not print it"
}
