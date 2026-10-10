variable "name" {
  type        = string
  default     = "memorydb"
  description = "Name of the cluster, as the _monolithic template had it, and the base name of its subnet group and security groups. Unique per account and region"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,39}$", var.name)) && !endswith(var.name, "-")
    error_message = "name must start with a lowercase letter and be up to 40 characters of lowercase letters, digits and hyphens, not ending in a hyphen."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC the security groups are created in"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Private subnets the cluster's nodes may be placed in"

  validation {
    condition     = length(var.subnet_ids) > 0 && alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "subnet_ids must contain at least one valid subnet ID."
  }
}
variable "ingress_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "CIDR blocks admitted on the Redis port in addition to the client group. Literal values known at plan, so a list is safe here (rules.md B-8)"

  validation {
    condition     = alltrue([for cidr in var.ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "ingress_cidr_blocks must contain valid CIDR blocks."
  }
}
variable "node_type" {
  type        = string
  default     = "db.r6g.large"
  description = "Node type, as the _monolithic template had it. Billed by the hour whether or not anything is connected - the most expensive single resource in this project"

  validation {
    condition     = startswith(var.node_type, "db.")
    error_message = "node_type must be a MemoryDB node type such as db.r6g.large."
  }
}
variable "engine_version" {
  type        = string
  default     = "7.1"
  description = "Redis engine version, as the _monolithic template had it - a number there, a string here. 7.1 is the first version whose parameter group offers the search module"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.engine_version))
    error_message = "engine_version must be a major.minor version such as 7.1."
  }
}
variable "parameter_group_name" {
  type        = string
  default     = "default.memorydb-redis7.search"
  description = "Parameter group, as the _monolithic template had it. The .search group enables vector search, which the item image service uses to find similar images"

  validation {
    condition     = length(var.parameter_group_name) > 0
    error_message = "parameter_group_name must not be empty."
  }
}
variable "num_replicas_per_shard" {
  type        = number
  default     = 0
  description = "Replicas per shard. None, as the _monolithic template had it - a node failure loses the cache, which the service rebuilds"

  validation {
    condition     = var.num_replicas_per_shard >= 0 && var.num_replicas_per_shard <= 5
    error_message = "num_replicas_per_shard must be between 0 and 5."
  }
}
variable "port" {
  type        = number
  default     = 6379
  description = "Port the cluster listens on, and the port the security group rules open"

  validation {
    condition     = var.port > 0 && var.port <= 65535
    error_message = "port must be a valid TCP port."
  }
}
variable "maintenance_window" {
  type        = string
  default     = "sun:05:00-sun:06:00"
  description = "Weekly maintenance window in UTC, as the _monolithic template had it"

  validation {
    condition     = can(regex("^(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]-(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]$", var.maintenance_window))
    error_message = "maintenance_window must look like sun:05:00-sun:06:00."
  }
}
variable "snapshot_retention_limit" {
  type        = number
  default     = 7
  description = "Days of daily snapshots kept, as the _monolithic template had it"

  validation {
    condition     = var.snapshot_retention_limit >= 0 && var.snapshot_retention_limit <= 35
    error_message = "snapshot_retention_limit must be between 0 and 35."
  }
}
