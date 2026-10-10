# Every value here is a projection of local.outputs in main.tf, which the README written onto the workbench renders
# from the same map - so no value expression exists twice, and an output cannot be added without also appearing
# in that README (rules.md B-5/H-2).
#
# description is the one thing that cannot be projected: Terraform rejects an expression in an output's
# description ("Variables not allowed"), so the wording is a literal on both sides.
output "vs_code" {
  value       = local.outputs.vs_code.value
  description = "code-server on the workbench. Every command below runs from its terminal"
}
output "gomoku_web" {
  value       = local.outputs.gomoku_web.value
  description = "The S3 static website, calling the ranking API from the browser. Empty until games have been played"
}
output "client_zip_file_download" {
  value       = local.outputs.client_zip_file_download.value
  description = "client.zip holds two configured Windows clients, one per player. Run both on a Windows machine and press start in each - FlexMatch pairs the two"
}
output "client_zip_presign_command" {
  value       = local.outputs.client_zip_presign_command.value
  description = "A one-hour download link for the same zip, for a Windows machine that is not signed in to the console"
}
output "player_credentials" {
  value       = local.outputs.player_credentials.value
  description = "What the two clients log in with. Not a secret and it protects nothing: game-match-request creates a player row with whatever password the first request for a name brings, compares it in plain text afterwards, and the API has no authorizer"
}
output "api_invoke_url" {
  value       = local.outputs.api_invoke_url.value
  description = "The stage both clients and the leaderboard page were configured with: POST /matchrequest, POST /matchstatus, GET /ranking"
}
output "matchmaking_configuration_name" {
  value       = local.outputs.matchmaking_configuration_name.value
  description = "The matchmaker game-match-request starts tickets against. Its rule set pairs two players whose scores are within 300, widening to 1000 over 30 seconds"
}
output "fleet_id" {
  value       = local.outputs.fleet_id.value
  description = "The Windows fleet game sessions are placed on, behind the alias and the queue below"
}
output "fleet_status_command" {
  value       = local.outputs.fleet_status_command.value
  description = "ACTIVE once the build has installed and its server processes have called ProcessReady. It says nothing about whether an instance is up now - a fleet whose instances have all been replaced stays ACTIVE. The capacity command below says that"
}
output "fleet_capacity_command" {
  value       = local.outputs.fleet_capacity_command.value
  description = "Matches are placed only while ACTIVE is at least 1. PENDING with ACTIVE 0 is an instance still booting - over ten minutes on Windows - and a match made meanwhile waits in the queue, up to its timeout"
}
output "fleet_events_command" {
  value       = local.outputs.fleet_events_command.value
  description = "Where a fleet stuck in ACTIVATING or sent to ERROR says why - a server process that crashed or never called ProcessReady shows up here, and so does an instance GameLift replaced (INSTANCE_RECYCLED)"
}
output "game_session_queue_name" {
  value       = local.outputs.game_session_queue_name.value
  description = "The queue the matchmaker places matches through, with the fleet's alias as its destination"
}
output "game_result_queue_url" {
  value       = local.outputs.game_result_queue_url.value
  description = "The game server sends each finished game here; game-sqs-process folds it into the player table, and the table's stream feeds the leaderboard"
}
output "ranking_api_command" {
  value       = local.outputs.ranking_api_command.value
  description = "The request the leaderboard page makes. [] before any game has finished; a 500 here with the function working means the integration, not the function"
}
output "rank_reader_invoke_command" {
  value       = local.outputs.rank_reader_invoke_command.value
  description = "Invokes game-rank-reader directly, bypassing API Gateway. A timeout here is the function failing to reach Redis"
}
output "redis_ranking_command" {
  value       = local.outputs.redis_ranking_command.value
  description = "The sorted set itself. Runs from this workbench, which the cache's security group admits on the Redis port; from elsewhere, a CloudShell VPC environment in this VPC with the GomokuDefault group works too"
}
