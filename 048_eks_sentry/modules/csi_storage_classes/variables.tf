variable "storage_class_name" {
  type        = string
  default     = "gp3"
  description = "Name of the StorageClass, as the _monolithic template named it. Nothing in this project references the name - the chart's claims name no class and reach it through the default annotation - so this is cosmetic, unlike in projects whose workload names its class"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.storage_class_name))
    error_message = "storage_class_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "volume_type" {
  type        = string
  default     = "gp3"
  description = "EBS volume type the class provisions, as the _monolithic template had it. gp3 rather than the gp2 EKS ships: cheaper per GiB, and its baseline throughput does not scale with size - which matters when eight volumes are provisioned at their minimum size"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2", "sc1", "st1"], var.volume_type)
    error_message = "volume_type must be one of: gp2, gp3, io1, io2, sc1, st1."
  }
}
variable "encrypted" {
  type        = bool
  default     = true
  description = "Whether volumes provisioned by this class are encrypted at rest. On, where the _monolithic template's class set only the type - which left Sentry's event data, its PostgreSQL database and every Kafka log segment on unencrypted volumes"
}
variable "is_default_class" {
  type        = bool
  default     = true
  description = "Whether this class carries the default annotation. Must stay true: none of the chart's eight claims names a storageClassName, so the annotation is the only thing that connects them to this class"

  validation {
    # A constant condition, because the constraint is about this variant rather than about a
    # combination of values (rules.md B-1). Nothing here could detect the violation later: every
    # claim would simply stay Pending, and the release would report "context deadline exceeded"
    # from its hook chain with no mention of storage.
    condition     = var.is_default_class
    error_message = "is_default_class must be true in this variant, because the Sentry chart's eight PersistentVolumeClaims name no storageClassName and resolve only through the default-class annotation. To run with it false, set each subchart's own persistence.storageClass value instead - postgresql, kafka, zookeeper, redis, rabbitmq and clickhouse each have their own path."
  }
}

variable "reclaim_policy" {
  type        = string
  default     = "Delete"
  description = "What happens to the EBS volume when its claim is deleted. Delete, as the _monolithic template had it. Note that it does not save a destroy from leaving volumes behind: seven of the eight claims come from StatefulSet volumeClaimTemplates, which helm uninstall does not delete, so the claims outlive the release and have to be removed before a reinstall"

  validation {
    condition     = contains(["Delete", "Retain"], var.reclaim_policy)
    error_message = "reclaim_policy must be either Delete or Retain."
  }
}
variable "volume_binding_mode" {
  type        = string
  default     = "WaitForFirstConsumer"
  description = "When the volume is created. WaitForFirstConsumer, as the _monolithic template had it, so each volume lands in the zone its pod was scheduled into. With Immediate, eight volumes are created in arbitrary zones before anything is scheduled, and any pod that cannot be placed in its volume's zone stays Pending with no message that explains why"

  validation {
    condition     = contains(["Immediate", "WaitForFirstConsumer"], var.volume_binding_mode)
    error_message = "volume_binding_mode must be either Immediate or WaitForFirstConsumer."
  }
}
variable "allow_volume_expansion" {
  type        = bool
  default     = true
  description = "Whether a claim's size can be increased in place. On, which the _monolithic template's class left off - and it cannot be turned on afterwards for volumes already provisioned by a class that had it off, which for Sentry's ClickHouse and Kafka volumes is the difference between resizing and reinstalling"
}

