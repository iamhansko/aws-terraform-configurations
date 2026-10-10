# The RDP credential for the workshop account, generated here and stored where
# the instance can read it back at boot.
#
# Three resources, because CloudFormation's GenerateSecretString has no Terraform
# equivalent. aws_secretsmanager_secret only declares the container, and asking
# Secrets Manager to invent the value would put it somewhere Terraform cannot
# read - so the generation moves to random_password and the value is written as a
# secret version. The conversion in _monolithic left GenerateSecretString as a
# "TODO cfn2tf: unmapped" comment, so its secret was created with no version at
# all: Get-SECSecretValue in the userdata raised ResourceNotFoundException
# inside the try block, no workshop account was created, and the RDP login this
# project hands out could never have worked.
#
# The template's generator settings map one to one: PasswordLength 20 is
# password_length; RequireEachIncludedType is the four min_* = 1 below;
# ExcludeCharacters "@/\ and IncludeSpace false are password_override_special,
# Secrets Manager's default punctuation with those removed and no space.
#
# The _monolithic template needed a fourth piece for this and it could never have
# worked. CloudFormation cannot resolve a secret's value into an output, so the
# template carried a SecretPlaintextLambda custom resource - an IAM role, an
# inline policy, AWSLambdaBasicExecutionRole, an archive_file, a
# aws_lambda_function and a aws_lambda_invocation - whose only job was to read
# the password back out, into an output that then printed it. It failed twice
# over: lambda_src/secret_plaintext_lambda/index.py imports cfnresponse, which
# AWS injects only into functions whose code was inlined as ZipFile and not into
# a zip from archive_file; and even vendored in, the handler speaks the custom
# resource protocol, reading event['RequestType'] and ResourceProperties and
# POSTing to event['ResponseURL'], while aws_lambda_invocation does a
# synchronous invoke, sends neither key, and reads a return value the handler
# never produces. None of it is reproduced and none of it should be reinstated.
# lambda_src/ is left on disk unreferenced, because the _monolithic copy still
# names it.
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
