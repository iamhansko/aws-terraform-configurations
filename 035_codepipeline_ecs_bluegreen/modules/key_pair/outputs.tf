output "key_name" {
  value       = aws_key_pair.key_pair.key_name
  description = "Generated name of the key pair, which the bastion instance and the container instance launch template both reference"
}
output "key_pair_id" {
  value       = aws_key_pair.key_pair.key_pair_id
  description = "ID of the key pair, which is also the last segment of the Parameter Store path holding the private key"
}
output "private_key_parameter_name" {
  value       = aws_ssm_parameter.key_pair_private_key.name
  description = "Name of the SecureString parameter holding the generated private key. The name rather than the key: a private key must not reach an output (rules.md H-2)"
}
output "private_key_command" {
  value       = "aws ssm get-parameter --name ${aws_ssm_parameter.key_pair_private_key.name} --with-decryption --query Parameter.Value --output text"
  description = "Command retrieving the generated private key from Parameter Store. Pipe it into a file with mode 600 before using it with ssh"
}
