variable "storage_class_name" {
  type        = string
  default     = "gp3"
  description = "Name of the StorageClass, gp3 as the blueprint named it. kube-prometheus-stack's Prometheus volume names it explicitly; the Kafka volumes reach it through the default annotation"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.storage_class_name))
    error_message = "storage_class_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "volume_type" {
  type        = string
  default     = "gp3"
  description = "EBS volume type the class provisions, gp3 as the blueprint had it"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2", "sc1", "st1"], var.volume_type)
    error_message = "volume_type must be one of: gp2, gp3, io1, io2, sc1, st1."
  }
}
variable "encrypted" {
  type        = bool
  default     = true
  description = "Whether volumes provisioned by this class are encrypted at rest, true as the blueprint had it"
}
variable "fs_type" {
  type        = string
  default     = "xfs"
  description = "Filesystem the driver formats each volume with, xfs as the blueprint had it"

  validation {
    condition     = contains(["xfs", "ext3", "ext4"], var.fs_type)
    error_message = "fs_type must be one of xfs, ext3 or ext4 - the EBS CSI driver's documented values, matched case-sensitively."
  }
}
variable "is_default_class" {
  type        = bool
  default     = true
  description = "Whether this class carries the default annotation. Must stay true: the Kafka node pools' volumes name no class and resolve only through this annotation"

  validation {
    # A constant condition, because the constraint is about this variant rather than a combination of
    # values (rules.md B-1). Nothing would report the violation: the Kafka resource is accepted, and its
    # brokers simply never start.
    condition     = var.is_default_class
    error_message = "is_default_class must be true in this variant, because the Kafka node pools' persistent-claim volumes name no storage class. To run with it false, set class on each node pool's volume in modules/kafka_cluster."
  }
}
variable "reclaim_policy" {
  type        = string
  default     = "Delete"
  description = "What happens to the EBS volume when its claim is deleted. Delete, as the blueprint had it - which is what lets terraform destroy remove the broker volumes rather than leave them billed and belonging to nothing"

  validation {
    condition     = contains(["Delete", "Retain"], var.reclaim_policy)
    error_message = "reclaim_policy must be either Delete or Retain."
  }
}
variable "volume_binding_mode" {
  type        = string
  default     = "WaitForFirstConsumer"
  description = "When the volume is created. WaitForFirstConsumer, as the blueprint had it, so the volume lands in the zone the pod was scheduled into"

  validation {
    condition     = contains(["Immediate", "WaitForFirstConsumer"], var.volume_binding_mode)
    error_message = "volume_binding_mode must be either Immediate or WaitForFirstConsumer."
  }
}
variable "allow_volume_expansion" {
  type        = bool
  default     = true
  description = "Whether a claim's size can be increased in place, true as the blueprint had it"
}
