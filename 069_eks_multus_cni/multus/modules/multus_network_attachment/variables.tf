variable "name" {
  type        = string
  description = "Name of the NetworkAttachmentDefinition. No default: it is the string a pod's k8s.v1.cni.cncf.io/networks annotation has to name, and a pod naming an attachment that does not exist stays in ContainerCreating with the reason only in its events - so the value belongs to the caller, which also annotates the pod"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "default"
  description = "Namespace the attachment lives in, as the _monolithic template had it. It matters more than it looks: a pod can only name an attachment in its own namespace unless the annotation is written as <namespace>/<name>, so this has to match the workload's namespace"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "master_interface" {
  type        = string
  description = "Host interface the attachment's addresses are put on. No default, because this is the one value that differs between this project's two Multus variants: with the kernel's predictable interface naming the second ENI comes up as ens6, and with net.ifnames=0 it comes up as eth1. Naming an interface the node does not have leaves every pod that asks for this attachment stuck in ContainerCreating"

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.master_interface))
    error_message = "master_interface must be an interface name such as ens6 or eth1."
  }
}
variable "cni_version" {
  type        = string
  default     = "0.3.1"
  description = "CNI specification version declared in the attachment's config. Has to match the version the Multus daemon was configured with, or the attachment is rejected when a pod first asks for it rather than when it is applied (rules.md B-5)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.cni_version))
    error_message = "cni_version must be a semantic version such as 0.3.1."
  }
}
variable "cni_type" {
  type        = string
  default     = "ipvlan"
  description = "CNI plugin the attachment uses, ipvlan as the _monolithic template and AWS's own guidance have it. ipvlan shares the master interface's MAC address, which is what makes it work on EC2 at all - macvlan hands each pod its own MAC, and a VPC ENI drops frames from a MAC it does not know"

  validation {
    condition     = contains(["ipvlan", "macvlan"], var.cni_type)
    error_message = "cni_type must be ipvlan or macvlan. macvlan needs the ENI to permit additional MAC addresses, which a VPC ENI does not."
  }
}
variable "cni_mode" {
  type        = string
  default     = "l3"
  description = "ipvlan mode, l3 as the _monolithic template had it. l3 routes rather than bridges, so the pod's traffic leaves the ENI with the ENI's own MAC and the VPC is none the wiser"

  validation {
    condition     = contains(["l2", "l3", "l3s"], var.cni_mode)
    error_message = "cni_mode must be l2, l3 or l3s."
  }
}
variable "subnet_cidr" {
  type        = string
  description = "CIDR of the subnet the master interface's ENI sits in. Taken from the network module rather than restated, because the addresses this attachment hands out have to be routable on that ENI's subnet (rules.md B-5)"

  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "subnet_cidr must be a valid IPv4 CIDR block."
  }
}
variable "pod_range_cidr" {
  type        = string
  description = "The block inside subnet_cidr that host-local hands addresses out of. Taken from the network module, which carves it from the subnet it owns, rather than derived here - the caller's VPC reservation has to name the same block and has to exist before any node boots (rules.md B-5)"

  validation {
    condition     = can(cidrhost(var.pod_range_cidr, 0))
    error_message = "pod_range_cidr must be a valid IPv4 CIDR block."
  }
  validation {
    # Containment, which the previous newbits/index interface made structurally impossible to get
    # wrong. Terraform has no "is this CIDR inside that one" function, so each end of the range is
    # re-masked with the subnet's prefix length: if both land on the subnet's own network address,
    # the range is inside it. A range outside - or one larger than the subnet - fails this
    # (rules.md B-1).
    #
    # Getting it wrong hands pods addresses that are not routable on the master interface's subnet,
    # and the symptom is a pod that starts with net1 and reaches nothing.
    condition = (
      cidrhost(var.subnet_cidr, 0) == cidrhost("${cidrhost(var.pod_range_cidr, 0)}/${split("/", var.subnet_cidr)[1]}", 0) &&
      cidrhost(var.subnet_cidr, 0) == cidrhost("${cidrhost(var.pod_range_cidr, -1)}/${split("/", var.subnet_cidr)[1]}", 0)
    )
    error_message = "pod_range_cidr must be a block inside subnet_cidr. Pass the network module's multus_pod_range_cidr output, which is carved from the same subnet this attachment's master interface sits in."
  }
}
variable "ipam_type" {
  type        = string
  description = "The IPAM plugin this attachment asks Multus to call. Taken from the module that installed it rather than written here (rules.md B-5)"

  validation {
    # A constant condition, because the key names in the configuration above are whereabouts
    # spelling. Switching plugin is a change to this module, not to this variable: host-local reads
    # "subnet", "rangeStart" and "rangeEnd" where whereabouts reads "range", "range_start" and
    # "range_end", and a plugin handed the wrong key names gets no range at all (rules.md B-1).
    condition     = var.ipam_type == "whereabouts"
    error_message = "ipam_type must be \"whereabouts\". The ipam block in this module is written with whereabouts key names; to use host-local or static, change those key names there as well - host-local spells them subnet, rangeStart and rangeEnd."
  }
}
variable "gateway" {
  type        = string
  default     = null
  description = "Gateway written into the attachment's IPAM configuration. Null - and null is right for ipvlan in l3 mode, which the _monolithic template also left out: the plugin installs routes itself and a gateway address would only be another thing to keep in step with the subnet. Set it for l2 mode, where the pod does need a next hop"

  validation {
    condition     = var.gateway == null || can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$", var.gateway))
    error_message = "gateway must be an IPv4 address, or null."
  }
}
