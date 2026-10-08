# The RDP credential for the workshop account, generated here and stored where
# the instance can read it back at boot.
#
# Three resources, because CloudFormation's GenerateSecretString has no Terraform
# equivalent. aws_secretsmanager_secret only declares the container, and asking
# Secrets Manager to invent the value would put it somewhere Terraform cannot
# read - so the generation moves to random_password and the value is written as a
# secret version.
#
# The _monolithic template needed a fourth piece for this and it could never have
# worked. CloudFormation cannot resolve a secret's value into an output, so the
# template carried a SecretPlaintextLambda custom resource - an IAM role, an
# inline policy, AWSLambdaBasicExecutionRole, an archive_file, a
# aws_lambda_function and a aws_lambda_invocation - whose only job was to read
# the password back out. The conversion's own comment records why it failed
# twice over: index.py imported cfnresponse, which AWS injects only into
# functions whose code was inlined as ZipFile and not into a zip from
# archive_file; and even vendored in, the handler spoke the custom resource
# protocol, reading event['RequestType'] and POSTing to event['ResponseURL'],
# while aws_lambda_invocation does a synchronous invoke and reads the return
# value. None of it is reproduced and none of it should be reinstated.
resource "random_password" "workshop_user" {
  length           = var.password_length
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = var.password_override_special
}
resource "aws_secretsmanager_secret" "workshop_user" {
  name_prefix = var.name_prefix

  # Demo teardown. Without this, destroy only schedules deletion: the secret
  # lingers for 30 days holding its name, and a re-apply inside that window gets
  # InvalidRequestException rather than a new secret.
  recovery_window_in_days = var.recovery_window_in_days
}
# The shape the instance parses. The _monolithic template's SecretStringTemplate
# was {"username": "<Username>"} with the generated value placed under
# GenerateStringKey "password", and the userdata reads exactly that:
#
#   ($SecretValue.SecretString | ConvertFrom-Json).password
#
# so the two key names are load-bearing, not descriptive. Renaming either one
# leaves the parse returning $null, ConvertTo-SecureString failing on an empty
# string, and no workshop account on the instance - with apply already reported
# as successful.
resource "aws_secretsmanager_secret_version" "workshop_user" {
  secret_id = aws_secretsmanager_secret.workshop_user.id
  secret_string = jsonencode({
    username = var.username
    password = random_password.workshop_user.result
  })
}
