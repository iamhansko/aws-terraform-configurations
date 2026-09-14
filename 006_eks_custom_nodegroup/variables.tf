variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.)"
}
variable "cluster_name" {
  type        = string
  default     = "stem-cluster"
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
  description = "Whether the EKS cluster API server endpoint is reachable from the public internet. Needed because the helm and kubectl providers run from the machine executing terraform apply rather than from inside the VPC (rules.md #18/#26); the _monolithic design instead ran helm and kubectl from the bastion inside the VPC, which is why the underlying eks_cluster module still defaults this to false. Restrict access with public_access_cidrs rather than leaving it open to 0.0.0.0/0"
}
variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDR blocks allowed to reach the EKS API server's public endpoint when endpoint_public_access is true. Set this to your own address in CIDR form (e.g. [\"203.0.113.4/32\"]) instead of leaving the default: bootstrap_cluster_creator_admin_permissions grants anyone who can reach this endpoint with the creating AWS identity full cluster admin"

  validation {
    condition     = alltrue([for cidr in var.public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "public_access_cidrs must contain valid IPv4 CIDR blocks."
  }
}
variable "key_name" {
  type        = string
  default     = "stem-key"
  description = "Name of the EC2 key pair created for the bastion and worker nodes"

  validation {
    condition     = can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be a non-empty string of printable ASCII characters, 255 characters or fewer."
  }
}
variable "ecr_repository_name" {
  type        = string
  default     = "stem-ecr"
  description = "Name of the ECR repository the VS Code EC2 instance builds and pushes the sample match-making image into"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]{1,255}$", var.ecr_repository_name))
    error_message = "ecr_repository_name must be a valid ECR repository name."
  }
}
variable "app_node_group_name" {
  type        = string
  default     = "stem-app"
  description = "Name of the managed node group carrying application workloads"

  validation {
    condition     = length(var.app_node_group_name) > 0
    error_message = "app_node_group_name must not be empty."
  }
}
variable "app_node_group_labels" {
  type        = map(string)
  default     = { "stem/dedicated" = "app" }
  description = "Kubernetes labels applied to the application node group's nodes, and used as the HPA demo's nodeSelector so its pods land there"

  validation {
    condition     = length(var.app_node_group_labels) > 0
    error_message = "app_node_group_labels must contain at least one label, since the HPA demo selects nodes with it."
  }
}
variable "addon_node_group_name" {
  type        = string
  default     = "stem-addon"
  description = "Name of the managed node group carrying cluster addons (load balancer controller, autoscaler, dashboards)"

  validation {
    condition     = length(var.addon_node_group_name) > 0
    error_message = "addon_node_group_name must not be empty."
  }
}
variable "addon_node_group_labels" {
  type        = map(string)
  default     = { "stem/dedicated" = "addon" }
  description = "Kubernetes labels applied to the addon node group's nodes"

  validation {
    condition     = alltrue([for key in keys(var.addon_node_group_labels) : length(key) > 0])
    error_message = "addon_node_group_labels must not contain empty Kubernetes label keys."
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
  description = "Desired node count per managed node group"

  validation {
    condition     = var.node_group_desired_size >= 0
    error_message = "node_group_desired_size must be zero or greater."
  }
}
variable "node_group_min_size" {
  type        = number
  default     = 2
  description = "Minimum node count per managed node group"

  validation {
    condition     = var.node_group_min_size >= 0
    error_message = "node_group_min_size must be zero or greater."
  }
}
variable "node_group_max_size" {
  type        = number
  default     = 4
  description = "Maximum node count per managed node group. The cluster autoscaler cannot grow a group past this, so it caps how far the HPA demo's scale-up can go"

  validation {
    condition     = var.node_group_max_size >= 0
    error_message = "node_group_max_size must be zero or greater."
  }
}
variable "node_group_custom_user_data" {
  type        = string
  default     = null
  description = <<-EOT
    Optional launch template user data for both node groups, demonstrating the custom launch template this project is about. EKS only honours MIME multipart content here: a bare shell script or a bare NodeConfig document is silently ignored. When node_group_custom_ami_id is null (the default), EKS merges its own NodeConfig boundary in, so this only needs the shell part:

      MIME-Version: 1.0
      Content-Type: multipart/mixed; boundary="==BOUNDARY=="

      --==BOUNDARY==
      Content-Type: text/x-shellscript; charset="us-ascii"

      #!/bin/bash
      timedatectl set-timezone Asia/Seoul

      --==BOUNDARY==--

    When node_group_custom_ami_id is set, EKS stops injecting NodeConfig and this document must supply an application/node.eks.aws part with the cluster's apiServerEndpoint, certificateAuthority, cidr and name itself.
  EOT

  validation {
    condition     = var.node_group_custom_user_data == null || can(regex("(?i)^\\s*MIME-Version:", var.node_group_custom_user_data))
    error_message = "node_group_custom_user_data must be a MIME multipart document starting with a MIME-Version header, or null. EKS silently ignores a bare shell script or a bare NodeConfig here."
  }
}
variable "node_group_custom_ami_id" {
  type        = string
  default     = null
  description = "Optional AMI ID for both node groups' launch templates, replacing the EKS-optimized AMI. Requires node_group_custom_user_data to carry a NodeConfig part, since EKS no longer injects one"

  validation {
    condition     = var.node_group_custom_ami_id == null || can(regex("^ami-[0-9a-f]+$", var.node_group_custom_ami_id))
    error_message = "node_group_custom_ami_id must be a valid AMI ID (e.g. ami-0123456789abcdef0), or null."
  }
}
variable "hpa_target_cpu_utilization_percentage" {
  type        = number
  default     = 60
  description = "Average CPU utilization the HPA demo's HorizontalPodAutoscaler steers toward, as a percentage of the pod's CPU request"

  validation {
    condition     = var.hpa_target_cpu_utilization_percentage > 0 && var.hpa_target_cpu_utilization_percentage <= 100
    error_message = "hpa_target_cpu_utilization_percentage must be between 1 and 100."
  }
}
variable "hpa_min_replicas" {
  type        = number
  default     = 1
  description = "Minimum replica count for the HPA demo"

  validation {
    condition     = var.hpa_min_replicas > 0
    error_message = "hpa_min_replicas must be greater than zero."
  }
}
variable "hpa_max_replicas" {
  type        = number
  default     = 10
  description = "Maximum replica count for the HPA demo. Set above what the app node group can hold so scale-up also forces the cluster autoscaler to add nodes"

  validation {
    condition     = var.hpa_max_replicas > 0
    error_message = "hpa_max_replicas must be greater than zero."
  }
}
variable "kube_ops_view_service_type" {
  type        = string
  default     = "LoadBalancer"
  description = "Service type for the kube-ops-view dashboard. LoadBalancer hands the Service to the AWS Load Balancer Controller, which provisions an internet-facing NLB from the annotations in main.tf - kube-ops-view has no authentication of its own, so anyone with the address can read the cluster's nodes and pods. Set ClusterIP to keep it private and reach it through 'kubectl port-forward' instead"

  validation {
    condition     = contains(["ClusterIP", "NodePort", "LoadBalancer"], var.kube_ops_view_service_type)
    error_message = "kube_ops_view_service_type must be one of: ClusterIP, NodePort, LoadBalancer."
  }
}
variable "vscode_instance_type" {
  type        = string
  default     = "t3.small"
  description = "EC2 instance type for the VS Code EC2 instance. It builds a container image locally, so give it more than a nano/micro"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must be a valid EC2 instance type (e.g. t3.small)."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether to allow inbound access to the code-server port (8000) on the VS Code EC2 instance from 0.0.0.0/0. Leave false and use SSM Session Manager port forwarding for anything but a short-lived demo"
}
variable "build_sample_image" {
  type        = bool
  default     = true
  description = "Whether the VS Code EC2 instance installs Docker and builds/pushes the sample Go match-making image into the ECR repository. This genuinely needs a Docker daemon on a host, which is why it stays in user data rather than becoming a provider resource"
}
variable "kubectl_download_version" {
  type        = string
  default     = "1.33.3/2025-08-03"
  description = "Version and release-date path segment of the kubectl binary downloaded onto the VS Code EC2 instance, from the amazon-eks S3 bucket layout (<version>/<date>)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.33.3/2025-08-03."
  }
}
