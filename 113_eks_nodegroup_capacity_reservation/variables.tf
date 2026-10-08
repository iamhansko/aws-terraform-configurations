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
  default     = "gpu-node-cluster"
  description = "Name of the EKS cluster, and the basis for the VPC, key pair and node group names. The _monolithic template derived every name from a stack_name standing in for AWS::StackName"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,99}$", var.cluster_name))
    error_message = "cluster_name must start with a letter or digit and contain only letters, digits, hyphens and underscores (100 characters or fewer)."
  }
}
variable "kubernetes_version" {
  type        = string
  default     = "1.34"
  description = <<-DESC
    Kubernetes version for the EKS cluster. 1.34 rather than the _monolithic template's 1.36, matching the rest
    of this repository.

    It also decides which EKS-optimized NVIDIA AMI the GPU node group launches, because the SSM parameter path
    is built from it. That template hardcoded 1.36 into the path while taking the cluster version as a
    parameter - so choosing 1.34 there gave a 1.34 cluster with a 1.36 kubelet, which is outside the supported
    skew in the direction EKS does not allow at all.
  DESC

  validation {
    condition     = can(regex("^1\\.(3[0-9]|[4-9][0-9])$", var.kubernetes_version))
    error_message = "kubernetes_version must be a supported 1.XX version, e.g. 1.34."
  }
}
variable "kubectl_download_version" {
  type        = string
  default     = "1.34.11/2026-09-22"
  description = "Version path used to download kubectl onto the workbench, in <version>/<release-date> form. Raised together with kubernetes_version: kubectl more than one minor from the API server is outside the supported skew (rules.md H-1)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.34.11/2026-09-22."
  }
}
variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the EKS API server endpoint is reachable from the internet. True as the _monolithic template had it, and needed here: the helm provider that installs the load balancer controller runs on the machine executing terraform apply"

  validation {
    # Pinned in the direction this variant depends on, with the alternative named (rules.md B-1/E-9).
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because the AWS Load Balancer Controller is installed by the helm provider from the machine running terraform. To run with a private endpoint, install it from the workbench through an SSM Association instead, as 041_eks_private_cluster does (rules.md E-9)."
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
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC, as the _monolithic template had it"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block."
  }
}
variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "c"]
  description = "Zones the VPC spans, a and c as the _monolithic template's subnets used. Two is EKS's minimum; the GPU node group only uses one of them, because a capacity reservation is zonal"

  validation {
    condition     = length(var.availability_zone_suffixes) >= 2
    error_message = "availability_zone_suffixes must name at least two zones - EKS requires subnets in two."
  }
}
variable "gpu_availability_zone_suffix" {
  type        = string
  default     = "c"
  description = <<-DESC
    Zone the capacity reservation is made in, and therefore the only zone the GPU node group can place a node
    in. c, as the _monolithic template reserved.

    A reservation is zonal, so this is the one value that ties three things together: the reservation, the
    subnet the node group is given, and where the GPU actually appears. Naming a zone the VPC has no private
    subnet in leaves the node group with nowhere to launch.
  DESC

  validation {
    condition     = can(regex("^[a-z]$", var.gpu_availability_zone_suffix))
    error_message = "gpu_availability_zone_suffix must be a single lowercase letter."
  }
}
variable "key_name" {
  type        = string
  default     = null
  description = "Name of the EC2 key pair created for the workbench and attached to the nodes. Null derives it from cluster_name. The _monolithic template built it from a uuid standing in for AWS::StackId, which made it unique but unguessable when looking for the private key in SSM"

  validation {
    condition     = var.key_name == null || length(var.key_name) > 0
    error_message = "key_name must be a non-empty string, or null to derive it from cluster_name."
  }
}
variable "gpu_instance_type" {
  type        = string
  default     = "g4dn.xlarge"
  description = "Instance type reserved and launched, g4dn.xlarge as the _monolithic template had it. One value feeds the reservation and the launch template, because a reservation covers one exact type and a template asking for a different one cannot use it (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.gpu_instance_type))
    error_message = "gpu_instance_type must be a valid EC2 instance type, e.g. g4dn.xlarge."
  }
}
variable "gpu_reserved_instance_count" {
  type        = number
  default     = 1
  description = "Instances reserved, one as the _monolithic template reserved. With capacity-reservations-only this is the hard ceiling on the node group: it cannot launch more than this, whatever its scaling configuration says"

  validation {
    condition     = var.gpu_reserved_instance_count >= 1
    error_message = "gpu_reserved_instance_count must be at least 1."
  }
}
variable "gpu_node_desired_size" {
  type        = number
  default     = 1
  description = "GPU nodes to run, one as the _monolithic template had it. It has to be no larger than the reservation - with capacity-reservations-only the extra instances cannot launch, and the node group sits in a degraded state rather than failing outright"

  validation {
    condition     = var.gpu_node_desired_size >= 1
    error_message = "gpu_node_desired_size must be at least 1."
  }
}
variable "gpu_reservation_end_date" {
  type        = string
  default     = null
  description = <<-DESC
    When the capacity reservation expires, in RFC 3339 form. Null makes it open-ended, which is what the
    _monolithic template created.

    This is the cost worth knowing about: reserved capacity is billed from creation until the reservation is
    deleted, whether or not an instance occupies it. Scaling the node group to zero does not stop it. An
    end date is the only thing that stops an abandoned demo from charging for a GPU indefinitely.
  DESC

  validation {
    condition     = var.gpu_reservation_end_date == null || can(formatdate("YYYY-MM-DD", var.gpu_reservation_end_date))
    error_message = "gpu_reservation_end_date must be an RFC 3339 timestamp such as 2026-12-31T23:59:59Z, or null for an open-ended reservation."
  }
}
variable "gpu_node_labels" {
  type = map(string)
  default = {
    nodegroup = "gpu"
  }
  description = "Kubernetes labels on the GPU nodes, as the _monolithic template set them. Worth keeping: with one GPU node in a cluster of general-purpose ones, a nodeSelector on this label is how a workload lands on it rather than anywhere. The root merges nvidia.com/gpu.present = true into this before using it, because the device plugin's DaemonSet requires one of three labels and that is the one that does not need node-feature-discovery - so this variable holds the project's own labels only"

  validation {
    condition     = alltrue([for key in keys(var.gpu_node_labels) : length(key) > 0])
    error_message = "gpu_node_labels must not contain empty label keys."
  }
}
variable "gpu_node_update_strategy" {
  type        = string
  default     = "MINIMAL"
  description = <<-DESC
    How EKS replaces the GPU node when its launch template or AMI changes. MINIMAL as the _monolithic template
    set it, and the only value that works here.

    DEFAULT launches the replacement before draining the node it replaces, so it needs a free instance slot.
    This reservation holds exactly gpu_reserved_instance_count instances and the launch template is
    capacity-reservations-only, so there is no spare slot and no ordinary On-Demand capacity to fall back
    on - the replacement never launches and the node group update fails on capacity rather than on anything
    in this configuration. MINIMAL drains first, which frees the reserved slot for the replacement.

    Changing a label or the NodeConfig is a launch template change, so this is what makes the GPU node's
    labels editable at all after the first apply.
  DESC

  validation {
    condition     = contains(["DEFAULT", "MINIMAL"], var.gpu_node_update_strategy)
    error_message = "gpu_node_update_strategy must be DEFAULT or MINIMAL."
  }
  validation {
    # Pinned in the direction this variant needs, with the alternative named (rules.md B-1).
    condition     = var.gpu_node_update_strategy == "MINIMAL"
    error_message = "gpu_node_update_strategy must stay MINIMAL in this variant, because the GPU node group launches into a capacity reservation sized to exactly the number of nodes it runs. To use DEFAULT, raise gpu_reserved_instance_count above gpu_node_desired_size so a replacement node has a slot to launch into."
  }
}
variable "gpu_node_update_max_unavailable" {
  type        = number
  default     = 1
  description = "How many GPU nodes EKS takes out of service at once when it replaces them. One, which is also the whole node group - with the MINIMAL strategy that means the cluster has no capacity for the length of a node replacement, which is the price of being able to replace a node at all on a full reservation"

  validation {
    condition     = var.gpu_node_update_max_unavailable >= 1
    error_message = "gpu_node_update_max_unavailable must be at least 1."
  }
}
variable "nvidia_device_plugin_chart_version" {
  type        = string
  default     = "0.17.3"
  description = "Pinned nvidia-device-plugin chart version. The plugin is what advertises nvidia.com/gpu: the EKS-optimized AL2023 NVIDIA AMI carries the driver and the container toolkit but not this, so without it the node is Ready with a working GPU that no pod can request. Pinned because the node affinity terms a GPU node has to match belong to the chart version"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.nvidia_device_plugin_chart_version))
    error_message = "nvidia_device_plugin_chart_version must be a semantic version, e.g. 0.17.3."
  }
}
variable "nvidia_device_plugin_timeout_seconds" {
  type        = number
  default     = 600
  description = "How long to wait for the device plugin's DaemonSet to report ready. The pod pulls its image from a private subnet through the NAT gateway"

  validation {
    condition     = var.nvidia_device_plugin_timeout_seconds > 0
    error_message = "nvidia_device_plugin_timeout_seconds must be positive."
  }
}
variable "enable_gpu_feature_discovery" {
  type        = bool
  default     = false
  description = <<-DESC
    Whether the device plugin chart also installs GPU Feature Discovery, which labels nodes with the GPU
    model, driver version and memory.

    False, because this cluster runs one node of one reserved instance type and there is nothing to tell
    apart. The reason it is a variable rather than a constant is that GFD brings node-feature-discovery with
    it, and NFD sets feature.node.kubernetes.io/pci-10de.present - the first of the three node affinity terms
    the plugin's DaemonSet accepts. So turning this on is the alternative to labelling the node with
    nvidia.com/gpu.present, which is what this project does instead and what costs nothing extra to run.
  DESC
}
variable "service_ipv4_cidr" {
  type        = string
  default     = "172.20.0.0/16"
  description = "Service CIDR for the cluster, as the _monolithic template set it. It is repeated in the GPU node group's NodeConfig, because a node bootstrapped with the wrong service CIDR cannot resolve cluster DNS - one value feeds both (rules.md B-5)"

  validation {
    condition     = can(cidrhost(var.service_ipv4_cidr, 0))
    error_message = "service_ipv4_cidr must be a valid IPv4 CIDR block."
  }
}
variable "aws_load_balancer_controller_chart_version" {
  type        = string
  default     = "1.14.1"
  description = "Pinned aws-load-balancer-controller chart version. The _monolithic template installed it with a helm command in user data, after an \"exec bash\" line that discarded every remaining line - so on a real boot it was never installed, and the IAM role and Pod Identity association it created sat unused (rules.md E-1/H-1)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.aws_load_balancer_controller_chart_version))
    error_message = "aws_load_balancer_controller_chart_version must be a semantic version."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the workbench security group accepts traffic from 0.0.0.0/0 on the code-server port. True as the _monolithic template had it - a bool here where that template used a string validated against [\"True\", \"False\"], so \"true\" would have been rejected. code-server has no authentication in front of it"
}
variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "EC2 instance type for the workbench, as the _monolithic template had it. It investigates the cluster; the GPU work happens on the node group"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must be a valid EC2 instance type, e.g. t3.medium."
  }
}
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the workbench where the bootstrap drops its completion marker. The README association waits for that marker rather than using depends_on (rules.md D-5/H-2)"

  validation {
    condition     = var.marker_file_path == null || can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/', or null."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the README association may take. It first waits for the instance bootstrap, which downloads kubectl, eksctl and helm"

  validation {
    condition     = var.readme_timeout_seconds > 0
    error_message = "readme_timeout_seconds must be positive."
  }
}
