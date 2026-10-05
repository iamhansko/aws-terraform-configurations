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
  default     = "nodegroup-update-cluster"
  description = "Name of the EKS cluster. The _monolithic template derived this from the CloudFormation stack name, which Terraform has no equivalent of, so it is a variable here (rules.md B-3)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,99}$", var.cluster_name))
    error_message = "cluster_name must start with a letter or digit and contain only letters, digits, hyphens and underscores (100 characters or fewer)."
  }
}
variable "kubernetes_version" {
  type        = string
  default     = "1.34"
  description = "Kubernetes version for the EKS cluster. This project updates a node group's launch template, not its Kubernetes version - but both go through the same UpdateNodegroupVersion call and drain nodes the same way, so the behaviour shown here is what a version upgrade does too"

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
  description = "Whether the EKS API server endpoint is reachable from the internet. True because the kubectl provider runs on the machine executing terraform apply rather than inside the VPC (rules.md E-2); the _monolithic template had this true as well. Narrow public_access_cidrs rather than leaving the default open"

  validation {
    # Pinned in the direction this variant depends on. The two forms fail differently and
    # the SSM alternative is E-9's, so the choice is recorded rather than left implicit
    # (rules.md B-1/E-9).
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because its Deployment and PodDisruptionBudget are applied by the kubectl provider from the machine running terraform. To run with a private endpoint, apply them from the bastion through an SSM Association instead, as 041_eks_private_cluster does (rules.md E-9)."
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
  default     = "nodegroup-update-key"
  description = "Name of the EC2 key pair created for the demo instance and attached to the worker nodes through the node group's launch template"

  validation {
    condition     = length(var.key_name) > 0
    error_message = "key_name must not be empty."
  }
}
variable "node_group_name" {
  type        = string
  default     = "core"
  description = "Name of the managed node group, \"core\" as the _monolithic template had it. Also the prefix of its launch template's name"

  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9_-]*)$", var.node_group_name))
    error_message = "node_group_name must start with a letter or digit and contain only letters, digits, hyphens and underscores."
  }
}
variable "node_group_instance_types" {
  type        = list(string)
  default     = ["t3.medium"]
  description = "Instance types for the managed node group"

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "node_group_instance_types must contain at least one instance type."
  }
}
variable "node_group_desired_size" {
  type        = number
  default     = 3
  description = "Desired node count, three as the _monolithic template had it - one per replica of the demo Deployment, so each node replacement during the update has exactly one pod to evict"

  validation {
    condition     = var.node_group_desired_size >= 1
    error_message = "node_group_desired_size must be at least 1."
  }
}
variable "node_group_min_size" {
  type        = number
  default     = 3
  description = "Minimum node count"

  validation {
    condition     = var.node_group_min_size >= 1
    error_message = "node_group_min_size must be at least 1."
  }
}
variable "node_group_max_size" {
  type        = number
  default     = 6
  description = "Maximum node count, six as the _monolithic template had it. Not idle headroom: the update's scale-up phase adds nodes before draining any, so a maximum equal to the desired size leaves EKS no room to bring replacements up and the update has to terminate first and replace after"

  validation {
    condition     = var.node_group_max_size >= 1
    error_message = "node_group_max_size must be at least 1."
  }
  validation {
    condition     = var.node_group_max_size >= var.node_group_min_size
    error_message = "node_group_max_size must be greater than or equal to node_group_min_size."
  }
}
variable "node_group_instance_name_tag" {
  type        = string
  default     = "v1"
  description = "Name tag written onto the worker instances through the launch template, and the thing this demo changes. Editing it rewrites the launch template, which creates a new launch template version, which is what makes EKS roll the node group - so a single apply with a new value here is the managed node group update. The tag itself does nothing except make old and new nodes tellable apart in the EC2 console. The _monolithic template produced the same second version by calling aws ec2 create-launch-template-version from the instance's user data, which no plan could show and no destroy could undo"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/+=@-]{1,255}$", var.node_group_instance_name_tag))
    error_message = "node_group_instance_name_tag must be 1-255 characters from the set AWS accepts in a tag value."
  }
}
variable "node_group_launch_template_version" {
  type        = string
  default     = null
  description = "Launch template version the node group runs. Null - the default - means it follows the template's latest version, so changing node_group_instance_name_tag creates a version and adopts it in one apply. Pin it to hold the node group on an older version instead, which is what \"an update is available\" looks like: the template has a newer version and the node group has not taken it. Note that a version only exists once something created it, so pinning to 2 on a cluster whose template has only ever had version 1 fails at apply"

  validation {
    condition     = var.node_group_launch_template_version == null || can(regex("^[1-9][0-9]*$", var.node_group_launch_template_version))
    error_message = "node_group_launch_template_version must be a launch template version number (a positive integer, as a string), or null to follow the latest version."
  }

  validation {
    # Version 1 is the only one that exists before the tag has ever been changed, so
    # asking for a higher one while the tag is still at its initial value can only fail.
    # The pair is what is wrong, not either value alone (rules.md B-1).
    condition     = var.node_group_launch_template_version == null || var.node_group_launch_template_version == "1" || var.node_group_instance_name_tag != "v1"
    error_message = "node_group_launch_template_version higher than 1 needs a launch template version that something has created. Change node_group_instance_name_tag away from v1 first - that apply is what creates version 2 - or leave this null to follow the latest version."
  }
}
variable "node_group_force_update_version" {
  type        = bool
  default     = false
  description = "Whether EKS forces the node group update through when a node still holds pods. False, which is the whole point of this project: an unforced update drains through the eviction API and honours the PodDisruptionBudget, and fails with PodEvictionFailure if a node is not empty after fifteen minutes. The _monolithic template had this true, which deletes the pods instead - so the budget it went to the trouble of creating could never affect anything, and the demo was indistinguishable from a cluster with no budget. Set it true deliberately, after watching an update be held up, to see the difference"
}
variable "node_group_update_max_unavailable" {
  type        = number
  default     = 1
  description = "How many nodes EKS cordons and drains at once during the update. One is AWS's own default, stated here so it is visible in plan. Raising it does not raise the eviction rate - the PodDisruptionBudget still allows only its own number of pods to be unavailable - so the two together are what decide the pace"

  validation {
    condition     = var.node_group_update_max_unavailable >= 1
    error_message = "node_group_update_max_unavailable must be at least 1."
  }
}
variable "workload_name" {
  type        = string
  default     = "nginx"
  description = "Name of the demo Deployment and of the PodDisruptionBudget that protects it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.workload_name))
    error_message = "workload_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "workload_namespace" {
  type        = string
  default     = "default"
  description = "Namespace the demo Deployment and its budget live in, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.workload_namespace))
    error_message = "workload_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "workload_replicas" {
  type        = number
  default     = 3
  description = "How many pods the demo Deployment runs, three as the _monolithic template had it. Matched to node_group_desired_size so that one pod lands on each node"

  validation {
    condition     = var.workload_replicas >= 1
    error_message = "workload_replicas must be at least 1."
  }
}
variable "workload_readiness_initial_delay_seconds" {
  type        = number
  default     = 60
  description = "How long a replacement pod stays NotReady before its readiness probe first runs, sixty seconds as the _monolithic template had it. This is the clock the demo runs on: an evicted pod's replacement counts against the budget until it turns Ready, so nothing else can be evicted for at least this long"

  validation {
    condition     = var.workload_readiness_initial_delay_seconds >= 0
    error_message = "workload_readiness_initial_delay_seconds must be zero or greater."
  }
}
variable "workload_pdb_max_unavailable" {
  type        = number
  default     = 1
  description = "How many of the demo pods may be unavailable at once, one as the _monolithic template had it. With one pod per node this makes the update evict strictly one at a time. Zero is valid and allows no voluntary disruption at all, which is how to see the PodEvictionFailure path: the drain waits the full fifteen minutes and the update fails unless node_group_force_update_version is true"

  validation {
    condition     = var.workload_pdb_max_unavailable >= 0
    error_message = "workload_pdb_max_unavailable must be zero or greater."
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
