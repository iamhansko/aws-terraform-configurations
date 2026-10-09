variable "vpc_id" {
  type        = string
  description = "VPC the security group and the target group are created in. Taken as an id rather than discovered here, so this module does not need to know that the caller resolves the account's default VPC (rules.md B-6)"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = <<-DESC
    Subnets the load balancer's nodes are placed in. Must be public while internal is false, and must cover
    at least two availability zones.

    The _monolithic template took two subnet ids as stack parameters named DefaultVpcPublicSubnet1Id and
    DefaultVpcPublicSubnet2Id, so whoever ran it supplied them by hand. The root discovers the account's
    default subnets instead and passes them here as ids, which keeps the lookup out of this module
    (rules.md B-6) and out of any module carrying depends_on (rules.md D-6).
  DESC

  validation {
    condition     = alltrue([for subnet in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", subnet))])
    error_message = "subnet_ids must contain valid subnet IDs (e.g. subnet-0123456789abcdef0)."
  }
  validation {
    # ELB requires two availability zones for an application load balancer and rejects a single-subnet
    # create during apply. Checked here because the caller may be handing over a discovered list whose
    # length it did not choose.
    condition     = length(var.subnet_ids) >= 2
    error_message = "subnet_ids must contain at least two subnets in different availability zones. An application load balancer cannot be created in one zone, and the ELB API refuses it during apply rather than at plan time."
  }
}
variable "name" {
  type        = string
  default     = null
  description = "Exact name for the load balancer. Null generates one from name_prefix, which is the default - the _monolithic template used the literal \"alb\", and a load balancer name is unique per account and region, so a second copy of this project fails with DuplicateLoadBalancerName"

  validation {
    condition     = var.name == null || can(regex("^[a-zA-Z0-9-]{1,32}$", var.name))
    error_message = "name must be 32 characters or fewer of letters, digits and hyphens, or null to generate one from name_prefix."
  }
}
variable "name_prefix" {
  type        = string
  default     = "alb-"
  description = "Prefix for the generated load balancer name, used when name is null. Six characters is the hard limit the ELB API puts on a name prefix, not a convention"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,6}$", var.name_prefix))
    error_message = "name_prefix must be 1-6 characters of letters, digits and hyphens. The ELB API rejects a longer prefix outright."
  }
}
variable "internal" {
  type        = bool
  default     = false
  description = "Whether the load balancer is internal. False, as the _monolithic template had it, which requires the subnets to be public - an internet-facing scheme in private subnets fails the create call because the subnets have no route to an internet gateway"
}
variable "enable_deletion_protection" {
  type        = bool
  default     = false
  description = "Whether the load balancer refuses to be deleted. False, which is both the AWS default and what this project wants: with it true terraform destroy stops here and leaves the web ACL, the target group and the instances behind"
}
variable "security_group_name" {
  type        = string
  default     = null
  description = "Exact name for the frontend security group. Null generates one from security_group_name_prefix. The _monolithic template left this group unnamed, so EC2 generated one"

  validation {
    condition     = var.security_group_name == null || (can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-"))
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs (rules.md F-1)."
  }
}
variable "security_group_name_prefix" {
  type        = string
  default     = "alb-sg-"
  description = "Prefix for the generated frontend security group name, used when security_group_name is null"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,100}$", var.security_group_name_prefix))
    error_message = "security_group_name_prefix must be 1-100 characters from the set AWS accepts for a security group name, leaving room for the generated suffix."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Frontend security group for the ALB the web ACL is associated with"
  description = "Description attached to the frontend security group. The _monolithic template said only \"Security Group\" for all three of its groups. Changing this value replaces the group - AWS has no API to modify a security group description - and a replacement cascades into the app server's ingress rule, which references it (rules.md F-1)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects the CreateSecurityGroup call with InvalidParameterValue, which otherwise only surfaces at apply time (rules.md F-1)."
  }
}
variable "revoke_rules_on_delete" {
  type        = bool
  default     = true
  description = "Whether Terraform revokes this group's rules before deleting it. True because the app server's security group has an ingress rule referencing this group, and AWS refuses to delete a group while any rule references it - which a destroy experiences as DependencyViolation rather than as an ordering problem (rules.md F-2)"
}
variable "ingress_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = <<-DESC
    Sources allowed to reach the listener port. An empty list creates no ingress rule, which makes the load
    balancer unreachable and every demo request time out.

    0.0.0.0/0 is what the _monolithic template opened, and it is right here rather than merely inherited: the
    point of the project is that an internet-facing endpoint is filtered by a web ACL, and narrowing this to
    one address would make the web ACL the second line of defence in a demo about the first.
  DESC

  validation {
    condition     = alltrue([for cidr in var.ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "ingress_cidr_blocks must contain valid IPv4 CIDR blocks (e.g. 203.0.113.0/24)."
  }
}
variable "listener_port" {
  type        = number
  default     = 80
  description = "Port the HTTP listener binds and the frontend security group opens, as the _monolithic template had it. One value feeds the listener, the security group rule and the URL output, so they cannot disagree (rules.md B-5)"

  validation {
    condition     = var.listener_port > 0 && var.listener_port <= 65535
    error_message = "listener_port must be between 1 and 65535."
  }
}
variable "target_group_name" {
  type        = string
  default     = null
  description = "Exact name for the target group. Null generates one from target_group_name_prefix. The _monolithic template used the literal \"alb-tg\", which collides on a second deployment in the same account and region in the same way the load balancer name does"

  validation {
    condition     = var.target_group_name == null || can(regex("^[a-zA-Z0-9-]{1,32}$", var.target_group_name))
    error_message = "target_group_name must be 32 characters or fewer of letters, digits and hyphens, or null to generate one from target_group_name_prefix."
  }
}
variable "target_group_name_prefix" {
  type        = string
  default     = "albtg-"
  description = "Prefix for the generated target group name, used when target_group_name is null. Capped at six characters by the ELB API"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,6}$", var.target_group_name_prefix))
    error_message = "target_group_name_prefix must be 1-6 characters of letters, digits and hyphens. The ELB API rejects a longer prefix outright."
  }
}
variable "target_port" {
  type        = number
  default     = 5000
  description = "Port on the target the listener forwards to, as the _monolithic template had it. Flask's default development server port, and the value the app server's own security group rule has to admit - which is why the caller passes one number into both modules and this one is handed back out (rules.md B-5)"

  validation {
    condition     = var.target_port > 0 && var.target_port <= 65535
    error_message = "target_port must be between 1 and 65535."
  }
}
variable "target_protocol" {
  type        = string
  default     = "HTTP"
  description = "Protocol the load balancer speaks to the target, as the _monolithic template had it. The Flask app serves plain HTTP"

  validation {
    condition     = contains(["HTTP", "HTTPS"], var.target_protocol)
    error_message = "target_protocol must be HTTP or HTTPS for an application load balancer target group."
  }
}
variable "target_type" {
  type        = string
  default     = "instance"
  description = <<-DESC
    How targets are addressed, as the _monolithic template had it.

    instance means the caller registers an instance id and the load balancer resolves its address, which is
    why the registration in the root passes an instance id rather than a private address. ip would take the
    address instead and lambda would take a function; neither matches what this project registers, and the
    mismatch is rejected by the ELB API during apply rather than by the plan.
  DESC

  validation {
    condition     = contains(["instance", "ip", "lambda", "alb"], var.target_type)
    error_message = "target_type must be instance, ip, lambda or alb."
  }
}
variable "health_check_path" {
  type        = string
  default     = "/"
  description = <<-DESC
    Path the health check requests, as the _monolithic template had it - the only health check value that
    template set.

    "/" because that is where the Flask app behind this serves its form. A path the app does not route
    answers 404, the check reads unhealthy forever, and the ALB returns 503 to every request while the app
    itself is working perfectly - so this is the first thing to compare against the app's routes when the
    demo URL answers 503 instead of 200.
  DESC

  validation {
    condition     = can(regex("^/", var.health_check_path))
    error_message = "health_check_path must start with a slash."
  }
}
variable "health_check_matcher" {
  type        = string
  default     = "200"
  description = "HTTP status codes counted as healthy. 200, which is the AWS default and what the Flask app's index returns"

  validation {
    condition     = can(regex("^[0-9]{3}(-[0-9]{3})?(,[0-9]{3}(-[0-9]{3})?)*$", var.health_check_matcher))
    error_message = "health_check_matcher must be a status code, a range, or a comma-separated list of them (e.g. 200, 200-299, 200,302)."
  }
}
variable "health_check_interval_seconds" {
  type        = number
  default     = 30
  description = "Seconds between health checks. 30 is the AWS default the _monolithic template inherited; together with health_check_healthy_threshold it sets how long after apply the URL starts answering"

  validation {
    condition     = var.health_check_interval_seconds >= 5 && var.health_check_interval_seconds <= 300
    error_message = "health_check_interval_seconds must be between 5 and 300."
  }
}
variable "health_check_timeout_seconds" {
  type        = number
  default     = 5
  description = "Seconds a single health check may take. 5 is the AWS default. It has to be below health_check_interval_seconds, which the ELB API enforces during apply"

  validation {
    condition     = var.health_check_timeout_seconds >= 2 && var.health_check_timeout_seconds <= 120
    error_message = "health_check_timeout_seconds must be between 2 and 120."
  }
  validation {
    condition     = var.health_check_timeout_seconds < var.health_check_interval_seconds
    error_message = "health_check_timeout_seconds must be less than health_check_interval_seconds. The ELB API rejects the pair otherwise, during apply rather than at plan time."
  }
}
variable "health_check_healthy_threshold" {
  type        = number
  default     = 5
  description = "Consecutive successes before a target is in service. 5 is the AWS default, so with the default interval a newly registered instance takes about two and a half minutes to start receiving traffic - that gap is why the root publishes a describe-target-health command rather than assuming the first curl works"

  validation {
    condition     = var.health_check_healthy_threshold >= 2 && var.health_check_healthy_threshold <= 10
    error_message = "health_check_healthy_threshold must be between 2 and 10."
  }
}
variable "health_check_unhealthy_threshold" {
  type        = number
  default     = 2
  description = "Consecutive failures before a target is taken out of service. 2 is the AWS default"

  validation {
    condition     = var.health_check_unhealthy_threshold >= 2 && var.health_check_unhealthy_threshold <= 10
    error_message = "health_check_unhealthy_threshold must be between 2 and 10."
  }
}
