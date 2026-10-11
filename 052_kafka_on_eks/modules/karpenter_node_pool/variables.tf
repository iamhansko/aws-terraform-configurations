variable "name" {
  type        = string
  description = "Name of both the NodePool and the EC2NodeClass. One name for the pair, because the NodePool's nodeClassRef names the class and nothing else ever refers to either separately"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 subdomain."
  }
}

variable "node_iam_role_name" {
  type        = string
  description = "Name of the IAM role the pool's instances assume. Karpenter creates and manages the instance profile from this itself, which is why the name is enough"

  validation {
    condition     = length(var.node_iam_role_name) > 0
    error_message = "node_iam_role_name must not be empty."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnets Karpenter may launch this pool's nodes in"

  validation {
    condition     = length(var.subnet_ids) > 0 && alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "subnet_ids must contain at least one valid subnet ID (e.g. subnet-0123456789abcdef0)."
  }
}

variable "security_group_ids" {
  type        = list(string)
  description = "Security groups attached to this pool's nodes. The cluster security group has to be among them, or the nodes cannot reach the API server and the control plane cannot reach their kubelets (rules.md B-6)"

  validation {
    condition     = length(var.security_group_ids) > 0 && alltrue([for id in var.security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "security_group_ids must contain at least one valid security group ID (e.g. sg-0123456789abcdef0)."
  }
}

variable "instance_categories" {
  type        = list(string)
  default     = []
  description = "EC2 instance categories this pool may choose from, such as [\"c\", \"m\", \"r\"] - the letter before the generation number. Empty leaves the category unconstrained"

  validation {
    condition     = alltrue([for c in var.instance_categories : can(regex("^[a-z]+$", c))])
    error_message = "instance_categories entries must be lowercase letters, e.g. c, m or r."
  }
}

variable "instance_families" {
  type        = list(string)
  default     = []
  description = "EC2 instance families this pool may choose from, such as [\"m6g\"]. Empty leaves the family unconstrained"

  validation {
    condition     = alltrue([for f in var.instance_families : can(regex("^[a-z0-9-]+$", f))])
    error_message = "instance_families entries must look like m6g or c7gd."
  }
  validation {
    # A pool constrained by neither may launch any shape in the region, including the most expensive
    # ones - Karpenter picks by price, but the ceiling is cpu_limit alone (rules.md B-1).
    condition     = length(var.instance_families) > 0 || length(var.instance_categories) > 0
    error_message = "Set instance_categories or instance_families (or both). With neither, the pool may launch any instance type in the region."
  }
}

variable "instance_sizes" {
  type        = list(string)
  default     = []
  description = "Instance sizes within the categories or families, such as [\"2xlarge\", \"4xlarge\"]. Empty leaves the size unconstrained, which is what the blueprint's pools did: Karpenter then sizes the node to the pods waiting for it"

  validation {
    condition     = alltrue([for s in var.instance_sizes : can(regex("^[a-z0-9-]+$", s))])
    error_message = "instance_sizes entries must look like xlarge, 2xlarge or metal."
  }
}

variable "node_architectures" {
  type        = list(string)
  default     = ["amd64", "arm64"]
  description = "CPU architectures this pool may choose"

  validation {
    condition     = length(var.node_architectures) > 0 && length(setsubtract(var.node_architectures, ["amd64", "arm64"])) == 0
    error_message = "node_architectures entries must be amd64 or arm64, and at least one is required."
  }
}

variable "capacity_types" {
  type        = list(string)
  default     = ["spot", "on-demand"]
  description = "Purchase options Karpenter may choose from. Karpenter prefers spot when both are allowed"

  validation {
    condition     = length(var.capacity_types) > 0 && length(setsubtract(var.capacity_types, ["spot", "on-demand", "reserved"])) == 0
    error_message = "capacity_types entries must be spot, on-demand or reserved, and at least one is required."
  }
}

variable "additional_requirements" {
  type = list(object({
    key      = string
    operator = string
    values   = list(string)
  }))
  default     = []
  description = "Extra NodePool requirements appended to the ones this module writes, for narrowing a pool without editing it"

  validation {
    condition     = alltrue([for r in var.additional_requirements : contains(["In", "NotIn", "Exists", "DoesNotExist", "Gt", "Lt"], r.operator)])
    error_message = "additional_requirements operators must be one of: In, NotIn, Exists, DoesNotExist, Gt, Lt."
  }
}

variable "node_labels" {
  type        = map(string)
  description = "Labels every node in this pool carries. These are what a workload's nodeSelector or affinity matches, so a pool whose labels match nothing provisions nothing"

  validation {
    condition     = length(var.node_labels) > 0
    error_message = "node_labels must not be empty. With several pools in one cluster, a pool with no labels can only be selected by accident."
  }
}

variable "taints" {
  type = list(object({
    key    = string
    value  = string
    effect = string
  }))
  default     = []
  description = "Taints applied to this pool's nodes. Empty on both of the blueprint's pools"

  validation {
    condition     = alltrue([for t in var.taints : contains(["NoSchedule", "PreferNoSchedule", "NoExecute"], t.effect)])
    error_message = "taints effects must be one of: NoSchedule, PreferNoSchedule, NoExecute."
  }
}

variable "ami_alias" {
  type        = string
  default     = "bottlerocket@latest"
  description = "AMI family and version, as an EC2NodeClass alias. Bottlerocket, as the blueprint chose"

  validation {
    condition     = can(regex("^(al2|al2023|bottlerocket|windows2019|windows2022)@", var.ami_alias))
    error_message = "ami_alias must look like <family>@<version>, e.g. bottlerocket@latest or al2023@v20240605."
  }
}

variable "block_device_mappings" {
  type = list(object({
    device_name           = string
    volume_size           = string
    volume_type           = optional(string, "gp3")
    encrypted             = optional(bool, true)
    delete_on_termination = optional(bool, true)
  }))
  default = [
    { device_name = "/dev/xvda", volume_size = "100Gi" },
  ]
  description = <<-DESC
    EBS volumes attached to each node. One 100Gi gp3 volume at /dev/xvda by default, which is what the
    karpenter-resources chart wrote when the blueprint gave it no mappings of its own.

    Worth knowing on Bottlerocket: /dev/xvda is the OS volume and /dev/xvdb the data volume that holds
    container images, so this default enlarges the OS volume and leaves the data volume at the AMI's
    size. The pools here also set RAID0, which moves images onto the instance store on the types that
    have one - the c6gd-style "d" types - and leaves the rest on that default data volume.
  DESC

  validation {
    condition     = length(var.block_device_mappings) > 0
    error_message = "block_device_mappings must contain at least one volume."
  }
  validation {
    condition     = alltrue([for m in var.block_device_mappings : can(regex("^[0-9]+(Gi|Ti|G|T)$", m.volume_size))])
    error_message = "block_device_mappings volume_size must be a quantity such as 100Gi - Karpenter takes a Kubernetes quantity here, not a bare number of gigabytes."
  }
  validation {
    condition     = alltrue([for m in var.block_device_mappings : startswith(m.device_name, "/dev/")])
    error_message = "block_device_mappings device_name must be a device path such as /dev/xvda."
  }
}

variable "instance_store_policy" {
  type        = string
  default     = null
  description = "What Karpenter does with the instance's local NVMe disks. RAID0 stripes them and points containerd and the kubelet at the result. Null omits the field (rules.md B-4)"

  validation {
    condition     = var.instance_store_policy == null || var.instance_store_policy == "RAID0"
    error_message = "instance_store_policy must be RAID0 or null; RAID0 is the only value Karpenter defines."
  }
}

variable "detailed_monitoring" {
  type        = bool
  default     = true
  description = "Whether the instances publish one-minute CloudWatch metrics instead of five-minute. True, the karpenter-resources chart's default"
}

variable "metadata_hop_limit" {
  type        = number
  default     = 2
  description = "IMDS hop limit on the nodes. Two rather than one, so a process inside a container can still reach the metadata service"

  validation {
    condition     = var.metadata_hop_limit >= 1 && var.metadata_hop_limit <= 64
    error_message = "metadata_hop_limit must be between 1 and 64."
  }
}

variable "cpu_limit" {
  type        = number
  default     = 1000
  description = "Total vCPUs this pool may provision. A hard ceiling, so a workload that keeps asking for capacity cannot scale the account's EC2 spend without bound"

  validation {
    condition     = var.cpu_limit > 0
    error_message = "cpu_limit must be greater than zero."
  }
}

variable "memory_limit" {
  type        = string
  default     = "1000Gi"
  description = "Total memory this pool may provision, as a Kubernetes quantity. 1000Gi, the karpenter-resources chart's default"

  validation {
    condition     = can(regex("^[0-9]+(Ki|Mi|Gi|Ti)$", var.memory_limit))
    error_message = "memory_limit must be a Kubernetes quantity such as 1000Gi."
  }
}

variable "consolidation_policy" {
  type        = string
  default     = "WhenEmpty"
  description = "When Karpenter may remove a node. WhenEmpty only removes nodes with no workload pods; WhenEmptyOrUnderutilized also moves pods to pack them onto fewer nodes"

  validation {
    condition     = contains(["WhenEmpty", "WhenEmptyOrUnderutilized"], var.consolidation_policy)
    error_message = "consolidation_policy must be either WhenEmpty or WhenEmptyOrUnderutilized."
  }
}

variable "consolidate_after" {
  type        = string
  default     = "30s"
  description = "How long a node has to stay a consolidation candidate before Karpenter acts, 30s as the karpenter-resources chart defaulted it"

  validation {
    condition     = can(regex("^[0-9]+(s|m|h)$", var.consolidate_after))
    error_message = "consolidate_after must be a duration such as 30s, 5m or 1h."
  }
}

variable "node_expire_after" {
  type        = string
  default     = "720h"
  description = "Maximum node lifetime, after which Karpenter replaces the node. Thirty days, the chart's default"

  validation {
    condition     = var.node_expire_after == "Never" || can(regex("^[0-9]+(s|m|h)$", var.node_expire_after))
    error_message = "node_expire_after must be a duration such as 720h, or the string Never."
  }
}

variable "termination_grace_period" {
  type        = string
  default     = "48h"
  description = "Longest Karpenter waits for a node's pods to leave before terminating it anyway, 48h as the chart defaulted it. This is what bounds a drain blocked by a PodDisruptionBudget - which Kafka brokers carry"

  validation {
    condition     = can(regex("^[0-9]+(s|m|h)$", var.termination_grace_period))
    error_message = "termination_grace_period must be a duration such as 48h."
  }
}

variable "disruption_budgets" {
  type        = list(string)
  default     = ["10%"]
  description = "How much of the pool Karpenter may disrupt at once, as node counts or percentages"

  validation {
    condition     = length(var.disruption_budgets) > 0
    error_message = "disruption_budgets must contain at least one budget."
  }
  validation {
    condition     = alltrue([for b in var.disruption_budgets : can(regex("^[0-9]+%?$", b))])
    error_message = "disruption_budgets entries must be a node count or a percentage, e.g. 2 or 10%."
  }
}

variable "weight" {
  type        = number
  default     = 10
  description = "Priority of this pool when more than one could take a pod, 10 as the chart set it on every pool. Equal weights leave the choice to Karpenter"

  validation {
    condition     = var.weight >= 1 && var.weight <= 100
    error_message = "weight must be between 1 and 100."
  }
}

variable "node_tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags on the EC2 instances this pool launches, merged with the Name tag the module sets from var.name"

  validation {
    condition     = alltrue([for key in keys(var.node_tags) : length(key) > 0 && !startswith(lower(key), "aws:")])
    error_message = "node_tags keys must be non-empty and must not use the reserved \"aws:\" prefix."
  }
}
