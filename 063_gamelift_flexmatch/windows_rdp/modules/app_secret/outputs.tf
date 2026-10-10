# No output carries the password.
#
# The _monolithic template had one - its 03GameClientAccess output printed
# "Password : <value>", read out of the secret_plaintext_lambda invocation's
# result, reproducing the CloudFormation stack's output of the same name. (It
# would have failed instead, for the reasons main.tf gives, but the intent was
# to print it.) Not printing it is a deliberate divergence, and the reason is
# that the value is reachable anyway: Secrets Manager holds it, the instance role can
# read it, and get_secret_value_command below retrieves it in one line. Printing
# it as well only adds copies - the apply summary, terminal scrollback, and any
# CI log that captures them.
#
# What it does not fix: terraform.tfstate still holds the password in plaintext,
# because random_password generated it. The secret is what a real version of this
# would read at runtime instead of generating at plan time.
output "secret_arn" {
  value       = aws_secretsmanager_secret.workshop_user.arn
  description = "ARN of the secret holding the workshop credential"
}
output "secret_id" {
  value       = aws_secretsmanager_secret.workshop_user.id
  description = "Identifier the Get-SECSecretValue call on the instance passes as -SecretId. For this resource it is the ARN, not the name"
}
output "secret_name" {
  value       = aws_secretsmanager_secret.workshop_user.name
  description = "Generated name of the secret, which is name_prefix plus a provider-chosen suffix"
}
# The retrieval command rather than the value, which is the form the repository
# uses for anything a person has to be handed but Terraform should not print
# (rules.md H-2 makes the same point about README entries). This replaces the
# _monolithic template's 03GameClientAccess output, which printed the password.
output "get_secret_value_command" {
  value       = "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.workshop_user.arn} --query SecretString --output text"
  description = "Retrieves the workshop username and password as the JSON object the instance parses. This is the stored JSON, not the password - a <, > or & in the password appears here as \\u003c, \\u003e or \\u0026. Use get_password_command to log in"
}
# The password decoded out of the JSON, because the raw SecretString is not the
# password whenever it contains <, > or &. Decoded with Python rather than jq,
# which is not installed by default on Windows or macOS.
#
# jsonencode always escapes those three as \u003c, \u003e and \u0026 (Go's
# HTML-safe JSON encoding; Terraform has no switch for it), and the default
# password_override_special includes all three, so a 20-character password drawn
# from it contains one about half the time. The secret then holds six literal
# characters where the Windows account has one. ConvertFrom-Json on the instance
# decodes the escape, so the setup creates the account with the right password -
# and a person copying the value out of get_secret_value_command, or out of the
# console's Plaintext tab, types a different one. RDP rejects it with
# 0xC000006A (bad password for an existing account) while the account, the
# secret and the instance are all correct, which is what this output exists to
# prevent.
output "get_password_command" {
  value       = "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.workshop_user.arn} --query SecretString --output text | python3 -c 'import json,sys; print(json.load(sys.stdin)[\"password\"])'"
  description = "Retrieves just the workshop password, JSON-decoded, which is what the RDP login needs. Requires python3 (use python where that is the name of the interpreter)"
}
# An input handed back out, so the caller does not keep a second copy of the
# username to build its own outputs from (rules.md B-5). It matters more than
# usual here: this is the name written into the secret, so it is the half of the
# credential pair that has to match the Windows account.
output "username" {
  value       = var.username
  description = "Account name stored in the secret, and the Windows local account the RDP login uses"
}
output "version_id" {
  value       = aws_secretsmanager_secret_version.workshop_user.version_id
  description = "Version holding the current password. Re-exposed so a caller can tell an empty secret - which is what the instance hits as ResourceNotFoundException if it boots first - from a populated one"
}
