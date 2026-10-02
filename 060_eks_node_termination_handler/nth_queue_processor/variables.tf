variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.)"
}
variable "prefix" {
  type        = string
  default     = "nth-queue"
  description = "Prefix for the network resources' Name tags (\"nth-queue\" produces nth-queue-vpc, nth-queue-igw, nth-queue-public-a, ...)"

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
  default     = "nth-queue-processor-eks-cluster"
  description = "Name of the EKS cluster"

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
  default     = "nth-queue-key"
  description = "Name of the EC2 key pair created for the VS Code instance and both managed node groups"

  validation {
    condition     = can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be a non-empty string of printable ASCII characters, 255 characters or fewer."
  }
}
variable "ondemand_node_group_name" {
  type        = string
  default     = "ondemand-nodegroup"
  description = "Name of the on-demand managed node group. Two groups rather than one, as the _monolithic template had it, so the demo can show the two triggers side by side: a spot interruption on one and an Auto Scaling scale-in on the other"

  validation {
    condition     = length(var.ondemand_node_group_name) > 0
    error_message = "ondemand_node_group_name must not be empty."
  }
}
variable "spot_node_group_name" {
  type        = string
  default     = "spot-nodegroup"
  description = "Name of the spot managed node group. A managed node group rather than a Karpenter pool, deliberately: the point here is the Auto Scaling group behind it, which is what the lifecycle hooks attach to"

  validation {
    condition     = length(var.spot_node_group_name) > 0
    error_message = "spot_node_group_name must not be empty."
  }
}
variable "node_group_instance_types" {
  type        = list(string)
  default     = ["t3.medium"]
  description = "EC2 instance types for both managed node groups"

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "node_group_instance_types must contain at least one instance type."
  }
}
variable "node_group_desired_size" {
  type        = number
  default     = 2
  description = "Desired node count per node group, two as the _monolithic template had it - four nodes in total, so the demo Deployment's replicas land on both groups"

  validation {
    condition     = var.node_group_desired_size >= 0
    error_message = "node_group_desired_size must be zero or greater."
  }
}
variable "node_group_min_size" {
  type        = number
  default     = 1
  description = "Minimum node count per node group. One rather than the _monolithic template's two, because a group whose minimum equals its desired size cannot be scaled in - and a scale-in is how the terminating lifecycle hook is exercised without waiting for a real interruption"

  validation {
    condition     = var.node_group_min_size >= 0
    error_message = "node_group_min_size must be zero or greater."
  }
}
variable "node_group_max_size" {
  type        = number
  default     = 4
  description = "Maximum node count per node group. Headroom for the replacement instance the Auto Scaling group launches while the drained one is still in Terminating:Wait"

  validation {
    condition     = var.node_group_max_size >= 0
    error_message = "node_group_max_size must be zero or greater."
  }
}
variable "node_termination_handler_managed_tag" {
  type        = string
  default     = "aws-node-termination-handler/managed"
  description = "Instance tag key both node groups write and the handler checks before draining. One variable, because the two sides have to agree: with checkTagBeforeDraining on - the chart's default - an instance without this tag is silently never drained. The _monolithic template tagged the instances correctly but left the check itself implicit, and its own attempt to set it was a commented-out line in the install script"

  validation {
    condition     = length(var.node_termination_handler_managed_tag) > 0
    error_message = "node_termination_handler_managed_tag must not be empty."
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
variable "node_termination_handler_replica_count" {
  type        = number
  default     = 3
  description = "Replicas of the queue-processor Deployment, three as the _monolithic template had it. They are not sharded - each polls the same queue and SQS hands a message to one of them - so this buys availability rather than throughput"

  validation {
    condition     = var.node_termination_handler_replica_count >= 1
    error_message = "node_termination_handler_replica_count must be at least 1."
  }
}
variable "interruption_queue_name" {
  type        = string
  default     = "nth-queue-processor"
  description = "Name of the SQS queue EventBridge delivers termination events to and the handler polls. The _monolithic template left the queue unnamed, so it got a generated name - which is unhelpful for the one resource the whole variant is about"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,80}$", var.interruption_queue_name))
    error_message = "interruption_queue_name must be 1-80 characters of letters, digits, hyphens and underscores."
  }
}
variable "lifecycle_hook_heartbeat_seconds" {
  type        = number
  default     = 300
  description = "How long an instance is held in the lifecycle wait state before the hook's default result applies, five minutes as the _monolithic template had it. Has to outlast a drain, and is entirely separate from the two minutes a spot interruption gives - no hook can extend that"

  validation {
    condition     = var.lifecycle_hook_heartbeat_seconds >= 30 && var.lifecycle_hook_heartbeat_seconds <= 7200
    error_message = "lifecycle_hook_heartbeat_seconds must be between 30 and 7200."
  }
}
variable "create_launching_lifecycle_hooks" {
  type        = bool
  default     = true
  description = "Whether to create the EC2_INSTANCE_LAUNCHING hooks alongside the terminating ones, as the _monolithic template did. The handler does not act on launching events - these are Auto Scaling guarding itself, so an instance that never reports healthy is terminated rather than added to the group"
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
  default     = 12
  description = "Replicas in the demo Deployment, twelve as the _monolithic template had it. Three per node across four nodes, so taking one node away evicts a visible group rather than a single pod"

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
  description = "How much of the demo Deployment a PodDisruptionBudget keeps available during a drain. The _monolithic template created no budget, so a drain could evict every replica at once. Here it also has a second effect worth seeing: the handler cannot complete the lifecycle action until the eviction finishes, so a budget that cannot be satisfied holds the instance in Terminating:Wait until the heartbeat expires"

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
  description = "Delay between the rebalance recommendation the CLI sends immediately and the interruption notice it sends afterwards, thirteen minutes as the _monolithic template's output suggested"

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
  description = "Version of eks-node-viewer installed on the VS Code instance, the tool that shows nodes appearing and disappearing while a drain plays out"

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
