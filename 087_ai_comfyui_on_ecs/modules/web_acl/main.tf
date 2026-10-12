# The blueprint's WAF: address allow-lists and an optional rate limit on ComfyUI's prompt API, in a regional
# web ACL on the load balancer. The root creates this module only when one of them is configured, as the
# blueprint created the ACL only then.
locals {
  ipv4_enabled = length(var.allowed_ipv4_address_ranges) > 0
  ipv6_enabled = length(var.allowed_ipv6_address_ranges) > 0
  # With either allow-list the default action blocks, so the lists are the only way in; with only the rate
  # limit it allows. The blueprint's rule.
  restricted = local.ipv4_enabled || local.ipv6_enabled
  # Priorities counted the way the blueprint counted them: one per rule present, in this order.
  ipv4_priority       = 1
  ipv6_priority       = local.ipv4_enabled ? 2 : 1
  rate_limit_priority = 1 + (local.ipv4_enabled ? 1 : 0) + (local.ipv6_enabled ? 1 : 0)
}
# Both sets exist whenever this module does, even with nothing in them, and it is the rules below that are
# conditional. The blueprint created each set only when its list had entries, and CloudFormation could do that
# because it updates a stack's resources before deleting the ones that left it.
#
# Terraform does not: emptying a list plans the set's deletion, but not an update of the web ACL that still
# references it before then, and WAF refuses to delete a set in use - the apply fails on
# WAFAssociatedItemException with the ACL unchanged. An empty set costs nothing (WAF bills per web ACL and
# per rule), and with the sets permanent the only thing that changes is the ACL's rule list.
resource "aws_wafv2_ip_set" "ipv4" {
  name               = "${var.name}-ipv4"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = var.allowed_ipv4_address_ranges
}
resource "aws_wafv2_ip_set" "ipv6" {
  name               = "${var.name}-ipv6"
  scope              = "REGIONAL"
  ip_address_version = "IPV6"
  addresses          = var.allowed_ipv6_address_ranges
}
resource "aws_wafv2_web_acl" "acl" {
  name  = var.name
  scope = "REGIONAL"

  default_action {
    dynamic "allow" {
      for_each = local.restricted ? [] : [1]
      content {}
    }
    dynamic "block" {
      for_each = local.restricted ? [1] : []
      content {}
    }
  }

  dynamic "rule" {
    for_each = local.ipv4_enabled ? [aws_wafv2_ip_set.ipv4.arn] : []
    content {
      name     = "IpV4SetRule"
      priority = local.ipv4_priority
      action {
        allow {}
      }
      statement {
        ip_set_reference_statement {
          arn = rule.value
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "IpV4SetRule"
        sampled_requests_enabled   = true
      }
    }
  }
  dynamic "rule" {
    for_each = local.ipv6_enabled ? [aws_wafv2_ip_set.ipv6.arn] : []
    content {
      name     = "IpV6SetRule"
      priority = local.ipv6_priority
      action {
        allow {}
      }
      statement {
        ip_set_reference_statement {
          arn = rule.value
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "IpV6SetRule"
        sampled_requests_enabled   = true
      }
    }
  }
  # Last, as the blueprint ordered it - which means an address on an allow-list never reaches it: an allow
  # ends the evaluation. With an allow-list in place the limit therefore applies to no one (everyone else is
  # blocked by default); it does its work only when the ACL has no lists. Confirmed by sending more than the
  # limit to the path with no lists configured: that path then answers 403 and every other path still 302.
  dynamic "rule" {
    for_each = var.rate_limit_enabled ? [1] : []
    content {
      name     = "RateLimitRule"
      priority = local.rate_limit_priority
      action {
        block {}
      }
      statement {
        rate_based_statement {
          limit                 = var.rate_limit_requests
          aggregate_key_type    = "IP"
          evaluation_window_sec = var.rate_limit_interval_seconds
          scope_down_statement {
            byte_match_statement {
              positional_constraint = "STARTS_WITH"
              search_string         = var.rate_limited_path
              field_to_match {
                uri_path {}
              }
              text_transformation {
                priority = 0
                type     = "NONE"
              }
            }
          }
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "RateLimitRule"
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "WebACL"
    sampled_requests_enabled   = true
  }
}
resource "aws_wafv2_web_acl_association" "load_balancer" {
  resource_arn = var.resource_arn
  web_acl_arn  = aws_wafv2_web_acl.acl.arn
}
