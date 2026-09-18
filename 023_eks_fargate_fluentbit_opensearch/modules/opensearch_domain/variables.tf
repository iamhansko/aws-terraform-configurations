variable "domain_name" {
  type        = string
  default     = "stem-fargate-logs"
  description = "Name of the OpenSearch domain. Part of the endpoint Fluent Bit writes to, so this value reaches the cluster as configuration"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,27}$", var.domain_name))
    error_message = "domain_name must be 3-28 characters, start with a lowercase letter, and contain only lowercase letters, digits and hyphens - the set OpenSearch accepts."
  }
}
variable "engine_version" {
  type        = string
  default     = "OpenSearch_2.19"
  description = "Engine and version of the domain"

  validation {
    condition     = can(regex("^(OpenSearch_[0-9]+\\.[0-9]+|Elasticsearch_[0-9]+\\.[0-9]+)$", var.engine_version))
    error_message = "engine_version must look like OpenSearch_2.19 or Elasticsearch_7.10."
  }
}
variable "instance_type" {
  type        = string
  default     = "m5.large.search"
  description = "Data node instance type. This is the largest cost in the project by a wide margin - the domain runs continuously whether or not anything is logging, unlike Fargate pods"

  validation {
    condition     = can(regex("\\.search$", var.instance_type))
    error_message = "instance_type must be an OpenSearch instance type ending in .search (e.g. m5.large.search)."
  }
}
variable "instance_count" {
  type        = number
  default     = 1
  description = "Number of data nodes. One, with zone awareness off, because a demo does not need replicas - and a single node is why the index Fluent Bit writes to reports yellow health rather than green"

  validation {
    condition     = var.instance_count >= 1
    error_message = "instance_count must be at least 1."
  }
}
variable "dedicated_master_enabled" {
  type        = bool
  default     = false
  description = "Whether to run dedicated master nodes. False for a single-node demo; a production domain wants three"
}
variable "zone_awareness_enabled" {
  type        = bool
  default     = false
  description = "Whether to spread data nodes across availability zones. False because it requires at least two nodes, and this domain has one"

  validation {
    condition     = var.zone_awareness_enabled == false
    error_message = "zone_awareness_enabled must be false in this configuration. OpenSearch requires an even instance_count of at least two for zone awareness, and instance_count defaults to 1 - the domain create call is rejected otherwise. Raise instance_count first if multi-AZ is wanted."
  }
}
variable "volume_type" {
  type        = string
  default     = "gp3"
  description = "EBS volume type backing the data nodes"

  validation {
    condition     = contains(["gp2", "gp3", "io1"], var.volume_type)
    error_message = "volume_type must be one of: gp2, gp3, io1."
  }
}
variable "volume_size" {
  type        = number
  default     = 50
  description = "EBS volume size in GiB per data node"

  validation {
    condition     = var.volume_size >= 10
    error_message = "volume_size must be at least 10 GiB, the minimum OpenSearch accepts for most instance types."
  }
}
variable "volume_iops" {
  type        = number
  default     = 3000
  description = "Provisioned IOPS, applied only when volume_type is gp3. gp2 derives IOPS from the volume size and rejects an explicit figure, so the module drops it in that case"

  validation {
    condition     = var.volume_iops >= 3000
    error_message = "volume_iops must be at least 3000, the gp3 baseline."
  }
}
variable "tls_security_policy" {
  type        = string
  default     = "Policy-Min-TLS-1-2-2019-07"
  description = "Minimum TLS version the endpoint accepts"

  validation {
    condition     = can(regex("^Policy-Min-TLS-1-[02]", var.tls_security_policy))
    error_message = "tls_security_policy must be one of the Policy-Min-TLS-1-* policies OpenSearch offers."
  }
}
variable "master_user_name" {
  type        = string
  default     = "admin"
  description = "Fine-grained access control master user. This is the OpenSearch Dashboards login, not an IAM identity"

  validation {
    condition     = length(var.master_user_name) > 0
    error_message = "master_user_name must not be empty."
  }
}
variable "master_user_password" {
  type        = string
  sensitive   = true
  description = "Password for the master user. Marked sensitive so it stays out of plan output and logs - the _monolithic template carried it as a plain default (adminPassword1234!), which put it in every plan, every state file and the CloudFormation console"

  validation {
    condition     = length(var.master_user_password) >= 8
    error_message = "master_user_password must be at least 8 characters."
  }
  validation {
    condition = (
      can(regex("[A-Z]", var.master_user_password)) &&
      can(regex("[a-z]", var.master_user_password)) &&
      can(regex("[0-9]", var.master_user_password)) &&
      can(regex("[^A-Za-z0-9]", var.master_user_password))
    )
    error_message = "master_user_password must contain an uppercase letter, a lowercase letter, a digit and a special character. OpenSearch enforces this and rejects the domain create call otherwise, after several minutes of waiting."
  }
}
variable "advanced_options" {
  type = map(string)
  default = {
    "indices.fielddata.cache.size"           = "20"
    "indices.query.bool.max_clause_count"    = "1024"
    "override_main_response_version"         = "false"
    "rest.action.multi.allow_explicit_index" = "true"
  }
  description = "Cluster-level settings passed through to the engine, carried over from the _monolithic template. Values are strings because the API takes them as strings, including the boolean-looking ones"

  validation {
    condition     = alltrue([for key in keys(var.advanced_options) : length(key) > 0])
    error_message = "advanced_options must not contain empty keys."
  }
}
variable "auto_software_update_enabled" {
  type        = bool
  default     = true
  description = "Whether AWS applies service software updates automatically"
}
variable "enable_key_rotation" {
  type        = bool
  default     = true
  description = "Whether the KMS key rotates annually. Not in the _monolithic template, which left the key at defaults"
}
variable "kms_deletion_window_in_days" {
  type        = number
  default     = 7
  description = "How long the KMS key stays in a pending-deletion state after terraform destroy. 7 is the minimum - the key cannot be deleted immediately, and until it is gone its alias-free presence is the only trace the domain leaves behind"

  validation {
    condition     = var.kms_deletion_window_in_days >= 7 && var.kms_deletion_window_in_days <= 30
    error_message = "kms_deletion_window_in_days must be between 7 and 30."
  }
}
variable "access_policy_principal" {
  type        = string
  default     = "*"
  description = "Principal in the domain access policy. '*' as the _monolithic template had it, which relies entirely on fine-grained access control to decide what a caller may do. Narrow it to the Fargate pod execution role and the bastion role for anything but a demo"

  validation {
    condition     = length(var.access_policy_principal) > 0
    error_message = "access_policy_principal must not be empty."
  }
}
