variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.)"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region such as ap-northeast-2, or null to fall back to the provider default chain."
  }
}
variable "cluster_name" {
  type        = string
  default     = "multus-eth-names-cluster"
  description = "Name of the EKS cluster"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,99}$", var.cluster_name))
    error_message = "cluster_name must start with a letter or digit and contain only letters, digits, hyphens and underscores (100 characters or fewer)."
  }
}
variable "kubernetes_version" {
  type        = string
  default     = "1.34"
  description = "Kubernetes version for the EKS cluster"

  validation {
    condition     = can(regex("^1\\.(3[0-9]|[4-9][0-9])$", var.kubernetes_version))
    error_message = "kubernetes_version must be a supported 1.XX version, e.g. 1.34."
  }
}
variable "kubectl_download_version" {
  type        = string
  default     = "1.34.11/2026-09-22"
  description = "Version path used to download kubectl onto the VS Code instance, in <version>/<release-date> form. Raised together with kubernetes_version: kubectl more than one minor version from the API server is outside the supported skew (rules.md H-1)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.34.11/2026-09-22."
  }
}
variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the EKS API server endpoint is reachable from the internet. True as the _monolithic template had it, and needed because the kubectl provider runs on the machine executing terraform apply rather than inside the VPC (rules.md E-2). Narrow public_access_cidrs rather than leaving the default open"

  validation {
    # Pinned in the direction this variant depends on, with the alternative named
    # (rules.md B-1/E-9).
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because Multus, its attachment and the demo workload are applied by the kubectl provider from the machine running terraform. To run with a private endpoint, apply them from the bastion through an SSM Association instead, as 041_eks_private_cluster does (rules.md E-9)."
  }
}
variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDR blocks allowed to reach the public API server endpoint. Set this to your own address in CIDR form: bootstrap_cluster_creator_admin_permissions means anyone who can reach this endpoint with a valid AWS credential for the creating principal has cluster-admin"

  validation {
    condition     = alltrue([for cidr in var.public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "public_access_cidrs must contain valid IPv4 CIDR blocks."
  }
}
variable "key_name" {
  type        = string
  default     = "multus-eth-names-key"
  description = "Name of the EC2 key pair created for the demo instance and attached to the worker nodes through the node group's launch template"

  validation {
    condition     = length(var.key_name) > 0
    error_message = "key_name must not be empty."
  }
}
variable "node_group_name" {
  type        = string
  default     = "al2023-nodegroup"
  description = "Name of the managed node group, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9_-]*)$", var.node_group_name))
    error_message = "node_group_name must start with a letter or digit and contain only letters, digits, hyphens and underscores."
  }
}
variable "node_group_instance_types" {
  type        = list(string)
  default     = ["t3.xlarge"]
  description = "Instance types for the managed node group, t3.xlarge as the _monolithic template had it. Unlike the multi_nic variant next door this does not need an instance type with several network cards - Multus works with ordinary additional ENIs, which every type supports - but it does need enough ENI slots for the primary interface plus the extra ones, and a t3.xlarge has three"

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "node_group_instance_types must contain at least one instance type."
  }
}
variable "node_group_labels" {
  type = map(string)
  default = {
    nodegroup = "al2023"
  }
  description = "Kubernetes labels on the nodes, as the _monolithic template set them. Worth keeping even though nothing here selects on them: the moment a cluster has one node group with the extra interfaces and one without, a pod asking for a Multus attachment has to be pinned to the right one - and a pod on the wrong node stays in ContainerCreating"

  validation {
    condition     = alltrue([for key in keys(var.node_group_labels) : length(key) > 0])
    error_message = "node_group_labels must not contain empty label keys."
  }
}
variable "node_group_desired_size" {
  type        = number
  default     = 1
  description = "Desired node count, one as the _monolithic template had it"

  validation {
    condition     = var.node_group_desired_size >= 1
    error_message = "node_group_desired_size must be at least 1."
  }
}
variable "node_group_min_size" {
  type        = number
  default     = 1
  description = "Minimum node count"

  validation {
    condition     = var.node_group_min_size >= 1
    error_message = "node_group_min_size must be at least 1."
  }
}
variable "node_group_max_size" {
  type        = number
  default     = 3
  description = "Maximum node count, three as the _monolithic template had it. Each node created also creates its own extra ENIs on boot, so scaling this group consumes addresses out of the Multus range"

  validation {
    condition     = var.node_group_max_size >= 1
    error_message = "node_group_max_size must be at least 1."
  }
  validation {
    condition     = var.node_group_max_size >= var.node_group_min_size
    error_message = "node_group_max_size must be greater than or equal to node_group_min_size."
  }
}
variable "multus_interface_count" {
  type        = number
  default     = 2
  description = "How many extra ENIs each node creates and attaches for Multus on boot, two as the _monolithic template had it. They are attached at device indexes 1 upward, which is what decides the names the kernel gives them - and the attachment below has to name one of those. More than the instance type's ENI limit minus one makes the node's bootstrap fail part way through, leaving a node that joins the cluster with fewer interfaces than the attachment expects"

  validation {
    condition     = var.multus_interface_count >= 1 && var.multus_interface_count <= 14
    error_message = "multus_interface_count must be between 1 and 14. The real ceiling is the instance type's ENI limit minus the primary interface - check with \"aws ec2 describe-instance-types --instance-types <type> --query 'InstanceTypes[].NetworkInfo.MaximumNetworkInterfaces'\"."
  }
}
variable "disable_predictable_interface_names" {
  type        = bool
  default     = true
  description = "Whether to turn off the kernel's predictable network interface naming on the nodes, by adding net.ifnames=0 and biosdevname=0 to the boot command line. True in this variant, which is the whole reason it exists: the extra ENIs then come up as eth1, eth2 rather than ens6, ens7, and the NetworkAttachmentDefinition names them accordingly. Worth knowing why anyone would: a lot of network appliance software and a lot of older CNI configuration assumes eth-style names, and predictable naming derives its names from the PCI slot the device happens to appear in - so the same appliance image on a different instance type finds a different interface. The cost is that the naming is now positional again, and an ENI attached at a different device index gets a different name"
}
variable "multus_interface_prefix" {
  type        = string
  default     = "eth"
  description = "Prefix the kernel gives the extra interfaces. \"ens\" with predictable naming on, \"eth\" with it off. Kept as a variable rather than derived from disable_predictable_interface_names because the mapping is the kernel's rather than this configuration's, and a node whose interfaces are named differently than assumed leaves pods stuck in ContainerCreating with nothing saying why"

  validation {
    condition     = contains(["ens", "eth"], var.multus_interface_prefix)
    error_message = "multus_interface_prefix must be ens (predictable naming) or eth (predictable naming disabled)."
  }
  validation {
    # The pair is what can be wrong, not either value alone (rules.md B-1).
    condition     = var.disable_predictable_interface_names ? var.multus_interface_prefix == "eth" : var.multus_interface_prefix == "ens"
    error_message = "multus_interface_prefix must be \"eth\" when disable_predictable_interface_names is true and \"ens\" when it is false. Getting the pair wrong produces nodes whose interfaces are named one way and an attachment that names them the other, and the only symptom is pods that never leave ContainerCreating."
  }
}
variable "multus_interface_start_index" {
  type        = number
  default     = 1
  description = "Number of the first extra interface. Six with predictable naming, because the EKS AL2023 AMI's primary interface is ens5 and the first ENI attached at device index 1 becomes ens6. One with predictable naming off, because the primary is then eth0"

  validation {
    condition     = var.multus_interface_start_index >= 0
    error_message = "multus_interface_start_index must be zero or greater."
  }
  validation {
    condition     = var.disable_predictable_interface_names ? var.multus_interface_start_index == 1 : var.multus_interface_start_index == 6
    error_message = "multus_interface_start_index must be 1 when disable_predictable_interface_names is true (the primary interface is then eth0) and 6 when it is false (the primary is ens5)."
  }
}
variable "multus_image_version" {
  type        = string
  default     = "v4.0.2-eksbuild.1_thick"
  description = "Multus image tag, from AWS's own EKS build rather than upstream's default branch. The _monolithic template applied the manifest from k8snetworkplumbingwg/multus-cni's master branch, so the version installed was whatever that branch held on the day the instance booted - for the component that sits in front of every pod's networking"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+-eksbuild\\.[0-9]+(_thick)?$", var.multus_image_version))
    error_message = "multus_image_version must look like v4.0.2-eksbuild.1_thick."
  }
}
variable "multus_image_registry_account" {
  type        = string
  default     = "602401143452"
  description = "AWS account that hosts the EKS container image registry. 602401143452 serves the commercial regions; China and GovCloud have their own, listed under \"Amazon container image registries\" in the EKS documentation. Combined with the current region so nodes pull from their own region rather than us-west-2, which the upstream manifest hardcodes"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.multus_image_registry_account))
    error_message = "multus_image_registry_account must be a 12-digit AWS account ID."
  }
}
variable "multus_pod_range_newbits" {
  type        = number
  default     = 1
  description = "How the Multus subnet is split. One bit means the upper half is the block host-local hands to pods and the lower half is left for the primary addresses of the ENIs the nodes attach there, which the VPC picks and this configuration cannot choose. The _monolithic template split the node's own private subnet this way instead, with two /26 reservations out of a /24; Multus has a subnet of its own here, so the split is no longer shared with the VPC CNI"

  validation {
    condition     = var.multus_pod_range_newbits >= 1 && var.multus_pod_range_newbits <= 8
    error_message = "multus_pod_range_newbits must be between 1 and 8."
  }
}
variable "multus_pod_range_index" {
  type        = number
  default     = 1
  description = "Which of those blocks the pods get, counting from zero. One with a single bit means the upper half, leaving the ENI addresses at the bottom of the Multus subnet"

  validation {
    condition     = var.multus_pod_range_index >= 0
    error_message = "multus_pod_range_index must be zero or greater."
  }
}
variable "workload_name" {
  type        = string
  default     = "multi-homed"
  description = "Name of the demo Deployment"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.workload_name))
    error_message = "workload_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "workload_namespace" {
  type        = string
  default     = "default"
  description = "Namespace the demo Deployment and the attachment live in, as the _monolithic template had it. One value for both, because a pod can only name an attachment in its own namespace unless the annotation carries the namespace too"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.workload_namespace))
    error_message = "workload_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the VS Code security group accepts traffic from 0.0.0.0/0 on the code-server port, as the _monolithic template had it. code-server has no authentication in front of it, so narrow this where possible and reach it through SSM Session Manager port forwarding instead"
}
variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "EC2 instance type for the VS Code EC2 instance"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must be a valid EC2 instance type, e.g. t3.medium."
  }
}
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the VS Code instance where the bootstrap drops its completion marker. The README association waits for that marker instead of trusting depends_on (rules.md D-5/H-2)"

  validation {
    condition     = var.marker_file_path == null || can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/', or null."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the README SSM association may take. It first waits for the instance bootstrap to finish, which includes downloading kubectl, eksctl and helm"

  validation {
    condition     = var.readme_timeout_seconds > 0
    error_message = "readme_timeout_seconds must be positive."
  }
}
variable "multus_ingress_source_security_groups" {
  type        = map(string)
  default     = {}
  description = "Security group IDs allowed inbound on the Multus network, keyed by a caller-chosen label. Empty by default: the group already allows traffic between its own members, which is what Multus pods on different nodes need, and anything beyond that is a hole in the separation the group exists to provide. A map rather than a list because such IDs are usually another module's output and unknown until apply (rules.md B-8)"

  validation {
    condition     = alltrue([for id in values(var.multus_ingress_source_security_groups) : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "multus_ingress_source_security_groups must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "multus_ingress_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "CIDR blocks allowed inbound on the Multus network. Empty by default, for the same reason as multus_ingress_source_security_groups"

  validation {
    condition     = alltrue([for cidr in var.multus_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "multus_ingress_cidr_blocks must contain valid IPv4 CIDR blocks."
  }
}
variable "whereabouts_reconciler_cron_expression" {
  type        = string
  default     = "*/15 * * * *"
  description = "How often whereabouts sweeps its allocation store for addresses whose pod no longer exists. Every fifteen minutes rather than the upstream default of once a day at 04:30: each attachment here hands out a /26, and a demo that recreates the same pods would report the range as exhausted long before a daily sweep ran"

  validation {
    condition     = length(split(" ", trimspace(var.whereabouts_reconciler_cron_expression))) == 5
    error_message = "whereabouts_reconciler_cron_expression must be a five-field cron expression (minute hour day-of-month month day-of-week)."
  }
}
