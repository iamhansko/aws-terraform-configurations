variable "subnet_ids" {
  type        = list(string)
  description = "Subnets the subnet group spans. Private subnets: see main.tf for why the public pair the _monolithic template also listed is left out"

  validation {
    condition     = length(var.subnet_ids) > 0 && alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "subnet_ids must contain at least one valid subnet ID (e.g. subnet-0123456789abcdef0)."
  }
}
variable "security_group_ids" {
  type        = list(string)
  description = "Security groups attached to the node. A list, not a map, because it is assigned to an attribute rather than iterated with for_each, so unknown values are fine here (rules.md B-8 is about for_each keys)"

  validation {
    condition     = length(var.security_group_ids) > 0 && alltrue([for id in var.security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "security_group_ids must contain at least one valid security group ID (e.g. sg-0123456789abcdef0)."
  }
}
variable "subnet_group_name" {
  type        = string
  default     = "gamelift-flexmatch-redis"
  description = "Name of the subnet group. Unique per account and region; the _monolithic template derived it from its stack name, and the root derives it from project_name"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,254}$", var.subnet_group_name))
    error_message = "subnet_group_name must be 1-255 characters of lowercase letters, digits and hyphens, starting with a letter or digit. ElastiCache lowercases the name it stores, so an uppercase name would show a perpetual diff."
  }
}
variable "cluster_id" {
  type        = string
  default     = "gomokuranking"
  description = "Cluster identifier, as the _monolithic template had it. Unique per account and region, and not read by any code - the functions get the node address through the REDIS environment variable"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,39}$", var.cluster_id)) && !strcontains(var.cluster_id, "--") && !endswith(var.cluster_id, "-")
    error_message = "cluster_id must be 1-40 characters of lowercase letters, digits and hyphens, start with a letter, and contain no consecutive hyphens and no trailing hyphen."
  }
}
variable "engine_version" {
  type        = string
  default     = "7.1"
  description = "Redis engine version, as the _monolithic template had it. From Redis 6 on ElastiCache takes major.minor (7.1) rather than a full patch version"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9x]+(\\.[0-9]+)?$", var.engine_version))
    error_message = "engine_version must look like 7.1, 6.x or 5.0.6."
  }
}
variable "node_type" {
  type        = string
  default     = "cache.r7g.large"
  description = "Node type, as the _monolithic template had it - and the most expensive line in this project after the Windows instance. cache.r7g.large is a memory-optimised node with about 13 GiB of memory; the leaderboard is one sorted set of a few players. The upstream workshop used cache.t2.medium, and a burstable type such as cache.t4g.micro does this job at a small fraction of the price. Kept as the template's default because changing it is a cost decision, not a conversion"

  validation {
    condition     = can(regex("^cache\\.[a-z0-9]+\\.[a-z0-9]+$", var.node_type))
    error_message = "node_type must be an ElastiCache node type such as cache.t4g.micro or cache.r7g.large."
  }
}
variable "port" {
  type        = number
  default     = 6379
  description = "Port the node listens on. Load-bearing: GetRank.py and Scoring.py in Lambda/code.zip connect with redis.Redis(host=..., port=6379) and take only the host from the environment"

  validation {
    condition     = var.port == 6379
    error_message = "port must stay 6379, because the handlers in the sample repository's Lambda/code.zip hard-code it and read only the host from the REDIS environment variable. Rebuild code.zip to read the port too before relaxing this."
  }
}
