variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.). Both VPCs, the service network and the endpoint are all in it - VPC Lattice can span regions, but this project does not"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region such as ap-northeast-2, or null to fall back to the provider default chain."
  }
}
variable "cluster_name" {
  type        = string
  default     = "private-api-server"
  description = "Name of the EKS cluster, and the basis for both VPCs, the key pair, the Lattice resources and their security groups. The _monolithic template named the Lattice resources literally - eks-cluster-vpc-resource-gateway, resource-gateway-sg, eks-api-server, eks-service-network, vpc-lattice-sne-sg - so two copies in one account would have collided on all five"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}$", var.cluster_name))
    error_message = "cluster_name must be 2-31 characters of lowercase letters, digits and hyphens, short enough to leave room for the per-resource suffixes."
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
  description = "Version path used to download kubectl onto the workbench, in <version>/<release-date> form (rules.md H-1)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.34.11/2026-09-22."
  }
}
variable "endpoint_public_access" {
  type        = bool
  default     = false
  description = <<-DESC
    Whether the EKS API server endpoint is reachable from the internet. False, as the _monolithic template had
    it, and the reason this project exists: everything else here - the resource gateway, the resource
    configuration, the service network, the endpoint and the private hosted zone - is there to reach a private
    endpoint from another VPC.

    Turning it on would make all of that unnecessary and remove the only thing the project demonstrates, which
    is why the validation pins it (rules.md B-1/E-9).
  DESC

  validation {
    condition     = var.endpoint_public_access == false
    error_message = "endpoint_public_access must stay false in this variant. The VPC Lattice resource gateway, resource configuration, service network and endpoint exist only to reach a private API server from a second VPC - with a public endpoint the client could reach it directly and none of them would be needed (rules.md E-9)."
  }
}
variable "cluster_vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the cluster's VPC, as the _monolithic template had it"

  validation {
    condition     = can(cidrhost(var.cluster_vpc_cidr_block, 0))
    error_message = "cluster_vpc_cidr_block must be a valid IPv4 CIDR block."
  }
}
variable "client_vpc_cidr_block" {
  type        = string
  default     = "192.168.0.0/16"
  description = "CIDR block for the client VPC. It must not overlap the cluster's - not because the two are routed to each other, which is precisely what Lattice avoids, but because a client resolving the API server's name to an address inside its own range would never leave the VPC"

  validation {
    condition     = can(cidrhost(var.client_vpc_cidr_block, 0))
    error_message = "client_vpc_cidr_block must be a valid IPv4 CIDR block."
  }
}
variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "c"]
  description = "Zones both VPCs span, a and c as the _monolithic template had them. Two is the minimum for EKS, for a resource gateway and for a VPC endpoint - all three"

  validation {
    condition     = length(var.availability_zone_suffixes) >= 2
    error_message = "availability_zone_suffixes must name at least two zones: EKS, the Lattice resource gateway and the VPC endpoint each require interfaces in two."
  }
}
variable "key_name" {
  type        = string
  default     = null
  description = "Name of the EC2 key pair created for the workbench and attached to the nodes. Null derives it from cluster_name"

  validation {
    condition     = var.key_name == null || length(var.key_name) > 0
    error_message = "key_name must be a non-empty string, or null to derive it from cluster_name."
  }
}
variable "node_group_instance_types" {
  type        = list(string)
  default     = ["t3.medium"]
  description = "Instance types for the managed node group, t3.medium as the _monolithic template had it"

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "node_group_instance_types must contain at least one instance type."
  }
}
variable "node_group_desired_size" {
  type        = number
  default     = 2
  description = "Desired node count, two as the _monolithic template had it"

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
  description = "Maximum node count, four as the _monolithic template had it"

  validation {
    condition     = var.node_group_max_size >= 1
    error_message = "node_group_max_size must be at least 1."
  }
  validation {
    condition     = var.node_group_max_size >= var.node_group_min_size
    error_message = "node_group_max_size must be greater than or equal to node_group_min_size."
  }
}
variable "lattice_port_ranges" {
  type        = list(string)
  default     = ["443"]
  description = "Ports the resource configuration forwards to the API server. The _monolithic template opened 1-65535 on a resource that serves one port - a resource configuration is what decides what a client on the other side can reach, so the width of it matters"

  validation {
    condition     = length(var.lattice_port_ranges) > 0
    error_message = "lattice_port_ranges must contain at least one port or range."
  }
}
variable "create_private_hosted_zone" {
  type        = bool
  default     = true
  description = <<-DESC
    Whether to create the private hosted zone that makes the cluster's own API server hostname resolve to the
    Lattice endpoint inside the client VPC.

    True, and it is what makes the arrangement usable rather than merely working: the client resolves the real
    endpoint name, so the certificate the API server presents matches and a kubeconfig written by
    aws eks update-kubeconfig needs no editing.

    False leaves a healthy endpoint that kubectl cannot use - it would have to target the endpoint's own DNS
    name, and TLS verification then fails on the name mismatch. Worth setting once to see that the failure reads
    as a certificate problem rather than a DNS one (rules.md B-4).
  DESC
}
variable "allowed_endpoint_ingress_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "Extra CIDR blocks allowed to reach the Lattice endpoint on 443, beyond the client VPC's own. Empty by default, as the _monolithic template had it: anything that reaches this endpoint reaches the cluster's API server"

  validation {
    condition     = alltrue([for cidr in var.allowed_endpoint_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "allowed_endpoint_ingress_cidr_blocks must contain valid IPv4 CIDR blocks."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the workbench security group accepts traffic from 0.0.0.0/0 on the code-server port. True as the _monolithic template had it - a bool here where that template used a string validated against [\"True\", \"False\"]. code-server has no authentication in front of it"
}
variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "EC2 instance type for the workbench, as the _monolithic template had it. It sits in the client VPC, which is the whole demonstration: it has no route to the cluster's network and reaches the API server through the Lattice endpoint"

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
  description = "How long the README association may take. It first waits for the instance bootstrap, which downloads kubectl and helm"

  validation {
    condition     = var.readme_timeout_seconds > 0
    error_message = "readme_timeout_seconds must be positive."
  }
}
