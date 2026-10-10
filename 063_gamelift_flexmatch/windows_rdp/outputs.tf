# These outputs carry their value expressions directly rather than projecting a
# local.outputs map.
#
# That map exists to keep a root's outputs and the README written onto a VS Code
# instance from drifting apart, so it applies only to roots that declare
# module "vscode_ec2" (rules.md H-2). There is no code-server here. The instance
# is a Windows desktop reached over RDP, and the person who connects gets two
# game client shortcuts, not a file to read - so there is no second copy of
# these values to keep in step.
#
# What this root does take from H-2 is its position on secrets: a value a person
# has to be handed but Terraform should not print is exposed as the command that
# retrieves it. The _monolithic template's 03GameClientAccess output printed the
# workshop password in the clear (read back through a custom-resource Lambda
# that could not have worked; modules/app_secret has the detail). Here it is
# workshop_password_command.
#
# The first five outputs are the template's five, in its order.
output "game_client_download_url" {
  value       = "https://${local.region}.console.aws.amazon.com/s3/object/${module.game_source_bucket.bucket_name}?region=${local.region}&bucketType=general&prefix=${var.client_archive_s3_key}"
  description = "Console page for client.zip, the two game clients configured for this deployment's API - the _monolithic template's 01GameClientZipFileDownload. The object exists only once the instance's setup has finished; game_artifacts_uploaded waits for that, so after a successful apply it is there"
}
output "leaderboard_url" {
  value       = module.web_bucket.website_url
  description = "Gomoku leaderboard page - the _monolithic template's 02GomokuWeb. Empty until a game has been played: the ranking is fed from the player table's stream"
}
output "game_client_access" {
  value       = "Computer : ${module.windows_ec2.public_ip} / Username : ${module.windows_ec2.workshop_username} / Password : run workshop_password_command"
  description = "RDP connection details for the game client desktop - the _monolithic template's 03GameClientAccess, without the password it printed. RDP answers long before the account exists; rdp_status_command tells waiting from broken"
}
output "game_server_access_command" {
  value       = module.gamelift_fleet.server_access_command
  description = "Credentials for RDP into a GameLift fleet instance - the _monolithic template's 04GameServerAccess (https://docs.aws.amazon.com/gameliftservers/latest/developerguide/fleets-remote-access.html)"
}
output "redis_command" {
  value       = "redis6-cli -h ${module.redis_cluster.address} -p ${module.redis_cluster.port} ZRANGE Rating 0 -1 WITHSCORES"
  description = "Reads the leaderboard's sorted set straight from Redis - the _monolithic template's 05ElasticacheRedisConnect. The node has no public address and admits only members of its security group, so run this from a CloudShell VPC environment launched in this VPC's private subnets with the gomoku_security_group_name group (GomokuDefault by default) attached"
}
output "workshop_password_command" {
  value       = module.app_secret.get_password_command
  description = "Retrieves the workshop account's password from Secrets Manager, JSON-decoded. A command rather than the value, replacing the password the _monolithic template printed into the apply summary"
}
output "administrator_password_command" {
  value       = "${module.key_pair.private_key_command} > /tmp/${module.key_pair.key_pair_id}.pem && chmod 600 /tmp/${module.key_pair.key_pair_id}.pem && aws ec2 get-password-data --instance-id ${module.windows_ec2.instance_id} --priv-launch-key /tmp/${module.key_pair.key_pair_id}.pem --query PasswordData --output text"
  description = "Retrieves the built-in Administrator password, which EC2 generates on the instance and encrypts with the key pair. Composed here because it needs both the key pair's parameter and the instance id, and neither module knows about the other (rules.md C-1)"
}
output "api_invoke_url" {
  value       = module.gomoku_api.invoke_url
  description = "Base URL of the published API stage, which both game clients have as MATCH_SERVER_API. Routes: /ranking (GET), /matchrequest and /matchstatus (POST)"
}
output "matchmaking_configuration_name" {
  value       = module.gamelift_matchmaking.configuration_name
  description = "The FlexMatch configuration game-match-request starts matchmaking against"
}
output "matchmaking_describe_command" {
  value       = module.gamelift_matchmaking.describe_configuration_command
  description = "The matchmaker's rule set, notification target and queue as GameLift has them"
}
output "fleet_id" {
  value       = module.gamelift_fleet.fleet_id
  description = "ID of the GameLift fleet"
}
output "fleet_status_command" {
  value       = module.gamelift_fleet.fleet_status_command
  description = "Fleet status and its active process, game session and player session counts"
}
output "instance_id" {
  value       = module.windows_ec2.instance_id
  description = "ID of the Windows desktop instance"
}
output "rdp_status_command" {
  value       = module.windows_ec2.rdp_status_command
  description = "Terminal Services, the workshop account, the RDP port, the setup's completion marker and the last lines of C:\\ProgramData\\GameliftWorkshop\\setup.log, read through SSM"
}
output "setup_log_command" {
  value       = module.windows_ec2.setup_log_command
  description = "The last 40 lines of the setup log on the instance, read through SSM. The first thing to read when game_artifacts_uploaded fails"
}
output "game_source_bucket_name" {
  value       = module.game_source_bucket.bucket_name
  description = "Bucket holding server.zip, client.zip and the uploaded clone with Lambda/code.zip"
}
output "private_key_command" {
  value       = module.key_pair.private_key_command
  description = "Retrieves the generated private key from Parameter Store"
}
output "user_data_byte_length" {
  value       = module.windows_ec2.user_data_byte_length
  description = "Size of the rendered setup script against EC2's 16384 byte limit"
}
