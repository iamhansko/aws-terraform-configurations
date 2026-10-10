variable "vpc_id" {
  type        = string
  description = "VPC the namespace's private hosted zone is associated with. Only resolvers in this VPC answer for the namespace"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "namespace_name" {
  type        = string
  default     = "service-discovery.local"
  description = "DNS name of the namespace, as the _monolithic template had it. Tasks are reachable at <service_name>.<namespace_name>. Scoped to the VPC, so two copies of this project in one account do not collide. Changing it replaces the namespace and its hosted zone"

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.namespace_name)) && length(var.namespace_name) <= 253
    error_message = "namespace_name must be a lowercase DNS name with at least two labels, such as service-discovery.local."
  }
}
variable "namespace_description" {
  type        = string
  default     = "Private DNS Namespace for ECS Service Discovery"
  description = "Description of the namespace, as the _monolithic template had it"

  validation {
    condition     = length(var.namespace_description) <= 1024
    error_message = "namespace_description must be 1024 characters or fewer."
  }
}
variable "service_name" {
  type        = string
  default     = "nginx"
  description = "Name of the Cloud Map service, as the _monolithic template had it - the first label of the DNS name the tasks are found at"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.service_name))
    error_message = "service_name must be a single lowercase DNS label of 1-63 letters, digits and hyphens."
  }
}
variable "dns_record_type" {
  type        = string
  default     = "A"
  description = "Record type registered per task, as the _monolithic template had it. A suits awsvpc tasks, each of which has its own address; SRV is for tasks that share a host address and differ by port"

  validation {
    condition     = contains(["A", "AAAA", "SRV"], var.dns_record_type)
    error_message = "dns_record_type must be A, AAAA or SRV - the record types an ECS service registry can use."
  }
}
variable "dns_ttl" {
  type        = number
  default     = 60
  description = "TTL in seconds of each record, as the _monolithic template had it. It bounds how long a client keeps using the address of a task that has stopped"

  validation {
    condition     = var.dns_ttl >= 0 && var.dns_ttl <= 2147483647 && floor(var.dns_ttl) == var.dns_ttl
    error_message = "dns_ttl must be a whole number of seconds, zero or greater."
  }
}
variable "routing_policy" {
  type        = string
  default     = "MULTIVALUE"
  description = "How Route 53 answers a query for the service, as the _monolithic template had it"

  validation {
    condition     = contains(["MULTIVALUE", "WEIGHTED"], var.routing_policy)
    error_message = "routing_policy must be MULTIVALUE or WEIGHTED."
  }
}
