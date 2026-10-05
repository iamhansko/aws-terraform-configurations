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
  default     = "eks-self-managed-node"
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
  description = "CIDR block of the VPC. The pod addresses come out of it too under the default CNI, which is what makes address exhaustion a real limit on this cluster rather than a theoretical one"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block."
  }
}

variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "c"]
  description = "Availability zones the VPC spans, by suffix. Two - a and c - exactly the pair the _monolithic template's AzMapping defined"

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
  description = "Name of the EKS cluster. Written into the self-managed node's NodeConfig, which is how the node knows what to join"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,99}$", var.cluster_name))
    error_message = "cluster_name must start with a letter or digit and contain only letters, digits, hyphens and underscores."
  }
}

variable "kubernetes_version" {
  type        = string
  default     = "1.34"
  description = "EKS cluster Kubernetes version. It has to agree with the version in node_ami_ssm_parameter_name: a self-managed node picks its AMI by that path, and nothing checks the two against each other"

  validation {
    condition     = can(regex("^1\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must look like 1.XX; the cluster module holds the list of versions this project is verified against."
  }
}

variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the cluster's API server has a public endpoint. True here, and pinned true, because the demo workload and the controller's Helm release are applied by providers running on the machine executing terraform"

  validation {
    # Not a free choice: this root declares kubectl and helm providers, and those run wherever
    # terraform runs. With a private-only endpoint they cannot connect, plan still passes, and
    # the failure appears mid-apply as a dial timeout that looks exactly like the
    # destroy-ordering problem rules.md D-4 describes (rules.md E-9).
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because its manifests and Helm release are applied by providers running on the machine executing terraform. To run with a private endpoint, drop those providers and apply everything from the workbench through SSM Associations instead, as 041_eks_private_cluster does."
  }
}

variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDRs allowed to reach the public API server endpoint. Narrow this for anything longer lived than a demo"

  validation {
    condition     = alltrue([for cidr in var.public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "public_access_cidrs must contain valid IPv4 CIDR blocks."
  }
}

variable "service_ipv4_cidr" {
  type        = string
  default     = "172.20.0.0/16"
  description = "CIDR the cluster allocates Service addresses from. Stated explicitly here, unlike most projects, because the self-managed node's NodeConfig carries this block and the DNS address derived from it - both flow from the cluster module's outputs so they cannot disagree (rules.md B-5)"

  validation {
    condition     = can(cidrhost(var.service_ipv4_cidr, 0))
    error_message = "service_ipv4_cidr must be a valid IPv4 CIDR block."
  }
}

variable "coredns_replica_count" {
  type        = number
  default     = 2
  description = "Number of CoreDNS replicas. Two on a single-node cluster means two pods that cannot be spread, which is worth knowing when counting what fits"

  validation {
    condition     = var.coredns_replica_count >= 1
    error_message = "coredns_replica_count must be at least 1."
  }
}

variable "vpc_cni_env" {
  type = map(string)
  default = {
    ENABLE_MULTI_NIC = "true"
  }
  description = <<-DESC
    Environment variables set on the vpc-cni DaemonSet, as the _monolithic template set them.

    ENABLE_MULTI_NIC is what this variant needs: the default CNI gives each pod an address from a network
    interface on the node, and the number of interfaces an instance type may have is the real ceiling on
    max_pods. With it on, the CNI attaches additional interfaces, so a t3.large can carry closer to the 110
    pods the NodeConfig asks for instead of running out of addresses well before that.

    The values are strings because the addon's configuration schema declares them that way - an EKS addon
    configuration value is the opposite of a Helm value in this respect (rules.md E-5/E-7).
  DESC

  validation {
    condition     = alltrue([for key in keys(var.vpc_cni_env) : can(regex("^[A-Z][A-Z0-9_]*$", key))])
    error_message = "vpc_cni_env keys are environment variable names, so each must be uppercase letters, digits and underscores."
  }
}

# --- The self-managed node ---

variable "node_instance_type" {
  type        = string
  default     = "t3.large"
  description = "Instance type of the self-managed node, as the _monolithic template sized it"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.node_instance_type))
    error_message = "node_instance_type must look like an EC2 instance type (e.g. t3.large)."
  }
}

variable "node_ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/eks/optimized-ami/1.34/amazon-linux-2023/x86_64/standard/recommended/image_id"
  description = "SSM parameter naming the EKS-optimized AMI. The Kubernetes version is in the path and has to match kubernetes_version - nothing validates the pair, and a node more than one minor behind the control plane is outside the supported skew"

  validation {
    condition     = can(regex("^/aws/service/eks/optimized-ami/1\\.[0-9]+/", var.node_ami_ssm_parameter_name))
    error_message = "node_ami_ssm_parameter_name must be an EKS optimized AMI parameter path (/aws/service/eks/optimized-ami/1.XX/...)."
  }
}

variable "node_max_pods" {
  type        = number
  default     = 110
  description = "Pods the node's kubelet will accept, as the _monolithic template set it. Only reachable because vpc_cni_env turns on ENABLE_MULTI_NIC; without it the node runs out of addresses first and the extra pods stay in ContainerCreating"

  validation {
    condition     = var.node_max_pods > 0
    error_message = "node_max_pods must be greater than zero."
  }
}

variable "node_timezone" {
  type        = string
  default     = "Asia/Seoul"
  description = "Timezone set on the node, as the _monolithic template set it. Cosmetic, and it is what makes journalctl timestamps line up with the person reading them"

  validation {
    condition     = length(var.node_timezone) > 0
    error_message = "node_timezone must not be empty."
  }
}

# --- AWS Load Balancer Controller ---

variable "load_balancer_controller_chart_version" {
  type        = string
  default     = "1.14.1"
  description = "Pinned aws-load-balancer-controller chart version. The _monolithic template ran `helm install` with no --version and no --wait from an SSM Association, so a failed release was invisible"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.load_balancer_controller_chart_version))
    error_message = "load_balancer_controller_chart_version must be a three-part semantic version."
  }
}

# --- Demo workload ---

variable "workload_replicas" {
  type        = number
  default     = 10
  description = "Replicas of the nginx Deployment, as the _monolithic template created. On a single-node cluster this is the demonstration: at some point the next pod does not fit, and which limit it hit is what the pending-pods command shows"

  validation {
    condition     = var.workload_replicas >= 1
    error_message = "workload_replicas must be at least 1."
  }
}

variable "workload_image" {
  type        = string
  default     = "public.ecr.aws/nginx/nginx:1.29"
  description = "Image the demo pods run. Tagged and from ECR Public, where the _monolithic template used a bare \"nginx\" - untagged, and pulled from Docker Hub through a shared NAT address that anonymous rate limits apply to"

  validation {
    condition     = can(regex(":", var.workload_image))
    error_message = "workload_image must carry an explicit tag."
  }
}

# --- Workbench instance ---

variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type of the code-server workbench"

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
  description = "kubectl build downloaded onto the workbench, as <version>/<release-date>. Kept within one minor of kubernetes_version"

  validation {
    condition     = can(regex("^1\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.34.11/2026-09-22."
  }
}

variable "code_server_version" {
  type        = string
  default     = "4.108.2"
  description = "code-server release installed on the workbench"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a three-part semantic version."
  }
}

variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the workbench where each bootstrap stage drops its completion marker (rules.md D-5)"

  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/'."
  }
}

variable "readme_timeout_seconds" {
  type        = number
  default     = 1800
  description = "How long the README association waits for success"

  validation {
    condition     = var.readme_timeout_seconds >= 300
    error_message = "readme_timeout_seconds must be at least 300."
  }
}
