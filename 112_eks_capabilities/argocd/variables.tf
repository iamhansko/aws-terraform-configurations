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
  default     = "eks-argocd-capability"
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
  description = "Whether the cluster's API server has a public endpoint. True here, and pinned true, because the demo Argo CD Application is applied by the kubectl provider running on the machine executing terraform"

  validation {
    # Not a free choice: this root declares a kubectl provider, and that runs wherever terraform
    # runs. With a private-only endpoint it cannot connect, plan still passes, and the failure
    # appears mid-apply as a dial timeout that looks exactly like the destroy-ordering problem
    # rules.md D-4 describes (rules.md E-9).
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because the demo Argo CD Application is applied by the kubectl provider running on the machine executing terraform. To run with a private endpoint, drop that provider and apply the manifest from the workbench through an SSM Association instead, as 041_eks_private_cluster does."
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
# --- The Argo CD capability ---

variable "capability_name_suffix" {
  type        = string
  default     = "argocd"
  description = "Appended to cluster_name to name the capability, as the _monolithic template composed it (\"<cluster>-argocd\")"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,30}$", var.capability_name_suffix))
    error_message = "capability_name_suffix must be letters, digits and hyphens, starting with a letter or digit."
  }
}

variable "capability_iam_policy_arns" {
  type        = list(string)
  default     = []
  description = <<-DESC
    Managed policies attached to the role AWS assumes to run the Argo CD capability.

    Empty, which is a deliberate departure from the _monolithic template's AdministratorAccess. Argo CD
    deploys Kubernetes objects; it calls no AWS API of its own. What it needs is Kubernetes permission, and
    that comes from capability_cluster_access_policy_arn below rather than from anything here.
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

    Required for Argo CD to deploy anything outside its own namespace. Creating a capability makes EKS
    create an access entry for the role by itself, with two baseline policies:
    AmazonEKSArgoCDClusterPolicy for cluster-wide discovery, and AmazonEKSArgoCDPolicy scoped to the
    namespace named in the capability configuration. Neither grants write access to any other namespace.

    Without this, the Application below is accepted and reports OutOfSync forever, with the refusal in its
    status conditions rather than anywhere an apply would notice.

    Note that only the association is declared, never the access entry - EKS already created that, and a
    second one for the same principal fails with ResourceInUseException.
  DESC

  validation {
    condition     = var.capability_cluster_access_policy_arn == null || can(regex("^arn:aws:eks::aws:cluster-access-policy/", var.capability_cluster_access_policy_arn))
    error_message = "capability_cluster_access_policy_arn must be an EKS cluster access policy ARN, or null."
  }
}

variable "argocd_namespace" {
  type        = string
  default     = "argocd"
  description = "Namespace the capability installs Argo CD into, as the _monolithic template set it. Also the namespace its namespace-scoped baseline access policy is bound to, and the only namespace it reads Applications from"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.argocd_namespace))
    error_message = "argocd_namespace must be a valid lowercase RFC 1123 label."
  }
}

variable "argocd_vpce_ids" {
  type        = list(string)
  default     = []
  description = "VPC endpoints the Argo CD API server is reachable through. Empty leaves it reachable over the internet, which is the default and what this demo uses"

  validation {
    condition     = alltrue([for id in var.argocd_vpce_ids : can(regex("^vpce-[0-9a-f]+$", id))])
    error_message = "argocd_vpce_ids must contain valid VPC endpoint IDs (e.g. vpce-0123456789abcdef0)."
  }
}

# --- IAM Identity Center ---
#
# Argo CD as an EKS capability has no local users: IAM Identity Center is the only way to sign in.
# That makes an Identity Center instance a hard prerequisite for this variant rather than an option,
# which is why the instance is discovered rather than created - an instance is an account-level
# (or organization-level) resource, and there is at most one per region.

variable "idc_instance_arn" {
  type        = string
  default     = null
  description = <<-DESC
    ARN of the IAM Identity Center instance Argo CD authenticates against. Null discovers the account's
    instance, which is the usual case.

    If there is no instance and none is named here, the capability module's validation fails the plan,
    naming Identity Center. That is deliberate and it is an error rather than a warning: Argo CD as a
    capability supports no local users, so there is no configuration without an instance that EKS would
    accept. Letting the plan through would spend the cluster build before failing at CreateCapability, for
    a reason that is not visible from the error there.

    What the plan cannot do is fix it. Enabling Identity Center is an account-level action outside this
    configuration - the AWS provider has no resource for an instance, only the data source above - so the
    plan stops and says so.

    In an AWS Workshop Studio account it cannot be fixed at all: sso:CreateInstance is denied by an
    explicit statement in the organization's service control policy, so neither the console nor the CLI
    can create one either. This variant does not run in such an account, and kro and ack do. See the
    comment on data.aws_ssoadmin_instances in main.tf for the measured error.

    Discovery is per region, because an instance belongs to one region. Naming an instance in another
    region here requires idc_region below as well.
  DESC

  validation {
    condition     = var.idc_instance_arn == null || can(regex("^arn:aws:sso:::instance/", var.idc_instance_arn))
    error_message = "idc_instance_arn must be an IAM Identity Center instance ARN (e.g. arn:aws:sso:::instance/ssoins-0123456789abcdef), or null to discover the account's instance."
  }
}

variable "idc_region" {
  type        = string
  default     = null
  description = <<-DESC
    Region the IAM Identity Center instance named in idc_instance_arn lives in. Null means the same region
    this configuration is applied to, which is the only thing discovery can find.

    Needed because an instance ARN does not carry its region: arn:aws:sso:::instance/ssoins-... has an empty
    region field, so EKS cannot infer where to look. An organization usually has exactly one instance, in
    one region, and a cluster in any other region reaches it only by being told both values.

    Leaving this null for an instance that is in fact elsewhere is not a plan error. EKS accepts the
    capability and the failure arrives as an instance it cannot resolve, so the pair is checked below
    (rules.md B-1).
  DESC

  validation {
    condition     = var.idc_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.idc_region))
    error_message = "idc_region must be an AWS region name (e.g. us-east-1), or null to use the region this configuration is applied to."
  }

  validation {
    # Discovery only ever finds an instance in the current region, so a region named here with no ARN
    # alongside it describes an instance this configuration is not using. The constraint is about the
    # pair rather than either value (rules.md B-1).
    condition     = var.idc_region == null || var.idc_instance_arn != null
    error_message = "idc_region needs idc_instance_arn set. Discovery finds only an instance in the region this configuration is applied to, so naming a different region without also naming the instance has no effect - set both, or leave both null."
  }
}

variable "create_identity_center_user" {
  type        = bool
  default     = true
  description = <<-DESC
    Whether to create a user in the identity store and map it to Argo CD's ADMIN role.

    True, because a capability with single sign-on configured and no role mapping is an Argo CD nobody can
    log in to - and nothing reports that. Skipped automatically when the account has no Identity Center
    instance, since there is no identity store to create the user in.

    The _monolithic template did this through a Lambda-backed custom resource whose source file was not
    Python at all; see modules/identity_center_user for what was wrong with it.
  DESC
}

variable "identity_center_user_name" {
  type        = string
  default     = "argocd"
  description = "User name created in the identity store, as the _monolithic template passed to its Lambda"

  validation {
    condition     = can(regex("^[A-Za-z0-9._@+-]{1,128}$", var.identity_center_user_name))
    error_message = "identity_center_user_name must be 1-128 characters of letters, digits and . _ @ + -."
  }
}

variable "identity_center_user_email" {
  type        = string
  default     = "argocd@example.com"
  description = "Primary email of the created user. Identity Center sends the one-time password here, so a real address is needed to actually sign in - the default is enough to create the user and the role mapping"

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.identity_center_user_email))
    error_message = "identity_center_user_email must look like an email address."
  }
}

variable "argocd_admin_group_ids" {
  type        = list(string)
  default     = []
  description = "Identity store group ids mapped to Argo CD's ADMIN role, in addition to the created user. Group ids, not names - a name here maps to nothing and reports no error"

  validation {
    condition     = alltrue([for id in var.argocd_admin_group_ids : can(regex("^[0-9a-f-]{8,}$", id))])
    error_message = "argocd_admin_group_ids must contain identity store group ids rather than group names."
  }
}

# --- The demo Application ---

variable "create_demo_application" {
  type        = bool
  default     = true
  description = "Whether to create an Argo CD Application. True, because a capability that is ACTIVE with no applications proves only that EKS installed some CRDs - and because signing in requires a one-time password sent to an email address, so an automated sync is the only way to see it working without one"
}

variable "demo_application_name" {
  type        = string
  default     = "guestbook"
  description = "Name of the Application object"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.demo_application_name))
    error_message = "demo_application_name must be a valid lowercase RFC 1123 label."
  }
}

variable "demo_application_repo_url" {
  type        = string
  default     = "https://github.com/argoproj/argocd-example-apps.git"
  description = "Git repository the Application syncs from. The upstream Argo CD example repository, which needs no credentials"

  validation {
    condition     = can(regex("^(https://|git@)", var.demo_application_repo_url))
    error_message = "demo_application_repo_url must be an https or ssh git URL."
  }
}

variable "demo_application_path" {
  type        = string
  default     = "guestbook"
  description = "Directory inside the repository to sync. guestbook is two plain manifests with no Helm or Kustomize in the way"

  validation {
    condition     = length(var.demo_application_path) > 0
    error_message = "demo_application_path must not be empty."
  }
}

variable "demo_application_target_revision" {
  type        = string
  default     = "HEAD"
  description = "Revision to sync. HEAD because the example repository publishes no releases; name a commit for anything longer lived, since automated sync means an upstream push changes this cluster"

  validation {
    condition     = length(var.demo_application_target_revision) > 0
    error_message = "demo_application_target_revision must not be empty."
  }
}

variable "demo_application_namespace" {
  type        = string
  default     = "guestbook"
  description = "Namespace Argo CD deploys the synced objects into. Created by Argo CD through its CreateNamespace sync option rather than declared here, so Argo CD owns what it creates"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.demo_application_namespace))
    error_message = "demo_application_namespace must be a valid lowercase RFC 1123 label."
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
