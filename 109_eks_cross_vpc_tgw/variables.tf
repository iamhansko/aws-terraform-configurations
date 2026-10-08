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
  default     = "eks-cross-vpc"
  description = "Prefix for resource names that have to be unique inside the account, and the title of the README written onto each workbench"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 3-32 lowercase letters, digits or hyphens and must not start or end with a hyphen."
  }
}

# --- Networks ---
#
# The CIDRs are variables rather than a mapping inside a module, because both VPCs have to know
# the other's primary block: it is the destination of every peer route. Keeping them here means one
# value reaches both, and neither module has to depend on the other (which would be a cycle).

variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "c"]
  description = "Availability zones both VPCs span, by suffix. Two - a and c - exactly the pair the _monolithic template's AzMapping defined"

  validation {
    condition     = length(var.availability_zone_suffixes) >= 2
    error_message = "availability_zone_suffixes must name at least two zones; an EKS control plane requires subnets in two, and so does an ALB."
  }
}

variable "vpc_a_cidr_block" {
  type        = string
  default     = "192.168.16.0/20"
  description = "Primary CIDR of VPC A. Routable across the transit gateway, so it must not overlap VPC B's"

  validation {
    condition     = can(cidrhost(var.vpc_a_cidr_block, 0))
    error_message = "vpc_a_cidr_block must be a valid IPv4 CIDR block."
  }
}

variable "vpc_b_cidr_block" {
  type        = string
  default     = "192.168.32.0/20"
  description = "Primary CIDR of VPC B"

  validation {
    condition     = can(cidrhost(var.vpc_b_cidr_block, 0))
    error_message = "vpc_b_cidr_block must be a valid IPv4 CIDR block."
  }

  validation {
    # Two overlapping primary blocks is not an error anything reports - it is a transit gateway
    # route table with two routes for the same destination, and traffic that goes to whichever one
    # is more specific (rules.md B-1).
    condition     = cidrhost(var.vpc_b_cidr_block, 0) != cidrhost(var.vpc_a_cidr_block, 0)
    error_message = "vpc_b_cidr_block must not start at the same address as vpc_a_cidr_block. Two routable blocks that overlap cannot both be reached through one transit gateway route table, and nothing reports the conflict."
  }
}

variable "secondary_cidr_block" {
  type        = string
  default     = "100.64.0.0/16"
  description = "Non-routable CIDR both VPCs attach as a secondary block, which their cluster and node tiers come out of. The same block in both on purpose: it is never routed, and the private NAT gateways translate out of it"

  validation {
    condition     = can(cidrhost(var.secondary_cidr_block, 0))
    error_message = "secondary_cidr_block must be a valid IPv4 CIDR block."
  }
}

variable "vpc_a_public_subnet_cidr_blocks" {
  type = map(string)
  default = {
    a = "192.168.16.0/24"
    c = "192.168.18.0/24"
  }
  description = "VPC A's public subnets per zone, as the _monolithic template's VpcAAzMapping had them"
}

variable "vpc_a_private_subnet_cidr_blocks" {
  type = map(string)
  default = {
    a = "192.168.17.0/24"
    c = "192.168.19.0/24"
  }
  description = "VPC A's private subnets per zone"
}

variable "vpc_b_public_subnet_cidr_blocks" {
  type = map(string)
  default = {
    a = "192.168.32.0/24"
    c = "192.168.34.0/24"
  }
  description = "VPC B's public subnets per zone, as the _monolithic template's VpcBAzMapping had them"
}

variable "vpc_b_private_subnet_cidr_blocks" {
  type = map(string)
  default = {
    a = "192.168.33.0/24"
    c = "192.168.35.0/24"
  }
  description = "VPC B's private subnets per zone"
}

variable "cluster_subnet_cidr_blocks" {
  type = map(string)
  default = {
    a = "100.64.1.0/28"
    c = "100.64.2.0/28"
  }
  description = "Cluster subnets per zone, out of the non-routable block, as the _monolithic template's NonRoutableAzMapping had them. The same values in both VPCs, which is only possible because the block is not routed. A /28 is enough: only the control plane's cross-account ENIs go here"
}

variable "node_subnet_cidr_blocks" {
  type = map(string)
  default = {
    a = "100.64.16.0/20"
    c = "100.64.32.0/20"
  }
  description = "Node subnets per zone, out of the non-routable block. A /20 per zone is 4096 addresses that cost nothing routable, which is the reason this design exists"
}

# --- EKS clusters ---

variable "kubernetes_version" {
  type        = string
  default     = "1.34"
  description = "Kubernetes version for both clusters. Keep kubectl_download_version within one minor of it"

  validation {
    condition     = can(regex("^1\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must look like 1.XX; the cluster module holds the list of versions this project is verified against."
  }
}

variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the clusters' API servers have public endpoints. True here, and pinned true, because the workload manifests and both Helm releases are applied by providers running on the machine executing terraform"

  validation {
    # Not a free choice: this root declares kubectl and helm providers, and those run wherever
    # terraform runs. With private-only endpoints they cannot connect, plan still passes, and the
    # failure appears mid-apply as a dial timeout that looks exactly like the destroy-ordering
    # problem rules.md D-4 describes (rules.md E-9).
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because its manifests and Helm releases are applied by providers running on the machine executing terraform. To run with private endpoints, drop those providers and apply everything from each workbench through SSM Associations instead, as 041_eks_private_cluster does."
  }
}

variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDRs allowed to reach the public API server endpoints. Narrow this for anything longer lived than a demo"

  validation {
    condition     = alltrue([for cidr in var.public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "public_access_cidrs must contain valid IPv4 CIDR blocks."
  }
}

variable "coredns_replica_count" {
  type        = number
  default     = 2
  description = "CoreDNS replicas in each cluster"

  validation {
    condition     = var.coredns_replica_count >= 1
    error_message = "coredns_replica_count must be at least 1."
  }
}

# --- Node groups ---

variable "node_group_name" {
  type        = string
  default     = "core"
  description = "Name of each cluster's managed node group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,62}$", var.node_group_name))
    error_message = "node_group_name must start with a letter or digit and contain only letters, digits, hyphens and underscores."
  }
}

variable "node_instance_types" {
  type        = list(string)
  default     = ["t3.medium"]
  description = "Instance types for both node groups"

  validation {
    condition     = length(var.node_instance_types) > 0
    error_message = "node_instance_types must contain at least one instance type."
  }
}

variable "node_desired_size" {
  type        = number
  default     = 2
  description = "Desired node count in each cluster"

  validation {
    condition     = var.node_desired_size >= 1
    error_message = "node_desired_size must be at least 1."
  }
}

variable "node_min_size" {
  type        = number
  default     = 2
  description = "Minimum node count in each cluster"

  validation {
    condition     = var.node_min_size >= 1
    error_message = "node_min_size must be at least 1."
  }
}

variable "node_max_size" {
  type        = number
  default     = 4
  description = "Maximum node count in each cluster"

  validation {
    condition     = var.node_max_size >= 1
    error_message = "node_max_size must be at least 1."
  }
}

# --- Load balancers and the workload ---

variable "load_balancer_controller_chart_version" {
  type        = string
  default     = "1.14.1"
  description = "Pinned aws-load-balancer-controller chart version, installed once per cluster. The _monolithic template ran `helm install` with no --version from each workbench's SSM Association"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.load_balancer_controller_chart_version))
    error_message = "load_balancer_controller_chart_version must be a three-part semantic version."
  }
}

variable "enable_backend_security_group" {
  type        = bool
  default     = false
  description = "Whether the controllers use one shared backend security group as the source of the node-side rules they write"

  validation {
    # Each Ingress names its own frontend security group and neither sets
    # manage-backend-security-group-rules, so the controllers write no node-side rules at all and
    # this project declares them itself. That is the second row of the table in rules.md G-2, and
    # it is the row that requires false (rules.md B-1).
    condition     = var.enable_backend_security_group == false
    error_message = "enable_backend_security_group must be false in this variant. Each Ingress names its own frontend security group and does not set manage-backend-security-group-rules, so the node-side rules are declared in Terraform. To let the controllers manage them instead, add that annotation to both Ingresses and set this to true (rules.md G-2)."
  }
}

variable "alb_security_group_name" {
  type        = string
  default     = "alb-sg"
  description = "Base name of each cluster's ALB frontend security group, as the _monolithic template named them. The VPC label is appended, so the two do not collide"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,240}$", var.alb_security_group_name)) && !startswith(var.alb_security_group_name, "sg-")
    error_message = "alb_security_group_name must be from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\"."
  }
}

variable "alb_allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether each ALB's frontend security group accepts traffic from 0.0.0.0/0. True reproduces the _monolithic template's InboundFromAnywhere default, and it is what lets the cross-VPC request be made from anywhere rather than only from the other cluster"
}

variable "workload_name" {
  type        = string
  default     = "nginx"
  description = "Name of the Deployment, Service and Ingress in each cluster, as the _monolithic template named them. Together with the namespace this is the ingress.k8s.aws/stack tag each pre-created ALB has to carry (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.workload_name))
    error_message = "workload_name must be a valid lowercase RFC 1123 label."
  }
}

variable "workload_namespace" {
  type        = string
  default     = "default"
  description = "Namespace the workload is created in, as the _monolithic template placed it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.workload_namespace))
    error_message = "workload_namespace must be a valid lowercase RFC 1123 label."
  }
}

variable "workload_image" {
  type        = string
  default     = "public.ecr.aws/nginx/nginx:1.29"
  description = "Image the demo pods run. Tagged and from ECR Public, where the _monolithic template used \"nginx:latest\" from Docker Hub - unpinned, and pulled through a shared NAT address that anonymous rate limits apply to"

  validation {
    condition     = can(regex(":", var.workload_image))
    error_message = "workload_image must carry an explicit tag."
  }
}

variable "workload_replicas" {
  type        = number
  default     = 5
  description = "Replicas in each cluster, as the _monolithic template set"

  validation {
    condition     = var.workload_replicas >= 1
    error_message = "workload_replicas must be at least 1."
  }
}

variable "workload_container_port" {
  type        = number
  default     = 80
  description = "Port the container listens on, the Service publishes, the Ingress targets, each ALB's frontend security group opens and the node-side rule allows. One value feeding all five (rules.md B-5)"

  validation {
    condition     = var.workload_container_port > 0 && var.workload_container_port <= 65535
    error_message = "workload_container_port must be a valid TCP port."
  }
}

# --- Workbench instances ---

variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type of each code-server workbench"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must look like an EC2 instance type (e.g. t3.medium)."
  }
}

variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether each workbench security group accepts code-server traffic from 0.0.0.0/0. True reproduces the _monolithic template's default; code-server runs with auth disabled, so restrict this for anything beyond a demo"
}

variable "kubectl_download_version" {
  type        = string
  default     = "1.34.11/2026-09-22"
  description = "kubectl build downloaded onto each workbench, as <version>/<release-date>. Kept within one minor of kubernetes_version"

  validation {
    condition     = can(regex("^1\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.34.11/2026-09-22."
  }
}

variable "code_server_version" {
  type        = string
  default     = "4.108.2"
  description = "code-server release installed on each workbench"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a three-part semantic version."
  }
}

variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on each workbench where the bootstrap drops its completion marker (rules.md D-5)"

  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/'."
  }
}

variable "readme_timeout_seconds" {
  type        = number
  default     = 1800
  description = "How long each README association waits for success"

  validation {
    condition     = var.readme_timeout_seconds >= 300
    error_message = "readme_timeout_seconds must be at least 300."
  }
}
