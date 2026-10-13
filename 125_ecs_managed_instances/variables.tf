variable "aws_region" {
  type        = string
  default     = null
  description = "Region to deploy into. Null follows the provider chain (AWS_REGION / AWS_DEFAULT_REGION), which is how the _monolithic template was run"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a region code such as ap-northeast-2, or null to follow the provider chain."
  }
}
variable "project_name" {
  type        = string
  default     = "url-shortener"
  description = "Prefix for the names CloudFormation used to generate. Replaces the _monolithic template's stack_name and keeps its default, so the cluster, the services and the capacity provider keep their names"

  validation {
    # 16 characters so "<project>-web-client" stays within the 32 an ALB and a target group name allow.
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,15}$", var.project_name)) && !endswith(var.project_name, "-")
    error_message = "project_name must be 1-16 characters of lowercase letters, digits and hyphens, not ending in a hyphen, so the ALB and target group names derived from it fit ELB's 32-character limit."
  }
}
# --- DNS ----------------------------------------------------------------------------------------------------
variable "default_domain" {
  type        = string
  description = "Domain whose public Route 53 hosted zone already exists in this account, e.g. example.com. Shlink is served at <shlink_subdomain>.<this>, which is also the host its short URLs are issued under"

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,}$", var.default_domain))
    error_message = "default_domain must be a lowercase domain name such as example.com, without a trailing dot."
  }
}
variable "route53_hosted_zone_id" {
  type        = string
  default     = null
  description = "Hosted zone for default_domain. Null looks the public zone up by name, which is what the _monolithic template's conversion did - and it also took this ID as a parameter and then never used it. Set it when the account has more than one zone of that name"

  validation {
    condition     = var.route53_hosted_zone_id == null || can(regex("^Z[A-Z0-9]+$", coalesce(var.route53_hosted_zone_id, "Z0")))
    error_message = "route53_hosted_zone_id must be a Route 53 hosted zone ID (e.g. Z0123456789ABCDEFGHIJ), or null to look the zone up by name."
  }
}
variable "shlink_subdomain" {
  type        = string
  default     = "shlink"
  description = "Label Shlink is served under, as the _monolithic template hardcoded it"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.shlink_subdomain))
    error_message = "shlink_subdomain must be a single lowercase DNS label."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = false
  description = "Whether the controlled inbound rules use 0.0.0.0/0. When false (the default), they use only the public IPv4 /32 dynamically returned by my_ip_lookup_url"
}
# --- Network ------------------------------------------------------------------------------------------------
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC, as the _monolithic template had it"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
}
variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "c"]
  description = "The two AZ letters the subnets, the NAT gateways and the EFS mount targets are placed in, as the _monolithic template's resources used them"

  validation {
    condition     = length(var.availability_zone_suffixes) == 2 && alltrue([for suffix in var.availability_zone_suffixes : can(regex("^[a-z]$", suffix))])
    error_message = "availability_zone_suffixes must contain exactly two single lowercase letters."
  }
}
# --- Managed instances --------------------------------------------------------------------------------------
variable "capacity_option_type" {
  type        = string
  default     = "ON_DEMAND"
  description = "Purchasing option for the managed instances, as the _monolithic template had it"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.capacity_option_type)
    error_message = "capacity_option_type must be ON_DEMAND or SPOT."
  }
}
variable "instance_vcpu_count" {
  type = object({
    min = number
    max = number
  })
  default = {
    min = 1
    max = 4
  }
  description = "vCPU range ECS chooses instance types from, as the _monolithic template had it"
}
variable "instance_memory_mib" {
  type = object({
    min = number
    max = number
  })
  default = {
    min = 2048
    max = 8192
  }
  description = "Memory range ECS chooses instance types from, as the _monolithic template had it"
}
variable "instance_storage_size_gib" {
  type        = number
  default     = 30
  description = "Root volume size of each managed instance, as the _monolithic template had it"

  validation {
    condition     = var.instance_storage_size_gib >= 30
    error_message = "instance_storage_size_gib must be at least 30."
  }
}
# --- Services -----------------------------------------------------------------------------------------------
variable "shlink_image" {
  type        = string
  default     = "shlinkio/shlink:stable"
  description = "Shlink image, as the _monolithic template had it. stable is a moving tag - docker/docker-compose.yaml pins 4.4.6, which is the version to pin here for a repeatable deployment"

  validation {
    condition     = length(var.shlink_image) > 0
    error_message = "shlink_image must not be empty."
  }
}
variable "web_client_image" {
  type        = string
  default     = "shlinkio/shlink-web-client:stable"
  description = "Shlink web client image, as the _monolithic template had it. stable is a moving tag - docker/docker-compose.yaml pins 4.4.0"

  validation {
    condition     = length(var.web_client_image) > 0
    error_message = "web_client_image must not be empty."
  }
}
variable "shlink_container_port" {
  type        = number
  default     = 8080
  description = "Port the Shlink image listens on. One value for the task definition, its health check command, the target group and both security group rules (rules.md B-5)"

  validation {
    condition     = var.shlink_container_port > 0 && var.shlink_container_port <= 65535
    error_message = "shlink_container_port must be a valid TCP port."
  }
}
variable "web_client_container_port" {
  type        = number
  default     = 8080
  description = "Port the web client image listens on"

  validation {
    condition     = var.web_client_container_port > 0 && var.web_client_container_port <= 65535
    error_message = "web_client_container_port must be a valid TCP port."
  }
}
variable "timezone" {
  type        = string
  default     = "Asia/Seoul"
  description = "Timezone Shlink reports visits in, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[A-Za-z_]+(/[A-Za-z0-9_+-]+)*$", var.timezone))
    error_message = "timezone must be an IANA timezone name such as Asia/Seoul or UTC."
  }
}
variable "log_retention_in_days" {
  type        = number
  default     = 30
  description = "Days CloudWatch keeps both services' container logs, as the _monolithic template had it"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365], var.log_retention_in_days)
    error_message = "log_retention_in_days must be one of 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180 or 365."
  }
}
variable "wait_for_steady_state" {
  type        = bool
  default     = true
  description = "Whether apply waits for both services to stabilise, which is what CloudFormation did for the _monolithic stack. It is what turns a task that cannot start into an apply failure rather than a service quietly cycling tasks"
}

variable "my_ip_lookup_url" {
  type        = string
  default     = "https://checkip.amazonaws.com/"
  description = "Trusted HTTPS endpoint that returns the public IPv4 address of the machine running Terraform. The address is converted to a /32 and used when an allow_inbound_from_anywhere switch is false"

  validation {
    condition     = startswith(var.my_ip_lookup_url, "https://")
    error_message = "my_ip_lookup_url must be an HTTPS URL because its response controls which source address the security groups admit."
  }
}
