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
  default     = "arc-cluster"
  description = "Name of the EKS cluster, and the basis for the VPC and key pair names. The _monolithic template derived every name from a stack_name standing in for AWS::StackName"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,99}$", var.cluster_name))
    error_message = "cluster_name must start with a letter or digit and contain only letters, digits, hyphens and underscores (100 characters or fewer)."
  }
}
variable "kubernetes_version" {
  type        = string
  default     = "1.34"
  description = "Kubernetes version for the EKS cluster. 1.34 rather than the _monolithic template's 1.36, matching the rest of this repository - it is the newest version still in standard support"

  validation {
    condition     = can(regex("^1\\.(3[0-9]|[4-9][0-9])$", var.kubernetes_version))
    error_message = "kubernetes_version must be a supported 1.XX version, e.g. 1.34."
  }
}
variable "kubectl_download_version" {
  type        = string
  default     = "1.34.11/2026-09-22"
  description = "Version path used to download kubectl onto the workbench, in <version>/<release-date> form. The _monolithic template hardcoded 1.33.3 while its cluster defaulted to 1.36 - three minor versions apart, well outside the supported skew (rules.md H-1)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.34.11/2026-09-22."
  }
}
variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the EKS API server endpoint is reachable from the internet. True as the _monolithic template had it, and needed here: the kubectl and helm providers that install ARC run on the machine executing terraform apply. Narrow public_access_cidrs rather than leaving the default open"

  validation {
    # Pinned in the direction this variant depends on, with the alternative named (rules.md B-1/E-9).
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because Actions Runner Controller is installed by the helm and kubectl providers from the machine running terraform. To run with a private endpoint, install it from the workbench through an SSM Association instead, as 041_eks_private_cluster does (rules.md E-9)."
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
  description = "CIDR block for the VPC, as the _monolithic template had it. The subnets are derived from it rather than listed in a mapping, so changing it moves them with it"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block."
  }
}
variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "c"]
  description = "Zones the VPC spans, a and c as the _monolithic template's AzMapping had them. Two is the minimum EKS accepts and enough here: nothing in this project is zone-aware, and each extra zone is another subnet for the runners to be spread across for no benefit (rules.md C-3)"

  validation {
    condition     = length(var.availability_zone_suffixes) >= 2
    error_message = "availability_zone_suffixes must name at least two zones - EKS requires subnets in two."
  }
}
variable "nat_availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "c"]
  description = "Zones the regional NAT gateway is given an address in, as the _monolithic template wired them. Runner pods run in the private subnets and pull their container image and their job's dependencies through this"

  validation {
    condition     = length(var.nat_availability_zone_suffixes) >= 1
    error_message = "nat_availability_zone_suffixes must name at least one zone."
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
variable "node_group_instance_types" {
  type        = list(string)
  default     = ["t3.medium"]
  description = "Instance types for the managed node group, t3.medium as the _monolithic template had it. Worth knowing what it means for the demo: a runner pod and its job share this, so a build that needs more than a couple of gigabytes will not fit"

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
  description = "Maximum node count, four as the _monolithic template had it. Nothing scales this node group, so it stays at the desired size - which is the real ceiling on how many runners can exist at once, whatever max_runners says"

  validation {
    condition     = var.node_group_max_size >= 1
    error_message = "node_group_max_size must be at least 1."
  }
  validation {
    condition     = var.node_group_max_size >= var.node_group_min_size
    error_message = "node_group_max_size must be greater than or equal to node_group_min_size."
  }
}
variable "github_owner" {
  type        = string
  description = "GitHub account or organisation that owns the repository the runners serve. No default: it is whoever is running this, and there is nothing to guess. The _monolithic template took the same value as git_hub_user"

  validation {
    condition     = can(regex("^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?$", var.github_owner))
    error_message = "github_owner must be a valid GitHub account name: up to 39 characters of letters, digits and hyphens, not starting or ending with a hyphen."
  }
}
variable "github_repository" {
  type        = string
  default     = "arc-repo"
  description = <<-DESC
    Repository the runners register with, as the _monolithic template named it. This root creates it.

    That template declared an AWS::CodeStar::GitHubRepository, a legacy resource type the AWS provider has no
    equivalent for, and cfn2tf dropped it with a note saying to use the GitHub provider. Two things followed.
    The runner set's githubConfigUrl kept a literal "UNSUPPORTED_REF_GitHubRepository" where the reference had
    been, which was noticed. The repository itself was gone, which was not - so the controller asked GitHub for
    a registration token for a repository that did not exist, got a 404, and never created a listener, while
    the apply reported success.

    Set to an empty string to register the scale set at the organisation level instead, which is the shape that
    scales past one repository. Then nothing is created on GitHub: the organisation already exists, and the
    workflow has to be added to a repository by hand.
  DESC

  validation {
    condition     = var.github_repository == "" || can(regex("^[A-Za-z0-9_.-]{1,100}$", var.github_repository))
    error_message = "github_repository must be 1-100 characters of letters, digits, underscores, dots and hyphens, or an empty string to register at the organisation level."
  }
}
variable "github_repository_visibility" {
  type        = string
  default     = "private"
  description = <<-DESC
    Visibility of the repository this root creates.

    Private, where the _monolithic template set IsPrivate: false. A deliberate deviation, and the reason is
    what this project builds: in a public repository anyone can open a pull request from a fork and have their
    code run on a runner pod inside this VPC, with that pod's network reach and whatever the node's instance
    profile allows. GitHub's hardening guide advises against self-hosted runners on public repositories.

    Set to "public" to match the original exactly.
  DESC

  validation {
    condition     = contains(["private", "public", "internal"], var.github_repository_visibility)
    error_message = "github_repository_visibility must be private, public or internal."
  }
}
variable "seed_demo_workflow" {
  type        = bool
  default     = true
  description = <<-DESC
    Whether to commit a workflow into the repository that runs on the scale set.

    True, because an empty repository makes the project untestable: the runners register, sit at zero, and
    nothing distinguishes that from a broken install. The seeded workflow has workflow_dispatch and push
    triggers, so the commit that creates it is also the first run.

    False leaves the repository empty, for adding a workflow by hand - and whatever is added has to carry the
    same runs-on value, which the workflow_snippet output prints.
  DESC
}
variable "github_token" {
  type        = string
  sensitive   = true
  description = <<-DESC
    Personal access token, used for two jobs: the GitHub provider creates the repository with it, and the
    runners authenticate with it.

    Creating the repository is the wider of the two requirements. A classic token needs the repo scope, which
    also covers the runners for a repository scale set; an organisation scale set needs admin:org as well. A
    fine-grained token needs Administration: write and Contents: write on the owner, plus the repository
    permissions the runners use.

    It goes into a Kubernetes Secret rather than onto a helm command line, which is where the _monolithic
    template put it - inside EC2 user data, so it was also in the instance's metadata, in
    /var/log/cloud-init-output.log under set -x, and in the process list while helm ran. That template's own
    description of this parameter recommended against exactly that.

    It still lands in Terraform state. A GitHub App private key in Secrets Manager, mounted with the Secrets
    Store CSI driver, is the production answer; this is the demo answer, named as such.
  DESC

  validation {
    condition     = can(regex("^[A-Za-z0-9_]{36,}$", var.github_token))
    error_message = "github_token must be at least 36 characters of letters, digits and underscores with no whitespace - most often this fails because the value was pasted with a trailing newline."
  }
}
variable "runner_set_name" {
  type        = string
  default     = "arc-runner-set"
  description = "Name of the runner scale set, as the _monolithic template named the helm release. It is also the value a workflow puts in runs-on, so changing it means changing every workflow that targets these runners - and a mismatch queues the job forever with no error"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.runner_set_name))
    error_message = "runner_set_name must be a valid lowercase RFC 1123 DNS label - it becomes the runs-on label in a workflow."
  }
}
variable "arc_chart_version" {
  type        = string
  default     = "0.14.2"
  description = "Version of both Actions Runner Controller charts. Pinned, where the _monolithic template's helm commands took whatever the registry served at boot - so two instances built a week apart could run different controllers"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.arc_chart_version))
    error_message = "arc_chart_version must be a semantic version, e.g. 0.14.2."
  }
}
variable "min_runners" {
  type        = number
  default     = 0
  description = "Runner pods kept running with nothing queued, zero as the _monolithic template had it. Zero is the point of ARC: nothing runs, and nothing is billed, until a workflow asks for a runner"

  validation {
    condition     = var.min_runners >= 0
    error_message = "min_runners must be zero or greater."
  }
}
variable "max_runners" {
  type        = number
  default     = 5
  description = "Most runner pods at once, five as the _monolithic template had it. The real ceiling is the node group, which nothing scales - five runners on two t3.medium nodes will not all be schedulable"

  validation {
    condition     = var.max_runners >= 1
    error_message = "max_runners must be at least 1."
  }
  validation {
    condition     = var.max_runners >= var.min_runners
    error_message = "max_runners must be greater than or equal to min_runners."
  }
}
variable "runner_container_mode" {
  type        = string
  default     = ""
  description = "How a job that declares containers gets them. Empty leaves ARC's default, which is what the _monolithic template had: the job runs in the runner pod, and a workflow with a container: key or a service container fails. \"dind\" needs a privileged container; \"kubernetes\" needs a ReadWriteMany storage class, which this cluster has none of - so neither is the default here"

  validation {
    condition     = contains(["kubernetes", "dind", ""], var.runner_container_mode)
    error_message = "runner_container_mode must be kubernetes, dind, or an empty string to leave it unset."
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
  description = "EC2 instance type for the workbench, as the _monolithic template had it. It only investigates the cluster here - the ARC install is done by the helm provider rather than by a script on the instance"

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
  description = "How long the README association may take. It waits for the registration check, which itself waits for the instance bootstrap that downloads kubectl, eksctl and helm"

  validation {
    condition     = var.readme_timeout_seconds > 0
    error_message = "readme_timeout_seconds must be positive."
  }
}
variable "verify_attempts" {
  type        = number
  default     = 60
  description = "How many times, ten seconds apart, the registration check looks for an AutoscalingListener before failing. Registration is a round trip to GitHub that starts when the controller first reconciles the scale set, so the check polls rather than reading once"

  validation {
    condition     = var.verify_attempts >= 1
    error_message = "verify_attempts must be at least 1."
  }
}
variable "verify_timeout_seconds" {
  type        = number
  default     = 1200
  description = <<-DESC
    How long the registration check may take, counted from when its SSM association is created.

    It covers two waits: the instance bootstrap it blocks on first, and then verify_attempts ten-second polls.
    If SSM gives up before the polling does, the failure is a bare "unexpected state 'Failed'" with none of the
    controller log the check was about to print - so this has to be the larger of the two.
  DESC

  validation {
    condition     = var.verify_timeout_seconds > 0
    error_message = "verify_timeout_seconds must be positive."
  }
  validation {
    # A constraint about the pair rather than about either number, so it is written as a cross-variable
    # condition (rules.md B-1). 300 seconds of margin for the bootstrap this check waits on.
    condition     = var.verify_timeout_seconds >= var.verify_attempts * 10 + 300
    error_message = "verify_timeout_seconds must leave room for verify_attempts ten-second polls plus the instance bootstrap the check waits for - at least verify_attempts * 10 + 300. Otherwise SSM reports a timeout before the check can print the controller log that explains the failure."
  }
}
