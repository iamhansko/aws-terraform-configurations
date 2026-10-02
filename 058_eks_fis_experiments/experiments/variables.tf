variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.)"
}
variable "prefix" {
  type        = string
  default     = "fis"
  description = "Prefix for the network resources' Name tags (\"fis\" produces fis-vpc, fis-igw, fis-public-a, ...)"

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
  default     = "experiments-eks-cluster"
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
  description = "Whether the EKS cluster API server endpoint is reachable from the public internet. Required here, because the helm and kubectl providers that install Karpenter, the Node Termination Handler, the node pools and the workloads run from the machine executing terraform apply rather than from inside the VPC (rules.md E-1/E-2). Narrow public_access_cidrs rather than turning this off"

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
  default     = "fis-key"
  description = "Name of the EC2 key pair created for the VS Code instance and the managed node group"

  validation {
    condition     = can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be a non-empty string of printable ASCII characters, 255 characters or fewer."
  }
}
variable "node_group_name" {
  type        = string
  default     = "core-nodegroup"
  description = "Name of the managed node group that hosts the Karpenter controller and the Node Termination Handler. Karpenter cannot provision the nodes its own controller runs on, so this group is a prerequisite rather than a duplicate of it"

  validation {
    condition     = length(var.node_group_name) > 0
    error_message = "node_group_name must not be empty."
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
  description = "Desired node count for the managed node group, two as the _monolithic template had it. Two nodes let the Karpenter controller's leader-elected replica pair spread across availability zones"

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
  description = "Maximum node count for the managed node group. Kept small on purpose: the workloads that scale are Karpenter's, not this group's"

  validation {
    condition     = var.node_group_max_size >= 0
    error_message = "node_group_max_size must be zero or greater."
  }
}
variable "karpenter_discovery_tag_key" {
  type        = string
  default     = "karpenter.sh/discovery"
  description = "Tag key written onto the private subnets and used in both EC2NodeClass subnet selectors, so Karpenter launches nodes only into this cluster's private subnets"

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
  default     = "experiments-karpenter-interruption"
  description = "Name of the SQS queue EventBridge delivers interruption notices to and Karpenter polls. This is the pairing the spot interruption experiment exercises: without it Karpenter learns a node is going away only when it disappears"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,80}$", var.karpenter_interruption_queue_name))
    error_message = "karpenter_interruption_queue_name must be 1-80 characters of letters, digits, hyphens and underscores."
  }
}
variable "karpenter_instance_families" {
  type        = list(string)
  default     = ["m5"]
  description = "EC2 instance families both node pools may provision, m5 as the _monolithic template pinned it. Expressed as a karpenter.k8s.aws/instance-family requirement, which intersects with the category and generation requirements the module always writes"

  validation {
    condition     = length(var.karpenter_instance_families) > 0 && alltrue([for family in var.karpenter_instance_families : can(regex("^[a-z][a-z0-9]*[0-9][a-z]*$", family))])
    error_message = "karpenter_instance_families must contain at least one EC2 instance family (e.g. m5, c7g)."
  }
}
variable "karpenter_instance_sizes" {
  type        = list(string)
  default     = ["xlarge", "2xlarge", "4xlarge", "8xlarge"]
  description = "Instance sizes both node pools may provision, as the _monolithic template pinned them. Karpenter picks the cheapest that fits the pending pods, so in practice this means one xlarge per pool - which is the point for an interruption demo: the pool has exactly one node to lose, and the replacement it launches is visible"

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
  description = "When Karpenter may replace or remove a node in either pool, WhenEmpty as the _monolithic template had it - and worth keeping for this project specifically: WhenEmptyOrUnderutilized lets Karpenter repack nodes on its own initiative, and a node that vanishes while an experiment is running is then impossible to attribute to the fault rather than to consolidation"

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
variable "spot_pool_name" {
  type        = string
  default     = "spot"
  description = "Name of the spot NodePool and its EC2NodeClass, and the Name tag Karpenter writes onto the instances it launches from it. That tag is what the spot interruption experiment searches for, which is why the same string serves all three: the experiment takes it from this pool's output rather than restating it (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.spot_pool_name))
    error_message = "spot_pool_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "ondemand_pool_name" {
  type        = string
  default     = "ondemand"
  description = "Name of the on-demand NodePool and its EC2NodeClass, and the Name tag the stop-instances experiment searches for"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.ondemand_pool_name))
    error_message = "ondemand_pool_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "spot_node_labels" {
  type        = map(string)
  default     = { nodegroup = "spot", type = "karpenter" }
  description = "Labels every node the spot pool provisions carries. The spot Deployment's nodeSelector is filled from this same map, so it is what keeps those pods off the managed node group and off the on-demand pool"

  validation {
    condition     = length(var.spot_node_labels) > 0
    error_message = "spot_node_labels must contain at least one label, since the spot workload selects on it."
  }
}
variable "ondemand_node_labels" {
  type        = map(string)
  default     = { nodegroup = "ondemand", type = "karpenter" }
  description = "Labels every node the on-demand pool provisions carries, and the selector the on-demand Deployment is pinned by"

  validation {
    condition     = length(var.ondemand_node_labels) > 0
    error_message = "ondemand_node_labels must contain at least one label, since the on-demand workload selects on it."
  }
}
variable "spot_workload_name" {
  type        = string
  default     = "spot"
  description = "Name of the Deployment pinned to the spot pool"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.spot_workload_name))
    error_message = "spot_workload_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "ondemand_workload_name" {
  type        = string
  default     = "ondemand"
  description = "Name of the Deployment pinned to the on-demand pool"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.ondemand_workload_name))
    error_message = "ondemand_workload_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "workload_replicas" {
  type        = number
  default     = 6
  description = "Replicas in each of the two demo Deployments, six as the _monolithic template had it"

  validation {
    condition     = var.workload_replicas >= 1
    error_message = "workload_replicas must be at least 1."
  }
}
variable "workload_image" {
  type        = string
  default     = "public.ecr.aws/nginx/nginx:1.29.5-alpine"
  description = "Container image for both demo Deployments. Pinned and from ECR Public, where the _monolithic template used the bare name \"nginx\": docker.io/library/nginx:latest, a floating tag on a registry that rate-limits anonymous pulls per source address - and a project whose whole purpose is to destroy and replace nodes pulls it again every time"

  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$", var.workload_image))
    error_message = "workload_image must carry an explicit tag."
  }
}
variable "workload_min_available" {
  type        = string
  default     = "50%"
  description = "How much of each Deployment a PodDisruptionBudget keeps available while a node is drained. The _monolithic template created no budget, so an interruption could evict every replica at once; with one, Karpenter has to bring capacity up before it can finish taking the old node away, which is the sequence worth watching. Set to null for the original behaviour"

  validation {
    condition     = var.workload_min_available == null || can(regex("^([0-9]+|[0-9]{1,3}%)$", var.workload_min_available))
    error_message = "workload_min_available must be a count such as 3 or a percentage such as 50%, or null to create no budget."
  }
}
variable "node_termination_handler_chart_version" {
  type        = string
  default     = "0.27.4"
  description = "Version of the aws-node-termination-handler chart, pinned where the _monolithic template's helm command left it floating - so what got installed depended on the day the stack was created"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.node_termination_handler_chart_version))
    error_message = "node_termination_handler_chart_version must be a semantic version (e.g. 0.27.4)."
  }
}
variable "enable_stop_instance_experiment" {
  type        = bool
  default     = true
  description = "Whether to create the stop-instances experiment targeting the on-demand pool. This is the variant that has it: EC2 issues no warning for an instance it is told to stop, so Karpenter's only signal is the instance state change event - which is why that EventBridge rule is not optional here. spot_instance_interruptions is the same project without this half"
}
variable "enable_spot_interruption_experiment" {
  type        = bool
  default     = true
  description = "Whether to create the spot interruption experiment targeting the spot pool. This produces the real two-minute warning, so it is what exercises the interruption queue end to end"

  validation {
    condition     = var.enable_spot_interruption_experiment || var.enable_stop_instance_experiment
    error_message = "At least one experiment must be enabled, otherwise the project creates an experiment role and no experiments, and there is nothing left to demonstrate."
  }
}
variable "spot_interruption_duration" {
  type        = string
  default     = "PT900S"
  description = "How long after the warning FIS actually reclaims the instance - not how long until the warning is sent, which is immediate. The real AWS notice period is two minutes; a longer value here leaves time to watch the drain"

  validation {
    condition     = can(regex("^PT([0-9]+M)?([0-9]+S)?$", var.spot_interruption_duration))
    error_message = "spot_interruption_duration must be an ISO 8601 duration of minutes and seconds between PT2M and PT1H, e.g. PT900S."
  }
}
variable "enable_fis_experiment_logging" {
  type        = bool
  default     = true
  description = "Whether experiments deliver their own log to CloudWatch Logs. Worth having: without it an experiment reports only a final state, and which instance it resolved to is recorded nowhere - so a target tag that matched the wrong node looks the same as one that matched the right one"
}
variable "fis_log_retention_days" {
  type        = number
  default     = 7
  description = "Retention for the experiment log group. A real number rather than never-expire, because an experiment log is only interesting while the experiment is being investigated"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.fis_log_retention_days)
    error_message = "fis_log_retention_days must be one of the retention periods CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, 60, 90, ... 3653)."
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
  description = "Version of eks-node-viewer installed on the VS Code instance, the tool that shows nodes appearing and disappearing while an experiment runs"

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
