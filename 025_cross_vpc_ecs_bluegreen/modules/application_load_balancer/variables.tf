variable "name" {
  type        = string
  description = "Name of the application load balancer. Region-wide within its type, so a second copy of this project in one region collides with DuplicateLoadBalancerName"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,32}$", var.name)) && !startswith(var.name, "internal-")
    error_message = "name must be 32 characters or fewer of letters, digits and hyphens, and must not start with \"internal-\", which elbv2 reserves."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC the load balancer and its security group belong to"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Private subnets the load balancer places its nodes in"

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "subnet_ids must contain at least two subnets: elbv2 requires two availability zones for an application load balancer."
  }
  validation {
    condition     = alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "subnet_ids must contain valid subnet IDs (e.g. subnet-0123456789abcdef0)."
  }
}
variable "listener_port" {
  type        = number
  description = "Port the HTTP listener accepts on, and the port opened in the security group"

  validation {
    condition     = var.listener_port > 0 && var.listener_port <= 65535
    error_message = "listener_port must be a valid TCP port."
  }
}
variable "idle_timeout" {
  type        = number
  description = "Seconds a connection may be idle before the load balancer closes it. The _monolithic template left it unset, taking the 60 second default"

  validation {
    condition     = var.idle_timeout >= 1 && var.idle_timeout <= 4000
    error_message = "idle_timeout must be between 1 and 4000 seconds."
  }
}
variable "fixed_response_content_type" {
  type        = string
  description = "Content type of both fixed responses. The _monolithic template used text/plain while writing HTML bodies, so a browser shows the markup"

  validation {
    condition     = contains(["text/plain", "text/css", "text/html", "application/javascript", "application/json"], var.fixed_response_content_type)
    error_message = "fixed_response_content_type must be one of the five content types elbv2 accepts in a fixed response: text/plain, text/css, text/html, application/javascript or application/json."
  }
}
variable "not_found_status_code" {
  type        = string
  description = "Status code of the listener default action, returned for a path no stack rule matches"

  validation {
    condition     = can(regex("^[2-5][0-9][0-9]$", var.not_found_status_code))
    error_message = "not_found_status_code must be a three digit HTTP status code as a string."
  }
}
variable "not_found_message_body" {
  type        = string
  description = "Body of the listener default action"

  validation {
    condition     = length(var.not_found_message_body) > 0 && length(var.not_found_message_body) <= 1024
    error_message = "not_found_message_body must be between 1 and 1024 characters, the limit elbv2 accepts in a fixed response body."
  }
}
variable "error_path" {
  type        = string
  description = "Path answered with a fixed 500, so the demo can make the 5xx alarm and the dashboard widget fire without breaking an application"

  validation {
    condition     = can(regex("^/", var.error_path))
    error_message = "error_path must start with '/'."
  }
}
variable "error_rule_priority" {
  type        = number
  description = "Listener rule priority for the error path. Has to be a number no stack uses: elbv2 rejects a duplicate priority at apply with a message naming only the rule that arrived second"

  validation {
    condition     = var.error_rule_priority >= 1 && var.error_rule_priority <= 50000
    error_message = "error_rule_priority must be between 1 and 50000."
  }
}
variable "error_status_code" {
  type        = string
  description = "Status code returned on error_path"

  validation {
    condition     = can(regex("^[2-5][0-9][0-9]$", var.error_status_code))
    error_message = "error_status_code must be a three digit HTTP status code as a string."
  }
}
variable "error_message_body" {
  type        = string
  description = "Body returned on error_path"

  validation {
    condition     = length(var.error_message_body) > 0 && length(var.error_message_body) <= 1024
    error_message = "error_message_body must be between 1 and 1024 characters, the limit elbv2 accepts in a fixed response body."
  }
}
variable "ingress_source_security_groups" {
  type        = map(string)
  default     = {}
  description = "Security groups allowed inbound on listener_port, keyed by a caller-chosen label. A map rather than a list because these IDs are another module's output and unknown until apply, and for_each needs statically known keys (rules.md B-8)"

  validation {
    condition     = alltrue([for label in keys(var.ingress_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "ingress_source_security_groups keys land in the rule descriptions, so each must be a non-empty string of letters, digits, dots, underscores or hyphens (rules.md F-1)."
  }
  validation {
    condition     = alltrue([for id in values(var.ingress_source_security_groups) : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "ingress_source_security_groups must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "all_traffic_source_security_groups" {
  type        = map(string)
  default     = {}
  description = "Security groups allowed inbound on every protocol and port, keyed by a caller-chosen label. The root passes the app VPC default security group here, reproducing the _monolithic template"

  validation {
    condition     = alltrue([for label in keys(var.all_traffic_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "all_traffic_source_security_groups keys land in the rule descriptions, so each must be a non-empty string of letters, digits, dots, underscores or hyphens."
  }
  validation {
    condition     = alltrue([for id in values(var.all_traffic_source_security_groups) : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "all_traffic_source_security_groups must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "security_group_name" {
  type        = string
  description = "Name of the load balancer security group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "security_group_description" {
  type        = string
  description = "Description of the load balancer security group"

  validation {
    condition     = length(var.security_group_description) > 0
    error_message = "security_group_description must not be empty."
  }
  validation {
    # rules.md F-1. Changing a description replaces the security group, and over a hundred rules
    # and both load balancers reference this one, so the replacement is where the _Security Group
    # Deletion Problem_ in the provider docs shows up.
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects the CreateSecurityGroup call with InvalidParameterValue, which otherwise only surfaces at apply time."
  }
}
