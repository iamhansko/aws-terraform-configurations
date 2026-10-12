output "key_name" {
  value       = aws_key_pair.this.key_name
  description = "Created EC2 key-pair name."
}

output "key_pair_id" {
  value       = aws_key_pair.this.key_pair_id
  description = "Created EC2 key-pair ID."
}

output "private_key_parameter_name" {
  value       = aws_ssm_parameter.private_key.name
  description = "Parameter Store path holding the generated private key (rules.md B-5)."
}

output "private_key_command" {
  value       = "aws ssm get-parameter --name ${aws_ssm_parameter.private_key.name} --with-decryption --query Parameter.Value --output text"
  description = "Command that retrieves the private key without exposing it as a Terraform output."
}
