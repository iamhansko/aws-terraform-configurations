variable "cluster_name" {
  type        = string
  description = "Name of the cluster the node joins. Written into its NodeConfig and used for the access entry"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}

variable "cluster_endpoint" {
  type        = string
  description = "API server endpoint the kubelet connects to. A self-managed node is told this directly - there is no bootstrap script that describes the cluster first (rules.md B-5)"

  validation {
    condition     = can(regex("^https://", var.cluster_endpoint))
    error_message = "cluster_endpoint must be an https URL."
  }
}

variable "certificate_authority_data" {
  type        = string
  description = "Base64 cluster CA certificate, so the kubelet can verify the API server it is told to trust"

  validation {
    condition     = length(var.certificate_authority_data) > 0
    error_message = "certificate_authority_data must not be empty."
  }
}

variable "service_ipv4_cidr" {
  type        = string
  description = "The cluster's Service CIDR, taken from the cluster rather than restated. nodeadm writes it into the kubelet's configuration, and a value that disagrees with the cluster produces a node that joins and pods that cannot reach any Service (rules.md B-5)"

  validation {
    condition     = can(cidrhost(var.service_ipv4_cidr, 0))
    error_message = "service_ipv4_cidr must be a valid IPv4 CIDR block."
  }
}

variable "cluster_dns_ip" {
  type        = string
  description = "Address of the cluster DNS Service, derived by the cluster module from its Service CIDR. A wrong value here produces a node that is Ready and pods that resolve nothing"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$", var.cluster_dns_ip))
    error_message = "cluster_dns_ip must be an IPv4 address."
  }
}

variable "subnet_id" {
  type        = string
  description = "Subnet the node is launched in. A private subnet: it reaches the API server and pulls images through the NAT gateway, and nothing outside the VPC has a reason to reach it"

  validation {
    condition     = can(regex("^subnet-[0-9a-f]+$", var.subnet_id))
    error_message = "subnet_id must be a valid subnet ID (e.g. subnet-0123456789abcdef0)."
  }
}

variable "vpc_security_group_ids" {
  type        = list(string)
  description = "Security groups on the node. The cluster security group has to be among them, or the kubelet cannot reach the API server and the control plane cannot reach the kubelet (rules.md B-6)"

  validation {
    condition     = length(var.vpc_security_group_ids) > 0 && alltrue([for id in var.vpc_security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "vpc_security_group_ids must contain at least one valid security group ID (e.g. sg-0123456789abcdef0)."
  }
}

variable "key_name" {
  type        = string
  default     = null
  description = "EC2 key pair for SSH access. Null leaves the node without one, which is fine when Session Manager is the way in"
}

variable "name" {
  type        = string
  default     = "self-managed-node"
  description = "Name tag of the instance, and the prefix of its IAM role and instance profile names"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$", var.name))
    error_message = "name must start with a letter or digit and contain only letters, digits and hyphens."
  }
}

variable "instance_type" {
  type        = string
  default     = "t3.large"
  description = "Instance type, as the _monolithic template sized it. The size also decides how many pod ENIs the node can carry, which is the other half of max_pods"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must look like an EC2 instance type (e.g. t3.large)."
  }
}

variable "ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/eks/optimized-ami/1.34/amazon-linux-2023/x86_64/standard/recommended/image_id"
  description = "SSM public parameter naming the EKS-optimized AMI. The Kubernetes version is part of the path, so it has to be kept in step with the cluster's version - a node more than one minor behind the control plane is outside the supported skew"

  validation {
    condition     = can(regex("^/aws/service/eks/optimized-ami/1\\.[0-9]+/", var.ami_ssm_parameter_name))
    error_message = "ami_ssm_parameter_name must be an EKS optimized AMI parameter path, which carries the Kubernetes version in it (/aws/service/eks/optimized-ami/1.XX/...)."
  }
}

variable "root_volume_size" {
  type        = number
  default     = 30
  description = "Root volume size in GiB. Container images accumulate here, and a full disk shows up as the kubelet evicting pods rather than as a disk error"

  validation {
    condition     = var.root_volume_size >= 20
    error_message = "root_volume_size must be at least 20 GiB."
  }
}

variable "max_pods" {
  type        = number
  default     = 110
  description = "Pods the kubelet will accept, as the _monolithic template set it. Not free: with the default CNI each pod takes an ENI address, and a number larger than the instance can supply produces pods stuck in ContainerCreating with no IP - which is what ENABLE_MULTI_NIC on the vpc-cni addon raises the ceiling for"

  validation {
    condition     = var.max_pods > 0
    error_message = "max_pods must be greater than zero."
  }
}

variable "instance_metadata_http_put_response_hop_limit" {
  type        = number
  default     = 2
  description = "IMDS hop limit. Two rather than one, so a process inside a container can still reach the metadata service"

  validation {
    condition     = var.instance_metadata_http_put_response_hop_limit >= 1 && var.instance_metadata_http_put_response_hop_limit <= 64
    error_message = "instance_metadata_http_put_response_hop_limit must be between 1 and 64."
  }
}

variable "node_iam_policy_arns" {
  type = list(string)
  default = [
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]
  description = "Managed policies on the node role, as the _monolithic template attached them. All four are load-bearing: the worker policy to describe the cluster, ECR read to pull images, the CNI policy to attach pod addresses, and SSM to make the node reachable without SSH"

  validation {
    condition     = alltrue([for arn in var.node_iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "node_iam_policy_arns must contain valid IAM policy ARNs."
  }
}

variable "additional_user_data" {
  type        = string
  default     = "dnf update -yq\n"
  description = "Shell script appended as the second MIME part of the node's user data, after the NodeConfig. The _monolithic template ran a yum update and set the timezone here"
}
