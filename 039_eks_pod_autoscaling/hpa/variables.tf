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
  default     = "hpa"
  description = "Name of the EKS cluster"
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,99}$", var.cluster_name))
    error_message = "cluster_name must start with a letter or digit and contain only letters, digits, hyphens and underscores (100 characters or fewer)."
  }
}
variable "kubernetes_version" {
  type        = string
  default     = "1.33"
  description = "Kubernetes version for the EKS cluster"
  validation {
    condition     = can(regex("^1\\.(3[0-9]|[4-9][0-9])$", var.kubernetes_version))
    error_message = "kubernetes_version must be a supported 1.XX version, e.g. 1.33."
  }
}
variable "kubectl_download_version" {
  type        = string
  default     = "1.33.3/2025-08-03"
  description = "Version path used to download kubectl onto the VS Code instance, in <version>/<release-date> form. Raised together with kubernetes_version: kubectl more than one minor version from the API server is outside the supported skew (rules.md H-1)"
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.33.3/2025-08-03."
  }
}
variable "eks_node_viewer_version" {
  type        = string
  default     = "v0.7.4"
  description = "eks-node-viewer release installed on the VS Code instance, as the _monolithic template pinned it. It renders nodes, the pods on them and their cost, which is what makes the node-side effect of a scale-up legible while the HPA adds replicas"
  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.eks_node_viewer_version))
    error_message = "eks_node_viewer_version must look like v0.7.4."
  }
}
variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the EKS API server endpoint is reachable from the internet. True because the kubectl provider in providers.tf applies this variant's Deployment, Service and HPA from wherever terraform runs, and has to reach the API server from there. Set it false only together with moving those manifests onto the bastion, which is what 041_eks_private_cluster does"
  validation {
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because the php_apache_hpa module's manifests are applied by the kubectl provider from the machine running terraform. To run with a private endpoint, apply them from the bastion through an SSM Association instead, as 041_eks_private_cluster does."
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
  default     = "hpa-key"
  description = "Name of the EC2 key pair created for the demo instances"
  validation {
    condition     = length(var.key_name) > 0
    error_message = "key_name must not be empty."
  }
}
variable "workload_name" {
  type        = string
  default     = "php-apache"
  description = "Name of the Deployment, Service and HorizontalPodAutoscaler the demo scales"
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.workload_name))
    error_message = "workload_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "workload_namespace" {
  type        = string
  default     = "default"
  description = "Namespace the demo workload is created in"
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.workload_namespace))
    error_message = "workload_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "workload_cpu_request" {
  type        = string
  default     = "200m"
  description = "CPU request on the demo container. The HPA's percentage target is measured against this, so the two are read together: 60% of 200m is 120m"
  validation {
    condition     = can(regex("^[0-9]+(m|\\.[0-9]+)?$", var.workload_cpu_request))
    error_message = "workload_cpu_request must be a Kubernetes CPU quantity, e.g. 200m."
  }
}
variable "hpa_target_cpu_utilization_percentage" {
  type        = number
  default     = 60
  description = "Average CPU utilisation the HPA holds, as a percentage of the request"
  validation {
    condition     = var.hpa_target_cpu_utilization_percentage > 0 && var.hpa_target_cpu_utilization_percentage <= 100
    error_message = "hpa_target_cpu_utilization_percentage must be between 1 and 100."
  }
}
variable "hpa_min_replicas" {
  type        = number
  default     = 1
  description = "Floor for the HPA"
  validation {
    condition     = var.hpa_min_replicas >= 1
    error_message = "hpa_min_replicas must be at least 1."
  }
}
variable "hpa_max_replicas" {
  type        = number
  default     = 15
  description = "Ceiling for the HPA, 15 as the _monolithic template set it. More replicas than the node group can hold, on purpose: the demo is meant to end with pods Pending, which is where pod autoscaling stops and node autoscaling would have to take over"
  validation {
    condition     = var.hpa_max_replicas >= 1
    error_message = "hpa_max_replicas must be at least 1."
  }
  validation {
    condition     = var.hpa_max_replicas >= var.hpa_min_replicas
    error_message = "hpa_max_replicas must be greater than or equal to hpa_min_replicas."
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
  default     = 2
  description = "Desired node count"
  validation {
    condition     = var.node_group_desired_size >= 1
    error_message = "node_group_desired_size must be at least 1."
  }
}
variable "node_group_min_size" {
  type        = number
  default     = 2
  description = "Minimum node count"
  validation {
    condition     = var.node_group_min_size >= 1
    error_message = "node_group_min_size must be at least 1."
  }
}
variable "node_group_max_size" {
  type        = number
  default     = 4
  description = "Maximum node count, 4 as the _monolithic template had it. Nothing scales the node group here - no Cluster Autoscaler, no Karpenter - so this is only headroom for a manual resize. The HPA's ceiling of 15 replicas is well past what these nodes hold, and that is the point: this variant scales pods, and shows where that alone runs out"
  validation {
    condition     = var.node_group_max_size >= 1
    error_message = "node_group_max_size must be at least 1."
  }
  validation {
    condition     = var.node_group_max_size >= var.node_group_min_size
    error_message = "node_group_max_size must be greater than or equal to node_group_min_size."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the VS Code security group accepts traffic from 0.0.0.0/0. False by default; code-server has no authentication in front of it"
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
  description = "How long the README SSM association may take. It first waits for the instance bootstrap to finish, which includes downloading kubectl, eksctl, helm and eks-node-viewer"
  validation {
    condition     = var.readme_timeout_seconds > 0
    error_message = "readme_timeout_seconds must be positive."
  }
}
