output "parameter_name" {
  value       = aws_ssm_parameter.token.name
  description = "Parameter Store name holding the token"
}
output "parameter_arn" {
  value       = aws_ssm_parameter.token.arn
  description = "ARN of the parameter, which the authorizer's ssm:GetParameter grant is scoped to"
}
output "parameter_version" {
  value       = aws_ssm_parameter.token.version
  description = "Version of the parameter. It changes when the token does, so passing it to the authorizer and into the workbench script makes a rotation reach both without the value itself being passed anywhere"
}
output "retrieve_command" {
  value       = "aws ssm get-parameter --name ${aws_ssm_parameter.token.name} --with-decryption --query Parameter.Value --output text"
  description = "Command that prints the token. A command rather than the value, so neither terraform output nor the workbench README contains it (rules.md H-2)"
}
