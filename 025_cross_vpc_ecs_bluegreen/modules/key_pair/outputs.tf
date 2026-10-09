output "key_name" {
  value       = aws_key_pair.key_pair.key_name
  description = "Generated key pair name, for an instance or a launch template to attach"
}
output "key_pair_id" {
  value       = aws_key_pair.key_pair.key_pair_id
  description = "Key pair ID, which is also the last segment of the Parameter Store path holding the private key"
}
output "private_key_parameter_name" {
  value       = aws_ssm_parameter.key_pair_private_key.name
  description = "Parameter Store path of the private key. The name rather than the value: the parameter is a SecureString and the key must not reach an output or the README on the workbench (rules.md H-2)"
}
output "private_key_command" {
  value       = "aws ssm get-parameter --with-decryption --name ${aws_ssm_parameter.key_pair_private_key.name} --query Parameter.Value --output text"
  description = "Command that fetches the private key. The retrieval command rather than the key itself, which is the form this repository uses for anything sensitive"
}
