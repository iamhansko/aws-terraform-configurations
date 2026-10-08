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
  default     = "soft-multi-tenancy"
  description = "Name of the EKS cluster, and the basis for the VPC, key pair, tenant role and security group names. The _monolithic template derived every name from a stack_name standing in for AWS::StackName"

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
  description = "Version path used to download kubectl onto the workbench, in <version>/<release-date> form. The _monolithic template hardcoded 1.33.3 while its cluster version was a parameter (rules.md H-1)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.34.11/2026-09-22."
  }
}
variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the EKS API server endpoint is reachable from the internet. True as the _monolithic template had it, and needed because the kubectl and helm providers that create every object here run on the machine executing terraform apply"

  validation {
    # Pinned in the direction this variant depends on, with the alternative named (rules.md B-1/E-9).
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because the namespaces, quotas, workloads and NetworkPolicies are applied by the kubectl provider from the machine running terraform. To run with a private endpoint, apply them from the workbench through an SSM Association instead, as 041_eks_private_cluster does (rules.md E-9)."
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
  description = "Zones the VPC spans, a and c as the _monolithic template's subnets used. Two is EKS's minimum and what the load balancer needs"

  validation {
    condition     = length(var.availability_zone_suffixes) >= 2
    error_message = "availability_zone_suffixes must name at least two zones - EKS requires subnets in two, and an ELB requires two as well."
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
  description = "Desired node count, two as the _monolithic template had it. Two matters here: the demo runs five pods across three namespaces, and the tenant quotas assume there is capacity to schedule them"

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
  description = "Maximum node count, four as the _monolithic template had it. Nothing scales this node group"

  validation {
    condition     = var.node_group_max_size >= 1
    error_message = "node_group_max_size must be at least 1."
  }
  validation {
    condition     = var.node_group_max_size >= var.node_group_min_size
    error_message = "node_group_max_size must be greater than or equal to node_group_min_size."
  }
}
variable "enable_network_policy" {
  type        = bool
  default     = true
  description = <<-DESC
    Whether the VPC CNI enforces NetworkPolicy objects.

    True, and this is the single most consequential difference from the _monolithic template, which declared the
    vpc-cni addon with no configuration at all. Without this the API server accepts every NetworkPolicy and
    nothing implements them - so tenant-a's frontend reaches tenant-b's backend, the management UI graph is
    fully connected, and the demo shows the exact opposite of what it is for.

    Nothing about that failure is visible from Kubernetes: kubectl get networkpolicies lists all six policies,
    and each one describes correctly.
  DESC

  validation {
    # Pinned, because this variant exists to demonstrate enforcement (rules.md B-1).
    condition     = var.enable_network_policy
    error_message = "enable_network_policy must be true in this variant. With it false the NetworkPolicies are accepted and not enforced, every tenant reaches every other, and the demonstration inverts - which is indistinguishable from the policies being wrong. Set apply_network_policies = false instead to see the unisolated cluster deliberately."
  }
}
variable "tenants" {
  type = map(string)
  default = {
    a = "tenant-a"
    b = "tenant-b"
  }
  description = <<-DESC
    Tenants, as a map of label to namespace. Two as the _monolithic template had them.

    One map feeds four things that had to agree by hand there: the namespaces, the quotas, the workload
    Deployments rendered by a shell for-loop, and the IAM roles with their namespace-scoped access entries -
    which were written out twice over (rules.md B-5).

    Adding a third entry here creates its namespace, quota, limit range, frontend, backend, three
    NetworkPolicies, IAM role, access entry and access policy association, and adds it to every probe's URL
    list and to the management UI's graph.
  DESC

  validation {
    condition     = length(var.tenants) >= 2
    error_message = "tenants must name at least two tenants - the demonstration is that one cannot reach the other."
  }
}
variable "apply_network_policies" {
  type        = bool
  default     = true
  description = "Whether to create the isolating NetworkPolicies at all. True is the finished state; false is the deliberate way to see an unisolated cluster, as opposed to enable_network_policy = false which produces the same appearance by accident (rules.md B-4)"
}
variable "tenant_role_trusts_account_root" {
  type        = bool
  default     = false
  description = <<-DESC
    Whether the tenant roles trust the whole account rather than just the workbench's role.

    False, where the _monolithic template trusted arn:aws:iam::<account>:root - which means any principal in the
    account with sts:AssumeRole permission could become either tenant. That does not break the demo, but it
    makes the IAM half of the boundary weaker than it looks, and the isolation being demonstrated is the
    Kubernetes half.

    Set true to get the original's behaviour, which is also what to do when assuming a tenant role from
    somewhere other than the workbench.
  DESC
}
variable "management_ui_service_port" {
  type        = number
  default     = 80
  description = "Port the management UI Service publishes, and therefore the NLB's listener port - the one the frontend security group opens"

  validation {
    condition     = var.management_ui_service_port > 0 && var.management_ui_service_port <= 65535
    error_message = "management_ui_service_port must be a valid TCP port."
  }
}
variable "aws_load_balancer_controller_chart_version" {
  type        = string
  default     = "1.14.1"
  description = "Pinned aws-load-balancer-controller chart version. It is what turns the management UI Service into the NLB; the _monolithic template installed it with a helm command in user data, below an \"exec bash\" line that discarded every remaining line - so on a real boot it was never installed and the Service never got an address (rules.md E-1/H-1)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.aws_load_balancer_controller_chart_version))
    error_message = "aws_load_balancer_controller_chart_version must be a semantic version."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the NLB frontend security group and the workbench security group accept traffic from 0.0.0.0/0. True as the _monolithic template had it - a bool here where that template used a string validated against [\"True\", \"False\"]. The management UI graph and code-server are both reached from a browser, and code-server has no authentication"
}
variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "EC2 instance type for the workbench, as the _monolithic template had it. It investigates the cluster and assumes the tenant roles; nothing is applied from it"

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
