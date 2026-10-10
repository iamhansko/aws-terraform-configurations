output "build_id" {
  value       = aws_gamelift_build.build.id
  description = "ID of the build"
}
output "fleet_id" {
  value       = aws_gamelift_fleet.fleet.id
  description = "ID of the fleet"
}
output "fleet_arn" {
  value       = aws_gamelift_fleet.fleet.arn
  description = "ARN of the fleet"
}
output "alias_arn" {
  value       = aws_gamelift_alias.alias.arn
  description = "ARN of the alias the queue places sessions on"
}
output "queue_arn" {
  value       = aws_gamelift_game_session_queue.queue.arn
  description = "ARN of the game session queue, which the matchmaking configuration places matches through"
}
output "queue_name" {
  value       = aws_gamelift_game_session_queue.queue.name
  description = "Name of the game session queue"
}
output "fleet_status_command" {
  value       = "aws gamelift describe-fleet-attributes --fleet-ids ${aws_gamelift_fleet.fleet.id} --query 'FleetAttributes[0].Status' --output text && aws gamelift describe-fleet-utilization --fleet-ids ${aws_gamelift_fleet.fleet.id} --query 'FleetUtilization[0].[ActiveServerProcessCount,ActiveGameSessionCount,CurrentPlayerSessionCount]' --output text"
  description = "Fleet status, then active server processes, game sessions and player sessions. ACTIVE with a non-zero process count is a fleet FlexMatch can place on"
}
output "server_access_command" {
  value       = "GAME_SERVER_INSTANCE=$(aws gamelift describe-instances --fleet-id ${aws_gamelift_fleet.fleet.id} --output text --query 'Instances[0].InstanceId'); aws gamelift get-instance-access --fleet-id ${aws_gamelift_fleet.fleet.id} --instance-id $GAME_SERVER_INSTANCE"
  description = "Credentials for RDP into a fleet instance, reproducing the _monolithic template's 04GameServerAccess output (https://docs.aws.amazon.com/gameliftservers/latest/developerguide/fleets-remote-access.html)"
}
