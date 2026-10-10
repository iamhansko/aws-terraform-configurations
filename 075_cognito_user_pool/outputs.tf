# Every value here is a projection of local.outputs in main.tf, which the README written onto the workbench
# renders from the same map - so no value expression exists twice, and an output cannot be added without also
# appearing in that README (rules.md B-5/H-2).
#
# description is the one thing that cannot be projected: Terraform rejects an expression in an output's
# description ("Variables not allowed"), so the wording is a literal on both sides.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "The workbench. The game's source, at the commit that was built, is in ~/spirit-of-kiro"
}
output "game_client_url" {
  value       = local.outputs.game_client_url.value
  description = "The _monolithic template's GameClient output. Sign up, then play - the server reaches the browser through this distribution under /ws*"
}
output "game_build_command" {
  value       = local.outputs.game_build_command.value
  description = "How the clone, the client build and both image builds went. When it failed, aws ssm describe-association-execution-targets with the execution ID shown here gives the command ID, and aws ssm get-command-invocation on that command ID shows the script output"
}
output "server_service_events_command" {
  value       = local.outputs.server_service_events_command.value
  description = "The service's own account of its tasks. A task that cannot pull, start or pass the health check is reported here first"
}
output "server_target_health_command" {
  value       = local.outputs.server_target_health_command.value
  description = "healthy for both tasks once the service is steady"
}
output "server_log_command" {
  value       = local.outputs.server_log_command.value
  description = "Sign-ups, websocket connections and the calls the server makes to Bedrock and the item image service"
}
output "image_generation_service_events_command" {
  value       = local.outputs.image_generation_service_events_command.value
  description = "Its load balancer is internal; the server is its only caller"
}
output "image_generation_log_command" {
  value       = local.outputs.image_generation_log_command.value
  description = "Image generation requests and their Bedrock calls"
}
output "list_users_command" {
  value       = local.outputs.list_users_command.value
  description = "The user pool, read directly. The server confirms each sign-up itself, so a player stuck in UNCONFIRMED means the server failed partway"
}
output "memorydb_ping_command" {
  value       = local.outputs.memorydb_ping_command.value
  description = "The item image service's store. PONG means the cluster answers on the address the service was given"
}
output "bedrock_image_model_command" {
  value       = local.outputs.bedrock_image_model_command.value
  description = "Whether the model the item image service invokes is still ACTIVE, in the region it invokes it in. A model past end of life answers ResourceNotFoundException here and in the service's log, and items are then stored without an image. ~/bedrock_models.txt is the deploy region's list at boot, as the _monolithic template wrote it, which is not where the services call Bedrock"
}
output "client_invalidate_command" {
  value       = local.outputs.client_invalidate_command.value
  description = "The edge keeps index.html for up to a day. The build step invalidates on its own; this is for a build run outside it"
}
output "private_key_command" {
  value       = local.outputs.private_key_command.value
  description = "Retrieves the generated private key from Parameter Store. No security group opens port 22; this is for the case where the SSM agent is what is broken"
}
