output "rule_set_name" {
  value       = awscc_gamelift_matchmaking_rule_set.rule_set.name
  description = "Name of the rule set"
}
output "rule_set_arn" {
  value       = awscc_gamelift_matchmaking_rule_set.rule_set.arn
  description = "ARN of the rule set"
}
output "configuration_name" {
  value       = awscc_gamelift_matchmaking_configuration.configuration.name
  description = "Name of the matchmaking configuration, which game-match-request passes to StartMatchmaking"
}
output "configuration_arn" {
  value       = awscc_gamelift_matchmaking_configuration.configuration.arn
  description = "ARN of the matchmaking configuration"
}
output "rule_set_body" {
  value       = local.rule_set_body
  description = "The rule set document as sent to GameLift, so it can be compared with the sample repository's Ruleset/GomokuRuleSet.json without an apply"
}
output "describe_configuration_command" {
  value       = "aws gamelift describe-matchmaking-configurations --names ${awscc_gamelift_matchmaking_configuration.configuration.name} --query 'Configurations[0].[Name,RuleSetName,NotificationTarget,GameSessionQueueArns[0]]' --output text"
  description = "The matchmaker's name, rule set, notification target and queue as GameLift has them"
}
