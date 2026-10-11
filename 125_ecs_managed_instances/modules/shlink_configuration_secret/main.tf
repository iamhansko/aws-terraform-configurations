# Shlink's configuration, and the API key both containers share, as one Secrets Manager secret.
#
# The API key replaces a Lambda function. The _monolithic template generated it with a CloudFormation custom
# resource whose handler returned uuid.uuid4() - and under aws_lambda_invocation that handler could not have
# run: it imported cfnresponse, which exists only in CloudFormation's inline-code runtime, and read
# event["RequestType"], which only CloudFormation sends. random_uuid is the same value with no function,
# no role and no archive behind it.
resource "random_uuid" "api_key" {}
resource "aws_secretsmanager_secret" "configuration" {
  # name_prefix rather than CloudFormation's generated name, so a second copy of this project in the same
  # account does not collide - and a secret pending deletion does not block the next apply.
  name_prefix = var.name_prefix
  description = "Shlink and Shlink Web Client configuration, including the shared API key"
  # Days a destroyed secret can be restored. Zero deletes it immediately, which suits a demo that is applied
  # and destroyed repeatedly; the API key in it is regenerated on every create anyway.
  recovery_window_in_days = var.recovery_window_in_days
}
# jsonencode rather than the heredoc JSON the _monolithic template interpolated into, so no value can break
# the document's quoting. The keys are the ones the task definitions' secrets entries pick out with
# <secret-arn>:<key>::. The original also stored SHLINK_PORT and WEB_CLIENT_PORT, which no task definition
# read - they are docker/docker-compose.yaml's host port mappings, carried over - so they are not repeated.
resource "aws_secretsmanager_secret_version" "configuration" {
  secret_id = aws_secretsmanager_secret.configuration.id
  secret_string = jsonencode({
    DEFAULT_DOMAIN     = var.short_domain
    IS_HTTPS_ENABLED   = "true"
    SHLINK_API_KEY     = random_uuid.api_key.result
    SHLINK_SERVER_URL  = "https://${var.short_domain}"
    SHLINK_SERVER_NAME = var.server_name
    TIMEZONE           = var.timezone
  })
}
