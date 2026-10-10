# FlexMatch, which is what this project is about and what the conversion dropped.
#
# The _monolithic template carried AWS::GameLift::MatchmakingRuleSet and AWS::GameLift::MatchmakingConfiguration
# as NOT CONVERTED comments, because the AWS provider has no matchmaking resources at all. Without them
# game-match-request calls StartMatchmaking against a configuration that does not exist, every client gets
# TicketId "MatchError", and nothing downstream - the SNS events, game-match-event, game-match-status, the game
# session on the fleet - ever runs.
#
# The awscc provider (Cloud Control API) has both, with the CloudFormation property names in snake case. This is
# the only module in the root that uses it.
resource "awscc_gamelift_matchmaking_rule_set" "rule_set" {
  name          = var.rule_set_name
  rule_set_body = var.rule_set_body
}
resource "awscc_gamelift_matchmaking_configuration" "configuration" {
  name                    = var.configuration_name
  acceptance_required     = var.acceptance_required
  request_timeout_seconds = var.request_timeout_seconds
  # The rule set's name taken from the resource rather than from the variable, so the configuration is created
  # after the rule set exists - CreateMatchmakingConfiguration refuses a rule set name it cannot find.
  rule_set_name           = awscc_gamelift_matchmaking_rule_set.rule_set.name
  game_session_queue_arns = var.game_session_queue_arns
  notification_target     = var.notification_topic_arn
}
