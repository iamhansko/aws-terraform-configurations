variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.)"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region such as ap-northeast-2, or null to fall back to the provider default chain."
  }
}
variable "nvidia_cluster_name" {
  type        = string
  default     = "nvidia-cluster"
  description = "Name of the cluster without GPU time slicing. It is the control in the comparison: one physical GPU per node is advertised as one nvidia.com/gpu"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,99}$", var.nvidia_cluster_name))
    error_message = "nvidia_cluster_name must start with a letter or digit and contain only letters, digits, hyphens and underscores (100 characters or fewer)."
  }
}
variable "time_slicing_cluster_name" {
  type        = string
  default     = "nvidia-time-slicing-cluster"
  description = "Name of the cluster with GPU time slicing. Identical to the other one in every respect except the device plugin's configuration, which is the point of having two"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,99}$", var.time_slicing_cluster_name))
    error_message = "time_slicing_cluster_name must start with a letter or digit and contain only letters, digits, hyphens and underscores (100 characters or fewer)."
  }
  validation {
    # Two clusters in one VPC with one name would be a single cluster built twice, and the second create
    # call fails part way through an apply that has already made the first (rules.md B-1).
    condition     = var.time_slicing_cluster_name != var.nvidia_cluster_name
    error_message = "time_slicing_cluster_name must differ from nvidia_cluster_name - the two clusters share a VPC and a region, so the names are what tell them apart."
  }
}
variable "kubernetes_version" {
  type        = string
  default     = "1.34"
  description = "Kubernetes version for both clusters. One value, because a version difference between them would be a second variable in a comparison meant to have one"

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
  description = "Whether the clusters' API server endpoints are reachable from the internet. True as the _monolithic template had it, and needed because the helm and kubectl providers run on the machine executing terraform apply rather than inside the VPC (rules.md E-2). Narrow public_access_cidrs rather than leaving the default open"

  validation {
    # Pinned in the direction this variant depends on, with the alternative named (rules.md B-1/E-9).
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because the device plugin releases and every pod manifest are applied by the helm and kubectl providers from the machine running terraform. To run with private endpoints, apply them from the bastion through SSM Associations instead, as 041_eks_private_cluster does (rules.md E-9)."
  }
}
variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDR blocks allowed to reach the public API server endpoints. Set this to your own address in CIDR form: bootstrap_cluster_creator_admin_permissions means anyone who can reach an endpoint with a valid AWS credential for the creating principal has cluster-admin on that cluster"

  validation {
    condition     = alltrue([for cidr in var.public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "public_access_cidrs must contain valid IPv4 CIDR blocks."
  }
}
variable "key_name" {
  type        = string
  default     = "musicgen-key"
  description = "Name of the EC2 key pair created for the demo instance and shared by both clusters' node groups"

  validation {
    condition     = length(var.key_name) > 0
    error_message = "key_name must not be empty."
  }
}
variable "gpu_node_group_name" {
  type        = string
  default     = "gpu-nodegroup"
  description = "Name of the GPU node group on each cluster, as the _monolithic template named both. The same name on two different clusters is fine - a node group name is scoped to its cluster - and keeping them identical is what makes the comparison a comparison. The launch template beside each node group takes this only as the prefix of a generated name, because launch template names are scoped to the region instead: a fixed name derived from it is what made the second cluster's node group fail with InvalidLaunchTemplateName.AlreadyExistsException"

  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9_-]*)$", var.gpu_node_group_name))
    error_message = "gpu_node_group_name must start with a letter or digit and contain only letters, digits, hyphens and underscores."
  }
}
variable "gpu_ami_type" {
  type        = string
  default     = "AL2023_x86_64_NVIDIA"
  description = "AMI type for the GPU node groups, as the _monolithic template had it. This is what puts the NVIDIA driver and the container runtime hook on the node - a standard AL2023 AMI on a g4dn instance boots a node with a GPU the kernel can see and Kubernetes cannot, and the device plugin then advertises nothing while reporting no error"

  validation {
    condition = contains([
      "AL2023_x86_64_NVIDIA", "AL2023_ARM_64_NVIDIA",
      "BOTTLEROCKET_x86_64_NVIDIA", "BOTTLEROCKET_ARM_64_NVIDIA",
      "AL2_x86_64_GPU",
    ], var.gpu_ami_type)
    error_message = "gpu_ami_type must be one of the GPU-enabled EKS AMI types. A standard AMI on a GPU instance produces a node with an invisible GPU: the device plugin finds no driver, advertises nothing, and every pod requesting nvidia.com/gpu stays Pending with nothing explaining why."
  }
}
variable "gpu_instance_types" {
  type        = list(string)
  default     = ["g4dn.xlarge"]
  description = "Instance types for the GPU node groups, g4dn.xlarge as the _monolithic template had it - one NVIDIA T4 per instance, which is what makes the time-slicing comparison legible: one card, advertised once or four times"

  validation {
    condition     = length(var.gpu_instance_types) > 0
    error_message = "gpu_instance_types must contain at least one instance type."
  }
}
variable "gpu_node_group_desired_size" {
  type        = number
  default     = 2
  description = "Desired GPU node count per cluster, two as the _monolithic template had it. Worth knowing the cost: this is four GPU instances across the two clusters, running until the stack is destroyed"

  validation {
    condition     = var.gpu_node_group_desired_size >= 1
    error_message = "gpu_node_group_desired_size must be at least 1."
  }
}
variable "gpu_node_group_min_size" {
  type        = number
  default     = 2
  description = "Minimum GPU node count per cluster"

  validation {
    condition     = var.gpu_node_group_min_size >= 1
    error_message = "gpu_node_group_min_size must be at least 1."
  }
}
variable "gpu_node_group_max_size" {
  type        = number
  default     = 6
  description = "Maximum GPU node count per cluster, six as the _monolithic template had it. Nothing scales these node groups, so it is headroom for a manual resize - and on this instance type that headroom is expensive"

  validation {
    condition     = var.gpu_node_group_max_size >= 1
    error_message = "gpu_node_group_max_size must be at least 1."
  }
  validation {
    condition     = var.gpu_node_group_max_size >= var.gpu_node_group_min_size
    error_message = "gpu_node_group_max_size must be greater than or equal to gpu_node_group_min_size."
  }
}
variable "device_plugin_chart_version" {
  type        = string
  default     = "0.17.3"
  description = "Pinned nvidia-device-plugin chart version, used on both clusters. The _monolithic template installed whatever helm repo update produced at boot time, on each cluster separately - so the two halves of a comparison could have been running different plugin versions"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.device_plugin_chart_version))
    error_message = "device_plugin_chart_version must be a semantic version."
  }
}
variable "time_slicing_replicas" {
  type        = number
  default     = 4
  description = "How many slices each GPU is advertised as on the time-slicing cluster, four as the _monolithic template's config map had it. This one number is the entire difference between the two clusters: with it, four pods asking for a GPU each are scheduled onto one card and take turns on it; without it, the second pod stays Pending. Nothing is enforced by the slicing - the pods share the card's throughput and all of its memory, so four pods that each want most of the memory will fail rather than run slowly"

  validation {
    condition     = var.time_slicing_replicas >= 2
    error_message = "time_slicing_replicas must be at least 2. One slice per GPU is what the other cluster already demonstrates."
  }
}
variable "workload_namespace" {
  type        = string
  default     = "default"
  description = "Namespace the demo pods run in on both clusters, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.workload_namespace))
    error_message = "workload_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "app_image" {
  type        = string
  default     = "gabotechs/musicgpt:0.3.28"
  description = "Image for the application pod on both clusters. Pinned to a version tag, where the _monolithic template used the bare name gabotechs/musicgpt - docker.io's floating latest, for an image large enough (about 2.1 GB compressed) that the pull is the slowest part of the apply. 0.3.28 is the newest tag the image is published under and carried the same digest as latest when it was pinned. Check the tag list before changing it: a tag that does not exist passes plan, leaves the pods in ImagePullBackOff, and surfaces only after the provider's ten-minute rollout wait as \"musicgpt failed to rollout Deployment\" - which is what the previous default, 0.6.0, did"

  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$|@sha256:[0-9a-f]{64}$", var.app_image))
    error_message = "app_image must carry an explicit tag or a digest."
  }
}
variable "app_replicas_without_time_slicing" {
  type        = number
  default     = 1
  description = "How many application pods to run on the cluster without time slicing. One, because one GPU is one nvidia.com/gpu there and a second pod would stay Pending - which is worth trying once, since it is the failure the other cluster exists to remove"

  validation {
    condition     = var.app_replicas_without_time_slicing >= 1
    error_message = "app_replicas_without_time_slicing must be at least 1."
  }
}
variable "app_replicas_with_time_slicing" {
  type        = number
  default     = 2
  description = "How many application pods to run on the time-slicing cluster. Two, so more pods than there are physical GPUs per node are scheduled and share one - which is the thing to look at. Raising it towards the slice count shows how far the sharing goes before the card's memory rather than its schedule becomes the limit"

  validation {
    condition     = var.app_replicas_with_time_slicing >= 1
    error_message = "app_replicas_with_time_slicing must be at least 1."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = false
  description = "Whether the VS Code security group accepts traffic from 0.0.0.0/0 on the code-server port. False, where the _monolithic template defaulted to True: code-server has no authentication in front of it and its instance role is AdministratorAccess, in a project running four GPU instances. The IDE is reached through the SSM port forward in vscode_port_forward_command instead, which needs no inbound rule"
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
