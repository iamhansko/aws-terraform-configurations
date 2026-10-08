variable "name_prefix" {
  type        = string
  description = "Base name for the endpoint's security group and the hosted zone's tags. No default: derived by the caller from the cluster name, where the _monolithic template named the security group literally (vpc-lattice-sne-sg)"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}$", var.name_prefix))
    error_message = "name_prefix must be 2-31 characters of lowercase letters, digits and hyphens."
  }
}
variable "vpc_id" {
  type        = string
  description = "The client VPC - the one that has no route to the cluster's network and reaches the API server only through this endpoint"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID."
  }
}
variable "vpc_cidr_block" {
  type        = string
  description = "CIDR block of the client VPC, which the endpoint's security group accepts 443 from. Passed in from the module that created the VPC so the rule and the network cannot disagree (rules.md B-5)"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Subnets the endpoint's interfaces are placed in. Two, so a client in either zone reaches it without a cross-zone hop"

  validation {
    condition     = length(var.subnet_ids) >= 2 && alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "subnet_ids must contain at least two valid subnet IDs."
  }
}
variable "service_network_arn" {
  type        = string
  description = "Service network this endpoint attaches to. Passed in from the module that created it (rules.md B-5)"

  validation {
    condition     = can(regex("^arn:aws:vpc-lattice:", var.service_network_arn))
    error_message = "service_network_arn must be a VPC Lattice service network ARN."
  }
}
variable "api_server_hostname" {
  type        = string
  description = "Hostname the private hosted zone is created for, and the name the alias record answers. The cluster's real API server hostname, so a kubeconfig from aws eks update-kubeconfig works unchanged - passed in rather than split out of the cluster endpoint again (rules.md B-5)"

  validation {
    # Lowercase for the same reason the resource configuration module requires it: the value arrives from that
    # module's re-exposed output, and Route 53 stores zone and record names lowercase too, so an uppercase one
    # would leave this zone in a permanent diff (rules.md B-1).
    condition     = can(regex("^[a-z0-9][a-z0-9.-]*\\.amazonaws\\.com$", var.api_server_hostname))
    error_message = "api_server_hostname must be a bare lowercase hostname with no scheme. EKS reports the cluster id in uppercase hex, so the caller has to lower() it."
  }
}
variable "allowed_ingress_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "Extra CIDR blocks allowed to reach the endpoint on 443, beyond the client VPC's own. Empty by default, as the _monolithic template had it - anything reaching this endpoint reaches the cluster's API server, so widening it widens that"

  validation {
    condition     = alltrue([for cidr in var.allowed_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "allowed_ingress_cidr_blocks must contain valid IPv4 CIDR blocks."
  }
}
variable "create_private_hosted_zone" {
  type        = bool
  default     = true
  description = <<-DESC
    Whether to create the private hosted zone and alias record that make the API server's own hostname resolve
    inside the client VPC.

    True, which is what makes the demonstration work: without it a client has the endpoint's DNS name but not
    the cluster's, and the certificate the API server presents does not match the endpoint's name - so kubectl
    fails on TLS verification rather than on connectivity.

    Setting it false is the way to see that difference (rules.md B-4).
  DESC
}
