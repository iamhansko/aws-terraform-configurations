variable "name" {
  type        = string
  description = "Name of the ALB and of its target group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,30}[a-zA-Z0-9]$", var.name)) && !startswith(var.name, "internal-")
    error_message = "name must be 2-32 characters of letters, digits and hyphens, must not begin or end with a hyphen, and must not begin with internal- - the limits ELB puts on both an ALB and a target group name."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC the target group and the security group are created in"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "vpc_cidr_block" {
  type        = string
  description = "CIDR block of the VPC. The ALB's only egress rule is to the target port inside it"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Public subnets the ALB is placed in. At least two, in different zones - ELB's own requirement"

  validation {
    condition     = length(var.subnet_ids) >= 2 && alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "subnet_ids must contain at least two valid subnet IDs."
  }
}
variable "security_group_name" {
  type        = string
  description = "Name of the ALB's security group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the listener ports accept traffic from 0.0.0.0/0. False leaves the ALB with no ingress, which is what the _monolithic template's InboundFromAnywhere=False meant"
}
variable "enable_https" {
  type        = bool
  default     = false
  description = "Whether the ALB serves HTTPS on 443 with port 80 redirecting to it, or plain HTTP on 80 only. A bool beside certificate_arn because the ARN is unknown at plan and the listener count has to be known then"
}
variable "certificate_arn" {
  type        = string
  default     = null
  description = "ACM certificate for an HTTPS listener on 443, with port 80 redirecting to it. Null serves plain HTTP on 80 and opens nothing else. Pass the validated ARN, not the bare certificate's, or the listener can be created before the certificate is issued"

  validation {
    condition     = var.certificate_arn == null || can(regex("^arn:aws[a-zA-Z-]*:acm:[a-z0-9-]+:[0-9]{12}:certificate/", var.certificate_arn))
    error_message = "certificate_arn must be an ACM certificate ARN, or null for HTTP only."
  }
  validation {
    # The pair is what matters, so it is checked as a pair (rules.md B-1).
    condition     = var.enable_https == (var.certificate_arn != null)
    error_message = "certificate_arn must be set exactly when enable_https is true - an HTTPS listener without a certificate is rejected by ELB, and a certificate without enable_https is silently unused."
  }
}
variable "ssl_policy" {
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  description = "TLS policy of the HTTPS listener, as the _monolithic template had it. Ignored without a certificate"

  validation {
    condition     = startswith(var.ssl_policy, "ELBSecurityPolicy-")
    error_message = "ssl_policy must be an ELB security policy name (ELBSecurityPolicy-...)."
  }
}
variable "target_port" {
  type        = number
  description = "Port the tasks listen on. Passed from the same value the task definition uses, so the target group, the health check and the ALB's egress rule agree with it (rules.md B-5)"

  validation {
    condition     = var.target_port > 0 && var.target_port <= 65535
    error_message = "target_port must be a valid TCP port."
  }
}
variable "health_check_path" {
  type        = string
  default     = "/"
  description = "Path the target group health checks"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must start with /."
  }
}
variable "health_check_matcher" {
  type        = string
  default     = "200"
  description = "HTTP codes that count as healthy"

  validation {
    condition     = can(regex("^[0-9]{3}([-,][0-9]{3})*$", var.health_check_matcher))
    error_message = "health_check_matcher must be HTTP codes such as 200, 200-399 or 200,302."
  }
}
variable "deregistration_delay_seconds" {
  type        = number
  default     = 30
  description = "Seconds a deregistering target keeps receiving in-flight requests, as the _monolithic template had it"

  validation {
    condition     = var.deregistration_delay_seconds >= 0 && var.deregistration_delay_seconds <= 3600
    error_message = "deregistration_delay_seconds must be between 0 and 3600."
  }
}
