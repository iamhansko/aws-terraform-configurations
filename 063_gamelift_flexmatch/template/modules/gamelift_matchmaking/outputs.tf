output "configuration_name" {
  value       = awscc_gamelift_matchmaking_configuration.configuration.name
  description = "Name of the matchmaking configuration"
}
output "configuration_arn" {
  value       = awscc_gamelift_matchmaking_configuration.configuration.arn
  description = "ARN of the matchmaking configuration, for the root's check that the SNS topic policy's SourceArn condition names it"
}
output "rule_set_name" {
  value       = awscc_gamelift_matchmaking_rule_set.rule_set.name
  description = "Name of the matchmaking rule set"
}
