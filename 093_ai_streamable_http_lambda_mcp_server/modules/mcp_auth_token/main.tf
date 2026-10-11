# The bearer token the MCP API's authorizer accepts.
#
# The _monolithic template took it as a variable defaulting to "Peccy" - the McpAuthToken parameter of the SAM
# template, whose own default lived in samconfig.toml - and then copied it into four places: the authorizer's
# environment, the Q CLI association's command document, the mcp.json written on the workbench, and a plain
# output. None of those is a secret store, and the default meant every deployment of the template accepted the
# same word.
#
# Here it is generated and kept in one SecureString parameter. The authorizer reads the parameter, and the
# workbench reads it to write the MCP client's header file; nothing else holds the value.
#
# It is still in Terraform state: random_password puts it there, and so does the parameter's value. An
# ephemeral random_password with the parameter's write-only value_wo would keep it out of state, but both need
# Terraform 1.11, newer than the >= 1.9 this repository is written against.
resource "random_password" "token" {
  length = var.length
  # Letters and digits only. The token is sent as "Authorization: Bearer <token>", written into a header file
  # by a shell script and compared verbatim by the authorizer - a character set with no quoting rules is one
  # less way for any of those three to disagree.
  special = false
}
resource "aws_ssm_parameter" "token" {
  name        = var.parameter_name
  description = "Bearer token the MCP API authorizer accepts"
  type        = "SecureString"
  # The AWS managed aws/ssm key, which is the parameter default. Its key policy admits any principal in the
  # account that calls through Parameter Store, so ssm:GetParameter is the only grant a reader needs. A customer
  # managed key would also need kms:Decrypt in the authorizer's policy.
  value = random_password.token.result
}
