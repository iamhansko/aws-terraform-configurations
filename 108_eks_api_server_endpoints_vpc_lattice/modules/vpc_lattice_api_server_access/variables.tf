variable "name_prefix" {
  type        = string
  description = "Base name for the resource gateway, its security group, the resource configuration and the service network. No default: the caller derives it from the cluster name, which is what keeps two copies of this project from colliding - the _monolithic template named all four literally (eks-cluster-vpc-resource-gateway, resource-gateway-sg, eks-api-server, eks-service-network)"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}$", var.name_prefix))
    error_message = "name_prefix must be 2-31 characters of lowercase letters, digits and hyphens, leaving room for the per-resource suffixes."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC the resource gateway is placed in - the cluster's VPC, since the gateway is what reaches the private API server endpoint"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Subnets the resource gateway's interfaces are placed in. Private subnets in the cluster's VPC: the gateway resolves and connects to the API server's private endpoint, which is only reachable from inside that VPC"

  validation {
    condition     = length(var.subnet_ids) >= 2 && alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "subnet_ids must contain at least two valid subnet IDs - a resource gateway needs interfaces in two availability zones."
  }
}
variable "api_server_hostname" {
  type        = string
  description = <<-DESC
    Hostname of the cluster's API server endpoint, without the scheme.

    Derived by the caller from the cluster's endpoint URL and passed in, rather than being split out of it in
    four separate places - which is what the _monolithic template did, once for the resource configuration's
    custom_domain_name, once for its DNS resource definition, once for the Route 53 zone name and once for the
    record name (rules.md B-5).

    This is the whole point of the resource configuration: the name a client resolves is the cluster's real
    endpoint hostname, so a kubeconfig built by aws eks update-kubeconfig works unchanged from the client VPC.
  DESC

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]*\\.amazonaws\\.com$", var.api_server_hostname))
    error_message = "api_server_hostname must be a bare lowercase hostname such as 018520d1274daa3bea8f179f2c3afcf4.gr7.ap-northeast-2.eks.amazonaws.com - no scheme and no trailing slash. Lowercase matters: EKS reports the cluster id in uppercase hex and VPC Lattice stores the domain name lowercase, so an uppercase value here is accepted by plan and then fails the apply with \"Provider produced inconsistent result after apply\" on custom_domain_name - after the resource configuration has been created. Wrap the derivation in lower(), as this project's root does (rules.md B-1)."
  }
}
variable "cluster_security_group_id" {
  type        = string
  description = "The cluster's own security group, which has to accept 443 from the resource gateway. Injected as an ID so this module never learns what it belongs to (rules.md B-6) - and without this rule the gateway resolves the endpoint and every connection through it times out"

  validation {
    condition     = can(regex("^sg-[0-9a-f]+$", var.cluster_security_group_id))
    error_message = "cluster_security_group_id must be a valid security group ID."
  }
}
variable "port_ranges" {
  type        = list(string)
  default     = ["443"]
  description = "Ports the resource configuration forwards. The _monolithic template opened 1-65535, which is every port on a resource that serves exactly one - 443. Narrower here, because a resource configuration is the thing that decides what a client on the other side can reach"

  validation {
    condition     = length(var.port_ranges) > 0
    error_message = "port_ranges must contain at least one port or range."
  }
  validation {
    condition     = alltrue([for range in var.port_ranges : can(regex("^[0-9]+(-[0-9]+)?$", range))])
    error_message = "port_ranges entries must be a port or a port range such as \"443\" or \"1-65535\"."
  }
}
variable "allow_association_to_shareable_service_network" {
  type        = bool
  default     = true
  description = "Whether this resource configuration may be associated with a service network shared through RAM. True, as the _monolithic template set it - that property came through the CloudFormation conversion as an unmapped TODO, so it was silently lost. It is what makes the cross-account version of this pattern possible, and it cannot be changed after creation"
}
variable "dns_resolution_scope" {
  type        = string
  default     = "IN_VPC"
  description = "Where the resource gateway resolves the target hostname. IN_VPC, as the _monolithic template had it, and the only value that works here: the API server's private endpoint resolves to a VPC-internal address, so resolution has to happen inside the cluster's VPC rather than at the client"

  validation {
    condition     = contains(["IN_VPC", "IN_VPC_ONLY", "FAILOVER"], var.dns_resolution_scope)
    error_message = "dns_resolution_scope must be IN_VPC, IN_VPC_ONLY or FAILOVER."
  }
}
variable "ip_address_type" {
  type        = string
  default     = "IPV4"
  description = "Address family for the gateway, as the _monolithic template had it. The cluster is created with an ipv4 service CIDR, so the two have to agree"

  validation {
    condition     = contains(["IPV4", "IPV6", "DUALSTACK"], var.ip_address_type)
    error_message = "ip_address_type must be IPV4, IPV6 or DUALSTACK."
  }
}
