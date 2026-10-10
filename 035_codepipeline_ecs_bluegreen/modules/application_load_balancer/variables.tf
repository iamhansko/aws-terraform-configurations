variable "name" {
  type        = string
  description = "Name of the load balancer"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,32}$", var.name)) && !startswith(var.name, "internal-")
    error_message = "name must be 32 characters or fewer of letters, digits and hyphens, and must not start with \"internal-\", which elbv2 reserves."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC the security group and both target groups are created in"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Subnets the load balancer's nodes are placed in. Public ones, which is what an internet-facing scheme requires"

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "subnet_ids must contain at least two subnets. elbv2 requires an Application Load Balancer to span at least two availability zones."
  }
  validation {
    condition     = alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "subnet_ids must contain valid subnet IDs (e.g. subnet-0123456789abcdef0)."
  }
}
variable "internal" {
  type        = bool
  default     = false
  description = "Whether the load balancer has only private addresses. False, as the _monolithic template had it: the demo URL is reached from outside the VPC"
}
variable "ip_address_type" {
  type        = string
  default     = "ipv4"
  description = "Address family of the load balancer's own interfaces"

  validation {
    condition     = contains(["ipv4", "dualstack", "dualstack-without-public-ipv4"], var.ip_address_type)
    error_message = "ip_address_type must be ipv4, dualstack or dualstack-without-public-ipv4."
  }
}
variable "idle_timeout" {
  type        = number
  default     = 60
  description = "Seconds an idle connection is held open. Sixty, which is what the _monolithic template's bare load balancer got by default"

  validation {
    condition     = var.idle_timeout >= 1 && var.idle_timeout <= 4000
    error_message = "idle_timeout must be between 1 and 4000 seconds."
  }
}
variable "listener_port" {
  type        = number
  default     = 80
  description = "Port the listener accepts on, which is also the port the security group opens"

  validation {
    condition     = var.listener_port >= 1 && var.listener_port <= 65535
    error_message = "listener_port must be between 1 and 65535."
  }
}
variable "listener_protocol" {
  type        = string
  default     = "HTTP"
  description = "Listener protocol. HTTP, as the _monolithic template had it - there is no certificate in this project, so HTTPS would need one supplied"

  validation {
    condition     = contains(["HTTP", "HTTPS"], var.listener_protocol)
    error_message = "listener_protocol must be HTTP or HTTPS. HTTPS additionally requires a certificate ARN, which this module does not take."
  }
}
variable "security_group_name" {
  type        = string
  description = "Name of the load balancer's security group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs (rules.md F-1)."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Security group for the Application Load Balancer fronting the blue/green ECS service"
  description = "Description attached to the load balancer's security group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects CreateSecurityGroup with InvalidParameterValue, which otherwise only surfaces partway through apply (rules.md F-1)."
  }
}
variable "ingress_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "Sources allowed to reach the listener port. Open to the internet as the _monolithic template had it, because the demo URL is the point of the project"

  validation {
    condition     = alltrue([for block in var.ingress_cidr_blocks : can(cidrhost(block, 0))])
    error_message = "ingress_cidr_blocks must contain valid IPv4 CIDR blocks."
  }
}
variable "ingress_source_security_groups" {
  type        = map(string)
  default     = {}
  description = "Additional sources allowed to reach the listener port, given as security group IDs keyed by a caller-chosen label. A map rather than a list because such an ID is usually another module's output, unknown until apply, and for_each needs statically known keys (rules.md B-8)"

  validation {
    condition     = alltrue([for label in keys(var.ingress_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "ingress_source_security_groups keys are labels used in the rule descriptions and resource addresses, so each must be a non-empty string of letters, digits, dots, underscores or hyphens (rules.md F-1 forbids an apostrophe in the description these end up in)."
  }
  validation {
    condition     = alltrue([for id in values(var.ingress_source_security_groups) : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "ingress_source_security_groups must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "revoke_rules_on_delete" {
  type        = bool
  default     = true
  description = "Whether to revoke every rule attached to the group before deleting it, including rules Terraform did not create. True because this is the public entry point and therefore the group most likely to carry a hand-added rule, and AWS refuses to delete a group while rules referencing it remain. The flag changes only Terraform's delete sequence and never replaces the group (rules.md F-2)"
}
variable "blue_target_group_name" {
  type        = string
  description = "Name of the target group production traffic starts on, which the _monolithic template called tg1"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,32}$", var.blue_target_group_name))
    error_message = "blue_target_group_name must be 32 characters or fewer of letters, digits and hyphens."
  }
}
variable "green_target_group_name" {
  type        = string
  description = "Name of the target group a replacement task set registers into, which the _monolithic template called tg2. Empty until the first deployment, and that is correct - CodeDeploy attaches it to the listener when it shifts traffic"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,32}$", var.green_target_group_name))
    error_message = "green_target_group_name must be 32 characters or fewer of letters, digits and hyphens."
  }
  validation {
    condition     = var.green_target_group_name != var.blue_target_group_name
    error_message = "green_target_group_name must differ from blue_target_group_name. CodeDeploy needs two distinct groups to swap between, and elbv2 rejects a duplicate name."
  }
}
variable "target_port" {
  type        = number
  default     = 80
  description = "Port the targets are registered on. With awsvpc networking this is the task's container port, because the task holds the address and there is no port translation"

  validation {
    condition     = var.target_port >= 1 && var.target_port <= 65535
    error_message = "target_port must be between 1 and 65535."
  }
}
variable "target_protocol" {
  type        = string
  default     = "HTTP"
  description = "Protocol used to reach the targets, which is also the health check protocol"

  validation {
    condition     = contains(["HTTP", "HTTPS"], var.target_protocol)
    error_message = "target_protocol must be HTTP or HTTPS."
  }
}
variable "target_type" {
  type        = string
  default     = "ip"
  description = "How targets are registered. Must be ip: the task definition uses awsvpc, so each task has its own interface and address, and target_type instance would register container instances on a host port that awsvpc never assigns"

  validation {
    condition     = var.target_type == "ip"
    error_message = "target_type must be ip in this project, because its task definition uses awsvpc network mode. To use target_type instance, change the task definition's network_mode to bridge and let ECS assign a host port - with awsvpc, hostPort has to equal containerPort and the interface holding it belongs to the task rather than to the instance, so instance targets would be health-checked on a port nothing is listening on."
  }
}
variable "target_ip_address_type" {
  type        = string
  default     = "ipv4"
  description = "Address family of the registered targets"

  validation {
    condition     = contains(["ipv4", "ipv6"], var.target_ip_address_type)
    error_message = "target_ip_address_type must be ipv4 or ipv6."
  }
}
variable "health_check_enabled" {
  type        = bool
  default     = true
  description = "Whether the target groups health check their targets. On, as the _monolithic template set"
}
variable "health_check_path" {
  type        = string
  default     = "/health"
  description = "Path the health check requests. The Go application the bastion writes serves this, and so does the image the pipeline builds"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must start with a slash."
  }
}
variable "health_check_interval" {
  type        = number
  default     = 10
  description = "Seconds between health checks"

  validation {
    condition     = var.health_check_interval >= 5 && var.health_check_interval <= 300
    error_message = "health_check_interval must be between 5 and 300 seconds."
  }
}
variable "health_check_timeout" {
  type        = number
  default     = 5
  description = "Seconds a health check may take before it counts as failed"

  validation {
    condition     = var.health_check_timeout >= 2 && var.health_check_timeout <= 120
    error_message = "health_check_timeout must be between 2 and 120 seconds."
  }
  validation {
    condition     = var.health_check_timeout < var.health_check_interval
    error_message = "health_check_timeout must be less than health_check_interval. elbv2 rejects a timeout that is not shorter than the interval."
  }
}
variable "health_check_healthy_threshold" {
  type        = number
  default     = 2
  description = "Consecutive successes before a target is considered healthy"

  validation {
    condition     = var.health_check_healthy_threshold >= 2 && var.health_check_healthy_threshold <= 10
    error_message = "health_check_healthy_threshold must be between 2 and 10."
  }
}
variable "health_check_unhealthy_threshold" {
  type        = number
  default     = 4
  description = "Consecutive failures before a target is considered unhealthy"

  validation {
    condition     = var.health_check_unhealthy_threshold >= 2 && var.health_check_unhealthy_threshold <= 10
    error_message = "health_check_unhealthy_threshold must be between 2 and 10."
  }
}
variable "health_check_matcher" {
  type        = string
  default     = "200"
  description = "HTTP status codes counted as a successful health check"

  validation {
    condition     = can(regex("^[0-9]{3}(-[0-9]{3})?(,[0-9]{3}(-[0-9]{3})?)*$", var.health_check_matcher))
    error_message = "health_check_matcher must be a status code, a range such as 200-299, or a comma separated list of either."
  }
}
variable "create_user_agent_rule" {
  type        = bool
  default     = true
  description = "Whether to create the User-Agent listener rule the _monolithic template declared. True to reproduce it; see the resource for why it never matches as written and why CodeDeploy owns its action after the first deployment"
}
variable "user_agent_rule_priority" {
  type        = number
  default     = 1
  description = "Priority of that rule. Rules are evaluated in priority order and the first match wins, so this one is evaluated before anything else on the listener"

  validation {
    condition     = var.user_agent_rule_priority >= 1 && var.user_agent_rule_priority <= 50000
    error_message = "user_agent_rule_priority must be between 1 and 50000."
  }
}
variable "user_agent_rule_header_name" {
  type        = string
  default     = "User-Agent"
  description = "Header the rule matches on"

  validation {
    condition     = can(regex("^[a-zA-Z0-9!#$%&'*+.^_`|~-]{1,40}$", var.user_agent_rule_header_name))
    error_message = "user_agent_rule_header_name must be 1-40 characters of the token characters RFC 7230 allows in a header name. Wildcards are not supported in a header name."
  }
}
variable "user_agent_rule_values" {
  type        = list(string)
  default     = ["Mozilla"]
  description = "Comparison strings for that header, as the _monolithic template had them. Whole-value matches, case insensitive, with * and ? as the only wildcards - so \"Mozilla\" does not match \"Mozilla/5.0 (...)\" and this rule never fires"

  validation {
    condition     = length(var.user_agent_rule_values) >= 1 && length(var.user_agent_rule_values) <= 3
    error_message = "user_agent_rule_values must contain between one and three strings. An ALB allows at most three match evaluations per condition."
  }
  validation {
    condition     = alltrue([for value in var.user_agent_rule_values : length(value) > 0 && length(value) <= 128])
    error_message = "user_agent_rule_values entries must each be 1-128 characters."
  }
}
