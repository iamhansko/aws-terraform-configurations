variable "node_role_name" {
  type        = string
  description = "Name of the IAM role Karpenter's nodes assume. Karpenter derives the instance profile from it, so this is a name rather than an ARN. Injected from the controller module, which owns the role, so this module never looks it up (rules.md B-6)"

  validation {
    condition     = length(var.node_role_name) > 0
    error_message = "node_role_name must not be empty."
  }
}
variable "node_class_name" {
  type        = string
  default     = "default"
  description = "Name of the EC2NodeClass describing how Karpenter builds instances"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.node_class_name))
    error_message = "node_class_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "node_pool_name" {
  type        = string
  default     = "default"
  description = "Name of the NodePool describing what Karpenter is allowed to provision"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.node_pool_name))
    error_message = "node_pool_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "ami_alias" {
  type        = string
  default     = "al2023@latest"
  description = "EC2NodeClass amiSelectorTerms alias, e.g. al2023@latest or bottlerocket@latest. Replaces the amiFamily field Karpenter used before v1"

  validation {
    condition     = can(regex("^(al2023|al2|bottlerocket|windows2019|windows2022)@[a-zA-Z0-9.-]+$", var.ami_alias))
    error_message = "ami_alias must look like al2023@latest or bottlerocket@v1.19.0."
  }
}
variable "subnet_selector_tags" {
  type        = map(string)
  description = "Tags that identify the subnets Karpenter launches nodes into. Passed in rather than discovered, so this module never has to know which network module created them (rules.md B-6)"

  validation {
    condition     = length(var.subnet_selector_tags) > 0
    error_message = "subnet_selector_tags must contain at least one tag, otherwise the selector matches every subnet in the VPC."
  }
}
variable "security_group_selector_tags" {
  type        = map(string)
  description = "Tags that identify the security groups attached to Karpenter-provisioned nodes. EKS tags the cluster security group with aws:eks:cluster-name, which is the usual choice here"

  validation {
    condition     = length(var.security_group_selector_tags) > 0
    error_message = "security_group_selector_tags must contain at least one tag, otherwise the selector matches every security group in the VPC."
  }
}
variable "node_architectures" {
  type        = list(string)
  default     = ["amd64"]
  description = "CPU architectures Karpenter may provision. Must match the architecture implied by ami_alias"

  validation {
    condition     = length(var.node_architectures) > 0 && alltrue([for a in var.node_architectures : contains(["amd64", "arm64"], a)])
    error_message = "node_architectures must be a non-empty subset of: amd64, arm64."
  }
}
variable "capacity_types" {
  type        = list(string)
  default     = ["on-demand"]
  description = "Capacity types Karpenter may provision. Adding spot lets it pick the cheaper option, but then interruption_queue_name should be set so nodes are drained before reclamation"

  validation {
    condition     = length(var.capacity_types) > 0 && alltrue([for c in var.capacity_types : contains(["on-demand", "spot", "reserved"], c)])
    error_message = "capacity_types must be a non-empty subset of: on-demand, spot, reserved."
  }
}
variable "instance_categories" {
  type        = list(string)
  default     = ["c", "m", "r", "t"]
  description = "EC2 instance categories Karpenter may pick from. Keeping this broad is the point of Karpenter: it chooses the cheapest shape that fits the pending pods"

  validation {
    condition     = length(var.instance_categories) > 0
    error_message = "instance_categories must contain at least one category."
  }
}
variable "minimum_instance_generation" {
  type        = number
  default     = 2
  description = "Instance generations at or below this are excluded, since the oldest families have low per-node pod and ENI limits"

  validation {
    condition     = var.minimum_instance_generation >= 1
    error_message = "minimum_instance_generation must be at least 1."
  }
}
variable "node_labels" {
  type        = map(string)
  default     = {}
  description = "Labels applied to every node this NodePool provisions (NodePool.spec.template.metadata.labels). A workload pins itself to Karpenter-provisioned capacity by matching these in a nodeSelector, and the map is re-exposed as an output so that selector references one source of truth (rules.md B-5). When empty the labels block is omitted entirely"

  validation {
    condition     = alltrue([for key in keys(var.node_labels) : can(regex("^([a-z0-9]([-a-z0-9.]*[a-z0-9])?/)?[a-zA-Z0-9]([-a-zA-Z0-9_.]*[a-zA-Z0-9])?$", key))])
    error_message = "node_labels keys must be valid Kubernetes label keys, optionally prefixed with a DNS subdomain (e.g. node-auto-scaling or example.com/pool)."
  }
}
variable "instance_types" {
  type        = list(string)
  default     = []
  description = "Exact EC2 instance types Karpenter may provision (node.kubernetes.io/instance-type). Empty by default, because letting Karpenter pick the cheapest shape that fits the pending pods is the point of it. Pinning one small type instead makes a scale-up demo legible: a pod requesting 1 vCPU no longer fits several to a node, so each replica forces another node"

  validation {
    condition     = alltrue([for type in var.instance_types : can(regex("^[a-z0-9]+\\.[a-z0-9]+$", type))])
    error_message = "instance_types must contain valid EC2 instance types (e.g. t3.small)."
  }
}
variable "additional_requirements" {
  type = list(object({
    key      = string
    operator = string
    values   = list(string)
  }))
  default     = []
  description = "Extra NodePool requirements appended to the built-in set, for constraints this module does not expose as named variables (e.g. karpenter.k8s.aws/instance-size)"

  validation {
    condition = alltrue([for req in var.additional_requirements : length(req.key) > 0 && contains([
      "In", "NotIn", "Exists", "DoesNotExist", "Gt", "Lt"
    ], req.operator)])
    error_message = "additional_requirements entries must each have a non-empty key and an operator of: In, NotIn, Exists, DoesNotExist, Gt, Lt."
  }
}
variable "cpu_limit" {
  type        = number
  default     = 1000
  description = "Maximum total vCPU this NodePool may provision, a hard ceiling on runaway scale-up"

  validation {
    condition     = var.cpu_limit > 0
    error_message = "cpu_limit must be greater than zero."
  }
}
variable "memory_limit" {
  type        = string
  default     = "1000Gi"
  description = "Maximum total memory this NodePool may provision"

  validation {
    condition     = can(regex("^[0-9]+(Ei|Pi|Ti|Gi|Mi|Ki)$", var.memory_limit))
    error_message = "memory_limit must be a Kubernetes binary quantity (e.g. 1000Gi)."
  }
}
variable "consolidation_policy" {
  type        = string
  default     = "WhenEmptyOrUnderutilized"
  description = "When Karpenter may replace or remove nodes. WhenEmptyOrUnderutilized also repacks partly used nodes onto cheaper shapes; WhenEmpty only removes nodes with no workload pods left"

  validation {
    condition     = contains(["WhenEmpty", "WhenEmptyOrUnderutilized"], var.consolidation_policy)
    error_message = "consolidation_policy must be either WhenEmpty or WhenEmptyOrUnderutilized."
  }
}
variable "consolidate_after" {
  type        = string
  default     = "1m"
  description = "How long a node must stay consolidatable before Karpenter acts, damping churn from short-lived pods"

  validation {
    condition     = can(regex("^[0-9]+(s|m|h)$", var.consolidate_after))
    error_message = "consolidate_after must be a duration such as 30s, 1m or 1h."
  }
}
variable "node_expire_after" {
  type        = string
  default     = "720h"
  description = "Maximum node lifetime before Karpenter recycles it, which is how nodes pick up new AMI releases"

  validation {
    condition     = var.node_expire_after == "Never" || can(regex("^[0-9]+(s|m|h)$", var.node_expire_after))
    error_message = "node_expire_after must be a duration such as 720h, or the literal Never."
  }
}
variable "root_volume_device_name" {
  type        = string
  default     = "/dev/xvda"
  description = "Root block device name for provisioned nodes. AL2023 uses /dev/xvda; Bottlerocket uses /dev/xvdb for its data volume"

  validation {
    condition     = can(regex("^/dev/", var.root_volume_device_name))
    error_message = "root_volume_device_name must be a device path starting with /dev/."
  }
}
variable "root_volume_size" {
  type        = string
  default     = "50Gi"
  description = "Root EBS volume size for provisioned nodes"

  validation {
    condition     = can(regex("^[0-9]+(Gi|Ti)$", var.root_volume_size))
    error_message = "root_volume_size must be a binary quantity such as 50Gi."
  }
}
variable "node_tags" {
  type        = map(string)
  default     = {}
  description = "Extra AWS tags applied to the instances, volumes and network interfaces Karpenter creates"

  validation {
    condition     = alltrue([for key in keys(var.node_tags) : length(key) > 0])
    error_message = "node_tags must not contain empty AWS tag keys."
  }
}
