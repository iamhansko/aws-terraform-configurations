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
  default     = "eks-fargate-efs"
  description = "Prefix for resource names that have to be unique inside the account, and the title of the README written onto the workbench"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 3-32 lowercase letters, digits or hyphens and must not start or end with a hyphen."
  }
}

# --- Network ---

variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block of the VPC. Subnet CIDRs are derived from it rather than listed, so changing it moves every subnet with it"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block."
  }
}

variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "c"]
  description = "Availability zones the VPC spans, by suffix. Two, matching the pair the _monolithic template wired"

  validation {
    condition     = length(var.availability_zone_suffixes) >= 2
    error_message = "availability_zone_suffixes must name at least two zones; an EKS control plane requires subnets in two."
  }
}

variable "nat_availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "c"]
  description = "Zones the regional NAT gateway is given an address in. One Elastic IP per entry"

  validation {
    condition     = length(setsubtract(var.nat_availability_zone_suffixes, var.availability_zone_suffixes)) == 0
    error_message = "nat_availability_zone_suffixes must be drawn from availability_zone_suffixes; an address in a zone with no subnet is routed nowhere."
  }
}

# --- EKS cluster ---

variable "cluster_name" {
  type        = string
  default     = "eks-cluster"
  description = "Name of the EKS cluster"

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
  description = "Whether the cluster's API server has a public endpoint. True here, and pinned true, because the Kubernetes objects are applied by the kubectl and helm providers from the machine running terraform"

  validation {
    # Not a free choice: this root declares kubectl and helm providers, and those
    # run wherever terraform runs. With a private-only endpoint they cannot
    # connect, plan still passes cleanly, and the failure appears mid-apply as a
    # dial timeout that looks exactly like the destroy-ordering problem
    # rules.md D-4 describes. Pinning it keeps the two shapes from mixing
    # (rules.md E-9, B-1).
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because its manifests and Helm releases are applied by providers running on the machine executing terraform. To run with a private endpoint, drop the kubectl and helm providers and apply the objects from the workbench through an SSM Association instead, as 041_eks_private_cluster does."
  }
}

variable "endpoint_private_access" {
  type        = bool
  default     = true
  description = "Whether the cluster's API server also answers on a VPC-internal address. True, as the _monolithic template had it, so the workbench reaches the API server without leaving the VPC"
}

variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDRs allowed to reach the public API server endpoint. Narrow this to an office range for anything longer lived than a demo"

  validation {
    condition     = alltrue([for cidr in var.public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "public_access_cidrs must contain valid IPv4 CIDR blocks."
  }
}

variable "enabled_cluster_log_types" {
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  description = "Control plane log types shipped to CloudWatch Logs"

  validation {
    condition = alltrue([for t in var.enabled_cluster_log_types :
      contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], t)
    ])
    error_message = "enabled_cluster_log_types entries must be among: api, audit, authenticator, controllerManager, scheduler."
  }
}

variable "coredns_replica_count" {
  type        = number
  default     = 2
  description = "Number of CoreDNS replicas. Each one is a Fargate pod on this cluster, so the count is also the bill"

  validation {
    condition     = var.coredns_replica_count >= 1
    error_message = "coredns_replica_count must be at least 1."
  }
}

# --- Fargate ---

variable "fargate_profile_name" {
  type        = string
  default     = "core-profile"
  description = "Name of the single Fargate profile, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,99}$", var.fargate_profile_name))
    error_message = "fargate_profile_name must start with a letter or digit and contain only letters, digits, hyphens and underscores."
  }
}

variable "fargate_namespaces" {
  type        = list(string)
  default     = ["default", "kube-system"]
  description = "Namespaces the Fargate profile selects. kube-system is not optional on a cluster with no node group - it is what gives CoreDNS and the load balancer controller somewhere to run - and default is where the EFS demo pods go"

  validation {
    condition     = contains(var.fargate_namespaces, "kube-system")
    error_message = "fargate_namespaces must include kube-system. This cluster has no node group, so without it CoreDNS and the AWS Load Balancer Controller stay Pending and nothing in the cluster works."
  }

  validation {
    condition     = contains(var.fargate_namespaces, "default")
    error_message = "fargate_namespaces must include default, which is where the EFS writer and reader pods are created."
  }
}

# --- AWS Load Balancer Controller ---

variable "load_balancer_controller_chart_version" {
  type        = string
  default     = "1.14.1"
  description = "Pinned aws-load-balancer-controller chart version. The _monolithic template ran `helm install` with no --version, so the release drifted with whatever the repository happened to hold that day"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.load_balancer_controller_chart_version))
    error_message = "load_balancer_controller_chart_version must be a three-part semantic version."
  }
}

variable "load_balancer_controller_replica_count" {
  type        = number
  default     = 2
  description = "Number of controller replicas. Two Fargate pods on this cluster"

  validation {
    condition     = var.load_balancer_controller_replica_count >= 1
    error_message = "load_balancer_controller_replica_count must be at least 1."
  }
}

variable "load_balancer_controller_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the Helm release waits for the controller to become Available. Longer than the node-based projects on purpose: every replica is a Fargate pod, and a Fargate pod needs a micro-VM started and an ENI attached before it is even scheduled"

  validation {
    condition     = var.load_balancer_controller_timeout_seconds >= 300
    error_message = "load_balancer_controller_timeout_seconds must be at least 300; Fargate pod startup alone regularly takes over a minute per replica."
  }
}

# --- EFS ---

variable "efs_name" {
  type        = string
  default     = "eks-fargate-efs"
  description = "Name tag of the EFS file system"

  validation {
    condition     = length(var.efs_name) > 0
    error_message = "efs_name must not be empty."
  }
}

variable "efs_security_group_name" {
  type        = string
  default     = "efs-sg"
  description = "Name of the security group in front of the EFS mount targets"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.efs_security_group_name)) && !startswith(var.efs_security_group_name, "sg-")
    error_message = "efs_security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\"."
  }
}

variable "efs_performance_mode" {
  type        = string
  default     = "generalPurpose"
  description = "EFS performance mode, as the _monolithic template set it"

  validation {
    condition     = contains(["generalPurpose", "maxIO"], var.efs_performance_mode)
    error_message = "efs_performance_mode must be either generalPurpose or maxIO."
  }
}

# --- EFS demo workload ---

variable "workload_namespace" {
  type        = string
  default     = "default"
  description = "Namespace the writer and reader pods and their claims are created in. Has to be one of fargate_namespaces"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.workload_namespace))
    error_message = "workload_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}

variable "workload_storage_capacity" {
  type        = string
  default     = "5Gi"
  description = "Capacity the persistent volumes advertise and the claims request. EFS is elastic, so this only has to match on both sides for the bind to happen"

  validation {
    condition     = can(regex("^[0-9]+(Ki|Mi|Gi|Ti|K|M|G|T)?$", var.workload_storage_capacity))
    error_message = "workload_storage_capacity must be a Kubernetes quantity such as 5Gi."
  }
}

variable "register_csi_driver" {
  type        = bool
  default     = false
  description = "Whether to apply a CSIDriver object for efs.csi.aws.com. False: Fargate registers it already, and spec.attachRequired is immutable. The _monolithic template also wrote this manifest to disk without ever applying it"
}

# --- Workbench instance ---

variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type of the code-server workbench, as the _monolithic template sized it"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must look like an EC2 instance type (e.g. t3.medium)."
  }
}

variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the workbench security group accepts code-server traffic from 0.0.0.0/0. True reproduces the _monolithic template's InboundFromAnywhere default; code-server runs with auth disabled, so restrict this for anything beyond a demo"
}

variable "kubectl_download_version" {
  type        = string
  default     = "1.34.11/2026-09-22"
  description = "kubectl build downloaded onto the workbench, as <version>/<release-date>. Kept within one minor of kubernetes_version - outside that the client is off the supported skew. The _monolithic template pinned a 1.33 build against a 1.34 cluster"

  validation {
    condition     = can(regex("^1\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.34.11/2026-09-22."
  }
}

variable "code_server_version" {
  type        = string
  default     = "4.108.1"
  description = "code-server release installed on the workbench"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a three-part semantic version."
  }
}

variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the workbench where each bootstrap stage drops its completion marker. The README association waits on <path>/userdata rather than trusting depends_on (rules.md D-5)"

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
    error_message = "readme_timeout_seconds must be at least 300; the command waits on the instance bootstrap marker before it writes anything."
  }
}
