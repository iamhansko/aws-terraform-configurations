output "build_id" {
  value       = aws_gamelift_build.build.id
  description = "ID of the GameLift build"
}
output "fleet_id" {
  value       = aws_gamelift_fleet.fleet.id
  description = "ID of the fleet, for the status and event commands in the README"
}
output "alias_id" {
  value       = aws_gamelift_alias.alias.id
  description = "ID of the alias in front of the fleet"
}
output "queue_name" {
  value       = aws_gamelift_game_session_queue.queue.name
  description = "Name of the game session queue"
}
output "queue_arn" {
  value       = aws_gamelift_game_session_queue.queue.arn
  description = "ARN of the game session queue, which the matchmaking configuration places matches through"
}
