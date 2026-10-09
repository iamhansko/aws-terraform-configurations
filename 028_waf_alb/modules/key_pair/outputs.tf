output "key_name" {
  value       = aws_key_pair.key_pair.key_name
  description = "Name of the created key pair, generated when the caller passed key_name as null. Both instances attach it"
}
output "key_pair_id" {
  value       = aws_key_pair.key_pair.key_pair_id
  description = "ID of the created key pair, which is also the last element of the Parameter Store path holding the private key"
}
output "private_key_parameter_name" {
  value       = aws_ssm_parameter.key_pair_private_key.name
  description = "Parameter Store path holding the private key. Re-exposed so the root can build the fetch command and the console link without reassembling /ec2/keypair/<id> itself (rules.md B-5)"
}
output "private_key_command" {
  value       = "aws ssm get-parameter --name ${aws_ssm_parameter.key_pair_private_key.name} --with-decryption --query Parameter.Value --output text"
  description = "Command that retrieves the private key. A command rather than the key, so terraform output does not print it and it does not have to be marked sensitive in every root that uses this module"
}
