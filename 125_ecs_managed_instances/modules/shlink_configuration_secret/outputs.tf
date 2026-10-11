output "secret_arn" {
  value       = aws_secretsmanager_secret.configuration.arn
  description = "ARN of the configuration secret, which the task definitions' secrets entries and the execution roles' GetSecretValue grants name"
}
output "secret_version_id" {
  value       = aws_secretsmanager_secret_version.configuration.version_id
  description = "Version of the secret value. A consumer that must not start before the value exists should reference this rather than the ARN, which exists first"
}
output "api_key" {
  value       = random_uuid.api_key.result
  sensitive   = true
  description = "The Shlink API key both containers are configured with"
}
output "get_api_key_command" {
  value       = "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.configuration.arn} --query SecretString --output text | python3 -c 'import json,sys; print(json.load(sys.stdin)[\"SHLINK_API_KEY\"])'"
  description = "Reads the API key from Secrets Manager rather than from Terraform state"
}
