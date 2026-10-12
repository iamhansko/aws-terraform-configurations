variable "name" {
  type        = string
  description = "Name of the load balancer"

  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]{0,30}[a-zA-Z0-9])?$", var.name)) && !startswith(lower(var.name), "internal-")
    error_message = "name must be 1-32 letters, digits and hyphens, must not begin or end with a hyphen, and must not begin with internal-."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC the load balancer, its security group and the target group are in"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Public subnets the internet-facing load balancer is placed in, at least two zones"

  validation {
    condition     = length(var.subnet_ids) >= 2 && alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "subnet_ids must contain at least two valid subnet IDs - an ALB needs two zones."
  }
}
variable "ingress_cidr_blocks" {
  type        = list(string)
  description = <<-DESC
    Source addresses admitted on both listener ports. Resolved by the caller, not here: a module that looked
    up the address itself would need network access of its own, and this one is ordered after the network
    module so that lookup would be deferred to apply (rules.md B-6/D-6).

    No default. The blueprint's value was 0.0.0.0/0, and a default of that would make an open load balancer
    the thing that happens when a caller says nothing - which is the one case worth making someone write
    down.
  DESC

  validation {
    condition     = length(var.ingress_cidr_blocks) > 0
    error_message = "ingress_cidr_blocks must contain at least one CIDR block. An empty list creates a load balancer with no inbound rule at all, which does not fail - it answers nothing, from anywhere, and looks like a broken deployment."
  }
  validation {
    # The pattern alongside cidrhost, which on its own would also accept an IPv6 block - and these rules are
    # cidr_ipv4, which EC2 rejects an IPv6 block in.
    condition     = alltrue([for cidr in var.ingress_cidr_blocks : can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}/[0-9]{1,2}$", cidr)) && can(cidrhost(cidr, 0))])
    error_message = "ingress_cidr_blocks must contain IPv4 CIDR blocks such as 203.0.113.4/32."
  }
}
variable "security_group_name" {
  type        = string
  description = "Name of the load balancer's security group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set EC2 accepts for a security group name (no apostrophe) and must not start with \"sg-\"."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Security Group for ALB"
  description = "Description of the load balancer's security group, as the blueprint wrote it. Changing it replaces the group (rules.md F-1)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set EC2 accepts for a security group description. An apostrophe is not allowed - EC2 rejects it only at apply."
  }
}
variable "ssl_policy" {
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09"
  description = "Security policy of the HTTPS listener. The blueprint set none, and a listener created through CloudFormation without one gets ELBSecurityPolicy-2016-08, which still accepts TLS 1.0 and 1.1. This default is the policy the ELB console picks and AWS recommends: TLS 1.2 and 1.3, with hybrid post-quantum key exchange for clients that offer it"

  validation {
    condition     = startswith(var.ssl_policy, "ELBSecurityPolicy-")
    error_message = "ssl_policy must be the name of an ELB security policy, such as ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09."
  }
}
variable "target_group_name" {
  type        = string
  description = "Name of the target group the ComfyUI task registers in"

  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]{0,30}[a-zA-Z0-9])?$", var.target_group_name))
    error_message = "target_group_name must be 1-32 letters, digits and hyphens, not beginning or ending with a hyphen."
  }
}
variable "target_port" {
  type        = number
  description = "Port the task listens on and is health-checked on - ComfyUI's --port in the Dockerfile"

  validation {
    condition     = var.target_port >= 1 && var.target_port <= 65535
    error_message = "target_port must be a TCP port number."
  }
}
variable "health_check_path" {
  type        = string
  default     = "/system_stats"
  description = "Path the target group checks, ComfyUI's /system_stats as the blueprint used it"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must start with a slash."
  }
}
variable "certificate_subject" {
  type = object({
    common_name         = string
    email_address       = string
    country             = string
    state               = string
    city                = string
    organization        = string
    organizational_unit = string
  })
  default = {
    common_name         = "example.com"
    email_address       = "customer@example.com"
    country             = "AT"
    state               = "."
    city                = "."
    organization        = "."
    organizational_unit = "."
  }
  description = "Subject of the self-signed certificate, the blueprint's self_signed_certificate config as it was. Browsers warn about the certificate whatever this says - it is self-signed and its name is not the load balancer's"

  validation {
    condition     = can(regex("^[A-Z]{2}$", var.certificate_subject.country))
    error_message = "certificate_subject.country must be a two-letter ISO 3166 country code."
  }
  validation {
    condition     = length(var.certificate_subject.common_name) > 0 && length(var.certificate_subject.common_name) <= 64
    error_message = "certificate_subject.common_name must be 1-64 characters - the X.509 limit, and ACM rejects longer."
  }
}
variable "certificate_validity_hours" {
  type        = number
  default     = 43800
  description = "How long the certificate is valid, five years as the blueprint's validity_seconds of 157680000. An apply after it expires issues a new one"

  validation {
    condition     = var.certificate_validity_hours >= 24
    error_message = "certificate_validity_hours must be at least 24."
  }
}
variable "certificate_version" {
  type        = number
  default     = 1
  description = "Version of the certificate's write-only private key. Increase it to issue a new key and certificate and swap them into the listener - the key is not in state, so this number is the only way to ask for a new one"

  validation {
    condition     = var.certificate_version >= 1 && floor(var.certificate_version) == var.certificate_version
    error_message = "certificate_version must be a positive whole number."
  }
}
variable "certificate_import_delay" {
  type        = string
  default     = "60s"
  description = <<-DESC
    How long to wait between generating the self-signed certificate and importing it into ACM.

    A margin rather than a tuning knob: the certificate's notBefore is the local clock's idea of now, and ACM
    refuses a certificate that its own clock says is still in the future, so a second of drift fails the
    import. See time_sleep.certificate_valid in main.tf.

    Sixty seconds covers ordinary drift and costs nothing, because it runs while the load balancer is coming
    up. Raise it if an apply still fails with "The certificate is valid in the future" - five minutes is the
    most it could ever need, since a machine further out than that cannot sign an AWS request at all. A
    machine that needs more than a few seconds here has a time synchronisation problem, and that is the thing
    worth fixing.
  DESC

  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?(s|m|h)$", var.certificate_import_delay))
    error_message = "certificate_import_delay must be a Go duration string such as 60s, 1.5m or 1h."
  }
  validation {
    # The ceiling the description names, as a condition. Beyond it the wait is not the problem being solved.
    condition     = endswith(var.certificate_import_delay, "s") ? tonumber(trimsuffix(var.certificate_import_delay, "s")) <= 300 : endswith(var.certificate_import_delay, "m") ? tonumber(trimsuffix(var.certificate_import_delay, "m")) <= 5 : false
    error_message = "certificate_import_delay must be 300s (5m) or less. AWS rejects a request signed more than five minutes from its own clock, so a longer wait cannot be what an apply needs - every other call would be failing too."
  }
}
