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
  default     = "flux-cluster"
  description = "Name of the EKS cluster"

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
  description = "Version path used to download kubectl onto the VS Code instance, in <version>/<release-date> form. Raised together with kubernetes_version: kubectl more than one minor version from the API server is outside the supported skew (rules.md H-1)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.34.11/2026-09-22."
  }
}
variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the EKS API server endpoint is reachable from the internet. True as the _monolithic template had it, and needed because the helm and kubectl providers run on the machine executing terraform apply rather than inside the VPC (rules.md E-2). Narrow public_access_cidrs rather than leaving the default open"

  validation {
    # Pinned in the direction this variant depends on, with the alternative named
    # (rules.md B-1/E-9).
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because the Flux controllers and its GitRepository and Kustomization are applied by the helm and kubectl providers from the machine running terraform. To run with a private endpoint, apply them from the bastion through an SSM Association instead, as 041_eks_private_cluster does (rules.md E-9)."
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
  default     = "flux-key"
  description = "Name of the EC2 key pair created for the demo instance"

  validation {
    condition     = length(var.key_name) > 0
    error_message = "key_name must not be empty."
  }
}
variable "node_group_instance_types" {
  type        = list(string)
  default     = ["t3.large"]
  description = "Instance types for the managed node group, t3.large as the _monolithic template had it. Larger than most projects here because a single node carries the five Flux controllers, the EBS CSI driver, CoreDNS and whatever the reconciled repository brings"

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "node_group_instance_types must contain at least one instance type."
  }
}
variable "node_group_desired_size" {
  type        = number
  default     = 1
  description = "Desired node count, one as the _monolithic template had it"

  validation {
    condition     = var.node_group_desired_size >= 1
    error_message = "node_group_desired_size must be at least 1."
  }
}
variable "node_group_min_size" {
  type        = number
  default     = 1
  description = "Minimum node count"

  validation {
    condition     = var.node_group_min_size >= 1
    error_message = "node_group_min_size must be at least 1."
  }
}
variable "node_group_max_size" {
  type        = number
  default     = 3
  description = "Maximum node count, three as the _monolithic template had it. Nothing scales this node group, so it is headroom - podinfo's HorizontalPodAutoscaler scales pods, not nodes"

  validation {
    condition     = var.node_group_max_size >= 1
    error_message = "node_group_max_size must be at least 1."
  }
  validation {
    condition     = var.node_group_max_size >= var.node_group_min_size
    error_message = "node_group_max_size must be greater than or equal to node_group_min_size."
  }
}
variable "storage_class_name" {
  type        = string
  default     = "gp3"
  description = "Name of the default StorageClass created for the cluster, gp3 as the _monolithic template named it. Nothing in this project claims a volume; it is the cluster's storage baseline, and it is here because the original set it up and because a cluster whose only default class is EKS's gp2 is a surprise for whatever gets added next"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.storage_class_name))
    error_message = "storage_class_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "flux_chart_version" {
  type        = string
  default     = "2.19.1"
  description = "Pinned flux2 chart version, which carries Flux 2.9.5. The _monolithic template piped fluxcd.io/install.sh into bash, so the Flux version was whatever was current on the day the instance booted"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.flux_chart_version))
    error_message = "flux_chart_version must be a semantic version."
  }
}
variable "github_owner" {
  type        = string
  description = "GitHub account the GitOps repository is created in, which is also what the github provider authenticates against. No default: this names somebody's account, and a wrong value creates a repository in the wrong place rather than failing a plan. For a personal account it is the username; for an organisation it is the organisation name, and the token must be allowed to create repositories there"

  validation {
    condition     = can(regex("^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?$", var.github_owner))
    error_message = "github_owner must be a valid GitHub account name: letters, digits and single hyphens, 39 characters or fewer."
  }
}
variable "github_token" {
  type        = string
  sensitive   = true
  description = "GitHub personal access token with repository scope. Used twice: by the github provider to create the repository, and as the password in the Kubernetes Secret the source controller clones it with. Pass it in a gitignored *.auto.tfvars file or as TF_VAR_github_token rather than on the command line, where it lands in the shell history. It ends up in the Terraform state file and in a Secret in the cluster - the first is the price of it being a variable, the second is unavoidable for an https source, because the controller has to read it"

  validation {
    condition     = length(var.github_token) > 0
    error_message = "github_token must not be empty."
  }
  validation {
    condition     = !can(regex("[[:space:]]", var.github_token))
    error_message = "github_token must not contain whitespace - a newline or trailing space from a paste reaches GitHub as part of the credential, and comes back as a 401 from the provider or as an authentication failure on the GitRepository (rules.md B-1)."
  }
}
variable "github_gitops_repository" {
  type        = string
  default     = "flux-infra"
  description = "Name of the repository created under github_owner, flux-infra as the _monolithic template's bootstrap command used. Created if it does not exist; an existing repository of this name is adopted rather than replaced only if it is imported first, so pick a name that is free"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.github_gitops_repository))
    error_message = "github_gitops_repository must be a valid GitHub repository name."
  }
}
variable "github_gitops_visibility" {
  type        = string
  default     = "private"
  description = "Visibility of that repository. Private by default, and private is the case worth wiring: it is the reason the source controller needs a Secret at all. A public one reconciles with no credentials and leaves that half untested"

  validation {
    condition     = contains(["private", "public"], var.github_gitops_visibility)
    error_message = "github_gitops_visibility must be either private or public."
  }
}
variable "github_gitops_name" {
  type        = string
  default     = "cluster-config"
  description = "Name shared by this source's GitRepository and Kustomization, and by the ConfigMap seeded into the repository. Distinct from gitops_name so the two sources do not collide in the Flux namespace"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.github_gitops_name))
    error_message = "github_gitops_name must be a valid lowercase RFC 1123 DNS label."
  }
}
# No target namespace variable for this repository, deliberately. The files in it are Flux custom
# resources that declare namespace: flux-system themselves, and a Kustomization's targetNamespace
# rewrites every object it applies - so any value here would move them out of the namespace the
# controllers watch. The module takes null for exactly this case (rules.md B-4).
variable "github_gitops_source_interval" {
  type        = string
  default     = "1m"
  description = "How often that repository is polled. This is how long after committing an edit on GitHub the cluster acts on it, so it is also the patience the demo asks for"

  validation {
    condition     = can(regex("^[0-9]+(s|m|h)$", var.github_gitops_source_interval))
    error_message = "github_gitops_source_interval must be a Go duration such as 30s, 1m or 1h."
  }
}
variable "github_gitops_git_username" {
  type        = string
  default     = "git"
  description = "Username stored in the Secret alongside the token. GitHub ignores it for token authentication, but the controller requires the key to be present and non-empty - \"git\" is the conventional filler"

  validation {
    condition     = length(var.github_gitops_git_username) > 0
    error_message = "github_gitops_git_username must not be empty - the Secret needs both keys and an empty username is reported as an authentication failure at clone time."
  }
}
variable "github_gitops_commit_message" {
  type        = string
  default     = "Seed GitOps manifests (terraform)"
  description = "Commit message for the seeded manifests"

  validation {
    condition     = length(var.github_gitops_commit_message) > 0
    error_message = "github_gitops_commit_message must not be empty."
  }
}
variable "github_gitops_archive_on_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy archives the repository instead of deleting it. True on purpose: everything else here is disposable AWS infrastructure, and this repository is the one thing that holds commits somebody wrote by hand. GitHub does not undo a repository deletion. Note that an archived repository is read-only, so a later apply cannot write to it until it is unarchived"
}
variable "flux_namespace" {
  type        = string
  default     = "flux-system"
  description = "Namespace the Flux controllers and its GitRepository and Kustomization live in. flux-system is what the flux CLI and every Flux tutorial assume"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.flux_namespace))
    error_message = "flux_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "gitops_name" {
  type        = string
  default     = "podinfo"
  description = "Name shared by the GitRepository and the Kustomization, podinfo as the _monolithic template's flux CLI calls produced"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.gitops_name))
    error_message = "gitops_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "gitops_url" {
  type        = string
  default     = "https://github.com/stefanprodan/podinfo"
  description = "Git repository Flux reconciles from. Public and read-only over https, as the _monolithic template had it, so this half of the demo needs no token and no Secret. Pointing it at a private repository means adding a Secret with credentials and naming it in the GitRepository's secretRef"

  validation {
    condition     = can(regex("^(https://|ssh://|git@)", var.gitops_url))
    error_message = "gitops_url must be an https://, ssh:// or git@ Git URL."
  }
}
variable "gitops_branch" {
  type        = string
  default     = "master"
  description = "Branch to track, master as the _monolithic template specified - the podinfo repository's actual default branch, not a typo for main"

  validation {
    condition     = length(var.gitops_branch) > 0
    error_message = "gitops_branch must not be empty."
  }
}
variable "gitops_path" {
  type        = string
  default     = "./kustomize"
  description = "Directory inside the repository the Kustomization applies, ./kustomize as the _monolithic template set it"

  validation {
    condition     = can(regex("^\\./", var.gitops_path))
    error_message = "gitops_path must be repository-relative and start with ./ - Flux rejects an absolute path."
  }
}
variable "gitops_target_namespace" {
  type        = string
  default     = "default"
  description = "Namespace the reconciled objects land in, default as the _monolithic template set it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.gitops_target_namespace))
    error_message = "gitops_target_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "gitops_source_interval" {
  type        = string
  default     = "1m"
  description = "How often the podinfo repository is polled for new commits, one minute as GOAL.md's --interval sets it. This is the delay between a push to podinfo and the cluster noticing"

  validation {
    condition     = can(regex("^[0-9]+(s|m|h)$", var.gitops_source_interval))
    error_message = "gitops_source_interval must be a Go duration such as 30s, 1m or 1h."
  }
}
variable "gitops_kustomization_interval" {
  type        = string
  default     = "5m"
  description = "How often the podinfo Kustomization re-applies what the source controller has fetched, five minutes as GOAL.md's --interval sets it. It is also the loop that undoes a manual kubectl edit, which is the property the drift step demonstrates"

  validation {
    condition     = can(regex("^[0-9]+(s|m|h)$", var.gitops_kustomization_interval))
    error_message = "gitops_kustomization_interval must be a Go duration such as 30s, 5m or 1h."
  }
}
variable "gitops_retry_interval" {
  type        = string
  default     = "2m"
  description = "How soon a failed podinfo reconciliation is retried, two minutes as GOAL.md's --retry-interval sets it. Shorter than the normal interval on purpose, so a transient failure does not cost a full cycle"

  validation {
    condition     = can(regex("^[0-9]+(s|m|h)$", var.gitops_retry_interval))
    error_message = "gitops_retry_interval must be a Go duration such as 30s, 2m or 1h."
  }
}
variable "gitops_health_check_timeout" {
  type        = string
  default     = "3m"
  description = "How long the podinfo Kustomization waits for the objects it applied to become ready before calling the reconciliation failed, three minutes as GOAL.md's --health-check-timeout sets it. Only meaningful because that Kustomization sets wait: true"

  validation {
    condition     = can(regex("^[0-9]+(s|m|h)$", var.gitops_health_check_timeout))
    error_message = "gitops_health_check_timeout must be a Go duration such as 30s, 3m or 1h."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the VS Code security group accepts traffic from 0.0.0.0/0 on the code-server port, as the _monolithic template had it. code-server has no authentication in front of it, so narrow this where possible and reach it through SSM Session Manager port forwarding instead"
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
variable "flux_cli_version" {
  type        = string
  default     = "2.9.5"
  description = "Version of the flux CLI installed on the workbench instance, matched to the Flux the chart installs. Pinned rather than piped from fluxcd.io/install.sh, which is what the _monolithic template did - a CLI more than a minor ahead of the controllers can emit manifests with API versions they do not serve. It is a diagnostic tool here: nothing uses it to create resources (rules.md H-1)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.flux_cli_version))
    error_message = "flux_cli_version must be a semantic version, e.g. 2.9.5."
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
  description = "How long the README SSM association may take. It first waits for the instance bootstrap to finish, which includes downloading kubectl, eksctl, helm and the flux CLI"

  validation {
    condition     = var.readme_timeout_seconds > 0
    error_message = "readme_timeout_seconds must be positive."
  }
}
