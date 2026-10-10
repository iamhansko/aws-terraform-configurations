output "key_name" {
  value       = aws_key_pair.key_pair.key_name
  description = "Name of the created key pair"
}
output "private_key_command" {
  value       = "aws ssm get-parameter --name ${aws_ssm_parameter.key_pair_private_key.name} --with-decryption --query Parameter.Value --output text"
  description = "Command that retrieves the private key. A command rather than the key, so neither terraform output nor the README on the workbench contains it (rules.md H-2)"
}
