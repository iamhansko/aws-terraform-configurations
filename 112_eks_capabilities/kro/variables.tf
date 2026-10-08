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
  default     = "eks-kro-capability"
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
  description = "CIDR block of the VPC"

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
  description = "Zones the regional NAT gateway is given an address in. One Elastic IP per entry, as the _monolithic template allocated two"

  validation {
    condition     = length(setsubtract(var.nat_availability_zone_suffixes, var.availability_zone_suffixes)) == 0
    error_message = "nat_availability_zone_suffixes must be drawn from availability_zone_suffixes; an address in a zone with no subnet is routed nowhere."
  }
}

# --- EKS cluster ---

variable "cluster_name" {
  type        = string
  default     = "eks-cluster"
  description = "Name of the EKS cluster. The capability name is derived from it, as the _monolithic template derived it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,99}$", var.cluster_name))
    error_message = "cluster_name must start with a letter or digit and contain only letters, digits, hyphens and underscores."
  }
}

variable "kubernetes_version" {
  type        = string
  default     = "1.34"
  description = "EKS cluster Kubernetes version. Keep kubectl_download_version within one minor of this"

  validation {
    condition     = can(regex("^1\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must look like 1.XX; the cluster module holds the list of versions this project is verified against."
  }
}

variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the cluster's API server has a public endpoint. True here, and pinned true, because the demo definition and its instance are applied by the kubectl provider running on the machine executing terraform"

  validation {
    # Not a free choice: this root declares a kubectl provider, and that runs wherever terraform
    # runs. With a private-only endpoint it cannot connect, plan still passes, and the failure
    # appears mid-apply as a dial timeout that looks exactly like the destroy-ordering problem
    # rules.md D-4 describes (rules.md E-9).
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because the demo ResourceGraphDefinition and its instance are applied by the kubectl provider running on the machine executing terraform. To run with a private endpoint, drop that provider and apply both manifests from the workbench through SSM Associations instead, as 041_eks_private_cluster does."
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

variable "coredns_replica_count" {
  type        = number
  default     = 2
  description = "Number of CoreDNS replicas"

  validation {
    condition     = var.coredns_replica_count >= 1
    error_message = "coredns_replica_count must be at least 1."
  }
}

# --- Node group ---

variable "node_group_name" {
  type        = string
  default     = "core-nodegroup"
  description = "Name of the managed node group, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,62}$", var.node_group_name))
    error_message = "node_group_name must start with a letter or digit and contain only letters, digits, hyphens and underscores."
  }
}

variable "node_instance_types" {
  type        = list(string)
  default     = ["t3.large"]
  description = "Instance types for the managed node group, as the _monolithic template sized them"

  validation {
    condition     = length(var.node_instance_types) > 0
    error_message = "node_instance_types must contain at least one instance type."
  }
}

variable "node_desired_size" {
  type        = number
  default     = 2
  description = "Desired node count"

  validation {
    condition     = var.node_desired_size >= 1
    error_message = "node_desired_size must be at least 1."
  }
}

variable "node_min_size" {
  type        = number
  default     = 2
  description = "Minimum node count"

  validation {
    condition     = var.node_min_size >= 1
    error_message = "node_min_size must be at least 1."
  }
}

variable "node_max_size" {
  type        = number
  default     = 4
  description = "Maximum node count"

  validation {
    condition     = var.node_max_size >= 1
    error_message = "node_max_size must be at least 1."
  }
}
# --- The kro capability ---

variable "capability_name_suffix" {
  type        = string
  default     = "kro"
  description = "Appended to cluster_name to name the capability, as the _monolithic template composed it (\"<cluster>-kro\")"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,30}$", var.capability_name_suffix))
    error_message = "capability_name_suffix must be letters, digits and hyphens, starting with a letter or digit."
  }
}

variable "capability_iam_policy_arns" {
  type        = list(string)
  default     = []
  description = <<-DESC
    Managed policies attached to the role AWS assumes to run the kro capability.

    Empty, which is a deliberate departure from the _monolithic template's AdministratorAccess. kro composes
    Kubernetes objects; it calls no AWS API of its own, and the EKS documentation says the capability role
    is used only for the trust relationship. What kro needs is Kubernetes permission, and that comes from
    capability_cluster_access_policy_arn below rather than from anything here.

    A definition that composes ACK resources still works with this empty: the AWS calls are then made by
    the ACK capability's role, not this one.
  DESC

  validation {
    condition     = alltrue([for arn in var.capability_iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "capability_iam_policy_arns must contain valid IAM policy ARNs."
  }
}

variable "capability_role_propagation_wait_seconds" {
  type        = number
  default     = 30
  description = <<-DESC
    How long to wait after creating the capability role before creating the capability, so its trust policy
    has propagated to the EKS capabilities service.

    This exists because of a failed apply. CreateCapability validates the trust policy first thing, and a
    role created moments earlier is not visible to it yet, so it answers with InvalidParameterException
    saying the policy must include sts:AssumeRole and sts:TagSession - on a role whose policy includes
    exactly those, for exactly that service principal. The message describes a configuration error and the
    configuration is correct, which is the whole difficulty: see time_sleep.role_propagation in
    modules/eks_capability/main.tf.

    Raise it rather than re-running the apply if that error appears. Re-running succeeds, because the role
    left behind by the failed run has propagated by then, but it hides the race instead of fixing it.
  DESC

  validation {
    condition     = var.capability_role_propagation_wait_seconds >= 0 && floor(var.capability_role_propagation_wait_seconds) == var.capability_role_propagation_wait_seconds
    error_message = "capability_role_propagation_wait_seconds must be a whole number of seconds, zero or greater."
  }
}

variable "capability_cluster_access_policy_arn" {
  type        = string
  default     = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  description = <<-DESC
    An extra EKS cluster access policy associated with the capability role, or null for none.

    Required for kro, and this is the part that is easy to miss. Creating a capability makes EKS create an
    access entry for the role by itself, with AmazonEKSKROPolicy attached - but that policy only covers
    ResourceGraphDefinitions and instances of them. It grants nothing on the Deployments, Services or
    ConfigMaps a definition actually composes, which is deliberate: different definitions need different
    permissions.

    Without this, everything looks correct. The capability reaches ACTIVE, the definition goes Active, the
    instance is accepted - and the objects are never created, with the refusal recorded in the instance's
    status conditions rather than anywhere an apply would notice.

    Cluster admin is the quick setup the EKS documentation suggests for exactly this demo. Narrow it to the
    resources the definitions compose for anything longer lived.

    Note that only the association is declared, never the access entry - EKS already created that, and a
    second one for the same principal fails with ResourceInUseException.
  DESC

  validation {
    condition     = var.capability_cluster_access_policy_arn == null || can(regex("^arn:aws:eks::aws:cluster-access-policy/", var.capability_cluster_access_policy_arn))
    error_message = "capability_cluster_access_policy_arn must be an EKS cluster access policy ARN, or null."
  }
}

# --- The demo API and one instance of it ---

variable "create_demo_resource_graph" {
  type        = bool
  default     = true
  description = "Whether to create a ResourceGraphDefinition and an instance of it. True, because a kro capability that has never processed a definition proves only that EKS installed a CRD - and because the _monolithic template created the capability and then stopped, leaving nothing to look at"
}

variable "demo_api_name" {
  type        = string
  default     = "nginxapps.kro.run"
  description = "Name of the ResourceGraphDefinition. kro's convention is <plural>.<group>"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.demo_api_name))
    error_message = "demo_api_name must be a valid lowercase DNS subdomain."
  }
}

variable "demo_api_kind" {
  type        = string
  default     = "NginxApp"
  description = "Kind of the new API the definition creates. The cluster serves this kind only after kro has processed the definition, which is why applying an instance needs a wait in between"

  validation {
    condition     = can(regex("^[A-Z][A-Za-z0-9]*$", var.demo_api_kind))
    error_message = "demo_api_kind must be UpperCamelCase, as Kubernetes kinds are."
  }
}

variable "demo_instance_name" {
  type        = string
  default     = "kro-demo"
  description = "Name of the instance object"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.demo_instance_name))
    error_message = "demo_instance_name must be a valid lowercase RFC 1123 label."
  }
}

variable "demo_namespace" {
  type        = string
  default     = "default"
  description = "Namespace the instance and the objects kro builds from it live in"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.demo_namespace))
    error_message = "demo_namespace must be a valid lowercase RFC 1123 label."
  }
}

variable "demo_workload_name" {
  type        = string
  default     = "kro-demo-nginx"
  description = "The one field the instance sets. The definition uses it to name the Deployment, the Service and the pod label selector"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.demo_workload_name))
    error_message = "demo_workload_name must be a valid lowercase RFC 1123 label."
  }
}

variable "api_wait_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the SSM step that waits for the generated CRD waits before failing. kro processes a definition in seconds, but the capability itself can still be finishing its installation when the definition is applied"

  validation {
    condition     = var.api_wait_timeout_seconds >= 300
    error_message = "api_wait_timeout_seconds must be at least 300."
  }
}

# --- Workbench instance ---

variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type of the code-server workbench, as the _monolithic template sized it"

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
  description = "kubectl build downloaded onto the workbench, as <version>/<release-date>. Kept within one minor of kubernetes_version; the _monolithic template pinned a 1.33 build"

  validation {
    condition     = can(regex("^1\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.34.11/2026-09-22."
  }
}

variable "code_server_version" {
  type        = string
  default     = "4.108.2"
  description = "code-server release installed on the workbench. Pinned rather than resolved from the GitHub releases API at boot, which is what the _monolithic template did - an API rate limit produced an empty version and a 404"

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
