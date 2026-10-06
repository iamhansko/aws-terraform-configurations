variable "cluster_name" {
  type        = string
  description = "EKS cluster the virtual cluster is backed by"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}

variable "namespace" {
  type        = string
  description = "Namespace the virtual cluster is bound to, taken from the module that authorised EMR in it rather than restated (rules.md B-5). CreateVirtualCluster reads this namespace, and it fails if the RBAC and the aws-auth mapping are not in place first (rules.md E-6)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 label."
  }
}

variable "oidc_provider_arn" {
  type        = string
  description = "ARN of the cluster's IAM OIDC provider, the Federated principal in the job execution role's trust policy"

  validation {
    condition     = can(regex("^arn:aws:iam::", var.oidc_provider_arn))
    error_message = "oidc_provider_arn must be a valid IAM OIDC provider ARN."
  }
}

variable "oidc_issuer_host" {
  type        = string
  description = "Cluster OIDC issuer URL without the https:// scheme, used in the trust policy's sub condition key"

  validation {
    condition     = length(var.oidc_issuer_host) > 0 && !can(regex("^https://", var.oidc_issuer_host))
    error_message = "oidc_issuer_host must be non-empty and must not include the https:// scheme."
  }
}

variable "name" {
  type        = string
  default     = "big-data-cluster"
  description = "Name of the EMR virtual cluster, as the _monolithic template named it. Also the prefix of the job execution role's generated name"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,63}$", var.name))
    error_message = "name must start with a letter or digit and contain only letters, digits, hyphens and underscores."
  }
}

variable "bucket_prefix" {
  type        = string
  default     = "emr-on-eks-"
  description = "Prefix for the generated job data bucket name. A prefix rather than a fixed name because bucket names are globally unique, so a fixed one stops this project from being deployed twice"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,36}$", var.bucket_prefix))
    error_message = "bucket_prefix must be 2-37 characters of lowercase letters, digits, dots and hyphens, starting with a letter or digit."
  }
}

variable "force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy deletes the objects in the job bucket along with it. True, because a job writes objects Terraform does not track - and S3 refuses to delete a non-empty bucket, so without it destroy stops here"
}

variable "log_group_name" {
  type        = string
  default     = "/emr/on/eks"
  description = "CloudWatch log group a job's monitoringConfiguration writes to, as the _monolithic template named it"

  validation {
    condition     = startswith(var.log_group_name, "/")
    error_message = "log_group_name must start with '/'."
  }
}

variable "log_retention_days" {
  type        = number
  default     = 14
  description = "Retention on the job log group. The _monolithic template set none, which means never expiring - and a Spark job at INFO writes a lot"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of the retention values CloudWatch Logs accepts."
  }
}
