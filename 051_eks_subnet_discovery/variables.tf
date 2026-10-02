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
  default     = "subnet-discovery-cluster"
  description = "Name of the EKS cluster"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,99}$", var.cluster_name))
    error_message = "cluster_name must start with a letter or digit and contain only letters, digits, hyphens and underscores (100 characters or fewer)."
  }
}
variable "kubernetes_version" {
  type        = string
  default     = "1.33"
  description = "Kubernetes version for the EKS cluster. Enhanced subnet discovery needs 1.25 or later on the control plane side, and a vpc-cni addon of 1.18.0 or later on the other"

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
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "Primary CIDR block of the VPC. Deliberately roomy: the point of this project is not that the VPC is short of address space, but that the subnets the nodes sit in are - which is the shape a real cluster ends up in years after the subnets were sized"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
}
variable "subnet_prefix_length" {
  type        = number
  default     = 28
  description = "Prefix length of the four primary subnets. 28 - eleven usable addresses each, after the five AWS reserves - as the _monolithic template had it, and the reason the demo shows anything: the VPC CNI only looks for another subnet once a node's own subnet has nothing left to give. Every other project in this repository leaves this at the module's default of 24"

  validation {
    condition     = var.subnet_prefix_length >= 16 && var.subnet_prefix_length <= 28
    error_message = "subnet_prefix_length must be between 16 and 28."
  }
  validation {
    # Cross-variable, available since Terraform 1.9 (rules.md B-1). Neither value is
    # wrong alone - a /24 subnet is ordinary and 50 pods is ordinary - but together they
    # produce an apply that succeeds and demonstrates nothing, because no subnet ever
    # runs dry and the CNI never consults the tagged ones. That failure is invisible:
    # every pod is Running, just with an address from the subnet it would have used
    # anyway.
    #
    # Conservative on purpose: every pod needs one address from somewhere, so if a
    # zone's share of the pods already outnumbers its subnet's usable addresses,
    # exhaustion is certain. The nodes' own addresses only make it more so.
    condition     = (pow(2, 32 - var.subnet_prefix_length) - 5) < (var.inflate_replicas / length(var.availability_zone_suffixes))
    error_message = "subnet_prefix_length leaves the primary subnets with more usable addresses than the pods in one Availability Zone will ask for, so they never run out and enhanced subnet discovery is never exercised - the apply succeeds and proves nothing. Either shorten it (28 gives 11 usable addresses) or raise inflate_replicas until a zone's share exceeds what one subnet holds."
  }
}
variable "secondary_cidr_block" {
  type        = string
  default     = "100.64.0.0/16"
  description = "CIDR block added to the VPC as a secondary range and carved into the tagged subnets. 100.64.0.0/10 is the CG-NAT range AWS recommends for this, and this default differs from the _monolithic template on purpose: that used 100.0.0.0/16, which is real, routable, allocated address space belonging to somebody else. AWS accepts it - a secondary block only has to be non-overlapping and outside a different RFC 1918 range than the primary - so nothing complains, and the VPC simply loses the ability to ever reach those hosts"

  validation {
    condition     = can(cidrhost(var.secondary_cidr_block, 0))
    error_message = "secondary_cidr_block must be a valid IPv4 CIDR block (e.g. 100.64.0.0/16)."
  }
}
variable "cni_subnet_prefix_length" {
  type        = number
  default     = 24
  description = "Prefix length of each tagged subnet carved out of secondary_cidr_block. 24 gives 251 usable addresses, against the 11 in the primary subnets - the asymmetry is the point, since the CNI prefers whichever discovered subnet has the most free addresses"

  validation {
    condition     = var.cni_subnet_prefix_length >= 16 && var.cni_subnet_prefix_length <= 28
    error_message = "cni_subnet_prefix_length must be between 16 and 28."
  }
}
variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "b"]
  description = "AZ letters this project spans. The network module names its subnets a and b individually rather than generating them from a list (rules.md C-3), so this does not create primary subnets - it states which zones exist, so the tagged subnets can be matched to them and to the nodes in them. The CNI only considers a tagged subnet in the same zone as the node, which is what makes the pairing matter"

  validation {
    condition     = length(var.availability_zone_suffixes) >= 2
    error_message = "availability_zone_suffixes must contain at least two AZ letters; EKS places its control plane endpoints in two or more Availability Zones."
  }
  validation {
    condition     = alltrue([for suffix in var.availability_zone_suffixes : can(regex("^[a-z]$", suffix))])
    error_message = "availability_zone_suffixes must contain single lowercase letters (e.g. [\"a\", \"b\"])."
  }
  validation {
    # The network module builds public_subnet_a/b and private_subnet_a/b as named
    # resources, so a third letter here would tag a subnet in a zone that has no nodes
    # to use it - discovered, correctly routed, and never touched.
    condition     = length(setsubtract(var.availability_zone_suffixes, ["a", "b"])) == 0
    error_message = "availability_zone_suffixes must be a subset of [\"a\", \"b\"], the zones the network module creates subnets in. Adding a zone means extending that module with a third pair of subnets and a third NAT gateway first; a tagged subnet in a zone with no nodes is never used."
  }
}
variable "enable_subnet_discovery" {
  type        = bool
  default     = true
  description = "Whether the VPC CNI allocates pod addresses from every tagged subnet in the node's zone rather than only from the node's own subnet. Rendered into the vpc-cni addon's configuration_values as the ENABLE_SUBNET_DISCOVERY environment variable, replacing a 'kubectl set env daemonset aws-node' step (rules.md E-5). It is the default in vpc-cni 1.18.0 and later, so this is set explicitly to make the demo's dependency visible rather than to change behaviour"

  validation {
    # Pinned in the direction the project depends on (rules.md B-1). With it off the
    # tagged subnets are still created and still carry the tag, the apply still
    # succeeds, and pods simply stop getting addresses once the /28s are full - which
    # reads as a broken cluster rather than a switch that was turned off.
    condition     = var.enable_subnet_discovery
    error_message = "enable_subnet_discovery must stay true in this variant; it is the only thing the project demonstrates. With it false the tagged subnets are ignored and the pressure workload's pods sit in ContainerCreating with no address, which is the failure the feature exists to fix rather than a useful comparison. To see that failure deliberately, apply with it true and then run 'kubectl set env daemonset aws-node -n kube-system ENABLE_SUBNET_DISCOVERY=false -c aws-node' - the next apply puts it back."
  }
}
variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the EKS API server endpoint is reachable from the internet. True because the kubectl provider runs on the machine executing terraform apply rather than inside the VPC (rules.md E-1/E-2); the _monolithic template had this true as well, driving the same objects from an SSM Association on the bastion. Narrow public_access_cidrs rather than leaving the default open"

  validation {
    # Pinned in the direction this variant actually depends on. The two forms fail
    # differently and the SSM alternative is E-9's, so the choice is recorded rather
    # than left implicit (rules.md B-1/E-9).
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because its Kubernetes objects are applied by the kubectl provider from the machine running terraform. To run with a private endpoint, apply them from the bastion through an SSM Association instead, as 041_eks_private_cluster does (rules.md E-9)."
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
  default     = "subnet-discovery-key"
  description = "Name of the EC2 key pair created for the demo instance"

  validation {
    condition     = length(var.key_name) > 0
    error_message = "key_name must not be empty."
  }
}
variable "node_group_instance_types" {
  type        = list(string)
  default     = ["t3.medium"]
  description = "Instance types for the managed node group. The instance type is also what caps pods per node - a t3.medium supports three interfaces of six addresses each, so seventeen pods - which is why the node count below is what it is"

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "node_group_instance_types must contain at least one instance type."
  }
}
variable "node_group_desired_size" {
  type        = number
  default     = 4
  description = "Desired node count, four as the _monolithic template had it. Not arbitrary: a t3.medium holds seventeen pods, two of which are the vpc-cni and kube-proxy DaemonSets, so four nodes are needed to place fifty pressure pods alongside CoreDNS. Three would leave pods Pending on capacity, which looks exactly like the address exhaustion this demo is trying to show"

  validation {
    condition     = var.node_group_desired_size >= 1
    error_message = "node_group_desired_size must be at least 1."
  }
}
variable "node_group_min_size" {
  type        = number
  default     = 4
  description = "Minimum node count"

  validation {
    condition     = var.node_group_min_size >= 1
    error_message = "node_group_min_size must be at least 1."
  }
}
variable "node_group_max_size" {
  type        = number
  default     = 12
  description = "Maximum node count, twelve as the _monolithic template had it. Nothing scales the node group here, so this is only headroom for a manual resize"

  validation {
    condition     = var.node_group_max_size >= var.node_group_min_size
    error_message = "node_group_max_size must be greater than or equal to node_group_min_size."
  }
}
variable "inflate_replicas" {
  type        = number
  default     = 50
  description = "How many pressure pods to run, fifty as the _monolithic template had it. This is the demo's dial: each pod holds one VPC address, so this is what empties the primary subnets and gives the CNI a reason to use the tagged ones. Raise it with terraform apply rather than kubectl scale, so the value lives in state instead of being undone by the next apply (rules.md B-4)"

  validation {
    condition     = var.inflate_replicas >= 0
    error_message = "inflate_replicas must be zero or greater."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the VS Code security group accepts traffic from 0.0.0.0/0 on the code-server port. True as the _monolithic template had it, because code-server is reached from a browser - but it runs with authentication disabled, so narrow this to your own address where possible"
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
