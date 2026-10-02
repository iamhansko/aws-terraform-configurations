variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.)"
}
variable "prefix" {
  type        = string
  default     = "nth-karpenter"
  description = "Prefix for the network resources' Name tags (\"nth-karpenter\" produces nth-karpenter-vpc, nth-karpenter-igw, nth-karpenter-public-a, ...)"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.prefix))
    error_message = "prefix must be lowercase alphanumeric, optionally with hyphens."
  }
}
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
}
variable "cluster_name" {
  type        = string
  default     = "nth-karpenter-eks-cluster"
  description = "Name of the EKS cluster. Also the value of the karpenter.sh/discovery subnet tag and of the aws:eks:cluster-name security group tag the EC2NodeClass selectors match on"

  validation {
    condition     = can(regex("^[0-9A-Za-z][A-Za-z0-9\\-_]{0,99}$", var.cluster_name))
    error_message = "cluster_name must start with a letter or digit and contain only letters, digits, hyphens and underscores (100 characters or fewer)."
  }
}
variable "kubernetes_version" {
  type        = string
  default     = "1.33"
  description = "EKS cluster Kubernetes version (1.XX)"

  validation {
    condition     = contains(["1.31", "1.32", "1.33"], var.kubernetes_version)
    error_message = "kubernetes_version must be one of: 1.31, 1.32, 1.33."
  }
}
variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the EKS cluster API server endpoint is reachable from the public internet. Required here, because the helm and kubectl providers that install the handler and the demo workload run from the machine executing terraform apply rather than from inside the VPC (rules.md E-1/E-2). Narrow public_access_cidrs rather than turning this off"

  validation {
    # Constant condition, because the constraint really is "only this value in this variant"
    # (rules.md B-1). Turning it off passes plan and fails partway through apply with a
    # connection timeout that reads like a dependency ordering problem (rules.md E-9).
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because its Kubernetes objects are applied by the helm and kubectl providers from the machine running terraform. To run with a private endpoint, apply them from the bastion through SSM Associations instead, as 041_eks_private_cluster does (rules.md E-9)."
  }
}
variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDR blocks allowed to reach the EKS API server's public endpoint. Set this to your own address in CIDR form (e.g. [\"203.0.113.4/32\"]) instead of leaving the default: bootstrap_cluster_creator_admin_permissions grants anyone who can reach this endpoint with the creating AWS identity full cluster admin"

  validation {
    condition     = alltrue([for cidr in var.public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "public_access_cidrs must contain valid IPv4 CIDR blocks."
  }
}
variable "key_name" {
  type        = string
  default     = "nth-karpenter-key"
  description = "Name of the EC2 key pair created for the VS Code instance and the managed node group"

  validation {
    condition     = can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be a non-empty string of printable ASCII characters, 255 characters or fewer."
  }
}
variable "node_group_name" {
  type        = string
  default     = "core-nodegroup"
  description = "Name of the managed node group that hosts the Karpenter controller and the termination handler. Karpenter cannot provision the nodes its own controller runs on, so this group is a prerequisite rather than a duplicate of it"

  validation {
    condition     = length(var.node_group_name) > 0
    error_message = "node_group_name must not be empty."
  }
}
variable "node_group_capacity_type" {
  type        = string
  default     = "ON_DEMAND"
  description = "Capacity type for the managed node group. ON_DEMAND as the _monolithic template had it, and the opposite of the nth_imds_processor variant - here the interruptible capacity comes from the Karpenter pool, and this group only has to be stable enough to host the Karpenter controller and the handler itself"

  validation {
    # Constant condition, because in this variant the value really is fixed: a spot node group
    # would make the components that react to an interruption interruptible themselves, which is
    # a confusing thing to debug in a demo about interruptions (rules.md B-1).
    condition     = var.node_group_capacity_type == "ON_DEMAND"
    error_message = "node_group_capacity_type must be ON_DEMAND in this variant. The interruptible capacity is the Karpenter pool; this group hosts the Karpenter controller and the termination handler, and putting those on spot means the things that respond to an interruption can themselves be interrupted."
  }
}
variable "node_group_instance_types" {
  type        = list(string)
  default     = ["t3.medium"]
  description = "EC2 instance types for the managed node group"

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "node_group_instance_types must contain at least one instance type."
  }
}
variable "node_group_desired_size" {
  type        = number
  default     = 2
  description = "Desired node count, two as the _monolithic template had it. Two is enough here because the demo workload does not run on this group at all - it is pinned to the Karpenter pool - so this group only carries the Karpenter controller and the handler"

  validation {
    condition     = var.node_group_desired_size >= 0
    error_message = "node_group_desired_size must be zero or greater."
  }
}
variable "node_group_min_size" {
  type        = number
  default     = 2
  description = "Minimum node count for the managed node group"

  validation {
    condition     = var.node_group_min_size >= 0
    error_message = "node_group_min_size must be zero or greater."
  }
}
variable "node_group_max_size" {
  type        = number
  default     = 4
  description = "Maximum node count for the managed node group. Kept small on purpose: capacity for workloads is the Karpenter pool's job, not this group's"

  validation {
    condition     = var.node_group_max_size >= 0
    error_message = "node_group_max_size must be zero or greater."
  }
}
variable "karpenter_discovery_tag_key" {
  type        = string
  default     = "karpenter.sh/discovery"
  description = "Tag key written onto the private subnets and used in the EC2NodeClass subnet selector, so Karpenter launches nodes only into this cluster's private subnets. The _monolithic template listed the two subnet IDs literally inside the YAML it echoed onto the bastion, which meant the pool could not follow a change to the network"

  validation {
    condition     = length(var.karpenter_discovery_tag_key) > 0
    error_message = "karpenter_discovery_tag_key must not be empty."
  }
}
variable "karpenter_chart_version" {
  type        = string
  default     = "1.8.3"
  description = "Version of the Karpenter Helm chart, which also installs the NodePool and EC2NodeClass CRDs. The _monolithic template pinned 1.7.0 through a shell variable inside an SSM document, where a version bump was invisible to plan"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.karpenter_chart_version))
    error_message = "karpenter_chart_version must be a semantic version (e.g. 1.8.3)."
  }
}
variable "karpenter_interruption_queue_name" {
  type        = string
  default     = "nth-karpenter-interruption"
  description = "Name of the SQS queue EventBridge delivers interruption notices to and Karpenter polls. This is the second of the two mechanisms in this variant: the termination handler covers the managed node group from each node's own metadata, and this queue covers the Karpenter pool - and unlike the handler, Karpenter also launches a replacement"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,80}$", var.karpenter_interruption_queue_name))
    error_message = "karpenter_interruption_queue_name must be 1-80 characters of letters, digits, hyphens and underscores."
  }
}
variable "karpenter_pool_name" {
  type        = string
  default     = "spot"
  description = "Name of the NodePool and its EC2NodeClass, and the Name tag Karpenter writes onto the instances it launches from them - which is how those instances are told apart from the managed node group's in the spot instance list"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.karpenter_pool_name))
    error_message = "karpenter_pool_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "karpenter_node_labels" {
  type        = map(string)
  default     = { nodegroup = "spot", type = "karpenter" }
  description = "Labels every node the Karpenter pool provisions carries. The demo Deployment's nodeSelector is filled from this same map, which is what keeps its pods off the managed node group - and the only reason Karpenter provisions at all, since it provisions for pending pods it can satisfy"

  validation {
    condition     = length(var.karpenter_node_labels) > 0
    error_message = "karpenter_node_labels must contain at least one label, since the demo workload selects on it."
  }
}
variable "karpenter_instance_families" {
  type        = list(string)
  default     = ["m5"]
  description = "EC2 instance families the pool may provision, m5 as the _monolithic template pinned it. Expressed as a karpenter.k8s.aws/instance-family requirement, which intersects with the category and generation requirements the module always writes"

  validation {
    condition     = length(var.karpenter_instance_families) > 0 && alltrue([for family in var.karpenter_instance_families : can(regex("^[a-z][a-z0-9]*[0-9][a-z]*$", family))])
    error_message = "karpenter_instance_families must contain at least one EC2 instance family (e.g. m5, c7g)."
  }
}
variable "karpenter_instance_sizes" {
  type        = list(string)
  default     = ["xlarge", "2xlarge", "4xlarge", "8xlarge"]
  description = "Instance sizes the pool may provision, as the _monolithic template pinned them. Karpenter picks the cheapest that fits the pending pods, so in practice this means a single xlarge - which suits the demo: the pool has exactly one node to lose, and the replacement it launches is unmistakable"

  validation {
    condition     = length(var.karpenter_instance_sizes) > 0
    error_message = "karpenter_instance_sizes must contain at least one size."
  }
}
variable "karpenter_node_volume_size" {
  type        = string
  default     = "100Gi"
  description = "Root volume size for Karpenter-provisioned nodes, as the _monolithic template had it. That template also attached a second 300Gi volume to every node which nothing formatted, mounted or wrote to - 300Gi of billed, unused EBS per node, on a pool designed to replace its nodes repeatedly (055_eks_node_multiple_ebs_volumes is where a second volume is actually put to use)"

  validation {
    condition     = can(regex("^[0-9]+(Gi|Ti)$", var.karpenter_node_volume_size))
    error_message = "karpenter_node_volume_size must be a binary quantity such as 100Gi."
  }
}
variable "karpenter_consolidation_policy" {
  type        = string
  default     = "WhenEmpty"
  description = "When Karpenter may replace or remove a node in the pool, WhenEmpty as the _monolithic template had it - and worth keeping here: WhenEmptyOrUnderutilized lets Karpenter repack nodes on its own initiative, and a node that vanishes during the demo is then impossible to attribute to the interruption rather than to consolidation"

  validation {
    condition     = contains(["WhenEmpty", "WhenEmptyOrUnderutilized"], var.karpenter_consolidation_policy)
    error_message = "karpenter_consolidation_policy must be either WhenEmpty or WhenEmptyOrUnderutilized."
  }
}
variable "karpenter_consolidate_after" {
  type        = string
  default     = "30s"
  description = "How long a node must stay consolidatable before Karpenter acts on it"

  validation {
    condition     = can(regex("^[0-9]+(s|m|h)$", var.karpenter_consolidate_after))
    error_message = "karpenter_consolidate_after must be a duration such as 30s, 1m or 1h."
  }
}
variable "node_termination_handler_chart_version" {
  type        = string
  default     = "0.27.6"
  description = "Version of the aws-node-termination-handler chart, pinned where the _monolithic template's helm command left it floating - so what got installed depended on the day the stack was created, for the one component that decides whether a node is drained before it disappears"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.node_termination_handler_chart_version))
    error_message = "node_termination_handler_chart_version must be a semantic version (e.g. 0.27.6)."
  }
}
variable "enable_rebalance_draining" {
  type        = bool
  default     = true
  description = "Whether a rebalance recommendation drains the node, not only an interruption warning. On as the _monolithic template had it, and worth keeping for this demo: the interrupt command sends the rebalance recommendation immediately and the interruption notice minutes later, so with this on the drain happens at the first signal and the notice arrives at an already-empty node"
}
variable "workload_name" {
  type        = string
  default     = "nginx"
  description = "Name of the demo Deployment, nginx as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.workload_name))
    error_message = "workload_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "workload_replicas" {
  type        = number
  default     = 6
  description = "Replicas in the demo Deployment, six as the _monolithic template had it. Fewer than the nth_imds_processor variant because they all sit on the Karpenter pool rather than spread across a three-node group"

  validation {
    condition     = var.workload_replicas >= 1
    error_message = "workload_replicas must be at least 1."
  }
}
variable "workload_image" {
  type        = string
  default     = "public.ecr.aws/nginx/nginx:1.29.5-alpine"
  description = "Container image for the demo Deployment. Pinned and from ECR Public, where the _monolithic template used the bare name \"nginx\": docker.io/library/nginx:latest, a floating tag on a registry that rate-limits anonymous pulls per source address - and every node here shares one NAT gateway address per zone"

  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$", var.workload_image))
    error_message = "workload_image must carry an explicit tag."
  }
}
variable "workload_min_available" {
  type        = string
  default     = "50%"
  description = "How much of the demo Deployment a PodDisruptionBudget keeps available during a drain. The _monolithic template created no budget, so a drain could evict every replica at once and the demo showed the workload going away and coming back rather than surviving. Set to null to see that original behaviour"

  validation {
    condition     = var.workload_min_available == null || can(regex("^([0-9]+|[0-9]{1,3}%)$", var.workload_min_available))
    error_message = "workload_min_available must be a count such as 6 or a percentage such as 50%, or null to create no budget."
  }
}
variable "spot_interrupter_version" {
  type        = string
  default     = "v0.0.16"
  description = "Version of amazon-ec2-spot-interrupter installed on the VS Code instance, the CLI that sends the interruption. The _monolithic template pinned v0.0.10 and built the download URL from a filename that embedded the version; the release assets dropped the version from their names, so the URL is assembled differently here"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.spot_interrupter_version))
    error_message = "spot_interrupter_version must be a v-prefixed semantic version (e.g. v0.0.16)."
  }
}
variable "spot_interrupt_delay" {
  type        = string
  default     = "13m"
  description = "Delay between the rebalance recommendation the CLI sends immediately and the interruption notice it sends afterwards, thirteen minutes as the _monolithic template's output suggested. Long enough to watch the handler react to the rebalance recommendation on its own before the interruption arrives"

  validation {
    condition     = can(regex("^[0-9]+(s|m|h)$", var.spot_interrupt_delay))
    error_message = "spot_interrupt_delay must be a Go duration such as 15s, 13m or 1h."
  }
}
variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "EC2 instance type for the VS Code EC2 instance"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must be a valid EC2 instance type (e.g. t3.medium)."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether to allow inbound access to the code-server port (8000) on the VS Code instance from 0.0.0.0/0, as the _monolithic template's InboundFromAnywhere parameter did. Set false and reach it through SSM Session Manager port forwarding instead"
}
variable "eks_node_viewer_version" {
  type        = string
  default     = "v0.7.4"
  description = "Version of eks-node-viewer installed on the VS Code instance, the tool that shows nodes appearing and disappearing while an interruption plays out"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.eks_node_viewer_version))
    error_message = "eks_node_viewer_version must be a v-prefixed semantic version (e.g. v0.7.4)."
  }
}
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory holding the bootstrap marker files, shared between the vscode_ec2 module (which touches <path>/userdata as the last step of its user data) and the SSM association that polls for it before writing the README (rules.md D-5/H-2). Under /run so the markers vanish on reboot rather than making a stale file look like a completed bootstrap"

  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/'."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the SSM association waits for the README command to report success. It has to cover the whole instance bootstrap, since the command's first act is to wait for the user data marker file"

  validation {
    condition     = var.readme_timeout_seconds > 0
    error_message = "readme_timeout_seconds must be greater than zero."
  }
}
variable "kubectl_download_version" {
  type        = string
  default     = "1.33.3/2025-08-03"
  description = "Version and release-date path segment of the kubectl binary downloaded onto the VS Code EC2 instance, from the amazon-eks S3 bucket layout (<version>/<date>). Keep within one minor version of kubernetes_version"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.33.3/2025-08-03."
  }
}
