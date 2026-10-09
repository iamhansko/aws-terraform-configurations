output "key_name" {
  value       = aws_key_pair.key_pair.key_name
  description = "Name of the created key pair, for the instance's key_name"
}
output "key_pair_id" {
  value       = aws_key_pair.key_pair.key_pair_id
  description = "ID of the created key pair, which is also the last element of the SSM parameter path the private key is stored under"
}
output "private_key_parameter_name" {
  value       = aws_ssm_parameter.key_pair_private_key.name
  description = "SSM parameter path holding the private key as a SecureString, re-exposed so a caller does not restate /ec2/keypair/<id> and get it wrong (rules.md B-5)"
}
output "private_key_command" {
  value       = "aws ssm get-parameter --with-decryption --name ${aws_ssm_parameter.key_pair_private_key.name} --query Parameter.Value --output text"
  description = "Fetches the private key. Nothing in this project can use it for SSH - the workbench is in a private subnet with no inbound rule - so this is here for parity with the _monolithic template and for anything added to these VPCs later"
}
