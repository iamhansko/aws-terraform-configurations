variable "name" {
  type        = string
  default     = "kubeadm-cluster-state"
  description = "Name tag of the bucket"

  validation {
    condition     = length(var.name) > 0
    error_message = "name must not be empty."
  }
}

variable "bucket_prefix" {
  type        = string
  default     = "kubeadm-state-"
  description = "Prefix for the generated bucket name. A prefix rather than a fixed name because bucket names are globally unique, so a fixed one stops this project from being deployed twice"

  validation {
    # S3 allows 63 characters and the provider allows a prefix of up to 37, leaving
    # room for the suffix it appends.
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,36}$", var.bucket_prefix))
    error_message = "bucket_prefix must be 2-37 characters of lowercase letters, digits, dots and hyphens, starting with a letter or digit."
  }
}

variable "force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy deletes the objects in the bucket along with it. True, because the instances put objects in it that Terraform does not track, and S3 refuses to delete a non-empty bucket - this is what the _monolithic template needed a Lambda for"
}

variable "sse_algorithm" {
  type        = string
  default     = "AES256"
  description = "Server-side encryption algorithm for objects at rest. AES256 is the S3 managed key, which needs no key policy; aws:kms would also need the instance roles granted on the key"

  validation {
    condition     = contains(["AES256", "aws:kms"], var.sse_algorithm)
    error_message = "sse_algorithm must be either AES256 or aws:kms."
  }
}

variable "object_keys" {
  type        = list(string)
  default     = ["kubeconfig", "join.sh"]
  description = "Object keys the generated IAM policy grants on, which is the whole protocol between the three instances: the control plane writes both, the worker reads join.sh, the workbench reads kubeconfig"

  validation {
    condition     = length(var.object_keys) > 0
    error_message = "object_keys must name at least one object; a policy granting nothing leaves the instances unable to exchange anything."
  }
  validation {
    condition     = alltrue([for key in var.object_keys : !startswith(key, "/")])
    error_message = "object_keys are S3 keys, not paths, so they must not start with a slash - the ARN already supplies the separator."
  }
}

variable "policy_name_prefix" {
  type        = string
  default     = "kubeadm-cluster-state-"
  description = "Prefix for the generated IAM policy name. A prefix, not a fixed name, for the same reason as the bucket: a fixed name collides with a second copy of this project"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.policy_name_prefix))
    error_message = "policy_name_prefix must be 1-64 characters valid in an IAM policy name."
  }
}
