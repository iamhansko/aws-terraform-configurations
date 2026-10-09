variable "name" {
  type        = string
  default     = "waf"
  description = "Name of the web ACL, as the _monolithic template named it. Changing it replaces the web ACL, which means the association below is torn down and recreated - requests are unfiltered for the few seconds in between"

  validation {
    condition     = can(regex("^[0-9A-Za-z_-]{1,128}$", var.name))
    error_message = "name must be 1-128 characters of letters, digits, hyphens and underscores, which is what the WAF API accepts for a web ACL name."
  }
}
variable "description" {
  type        = string
  default     = "Common rule set demo - AWS managed rule groups in front of the ALB"
  description = <<-DESC
    Description recorded on the web ACL. The _monolithic template set none.

    Worth validating for the same reason a security group description is (rules.md F-1): WAF accepts a
    narrower character set than the sentence someone would naturally write, and it rejects the request
    during apply rather than at plan time. An apostrophe, a parenthesis or a semicolon all fail - so
    "the ALB's web ACL" is not a description this will accept.
  DESC

  validation {
    condition     = var.description == null || can(regex("^[0-9A-Za-z_+=:#@/,.-][0-9A-Za-z_+=:#@/,. -]*[0-9A-Za-z_+=:#@/,.-]$", var.description))
    error_message = "description must be made up of letters, digits, spaces and the characters _ + = : # @ / , . - only. WAF rejects anything else - including apostrophes and parentheses - with a validation error during apply, which terraform plan cannot see."
  }
  validation {
    condition     = var.description == null || length(var.description) <= 256
    error_message = "description must be 256 characters or fewer."
  }
}
variable "scope" {
  type        = string
  default     = "REGIONAL"
  description = <<-DESC
    Scope of the web ACL. REGIONAL, and it has to stay REGIONAL in this project.

    A web ACL's scope decides what it can be attached to. CLOUDFRONT scope web ACLs live in us-east-1 no
    matter where the rest of the stack is, and they are not attached with AssociateWebACL at all - a
    CloudFront distribution carries the web ACL id in its own configuration, which is why the API
    documentation tells callers not to use AssociateWebACL for CloudFront. An Application Load Balancer is a
    regional resource and can only be associated with a regional web ACL.

    It is a variable with a pinned validation rather than a bare literal in main.tf so that the reason is
    written where someone would change it, and so that a tfvars override is refused at plan time. Setting
    CLOUDFRONT here fails twice over: the create call needs a us-east-1 provider this root does not declare,
    and the association call then has a load balancer ARN and a global web ACL that cannot be joined.
  DESC

  validation {
    condition     = var.scope == "REGIONAL"
    error_message = "scope must stay REGIONAL. This web ACL is associated with an Application Load Balancer, which is a regional resource; a CLOUDFRONT scope web ACL must be created through a provider in us-east-1 and is attached by setting the web ACL on the distribution rather than by an association. To protect a CloudFront distribution, add an aliased us-east-1 provider and move the attachment onto the distribution."
  }
}
variable "default_action" {
  type        = string
  default     = "allow"
  description = <<-DESC
    What happens to a request that no rule matched. allow, as the _monolithic template had it.

    This is the value that makes the demo readable: one URL returns 200 and the same URL with an injection
    probe in the query string returns 403, and the only difference is whether a managed rule matched. Set it
    to block and nothing is served at all - the managed rule groups here only block and count, they never
    allow, so with a block default there is no rule that can let a request through.
  DESC

  validation {
    condition     = contains(["allow", "block"], var.default_action)
    error_message = "default_action must be allow or block. Note that block leaves nothing able to serve traffic unless an allow rule is added, because a managed rule group's rules do not allow."
  }
}
variable "metric_name" {
  type        = string
  default     = "waf"
  description = "CloudWatch metric name for the web ACL as a whole, as the _monolithic template had it. This is the name under which requests handled by the default action are counted"

  validation {
    condition     = can(regex("^[0-9A-Za-z_-]{1,128}$", var.metric_name))
    error_message = "metric_name must be 1-128 characters of letters, digits, hyphens and underscores."
  }
  validation {
    condition     = !contains(["All", "Default_Action"], var.metric_name)
    error_message = "metric_name must not be All or Default_Action, which WAF reserves."
  }
}
variable "sampled_requests_enabled" {
  type        = bool
  default     = true
  description = "Whether WAF keeps a sample of the requests it evaluated for the web ACL as a whole, as the _monolithic template had it. This project's verification depends on it: with it false, aws wafv2 get-sampled-requests returns nothing and a 403 cannot be attributed to WAF at all"
}
variable "cloudwatch_metrics_enabled" {
  type        = bool
  default     = true
  description = "Whether the web ACL publishes AllowedRequests/BlockedRequests to CloudWatch, as the _monolithic template had it"
}
variable "managed_rule_groups" {
  type = map(object({
    priority                   = number
    vendor_name                = optional(string, "AWS")
    version                    = optional(string)
    metric_name                = string
    override_action            = optional(string, "none")
    rule_action_overrides      = optional(map(string), {})
    sampled_requests_enabled   = optional(bool, true)
    cloudwatch_metrics_enabled = optional(bool, true)
  }))
  default = {
    AWSManagedRulesSQLiRuleSet = {
      priority    = 1
      metric_name = "sqli-rule"
    }
    AWSManagedRulesCommonRuleSet = {
      priority    = 2
      metric_name = "base-rule"
    }
  }
  description = <<-DESC
    The managed rule groups this web ACL runs, keyed by the rule group's own name. These two at these
    priorities with these metric names are exactly what the _monolithic template declared, and they are the
    content of the demo.

    Keyed by name rather than held in a list because the key is the only stable identifier a rule group has.
    priority decides evaluation order and nothing else; it is not an index, so the numbers may have gaps and
    need not start at 1.

    What the defaults do:

      AWSManagedRulesSQLiRuleSet   inspects the query string, body, cookies and URI path for SQL syntax.
                                   This is the group that answers the /lookup?id=1' OR '1'='1 probe with a
                                   403, and the app behind the ALB really is injectable, so the block is
                                   doing work rather than demonstrating a pattern match.
      AWSManagedRulesCommonRuleSet the OWASP-shaped baseline: path traversal, cross-site scripting, oversized
                                   bodies, requests with no User-Agent. This is what answers the
                                   ../../etc/passwd probe.

    rule_action_overrides maps an individual rule inside the group to an action - count, allow, block,
    captcha or challenge. Empty for both groups, which reproduces the template. It is the right tool when
    one managed rule rejects legitimate traffic: set that rule to count and leave the rest of the group
    blocking, rather than overriding the whole group. The names are the vendor's, and a name that does not
    exist in the group is rejected during apply with nothing in the plan to warn about it - aws wafv2
    describe-managed-rule-group --vendor-name AWS --name <group> --scope REGIONAL lists them.

    override_action is the group-wide form of the same idea; see main.tf.
  DESC

  validation {
    condition     = length(var.managed_rule_groups) > 0
    error_message = "managed_rule_groups must contain at least one rule group. An empty map produces a web ACL with no rules, which serves every request through its default action - the association succeeds and nothing is ever filtered."
  }
  validation {
    condition     = alltrue([for name in keys(var.managed_rule_groups) : can(regex("^[0-9A-Za-z_-]{1,128}$", name))])
    error_message = "managed_rule_groups keys must be rule group names of 1-128 letters, digits, hyphens and underscores - they are used verbatim as the managed rule group name and as part of each rule's name."
  }
  validation {
    # WAF rejects two rules sharing a priority, and a map keyed by name makes it easy to copy an entry and
    # leave the number alone. The failure is WAFInvalidParameterException partway through apply.
    condition     = length(distinct([for group in values(var.managed_rule_groups) : group.priority])) == length(var.managed_rule_groups)
    error_message = "managed_rule_groups priorities must be unique. WAF refuses a web ACL with two rules at the same priority, and that refusal arrives during apply rather than at plan time."
  }
  validation {
    condition     = alltrue([for group in values(var.managed_rule_groups) : group.priority >= 0])
    error_message = "managed_rule_groups priorities must be zero or greater."
  }
  validation {
    condition     = alltrue([for group in values(var.managed_rule_groups) : contains(["none", "count"], group.override_action)])
    error_message = "managed_rule_groups override_action must be none (the group's rules act as published) or count (every match is recorded and nothing is blocked). These are the only two values a managed rule group statement accepts."
  }
  validation {
    condition = alltrue([
      for group in values(var.managed_rule_groups) :
      alltrue([for action in values(group.rule_action_overrides) : contains(["allow", "block", "count", "captcha", "challenge"], action)])
    ])
    error_message = "managed_rule_groups rule_action_overrides values must be allow, block, count, captcha or challenge."
  }
  validation {
    condition     = alltrue([for group in values(var.managed_rule_groups) : can(regex("^[0-9A-Za-z_-]{1,128}$", group.metric_name))])
    error_message = "managed_rule_groups metric_name values must be 1-128 characters of letters, digits, hyphens and underscores."
  }
  validation {
    # Not a WAF constraint, a demo constraint: get-sampled-requests is asked for one rule metric name, so two
    # rules sharing one makes the answer ambiguous about which group blocked the request.
    condition     = length(distinct([for group in values(var.managed_rule_groups) : group.metric_name])) == length(var.managed_rule_groups)
    error_message = "managed_rule_groups metric_name values must be unique. They are what aws wafv2 get-sampled-requests is asked for, so a shared name makes it impossible to tell which rule group blocked a request."
  }
  validation {
    condition     = alltrue([for group in values(var.managed_rule_groups) : group.version == null || can(regex("^[0-9A-Za-z_.-]{1,64}$", group.version))])
    error_message = "managed_rule_groups version values must be a vendor version string such as Version_1.5, or null to track the group's default version."
  }
}
variable "associated_resource_arns" {
  type        = map(string)
  default     = {}
  description = <<-DESC
    ARNs this web ACL is associated with, keyed by a label the caller chooses. Empty creates no association,
    which leaves the web ACL inert.

    A map rather than a list because these ARNs are another module's output and so are unknown until apply,
    while for_each keys must be known at plan time (rules.md B-8). The label is the caller's, which is also
    what makes the resource address say what is being protected.

    Only the resource types WAF supports can go here, and an Application Load Balancer is the one this
    project uses. A Network Load Balancer cannot: WAF operates on HTTP requests and an NLB does not parse
    them.
  DESC

  validation {
    condition     = alltrue([for label in keys(var.associated_resource_arns) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "associated_resource_arns keys are labels used in resource addresses, so each must be a non-empty string of letters, digits, dots, underscores or hyphens."
  }
  validation {
    # Checked against the ARN prefix only. The value is unknown at plan time when it comes from another
    # module, so Terraform defers this one to apply - but it still fires before the AssociateWebACL call,
    # which is where a wrong resource type otherwise surfaces as WAFInvalidParameterException.
    condition     = alltrue([for arn in values(var.associated_resource_arns) : can(regex("^arn:aws[a-z-]*:", arn))])
    error_message = "associated_resource_arns values must be ARNs."
  }
  validation {
    condition = alltrue([
      for arn in values(var.associated_resource_arns) :
      can(regex("^arn:aws[a-z-]*:elasticloadbalancing:[a-z0-9-]+:[0-9]{12}:loadbalancer/app/", arn))
    ])
    error_message = "associated_resource_arns values must be Application Load Balancer ARNs of the form arn:aws:elasticloadbalancing:<region>:<account>:loadbalancer/app/<name>/<id>. A Network Load Balancer ARN (loadbalancer/net/...) is rejected by WAF, which inspects HTTP requests an NLB never parses, and that rejection arrives during apply."
  }
}
variable "sampled_requests_window_minutes" {
  type        = number
  default     = 30
  description = "How far back the generated get-sampled-requests commands look. WAF keeps samples for the last three hours, so a larger window than that returns the same thing as three hours"

  validation {
    condition     = var.sampled_requests_window_minutes > 0 && var.sampled_requests_window_minutes <= 180
    error_message = "sampled_requests_window_minutes must be between 1 and 180. WAF retains sampled requests for three hours, so a longer window cannot return more."
  }
}
variable "sampled_requests_max_items" {
  type        = number
  default     = 100
  description = "How many sampled requests the generated commands ask for. WAF samples rather than logs, so this is a ceiling on the sample and not on the traffic"

  validation {
    condition     = var.sampled_requests_max_items >= 1 && var.sampled_requests_max_items <= 500
    error_message = "sampled_requests_max_items must be between 1 and 500, which is the range GetSampledRequests accepts."
  }
}
