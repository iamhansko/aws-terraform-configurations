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
  default     = "multi-nic-cluster"
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
    error_message = "endpoint_public_access must be true in this variant, because its demo Deployment is applied by the kubectl provider from the machine running terraform. To run with a private endpoint, apply it from the bastion through an SSM Association instead, as 041_eks_private_cluster does (rules.md E-9)."
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
  default     = "multi-nic-key"
  description = "Name of the EC2 key pair created for the demo instance"

  validation {
    condition     = length(var.key_name) > 0
    error_message = "key_name must not be empty."
  }
}
variable "vpc_cni_addon_version" {
  type        = string
  default     = null
  description = "vpc-cni addon version. Null lets EKS pick the default for the cluster's Kubernetes version, which on 1.34 is well past the 1.20.0 the multi-NIC feature needs. Pin it only to hold a cluster on a known version - and check with \"aws eks describe-addon-versions --addon-name vpc-cni --kubernetes-version <v>\" rather than guessing, because an addon older than 1.20.0 ignores ENABLE_MULTI_NIC without reporting anything"

  validation {
    condition     = var.vpc_cni_addon_version == null || can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+-eksbuild\\.[0-9]+$", var.vpc_cni_addon_version))
    error_message = "vpc_cni_addon_version must look like v1.20.0-eksbuild.1, or null to let EKS choose."
  }
}
variable "enable_multi_nic" {
  type        = bool
  default     = true
  description = "Whether the VPC CNI's multi-NIC support is switched on, through ENABLE_MULTI_NIC in the addon's configuration_values rather than a \"kubectl set env daemonset aws-node\" call (rules.md E-5). True, because it is the only thing this project demonstrates. Note the side effect AWS documents: with it on the CNI stops allocating addresses in bulk and assigns them on demand, so pods on a fresh node start more slowly"

  validation {
    # The constraint is about what this project is for, not about the value's shape
    # (rules.md B-1).
    condition     = var.enable_multi_nic
    error_message = "enable_multi_nic must stay true in this variant. With it off the demo Deployment is created successfully, its nicConfig annotation is accepted as an ordinary annotation, and the pod gets a single interface - so the project reports success while demonstrating the opposite of its point. To see that comparison deliberately, keep this true and set multi_homed_annotate = false instead."
  }
}
variable "node_group_instance_types" {
  type        = list(string)
  default     = ["c6in.32xlarge"]
  description = "Instance types for the managed node group, c6in.32xlarge as the _monolithic template had it - and the choice is the demo rather than a sizing decision. The multi-NIC feature needs an instance type with more than one network card, which is not the same as more than one ENI: every type has several ENIs, while more than one card is confined to the largest sizes of a few families. A single-card type produces pods with one interface and no error anywhere. Check a candidate with \"aws ec2 describe-instance-types --instance-types <type> --query 'InstanceTypes[].NetworkInfo.MaximumNetworkCards'\". Be aware of the cost: this is a 128-vCPU instance, and it is the smallest thing in the c6in family that has two cards"

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "node_group_instance_types must contain at least one instance type."
  }
}
variable "node_group_desired_size" {
  type        = number
  default     = 1
  description = "Desired node count, one as the _monolithic template had it. One is the right number here for a reason beyond the demo: these instances are expensive, and a second one demonstrates nothing the first does not"

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
  description = "Maximum node count, three as the _monolithic template had it. Nothing scales this node group, so it is headroom - and headroom on this instance type is worth thinking about before using it"

  validation {
    condition     = var.node_group_max_size >= 1
    error_message = "node_group_max_size must be at least 1."
  }
  validation {
    condition     = var.node_group_max_size >= var.node_group_min_size
    error_message = "node_group_max_size must be greater than or equal to node_group_min_size."
  }
}
variable "multi_homed_name" {
  type        = string
  default     = "multi-homed"
  description = "Name of the demo Deployment"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.multi_homed_name))
    error_message = "multi_homed_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "multi_homed_namespace" {
  type        = string
  default     = "default"
  description = "Namespace the demo Deployment runs in, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.multi_homed_namespace))
    error_message = "multi_homed_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "multi_homed_annotate" {
  type        = bool
  default     = true
  description = "Whether the demo pod template carries the k8s.amazonaws.com/nicConfig annotation. True, which is the finished state. Set false to apply the identical Deployment without it and compare what \"ip -brief address\" reports inside the pod - that comparison is the only way to see the feature working, because a pod that did not get a second interface reports nothing (rules.md B-4)"
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
