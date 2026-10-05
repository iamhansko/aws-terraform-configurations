variable "name" {
  type        = string
  default     = "ebs-sc"
  description = "Name of the StorageClass, as the guidance installer named it - and the value passed to the chart as etcd.internal.pvc.storageClass, so it is the interface between this module and the control plane rather than a label (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "volume_type" {
  type        = string
  default     = "gp3"
  description = "EBS volume type the class provisions, as the installer's class had it. gp3 rather than gp2: cheaper per GiB, and its baseline throughput does not scale with size"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2", "sc1", "st1"], var.volume_type)
    error_message = "volume_type must be one of: gp2, gp3, io1, io2, sc1, st1."
  }
}
variable "encrypted" {
  type        = bool
  default     = true
  description = "Whether volumes provisioned by this class are encrypted at rest, as the installer's class had it. On matters more here than it looks: the volume this class provisions holds Karmada's etcd, which is where every credential for every member cluster is stored"
}
variable "is_default_class" {
  type        = bool
  default     = true
  description = "Whether this class carries the default annotation, as the installer's class had it. The control plane names the class explicitly, so nothing here depends on it - it is kept on so that a claim created by hand on this cluster resolves to something, because EKS's built-in gp2 carries no default annotation on current Kubernetes versions"
}
variable "reclaim_policy" {
  type        = string
  default     = "Delete"
  description = "What happens to the EBS volume when its claim is deleted. Delete, so that destroying the control plane does not leave a billed volume behind holding etcd's data"

  validation {
    condition     = contains(["Delete", "Retain"], var.reclaim_policy)
    error_message = "reclaim_policy must be either Delete or Retain."
  }
}
variable "volume_binding_mode" {
  type        = string
  default     = "WaitForFirstConsumer"
  description = "When the volume is created. WaitForFirstConsumer, as the installer's class had it, so the volume lands in the zone the pod was scheduled into (see main.tf for what Immediate does to an etcd pod)"

  validation {
    condition     = contains(["Immediate", "WaitForFirstConsumer"], var.volume_binding_mode)
    error_message = "volume_binding_mode must be either Immediate or WaitForFirstConsumer."
  }
}
variable "allow_volume_expansion" {
  type        = bool
  default     = true
  description = "Whether a claim's size can be increased in place. On, which the installer's class left off - and it cannot be turned on later for volumes already provisioned by a class that had it off, so growing etcd would mean replacing it"
}
