variable "storage_class_name" {
  type        = string
  default     = "gp3"
  description = "Name of the StorageClass, as the _monolithic template named it. The Vault module names this explicitly in its volumeClaimTemplate rather than relying on the default annotation, so the name is part of the interface between the two modules (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.storage_class_name))
    error_message = "storage_class_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "volume_type" {
  type        = string
  default     = "gp3"
  description = "EBS volume type the class provisions, as the _monolithic template had it. gp3 rather than the gp2 EKS ships: cheaper per GiB, and its baseline throughput does not scale with size"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2", "sc1", "st1"], var.volume_type)
    error_message = "volume_type must be one of: gp2, gp3, io1, io2, sc1, st1."
  }
}
variable "encrypted" {
  type        = bool
  default     = true
  description = "Whether volumes provisioned by this class are encrypted at rest. On, where the _monolithic template's class set only the type - which left Vault's entire storage backend, unseal keys and all, on an unencrypted volume"
}
variable "is_default_class" {
  type        = bool
  default     = true
  description = "Whether this class carries the default annotation, as the _monolithic template's did. It is what lets a claim that names no storageClassName - which is most charts' default - resolve to anything at all on this cluster"
}

variable "reclaim_policy" {
  type        = string
  default     = "Delete"
  description = "What happens to the EBS volume when its claim is deleted. Delete, as the _monolithic template had it. Retain is worth considering for a real Vault, where losing the storage backend loses every secret - here the demo is re-initialised on each apply anyway, and Retain would leave a volume behind after every destroy"

  validation {
    condition     = contains(["Delete", "Retain"], var.reclaim_policy)
    error_message = "reclaim_policy must be either Delete or Retain."
  }
}
variable "volume_binding_mode" {
  type        = string
  default     = "WaitForFirstConsumer"
  description = "When the volume is created. WaitForFirstConsumer, as the _monolithic template had it, so the volume lands in the zone the pod was scheduled into. Immediate creates it in an arbitrary zone first, and a pod that cannot be scheduled there stays Pending with no message that explains why"

  validation {
    condition     = contains(["Immediate", "WaitForFirstConsumer"], var.volume_binding_mode)
    error_message = "volume_binding_mode must be either Immediate or WaitForFirstConsumer."
  }
}
variable "allow_volume_expansion" {
  type        = bool
  default     = true
  description = "Whether a claim's size can be increased in place. On, which the _monolithic template's class left off - and it cannot be turned on afterwards for volumes already provisioned by a class that had it off"
}
