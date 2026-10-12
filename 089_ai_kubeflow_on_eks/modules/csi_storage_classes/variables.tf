variable "storage_class_name" {
  type        = string
  default     = "gp3"
  description = "Name of the StorageClass, as the _monolithic template named it. Cosmetic rather than referenced: Kubeflow's claims come from upstream kustomize manifests that name no class, so they reach this one through its default annotation"

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
  description = "Whether volumes provisioned by this class are encrypted at rest. On, where the _monolithic template's class set only the type - which left the pipeline metadata database and every artifact written to the object store on unencrypted volumes"
}
variable "is_default_class" {
  type        = bool
  default     = true
  description = "Whether this class carries the default annotation. Must stay true: Kubeflow's claims are upstream manifests that name no storageClassName, and unlike a Helm chart there is no value to override, so the annotation is the only thing that connects them to this class"

  validation {
    # A constant condition, because the constraint is about this variant rather than about a
    # combination of values (rules.md B-1). Nothing would report the violation: the kustomize apply
    # succeeds either way and the install association finishes, leaving Katib and the pipeline
    # components Pending behind a dashboard that loads fine.
    condition     = var.is_default_class
    error_message = "is_default_class must be true in this variant, because Kubeflow is installed from upstream kustomize manifests whose PersistentVolumeClaims name no storageClassName and resolve only through the default-class annotation. There is no chart value to set instead - running with it false would need a kustomize patch adding storageClassName to each claim."
  }
}

variable "reclaim_policy" {
  type        = string
  default     = "Delete"
  description = "What happens to the EBS volume when its claim is deleted. Delete, as the _monolithic template had it - so a destroy does not leave the pipeline database and artifact store behind, billed and belonging to nothing"

  validation {
    condition     = contains(["Delete", "Retain"], var.reclaim_policy)
    error_message = "reclaim_policy must be either Delete or Retain."
  }
}
variable "volume_binding_mode" {
  type        = string
  default     = "WaitForFirstConsumer"
  description = "When the volume is created. WaitForFirstConsumer, as the _monolithic template had it, so the volume lands in the zone the pod was scheduled into. That matters more here than usual: Karpenter picks the zone it has capacity in, and a volume created up front in a different one cannot be followed - the pod stays Pending with no message that explains why"

  validation {
    condition     = contains(["Immediate", "WaitForFirstConsumer"], var.volume_binding_mode)
    error_message = "volume_binding_mode must be either Immediate or WaitForFirstConsumer."
  }
}
variable "allow_volume_expansion" {
  type        = bool
  default     = true
  description = "Whether a claim's size can be increased in place. On, which the _monolithic template's class left off - and it cannot be turned on afterwards for volumes already provisioned by a class that had it off, which for a filling artifact store means reinstalling rather than resizing"
}
variable "workload_namespace" {
  type        = string
  description = "Namespace whose claims the diagnostic command this module outputs looks at. The StorageClass itself is cluster-scoped, so nothing about its creation depends on this"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.workload_namespace))
    error_message = "workload_namespace must be a valid lowercase RFC 1123 label."
  }
}
