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
  description = "Name of the IAM role the pool's instances assume. Karpenter creates and manages the instance profile from this itself, which is why the name is enough - the _monolithic template also created a profile explicitly and pointed the node class at it, giving the same profile two owners"

  validation {
    condition     = length(var.node_iam_role_name) > 0
    error_message = "node_iam_role_name must not be empty."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnets Karpenter may launch this pool's nodes in. Private subnets: the nodes pull large container images through the NAT gateway and nothing outside the VPC has a reason to reach them"

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

variable "instance_families" {
  type        = list(string)
  description = "EC2 instance families this pool may choose from, such as [\"g5\"] or [\"m5\"]. The family is what makes a pool a GPU pool or a CPU pool"

  validation {
    condition     = length(var.instance_families) > 0
    error_message = "instance_families must name at least one family; a pool with no family requirement may choose anything in the region."
  }
}

variable "instance_sizes" {
  type        = list(string)
  description = "Instance sizes within the families, such as [\"2xlarge\", \"4xlarge\"]. Small sizes are left out deliberately: their per-node pod and ENI limits make them a poor fit, and on a GPU family they do not exist"

  validation {
    condition     = length(var.instance_sizes) > 0
    error_message = "instance_sizes must name at least one size."
  }
}

variable "node_architectures" {
  type        = list(string)
  default     = ["amd64"]
  description = "CPU architectures this pool may choose. amd64 only, because the container images this project runs are built for it - an arm64 node would be provisioned successfully and then fail every image pull"

  validation {
    condition     = length(setsubtract(var.node_architectures, ["amd64", "arm64"])) == 0
    error_message = "node_architectures entries must be amd64 or arm64."
  }
}

variable "capacity_types" {
  type        = list(string)
  default     = ["spot", "on-demand"]
  description = "Purchase options Karpenter may choose from, in no particular order - Karpenter prefers spot when both are allowed. Both, as the _monolithic template had it: a GPU instance on spot is a fraction of the price, and the demo tolerates an interruption"

  validation {
    condition     = length(var.capacity_types) > 0 && length(setsubtract(var.capacity_types, ["spot", "on-demand"])) == 0
    error_message = "capacity_types entries must be spot or on-demand, and at least one is required."
  }
}

variable "additional_requirements" {
  type = list(object({
    key      = string
    operator = string
    values   = list(string)
  }))
  default     = []
  description = "Extra NodePool requirements appended to the ones this module always writes, for narrowing a pool without editing it"

  validation {
    condition     = alltrue([for r in var.additional_requirements : contains(["In", "NotIn", "Exists", "DoesNotExist", "Gt", "Lt"], r.operator)])
    error_message = "additional_requirements operators must be one of: In, NotIn, Exists, DoesNotExist, Gt, Lt."
  }
}

variable "node_labels" {
  type        = map(string)
  description = "Labels every node in this pool carries. These are what a workload's nodeSelector matches, so a pool whose labels do not match anything provisions nothing - and a workload whose selector matches two pools lands on either"

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
  description = "Taints applied to this pool's nodes. Empty on a CPU pool; on a GPU pool the nvidia.com/gpu taint is what stops unrelated pods from occupying an expensive instance, and the workload's toleration is what lets the right ones through (rules.md B-4)"

  validation {
    condition     = alltrue([for t in var.taints : contains(["NoSchedule", "PreferNoSchedule", "NoExecute"], t.effect)])
    error_message = "taints effects must be one of: NoSchedule, PreferNoSchedule, NoExecute."
  }
}

variable "ami_alias" {
  type        = string
  default     = "bottlerocket@latest"
  description = "AMI family and version, as an EC2NodeClass alias. Bottlerocket, as the _monolithic template chose: a container-only host with a read-only root filesystem, and its GPU variant ships the NVIDIA driver so no driver install step is needed"

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
  description = <<-DESC
    EBS volumes attached to each node.

    Bottlerocket needs two, and which one is which matters: /dev/xvda is the OS volume and
    stays small, while /dev/xvdb is the data volume that holds container images and writable
    layers. Sizing xvda instead of xvdb is a common way to end up with a node that cannot
    pull a multi-gigabyte image while reporting plenty of free disk.
  DESC

  validation {
    condition     = length(var.block_device_mappings) > 0
    error_message = "block_device_mappings must contain at least one volume."
  }
  validation {
    condition     = alltrue([for m in var.block_device_mappings : can(regex("^[0-9]+(Gi|Ti|G|T)$", m.volume_size))])
    error_message = "block_device_mappings volume_size must be a quantity such as 50Gi - Karpenter takes a Kubernetes quantity here, not a bare number of gigabytes."
  }
  validation {
    condition     = alltrue([for m in var.block_device_mappings : startswith(m.device_name, "/dev/")])
    error_message = "block_device_mappings device_name must be a device path such as /dev/xvda."
  }
}

variable "instance_store_policy" {
  type        = string
  default     = null
  description = "What Karpenter does with the instance's local NVMe disks. RAID0 stripes them and points containerd at the result, which keeps large model images off the EBS root volume. Null omits the field, which is the only correct value for a family that has no instance store (rules.md B-4)"

  validation {
    condition     = var.instance_store_policy == null || var.instance_store_policy == "RAID0"
    error_message = "instance_store_policy must be RAID0 or null; RAID0 is the only value Karpenter defines."
  }
}

variable "detailed_monitoring" {
  type        = bool
  default     = true
  description = "Whether the instances publish one-minute CloudWatch metrics instead of five-minute. True, as the _monolithic template set it: a GPU node that comes and goes within five minutes is invisible at the coarser interval"
}

variable "metadata_hop_limit" {
  type        = number
  default     = 2
  description = "IMDS hop limit on the nodes. Two rather than one, so a process inside a container can still reach the metadata service - the default of one stops at the host network namespace"

  validation {
    condition     = var.metadata_hop_limit >= 1 && var.metadata_hop_limit <= 64
    error_message = "metadata_hop_limit must be between 1 and 64."
  }
}

variable "cpu_limit" {
  type        = number
  default     = 1000
  description = "Total vCPUs this pool may provision. A hard ceiling, so a workload that keeps asking for more replicas cannot scale the account's EC2 spend without bound"

  validation {
    condition     = var.cpu_limit > 0
    error_message = "cpu_limit must be greater than zero."
  }
}

variable "memory_limit" {
  type        = string
  default     = "1000Gi"
  description = "Total memory this pool may provision, as a Kubernetes quantity"

  validation {
    condition     = can(regex("^[0-9]+(Ki|Mi|Gi|Ti)$", var.memory_limit))
    error_message = "memory_limit must be a Kubernetes quantity such as 1000Gi."
  }
}

variable "consolidation_policy" {
  type        = string
  default     = "WhenEmpty"
  description = "When Karpenter may remove a node. WhenEmpty, as the _monolithic template had it: only a node with no workload pods is a candidate. WhenEmptyOrUnderutilized is more aggressive and will move a running Ray worker, which restarts the model load"

  validation {
    condition     = contains(["WhenEmpty", "WhenEmptyOrUnderutilized"], var.consolidation_policy)
    error_message = "consolidation_policy must be either WhenEmpty or WhenEmptyOrUnderutilized."
  }
}

variable "consolidate_after" {
  type        = string
  default     = "300s"
  description = "How long a node has to stay a consolidation candidate before Karpenter acts. Five minutes, so a brief gap between requests does not cost a GPU node and the several minutes of model loading that replacing it takes"

  validation {
    condition     = can(regex("^[0-9]+(s|m|h)$", var.consolidate_after))
    error_message = "consolidate_after must be a duration such as 300s, 5m or 1h."
  }
}

variable "node_expire_after" {
  type        = string
  default     = "720h"
  description = "Maximum node lifetime, after which Karpenter replaces it. Thirty days, which is what keeps nodes from drifting arbitrarily far from the current AMI"

  validation {
    condition     = var.node_expire_after == "Never" || can(regex("^[0-9]+(s|m|h)$", var.node_expire_after))
    error_message = "node_expire_after must be a duration such as 720h, or the string Never."
  }
}

variable "disruption_budgets" {
  type        = list(string)
  default     = ["10%"]
  description = "How much of the pool Karpenter may disrupt at once, as node counts or percentages. Ten percent, as the _monolithic template had it"

  validation {
    condition     = length(var.disruption_budgets) > 0
    error_message = "disruption_budgets must contain at least one budget."
  }
  validation {
    condition     = alltrue([for b in var.disruption_budgets : can(regex("^[0-9]+%?$", b))])
    error_message = "disruption_budgets entries must be a node count or a percentage, e.g. 2 or 10%."
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
