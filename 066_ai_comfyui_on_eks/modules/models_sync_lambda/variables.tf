variable "function_name" {
  type        = string
  default     = "comfy-models-sync"
  description = "Name of the Lambda function, comfy-models-sync as the blueprint named it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,64}$", var.function_name))
    error_message = "function_name must be 1-64 characters of letters, digits, hyphens and underscores."
  }
}
variable "source_dir" {
  type        = string
  description = "Directory holding model_sync.py, zipped into the function package"

  validation {
    condition     = length(var.source_dir) > 0
    error_message = "source_dir must not be empty."
  }
}
variable "models_bucket_name" {
  type        = string
  description = "Bucket the function copies models from, passed to it as MODELS_BUCKET"

  validation {
    condition     = length(var.models_bucket_name) >= 3
    error_message = "models_bucket_name must be a bucket name."
  }
}
variable "models_bucket_arn" {
  type        = string
  description = "ARN of models_bucket_name. The bucket is the only principal allowed to invoke the function"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:s3:::", var.models_bucket_arn))
    error_message = "models_bucket_arn must be an S3 bucket ARN."
  }
}
variable "node_models_path" {
  type        = string
  description = "Directory on the GPU nodes the models are copied into - the instance-store mount the node user data prepares and the ComfyUI pod mounts as a hostPath. One value for all three (rules.md B-5)"

  validation {
    condition     = can(regex("^/[A-Za-z0-9/_.-]+$", var.node_models_path)) && !strcontains(var.node_models_path, "..")
    error_message = "node_models_path must be an absolute path of plain characters - it is written into shell commands on the nodes."
  }
}
variable "cluster_name" {
  type        = string
  description = "EKS cluster whose GPU nodes are synced. Matched against the eks:eks-cluster-name tag Karpenter writes on every instance it launches, both when finding the nodes and in the IAM condition that limits where commands may run"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "node_pool_name" {
  type        = string
  description = "Karpenter NodePool whose instances are synced, matched against the karpenter.sh/nodepool tag"

  validation {
    condition     = length(var.node_pool_name) > 0
    error_message = "node_pool_name must not be empty."
  }
}
variable "runtime" {
  type        = string
  default     = "python3.12"
  description = "Lambda runtime, python3.12 as the blueprint had it"

  validation {
    condition     = can(regex("^python3\\.(1[2-9]|[2-9][0-9])$", var.runtime))
    error_message = "runtime must be python3.12 or newer."
  }
}
variable "timeout" {
  type        = number
  default     = 120
  description = "How long the function may run, 120 seconds as the blueprint had it. It only sends commands and does not wait for the copies, which can take minutes for a large model"

  validation {
    condition     = var.timeout >= 1 && var.timeout <= 900
    error_message = "timeout must be between 1 and 900 seconds."
  }
}
variable "memory_size" {
  type        = number
  default     = 256
  description = "Memory for the function in MB, 256 as the blueprint had it"

  validation {
    condition     = var.memory_size >= 128 && var.memory_size <= 10240
    error_message = "memory_size must be between 128 and 10240 MB."
  }
}
variable "log_retention_days" {
  type        = number
  default     = 14
  description = "How long the function's logs are kept"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of the retention periods CloudWatch Logs accepts."
  }
}
