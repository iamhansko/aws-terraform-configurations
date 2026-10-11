variable "storage_class_name" {
  type        = string
  default     = "gp3"
  description = "Name of the StorageClass, as the _monolithic template named it. The demo's volumeClaimTemplate names this explicitly rather than relying on the default annotation, so the name is part of the interface between the two modules (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.storage_class_name))
    error_message = "storage_class_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "volume_type" {
  type        = string
  default     = "gp3"
  description = "EBS volume type the class provisions. gp3 rather than the gp2 EKS defaults to: cheaper per GiB, and its baseline throughput does not scale with size"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2", "sc1", "st1"], var.volume_type)
    error_message = "volume_type must be one of: gp2, gp3, io1, io2, sc1, st1."
  }
}
variable "encrypted" {
  type        = bool
  default     = true
  description = "Whether volumes provisioned by this class are encrypted at rest. On, where the _monolithic template's class set only the type - which left the demo's volume, the EBS snapshot taken from it and the data moved into the backup bucket all unencrypted"
}
variable "is_default_class" {
  type        = bool
  default     = true
  description = "Whether this class carries the default annotation, as the _monolithic template's did. Leave it on: it is what lets a claim naming no storageClassName resolve to anything at all, because EKS's built-in gp2 carries no default annotation on current Kubernetes versions"
}
variable "reclaim_policy" {
  type        = string
  default     = "Delete"
  description = "What happens to the EBS volume when its claim is deleted. Delete, as the _monolithic template had it - which is also why a restore into the second cluster creates a new volume from the snapshot rather than reattaching anything"

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
  description = "Whether a claim's size can be increased in place. On, which the _monolithic template's class left off - and it cannot be turned on for volumes already provisioned by a class that had it off"
}
variable "create_volume_snapshot_class" {
  type        = bool
  default     = false
  description = "Whether to create a VolumeSnapshotClass alongside the StorageClass. Off here, because its kind comes from the snapshot-controller addon's CRDs and this project does not install that addon - a cluster without it rejects the manifest at apply, long after a clean plan (rules.md B-4). Turn it on only together with a snapshot-controller addon module"
}
variable "volume_snapshot_class_name" {
  type        = string
  default     = "ebs-vsc"
  description = "Name of the VolumeSnapshotClass. Ignored when create_volume_snapshot_class is off"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.volume_snapshot_class_name))
    error_message = "volume_snapshot_class_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "is_default_snapshot_class" {
  type        = bool
  default     = true
  description = "Whether the snapshot class carries the default annotation, as the _monolithic template's did. Velero also needs the velero.io/csi-volumesnapshot-class label, which this module always sets - the annotation alone is what the original relied on, and it stops being enough as soon as a second snapshot class exists"
}
variable "snapshot_deletion_policy" {
  type        = string
  default     = "Delete"
  description = "What happens to the EBS snapshot when its VolumeSnapshot is deleted. Delete, as the _monolithic template had it. Retain leaves snapshots behind after a destroy, billed and belonging to nothing - which in a project that takes snapshots repeatedly adds up quietly"

  validation {
    condition     = contains(["Delete", "Retain"], var.snapshot_deletion_policy)
    error_message = "snapshot_deletion_policy must be either Delete or Retain."
  }
}
