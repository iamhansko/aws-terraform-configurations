# These outputs carry their value expressions directly rather than projecting a
# local.outputs map.
#
# That map exists to keep a root's outputs and the README written onto a VS Code
# instance from drifting apart, so it applies only to roots that declare
# module "vscode_ec2" (rules.md H-2). The instance here runs a Windows desktop
# reached over RDP with the Kiro IDE on it, not code-server, and no SSM
# association writes a README onto it - the person who connects gets a desktop
# and two shortcuts, not a file to read - so there is no second copy of these
# values to keep in step.
#
# What this root does borrow from H-2 is its position on secrets: a value a
# person has to be handed, but that Terraform should not print, is exposed as the
# command that retrieves it. Both passwords here are that case, and both are
# commands below. The _monolithic template's 03Password output printed the
# workshop password in the clear, wrapping it in nonsensitive() to get past
# Terraform's refusal - that is the one deliberate behavioural divergence in this
# conversion, and app_secret/outputs.tf records what it does and does not fix.
output "rdp_endpoint" {
  value       = module.windows_ec2.rdp_endpoint
  description = "Address and port to put into the RDP client, reproducing the _monolithic template's 01RdpUrl output. It answers within a minute of apply and that means nothing: the account you are about to log in as does not exist for several more minutes, and the instance reboots once at the end. The rdp_status check in setup_check_results_command tells waiting from broken"
}
output "workshop_username" {
  value       = module.windows_ec2.workshop_username
  description = "Account to log in as, reproducing the _monolithic template's 02Username output"
}
output "workshop_password_command" {
  value       = module.app_secret.get_password_command
  description = "Retrieves the workshop account's password from Secrets Manager, decoded out of the JSON secret string. A command rather than the value - this replaces the _monolithic template's 03Password output, which printed the password into the apply summary and any log that captured it. Decoded because the raw secret string escapes <, > and & as \\u003c, \\u003e and \\u0026, and copying the escaped form is a wrong password; app_secret/outputs.tf has the detail. The same secret is what the instance reads at boot to create the account, so this is the authoritative copy rather than a second one"
}
output "administrator_password_command" {
  value       = "${module.key_pair.private_key_command} > /tmp/${module.key_pair.key_pair_id}.pem && chmod 600 /tmp/${module.key_pair.key_pair_id}.pem && aws ec2 get-password-data --instance-id ${module.windows_ec2.instance_id} --priv-launch-key /tmp/${module.key_pair.key_pair_id}.pem --query PasswordData --output text"
  description = "Retrieves the built-in Administrator password, which is a command and not a value for a reason Terraform cannot work around: EC2 generates that password on the instance and encrypts it with the key pair's public half, so it exists nowhere in this configuration. Composed in the root because it needs the key pair module's parameter path and the instance module's id, and neither module knows about the other (rules.md C-1). Returns an empty string for the first few minutes after launch, before EC2Launch has published it"
}
output "instance_id" {
  value       = module.windows_ec2.instance_id
  description = "ID of the instance, for describe-instances, get-password-data and start-session"
}
output "setup_check_results_command" {
  value       = module.windows_ec2.setup_check_results_command
  description = "What the three readiness check associations printed: setup_log (the tail of the setup log and the status marker), rdp_status (Terminal Services, the workshop account, the RDP listener) and app_status (the launcher scripts and the clone, and whether the game server and client are listening). They run on their own once the instance registers with SSM, about a quarter of an hour after apply returns, so this sends nothing to the instance. Apply does not wait for them - an error before then means there is no execution yet, not that the setup failed. First thing to read when RDP rejects the password: every step of the setup runs inside a try block, so a failure appears as the log stopping rather than as anything Terraform reported"
}
output "setup_check_association_ids" {
  value       = module.windows_ec2.setup_check_association_ids
  description = "ID of each readiness check association. aws ssm start-associations-once --association-ids <id> runs one again - app_status after starting the game server, for instance"
}
output "private_key_command" {
  value       = module.key_pair.private_key_command
  description = "Retrieves the generated private key from Parameter Store. Needed to decrypt the Administrator password, which administrator_password_command does in one step; on its own it is for inspecting the instance when the setup did not complete"
}
output "user_data_byte_length" {
  value       = module.windows_ec2.user_data_byte_length
  description = "Size of the rendered setup script against EC2's 16384 byte limit. Worth reading once: the script reproduced from the _monolithic template already takes about 15 KB, so additional_user_data has roughly 1 KB to work with before the instance stops being creatable"
}
output "cognito_user_pool_id" {
  value       = module.cognito_user_pool.user_pool_id
  description = "User pool id, which the game server reads as COGNITO_USER_POOL_ID"
}
output "cognito_client_id" {
  value       = module.cognito_user_pool.client_id
  description = "App client id, which the game server reads as COGNITO_CLIENT_ID"
}
output "cognito_players_command" {
  value       = module.cognito_user_pool.list_users_command
  description = "Players registered in the pool. Empty until someone signs up through the game client, which is the expected state after apply"
}
output "dynamodb_table_names" {
  value       = module.dynamodb_tables.table_names
  description = "Table name per logical key, in the same shape the game server receives them as DYNAMODB_TABLE_* environment variables. Reading this is how the six names the instance was given can be checked without logging in"
}
output "dynamodb_status_command" {
  value       = module.dynamodb_tables.describe_tables_command
  description = "Status and key schema of all six tables in one pass. ACTIVE on every one is the check"
}
output "vpc_id" {
  value       = module.network.vpc_id
  description = "ID of the VPC"
}
output "public_subnet_id" {
  value       = module.network.public_subnet_a_id
  description = "ID of the public subnet holding the instance"
}
