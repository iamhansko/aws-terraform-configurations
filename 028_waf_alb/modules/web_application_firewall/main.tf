# The web ACL, which is the whole subject of this project: everything else here exists so that there is
# something for it to be in front of.
#
# The _monolithic template declared the two AWS managed rule groups as two hand-written rule blocks that
# differ only in a name, a priority and a metric name. They are a map here instead, keyed by the rule group's
# own name and rendered through a dynamic block, for the reason given above the block.
resource "aws_wafv2_web_acl" "web_acl" {
  name        = var.name
  description = var.description
  # REGIONAL, and this is not a free choice - see the scope variable. A web ACL's scope decides what it can
  # be attached to, and an Application Load Balancer is a regional resource.
  scope = var.scope

  # allow, as the _monolithic template had it: a request that no rule matches is served. That is what makes
  # this demo legible - the same URL returns 200 or 403 depending only on whether a managed rule matched it.
  # Flipping this to block turns the project into the opposite demo, where everything is refused unless a
  # rule allows it, and the managed rule groups below do not allow anything (their rules only block and
  # count), so a block default serves nothing at all.
  default_action {
    dynamic "allow" {
      for_each = var.default_action == "allow" ? [1] : []
      content {}
    }
    dynamic "block" {
      for_each = var.default_action == "block" ? [1] : []
      content {}
    }
  }

  # A dynamic block over a map whose keys are the managed rule group names, rather than one hand-written
  # rule block per group.
  #
  # The keys are what makes this readable. The provider stores rule as a set, so a plan prints whole rule
  # blocks rather than indices - and a block written out by hand, identified only by its position in the
  # file, cannot be matched back to the rule group it came from when three of them move at once. Keyed by
  # name, the configuration says which group is at which priority in one place, and adding a group is one
  # map entry rather than a fifteen-line copy. The same argument is made for Cognito schema blocks in
  # 102_windows_rdp/modules/cognito_user_pool/main.tf.
  #
  # It also makes the constraints checkable at plan time. Duplicate priorities and a reused metric name are
  # both easy to introduce by copying an entry, and both are rejected by the WAF API rather than by
  # Terraform - so variables.tf checks them (rules.md B-1).
  dynamic "rule" {
    for_each = var.managed_rule_groups

    content {
      # "AWS-AWSManagedRulesSQLiRuleSet", which is exactly what the _monolithic template named its rules and
      # what the console names a rule it adds for a managed group. Derived rather than configured, so the
      # rule's name cannot name one group while the statement references another (rules.md B-1).
      name     = "${rule.value.vendor_name}-${rule.key}"
      priority = rule.value.priority

      # override_action applies to the group as a whole and is the single most consequential value in this
      # file.
      #
      #   none  - the group's own rules act as the vendor published them, so an SQLi rule blocks. This is
      #           what the _monolithic template set and what produces the 403 the demo is about.
      #   count - every match is recorded and nothing is blocked. The curl probes then return 200 while
      #           get-sampled-requests still shows them, which is how a rule group is evaluated against real
      #           traffic before it is allowed to refuse anything.
      #
      # Note that this is override_action and not action: a managed rule group statement must carry
      # override_action, and a rule with action instead fails the plan with "Insufficient override_action
      # blocks". The two are not interchangeable.
      override_action {
        dynamic "none" {
          for_each = rule.value.override_action == "none" ? [1] : []
          content {}
        }
        dynamic "count" {
          for_each = rule.value.override_action == "count" ? [1] : []
          content {}
        }
      }

      statement {
        managed_rule_group_statement {
          vendor_name = rule.value.vendor_name
          name        = rule.key
          # Null leaves the version unset, which pins nothing and tracks the vendor's default version. The
          # _monolithic template did the same by omission. Setting it is how a managed group is held still
          # while the vendor rolls a new default out.
          version = rule.value.version

          # Per-rule overrides inside the group, which is the finer-grained form of override_action above:
          # it leaves the rest of the group blocking and singles out individual rules. This is the usual
          # answer to one managed rule producing false positives on an application - setting the offending
          # rule to count rather than switching the whole group off.
          #
          # The key is the rule name as the vendor publishes it, e.g. SizeRestrictions_BODY or
          # NoUserAgent_HEADER in AWSManagedRulesCommonRuleSet. A name that does not exist in the group is
          # rejected by the WAF API during apply, not by the plan - there is no list of valid names in the
          # configuration to check against. aws wafv2 describe-managed-rule-group prints them.
          dynamic "rule_action_override" {
            for_each = rule.value.rule_action_overrides

            content {
              name = rule_action_override.key
              action_to_use {
                dynamic "allow" {
                  for_each = rule_action_override.value == "allow" ? [1] : []
                  content {}
                }
                dynamic "block" {
                  for_each = rule_action_override.value == "block" ? [1] : []
                  content {}
                }
                dynamic "count" {
                  for_each = rule_action_override.value == "count" ? [1] : []
                  content {}
                }
                dynamic "captcha" {
                  for_each = rule_action_override.value == "captcha" ? [1] : []
                  content {}
                }
                dynamic "challenge" {
                  for_each = rule_action_override.value == "challenge" ? [1] : []
                  content {}
                }
              }
            }
          }
        }
      }

      # Per-rule visibility, which is what makes a block attributable to a rule group afterwards.
      # metric_name is the name get-sampled-requests is asked for, so the two metric names the _monolithic
      # template chose - sqli-rule and base-rule - are the identifiers the demo's verification commands use.
      # With sampled_requests_enabled false those commands return nothing and a 403 becomes unexplainable.
      visibility_config {
        sampled_requests_enabled   = rule.value.sampled_requests_enabled
        cloudwatch_metrics_enabled = rule.value.cloudwatch_metrics_enabled
        metric_name                = rule.value.metric_name
      }
    }
  }

  # The web ACL's own visibility, covering requests handled by the default action as well as the totals per
  # rule. The metric name here is the one GetSampledRequests accepts as DefaultAction.
  visibility_config {
    sampled_requests_enabled   = var.sampled_requests_enabled
    cloudwatch_metrics_enabled = var.cloudwatch_metrics_enabled
    metric_name                = var.metric_name
  }
}
# The association, which is what actually puts the web ACL in the request path. A web ACL that is associated
# with nothing costs nothing and filters nothing, and nothing in a plan says so.
#
# It lives in this module rather than in the root even though it joins two modules, which is the one place
# this project departs from the usual "the root connects two modules" split (rules.md C-1). The reason is
# that an unassociated regional web ACL is not a half-built thing, it is an inert thing, so the association
# belongs with the ACL the way an app client belongs with its Cognito user pool. The ARN it attaches to is
# injected rather than looked up, so this module still never learns what kind of resource it is protecting
# (rules.md B-6).
#
# A map keyed by a caller-chosen label, not a list. The values are another module's output - a load balancer
# ARN that does not exist at plan time - and for_each keys have to be known at plan time, so toset() of those
# ARNs fails the plan with "Invalid for_each argument: the set includes values derived from resource
# attributes that cannot be determined until apply" (rules.md B-8). The label also lands in the resource
# address, so a plan says which target is being attached.
resource "aws_wafv2_web_acl_association" "web_acl_association" {
  for_each = var.associated_resource_arns

  resource_arn = each.value
  web_acl_arn  = aws_wafv2_web_acl.web_acl.arn
}
locals {
  # The rule group names in evaluation order.
  #
  # Iterating the map directly gives key order, which is alphabetical and therefore says nothing about when
  # a group runs. priority is what WAF evaluates in, so the summary and the sampled-request commands are
  # built in that order instead: pack priority and name into one sortable string, sort, unpack. The %04d
  # padding is what keeps 10 after 9 rather than between 1 and 2.
  rule_group_names_by_priority = [
    for packed in sort([for name, group in var.managed_rule_groups : format("%04d|%s", group.priority, name)]) :
    split("|", packed)[1]
  ]
  # Shared by every generated get-sampled-requests command. GNU date is what Amazon Linux has, which is what
  # these commands are meant to be pasted into - the README on the workbench instance.
  sampled_requests_time_window = "StartTime=$(date -u -d '${var.sampled_requests_window_minutes} minutes ago' +%s),EndTime=$(date -u +%s)"
  # One command per rule group, plus one for the default action.
  #
  # DefaultAction is the metric name WAF reserves for requests no rule matched, so that last line is how the
  # allowed half of the demo is confirmed. Without it a reader who sees nothing in the SQLi samples cannot
  # tell whether the probe was not blocked or whether sampling is off altogether.
  sampled_requests_commands = join("\n", concat(
    [
      for name in local.rule_group_names_by_priority :
      "aws wafv2 get-sampled-requests --scope ${var.scope} --web-acl-arn ${aws_wafv2_web_acl.web_acl.arn} --rule-metric-name ${var.managed_rule_groups[name].metric_name} --max-items ${var.sampled_requests_max_items} --time-window ${local.sampled_requests_time_window}"
    ],
    [
      "aws wafv2 get-sampled-requests --scope ${var.scope} --web-acl-arn ${aws_wafv2_web_acl.web_acl.arn} --rule-metric-name DefaultAction --max-items ${var.sampled_requests_max_items} --time-window ${local.sampled_requests_time_window}"
    ],
  ))
  # What is actually configured, flattened into something a person can read next to a 403. This is the
  # answer to "which group should have caught that" and it is not available from any resource attribute -
  # the web ACL's own attributes do not echo the rule set back.
  managed_rule_group_summary = join("\n", [
    for name in local.rule_group_names_by_priority :
    format(
      "priority %d  %s/%s  override_action=%s  metric=%s%s",
      var.managed_rule_groups[name].priority,
      var.managed_rule_groups[name].vendor_name,
      name,
      var.managed_rule_groups[name].override_action,
      var.managed_rule_groups[name].metric_name,
      length(var.managed_rule_groups[name].rule_action_overrides) == 0 ? "" : "  rule_action_overrides=${jsonencode(var.managed_rule_groups[name].rule_action_overrides)}",
    )
  ])
  # list-metrics first and get-metric-statistics second, deliberately in that order. AWS WAF publishes
  # BlockedRequests under more than one dimension set depending on scope, so the second command's
  # WebACL+Rule pair is a guess that list-metrics confirms or corrects - and an empty statistics result with
  # a populated list-metrics result is a dimension mismatch rather than an absence of blocks.
  blocked_request_metrics_commands = join("\n", [
    "aws cloudwatch list-metrics --namespace AWS/WAFV2 --metric-name BlockedRequests --dimensions Name=WebACL,Value=${var.name}",
    "aws cloudwatch get-metric-statistics --namespace AWS/WAFV2 --metric-name BlockedRequests --dimensions Name=WebACL,Value=${var.name} Name=Rule,Value=ALL --start-time $(date -u -d '${var.sampled_requests_window_minutes} minutes ago' +%Y-%m-%dT%H:%M:%SZ) --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) --period 60 --statistics Sum",
  ])
  # Asks the resource which web ACL is in front of it, which is the other direction from this module's own
  # state and therefore the one worth checking. A 403 from an ALB with no web ACL attached came from
  # somewhere else - the target, or the listener's own default action.
  web_acl_for_resource_commands = length(var.associated_resource_arns) == 0 ? "# nothing is associated with this web ACL, so it filters nothing" : join("\n", [
    for label, arn in var.associated_resource_arns :
    "aws wafv2 get-web-acl-for-resource --resource-arn ${arn}   # ${label}"
  ])
}
