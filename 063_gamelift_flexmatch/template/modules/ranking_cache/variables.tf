variable "cluster_id" {
  type        = string
  default     = "gomokuranking"
  description = "ElastiCache cluster ID, as the _monolithic template had it. Unique per account and region"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.cluster_id)) && length(var.cluster_id) <= 40 && !strcontains(var.cluster_id, "--") && !endswith(var.cluster_id, "-")
    error_message = "cluster_id must be 1-40 lowercase letters, digits and hyphens, start with a letter, and contain no consecutive or trailing hyphen."
  }
}
variable "subnet_group_name" {
  type        = string
  description = "Name of the ElastiCache subnet group. CloudFormation generated one; Terraform requires it"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.subnet_group_name)) && length(var.subnet_group_name) <= 255
    error_message = "subnet_group_name must be 1-255 lowercase letters, digits and hyphens."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Subnets the node may be placed in"

  validation {
    condition     = length(var.subnet_ids) > 0 && alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "subnet_ids must contain at least one valid subnet ID."
  }
}
variable "security_group_ids" {
  type        = list(string)
  description = "Security groups attached to the node. Not iterated, so a list of another module's outputs is fine here (rules.md B-8 applies to for_each only)"

  validation {
    condition     = alltrue([for id in var.security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "security_group_ids must contain valid security group IDs."
  }
}
variable "node_type" {
  type        = string
  default     = "cache.r7g.large"
  description = "Node type, as the _monolithic template had it. Expensive for a demo: a memory-optimized node billed by the hour for a sorted set of a few dozen players. cache.t4g.micro holds the same data"

  validation {
    condition     = can(regex("^cache\\.[a-z0-9-]+\\.[a-z0-9]+$", var.node_type))
    error_message = "node_type must be an ElastiCache node type (e.g. cache.t4g.micro)."
  }
}
variable "engine_version" {
  type        = string
  default     = "7.1"
  description = "Redis engine version. The _monolithic template wrote it as the number 7.1; the provider takes a string"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9x]+(\\.[0-9]+)?$", var.engine_version))
    error_message = "engine_version must be a Redis version such as 7.1."
  }
}
variable "port" {
  type        = number
  default     = 6379
  description = "Redis port. The two Lambda handlers connect on 6379 literally (redis.Redis(host=..., port=6379)), so the root keeps it there"

  validation {
    condition     = var.port > 0 && var.port <= 65535
    error_message = "port must be a valid TCP port."
  }
}
