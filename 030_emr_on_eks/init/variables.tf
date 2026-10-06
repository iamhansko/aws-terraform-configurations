variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. Null falls through to the provider chain (AWS_REGION / AWS_DEFAULT_REGION)"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region name (e.g. ap-northeast-2), or null."
  }
}

variable "project_name" {
  type        = string
  default     = "emr-on-eks-init"
  description = "Prefix for resource names that have to be unique inside the account, and the title of the README written onto the bastion"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 3-32 lowercase letters, digits or hyphens and must not start or end with a hyphen."
  }
}

# --- Network ---

variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block of the VPC"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block."
  }
}

# --- EKS cluster ---

variable "cluster_name" {
  type        = string
  default     = "eks-cluster"
  description = "Name of the EKS cluster. Karpenter is given this as settings.clusterName, which is how its controller finds the cluster it provisions for"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,99}$", var.cluster_name))
    error_message = "cluster_name must start with a letter or digit and contain only letters, digits, hyphens and underscores."
  }
}

variable "kubernetes_version" {
  type        = string
  default     = "1.34"
  description = "EKS cluster Kubernetes version. Keep kubectl_download_version within one minor of this"

  validation {
    condition     = can(regex("^1\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must look like 1.XX; the cluster module holds the list of versions this project is verified against."
  }
}

variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the cluster's API server has a public endpoint. True here, and pinned true, because every Kubernetes object and Helm release in this project is applied by providers running on the machine executing terraform"

  validation {
    # Not a free choice: this root declares kubectl and helm providers, and those run
    # wherever terraform runs. With a private-only endpoint they cannot connect, plan
    # still passes, and the failure appears mid-apply as a dial timeout that looks
    # exactly like the destroy-ordering problem rules.md D-4 describes (rules.md E-9).
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because its manifests and Helm releases are applied by providers running on the machine executing terraform. To run with a private endpoint, drop those providers and apply everything from the bastion through SSM Associations instead, as 041_eks_private_cluster does."
  }
}

variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDRs allowed to reach the public API server endpoint. Narrow this for anything longer lived than a demo"

  validation {
    condition     = alltrue([for cidr in var.public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "public_access_cidrs must contain valid IPv4 CIDR blocks."
  }
}

variable "coredns_replica_count" {
  type        = number
  default     = 2
  description = "Number of CoreDNS replicas"

  validation {
    condition     = var.coredns_replica_count >= 1
    error_message = "coredns_replica_count must be at least 1."
  }
}

# --- Core managed node group ---

variable "core_node_group_name" {
  type        = string
  default     = "core"
  description = "Name of the managed node group that runs the cluster's own controllers, as the _monolithic template named it. Karpenter itself runs here: a controller that provisions nodes cannot depend on the nodes it provisions"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,62}$", var.core_node_group_name))
    error_message = "core_node_group_name must start with a letter or digit and contain only letters, digits, hyphens and underscores."
  }
}

variable "core_node_instance_types" {
  type        = list(string)
  default     = ["t3.medium"]
  description = "Instance types for the core node group"

  validation {
    condition     = length(var.core_node_instance_types) > 0
    error_message = "core_node_instance_types must contain at least one instance type."
  }
}

variable "core_node_labels" {
  type = map(string)
  default = {
    "node-type" = "core"
  }
  description = "Labels on the core nodes, as the _monolithic template set them"

  validation {
    condition     = alltrue([for key in keys(var.core_node_labels) : length(key) > 0])
    error_message = "core_node_labels keys must not be empty."
  }
}

variable "core_node_desired_size" {
  type        = number
  default     = 2
  description = "Desired core node count"

  validation {
    condition     = var.core_node_desired_size >= 1
    error_message = "core_node_desired_size must be at least 1."
  }
}

variable "core_node_min_size" {
  type        = number
  default     = 2
  description = "Minimum core node count"

  validation {
    condition     = var.core_node_min_size >= 1
    error_message = "core_node_min_size must be at least 1."
  }
}

variable "core_node_max_size" {
  type        = number
  default     = 4
  description = "Maximum core node count"

  validation {
    condition     = var.core_node_max_size >= 1
    error_message = "core_node_max_size must be at least 1."
  }
}

# --- Karpenter ---

variable "karpenter_chart_version" {
  type        = string
  default     = "1.8.3"
  description = "Pinned Karpenter chart version. The _monolithic template pinned 1.6.0 inside a shell script it wrote on the bastion"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.karpenter_chart_version))
    error_message = "karpenter_chart_version must be a three-part semantic version."
  }
}

variable "karpenter_node_pools" {
  type = map(object({
    instance_families = list(string)
    instance_sizes    = list(string)
    node_labels       = map(string)
    capacity_types    = optional(list(string), ["spot", "on-demand"])
    ami_alias         = optional(string, "bottlerocket@latest")
    block_device_mappings = list(object({
      device_name           = string
      volume_size           = string
      volume_type           = optional(string, "gp3")
      encrypted             = optional(bool, true)
      delete_on_termination = optional(bool, true)
    }))
    instance_store_policy = optional(string)
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
    cpu_limit    = optional(number, 1000)
    memory_limit = optional(string, "1000Gi")
  }))
  default = {
    x86-cpu-karpenter = {
      instance_families = ["m5"]
      instance_sizes    = ["xlarge", "2xlarge", "4xlarge", "8xlarge"]
      node_labels       = { nodegroup = "x86-cpu", type = "karpenter" }
      block_device_mappings = [
        { device_name = "/dev/xvda", volume_size = "100Gi" },
        { device_name = "/dev/xvdb", volume_size = "300Gi" },
      ]
      # No instance store policy: the m5 family has no local NVMe disks, and Karpenter
      # rejects the field on a shape that has none. The _monolithic template's x86 node
      # class left it out too - the only one of its three that did.
    }
    g5-gpu-karpenter = {
      instance_families = ["g5"]
      instance_sizes    = ["2xlarge", "4xlarge", "8xlarge", "12xlarge", "16xlarge", "24xlarge", "48xlarge"]
      node_labels       = { nodegroup = "g5-gpu", type = "karpenter" }
      block_device_mappings = [
        { device_name = "/dev/xvda", volume_size = "50Gi" },
        { device_name = "/dev/xvdb", volume_size = "300Gi" },
      ]
      instance_store_policy = "RAID0"
      taints                = [{ key = "nvidia.com/gpu", value = "Exists", effect = "NoSchedule" }]
    }
    g6-gpu-karpenter = {
      instance_families = ["g6"]
      instance_sizes    = ["2xlarge", "4xlarge", "8xlarge", "12xlarge", "16xlarge", "24xlarge", "48xlarge"]
      node_labels       = { nodegroup = "g6-gpu", type = "karpenter" }
      # One volume, as the _monolithic template's g6 class had it - and worth noticing
      # next to g5's two: the g6 nodes get a 50Gi root and nothing else, so container
      # images share the OS volume unless the instance store is used, which it is.
      block_device_mappings = [
        { device_name = "/dev/xvda", volume_size = "50Gi" },
      ]
      instance_store_policy = "RAID0"
      taints                = [{ key = "nvidia.com/gpu", value = "Exists", effect = "NoSchedule" }]
    }
  }
  description = <<-DESC
    The Karpenter pools, keyed by name. Three, as the _monolithic template defined them: a CPU pool for
    ordinary workloads, and two GPU pools for anything that asks for a GPU.

    A map rather than three module blocks, because the pools differ only in their values. The keys are
    literals from this configuration, so they are safe as for_each keys - nothing here comes from another
    module's output (rules.md B-7, and the reason B-8 does not apply).
  DESC

  validation {
    condition     = length(var.karpenter_node_pools) > 0
    error_message = "karpenter_node_pools must define at least one pool."
  }

  validation {
    condition     = alltrue([for name in keys(var.karpenter_node_pools) : can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", name))])
    error_message = "karpenter_node_pools keys become Kubernetes object names, so each must be a valid lowercase RFC 1123 subdomain."
  }

  validation {
    condition     = alltrue([for pool in values(var.karpenter_node_pools) : length(pool.node_labels) > 0])
    error_message = "every pool needs node_labels. With three pools in one cluster, a pool with no labels can only be selected by accident, and a workload that selects nothing lands on whichever pool fits first."
  }
}

# --- NVIDIA device plugin ---

variable "nvidia_device_plugin_chart_version" {
  type        = string
  default     = "0.17.3"
  description = "Pinned nvidia-device-plugin chart version. The _monolithic template applied the plugin's static DaemonSet manifest from a GitHub raw URL at v0.17.1 instead, so it was neither versioned by Helm nor upgradeable"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.nvidia_device_plugin_chart_version))
    error_message = "nvidia_device_plugin_chart_version must be a three-part semantic version."
  }
}

# --- Bastion and CloudFront ---

variable "bastion_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type of the code-server bastion, as the _monolithic template sized it"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.bastion_instance_type))
    error_message = "bastion_instance_type must look like an EC2 instance type (e.g. t3.medium)."
  }
}

variable "allow_bastion_inbound_from_anywhere" {
  type        = bool
  default     = false
  description = "Whether the bastion's security group accepts code-server traffic from 0.0.0.0/0. False, as the _monolithic template had it: the only inbound rule is the CloudFront origin-facing prefix list, so the IDE is reached through the distribution rather than directly"
}

variable "cloudfront_prefix_list_name" {
  type        = string
  default     = "com.amazonaws.global.cloudfront.origin-facing"
  description = "Managed prefix list holding the addresses CloudFront makes origin requests from, looked up by name. The _monolithic template carried a mapping of hardcoded prefix list IDs keyed by region, so a region missing from the table failed with an error about a map key"

  validation {
    condition     = length(var.cloudfront_prefix_list_name) > 0
    error_message = "cloudfront_prefix_list_name must not be empty."
  }
}

variable "cloudfront_origin_request_policy_name" {
  type        = string
  default     = "Managed-AllViewer"
  description = "Managed origin request policy, by name. The distribution needs every header forwarded, because code-server upgrades to a WebSocket"

  validation {
    condition     = length(var.cloudfront_origin_request_policy_name) > 0
    error_message = "cloudfront_origin_request_policy_name must not be empty."
  }
}

variable "cloudfront_price_class" {
  type        = string
  default     = "PriceClass_200"
  description = "CloudFront price class"

  validation {
    condition     = contains(["PriceClass_All", "PriceClass_200", "PriceClass_100"], var.cloudfront_price_class)
    error_message = "cloudfront_price_class must be one of: PriceClass_All, PriceClass_200, PriceClass_100."
  }
}

variable "kubectl_download_version" {
  type        = string
  default     = "1.34.11/2026-09-22"
  description = "kubectl build downloaded onto the bastion, as <version>/<release-date>. Kept within one minor of kubernetes_version; the _monolithic template pinned a 1.33 build"

  validation {
    condition     = can(regex("^1\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.34.11/2026-09-22."
  }
}

variable "code_server_version" {
  type        = string
  default     = "4.108.2"
  description = "code-server release installed on the bastion. The _monolithic template pinned 4.102.3"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a three-part semantic version."
  }
}

variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the bastion where each bootstrap stage drops its completion marker (rules.md D-5)"

  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/'."
  }
}

variable "readme_timeout_seconds" {
  type        = number
  default     = 1800
  description = "How long the README association waits for success. It has to cover the whole instance bootstrap, since the command blocks on the userdata marker"

  validation {
    condition     = var.readme_timeout_seconds >= 300
    error_message = "readme_timeout_seconds must be at least 300."
  }
}
