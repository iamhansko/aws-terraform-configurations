# FlexMatch - the subject of this project, and the part the conversion dropped.
#
# The _monolithic template has AWS::GameLift::MatchmakingRuleSet and
# AWS::GameLift::MatchmakingConfiguration only as NOT CONVERTED comments,
# because hashicorp/aws has no resource for either. Without them,
# game-match-request calls StartMatchmaking(ConfigurationName =
# 'GomokuMatchConfig') against a configuration that does not exist, catches
# the exception and returns MatchError; no ticket is ever created, the topic
# never hears anything, and the fleet never hosts a game. hashicorp/awscc
# carries both types, generated from the same CloudFormation schemas the
# template used.

# The rule set body is built from a typed object rather than read from a file.
#
# The template carried the body as a JSON string inside Fn::Sub. Parsed, it is
# the same document as Ruleset/GomokuRuleSet.json in the sample repository the
# root's git_clone_url names - but that file exists only in the clone on the
# instance, at apply time, and a variant does not read paths outside itself
# (rules.md A-1). So the document is the root's matchmaking_rule_set variable,
# and the JSON is rendered here.
#
# Optional attributes the caller left unset arrive as null, and a rule set with
# "operation": null in a distance rule is not the same document as one without
# the key, so nulls are dropped before encoding.
locals {
  rule_set_document = {
    ruleLanguageVersion = var.rule_set.ruleLanguageVersion
    playerAttributes    = var.rule_set.playerAttributes
    teams               = var.rule_set.teams
    rules = [
      for rule in var.rule_set.rules : { for key, value in rule : key => value if value != null }
    ]
    expansions = var.rule_set.expansions
  }
  rule_set_body = jsonencode(local.rule_set_document)
}
resource "awscc_gamelift_matchmaking_rule_set" "rule_set" {
  name          = var.rule_set_name
  rule_set_body = local.rule_set_body

  lifecycle {
    # RuleSetBody is limited to 65535 characters. Known at plan time, because
    # the document is entirely configuration, so this fails before anything is
    # created rather than as a validation error from GameLift.
    precondition {
      condition     = length(local.rule_set_body) <= 65535
      error_message = "The rendered matchmaking rule set exceeds the 65535 characters GameLift accepts."
    }
  }
}
resource "awscc_gamelift_matchmaking_configuration" "configuration" {
  name                    = var.configuration_name
  rule_set_name           = awscc_gamelift_matchmaking_rule_set.rule_set.name
  acceptance_required     = var.acceptance_required
  request_timeout_seconds = var.request_timeout_seconds
  flex_match_mode         = "WITH_QUEUE"
  game_session_queue_arns = var.game_session_queue_arns
  notification_target     = var.notification_target
}
