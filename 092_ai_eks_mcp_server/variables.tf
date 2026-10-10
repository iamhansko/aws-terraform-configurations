variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.). It also becomes the AWS_REGION the EKS MCP server runs with, so the region Q operates in is the region this is applied to"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region such as ap-northeast-2, or null to fall back to the provider default chain."
  }
}
variable "cluster_name" {
  type        = string
  default     = "q-cli-eks-cluster"
  description = "Name of the EKS cluster, and the basis for the VPC, key pair and cache policy names. The _monolithic template derived every name from a stack_name standing in for AWS::StackName"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,99}$", var.cluster_name))
    error_message = "cluster_name must start with a letter or digit and contain only letters, digits, hyphens and underscores (100 characters or fewer)."
  }
}
variable "kubernetes_version" {
  type        = string
  default     = "1.34"
  description = "Kubernetes version for the EKS cluster. 1.34 rather than the _monolithic template's 1.33, matching the rest of this repository"

  validation {
    condition     = can(regex("^1\\.(3[0-9]|[4-9][0-9])$", var.kubernetes_version))
    error_message = "kubernetes_version must be a supported 1.XX version, e.g. 1.34."
  }
}
variable "kubectl_download_version" {
  type        = string
  default     = "1.34.11/2026-09-22"
  description = "Version path used to download kubectl onto the workbench, in <version>/<release-date> form. Raised together with kubernetes_version: kubectl more than one minor from the API server is outside the supported skew (rules.md H-1)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.34.11/2026-09-22."
  }
}
variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the EKS API server endpoint is reachable from the internet. True as the _monolithic template had it. Nothing outside the VPC needs it here - the workbench reaches the API server through the cluster security group - so this can be set false, which is the tighter configuration"
}
variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDR blocks allowed to reach the public API server endpoint, when it is enabled. Set this to your own address in CIDR form: bootstrap_cluster_creator_admin_permissions means anyone who can reach this endpoint with a valid AWS credential for the creating principal has cluster-admin"

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
  description = "Maximum node count, four as the _monolithic template had it. Nothing scales this node group - but it is the headroom an MCP server asked to scale a deployment would have"

  validation {
    condition     = var.node_group_max_size >= 1
    error_message = "node_group_max_size must be at least 1."
  }
  validation {
    condition     = var.node_group_max_size >= var.node_group_min_size
    error_message = "node_group_max_size must be greater than or equal to node_group_min_size."
  }
}
variable "node_group_labels" {
  type = map(string)
  default = {
    "node-type" = "core"
  }
  description = "Kubernetes labels on the nodes, as the _monolithic template set them. Nothing selects on them here, and they are kept because they give Q something to find when asked about the cluster's topology"

  validation {
    condition     = alltrue([for key in keys(var.node_group_labels) : length(key) > 0])
    error_message = "node_group_labels must not contain empty label keys."
  }
}
variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "EC2 instance type for the workbench, as the _monolithic template had it. It runs code-server, the Q CLI, and the MCP servers Q starts as child processes - each of which is a Python process fetched with uvx"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must be a valid EC2 instance type, e.g. t3.medium."
  }
}
variable "code_server_version" {
  type        = string
  default     = "4.102.3"
  description = "code-server release installed on the workbench, pinned as the _monolithic template pinned it. Most projects in this repository resolve the latest release at boot; this one is pinned, and pinned is the better half of that difference - the cache policy in front of it is tuned to a known version's behaviour"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a semantic version, e.g. 4.102.3."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = false
  description = <<-DESC
    Whether the workbench security group accepts traffic from 0.0.0.0/0 on the code-server port.

    False, which is the point of this project's shape: the instance is reached through CloudFront, and its
    only ingress rule is the CloudFront origin-facing prefix list. That is the one thing this template does
    better than most of the others in this repository, which open 8000 to the world.

    Setting it true does not disable the prefix list rule - it adds a second, wider one - so it is a way to
    bypass CloudFront for debugging rather than a replacement for it.
  DESC
}
variable "cloudfront_prefix_list_name" {
  type        = string
  default     = "com.amazonaws.global.cloudfront.origin-facing"
  description = "Managed prefix list whose addresses the workbench accepts. Looked up by name, where the _monolithic template carried a 17-region mapping of hardcoded prefix list ids - a table that goes stale silently and has no entry at all for a region not in it"

  validation {
    condition     = can(regex("^com\\.amazonaws\\.", var.cloudfront_prefix_list_name))
    error_message = "cloudfront_prefix_list_name must be an AWS managed prefix list name, which all begin com.amazonaws."
  }
}
variable "cloudfront_origin_request_policy_name" {
  type        = string
  default     = "Managed-AllViewer"
  description = "Managed origin request policy the distribution uses, looked up by name. The _monolithic template wrote the bare uuid 216adef6-5c7f-47e4-b989-5492eafa07d3 - which is this policy, and says so nowhere. AllViewer forwards every header, cookie and query string, which is what code-server's WebSocket upgrade needs"

  validation {
    condition     = can(regex("^Managed-", var.cloudfront_origin_request_policy_name))
    error_message = "cloudfront_origin_request_policy_name must name one of CloudFront's managed policies, which are all prefixed Managed-."
  }
}
variable "cloudfront_price_class" {
  type        = string
  default     = "PriceClass_200"
  description = "Which edge locations serve the distribution. The _monolithic template left it unset, which is PriceClass_All - every location, for a distribution one person uses"

  validation {
    condition     = contains(["PriceClass_All", "PriceClass_200", "PriceClass_100"], var.cloudfront_price_class)
    error_message = "cloudfront_price_class must be PriceClass_All, PriceClass_200 or PriceClass_100."
  }
}
variable "mcp_servers" {
  type = map(object({
    command     = string
    args        = list(string)
    env         = optional(map(string), {})
    disabled    = optional(bool, false)
    autoApprove = optional(list(string), [])
  }))
  default = {
    "awslabs.aws-documentation-mcp-server" = {
      command = "uvx"
      args    = ["awslabs.aws-documentation-mcp-server@latest"]
      env = {
        FASTMCP_LOG_LEVEL           = "ERROR"
        AWS_DOCUMENTATION_PARTITION = "aws"
      }
    }
    "awslabs.eks-mcp-server" = {
      command = "uvx"
      args = [
        "awslabs.eks-mcp-server@latest",
        # The two flags that make this demo what it is, and the two worth understanding before applying it.
        # --allow-write lets the MCP server create and modify Kubernetes objects; --allow-sensitive-data-access
        # lets it read Secrets and pod logs. Combined with AdministratorAccess on the instance, an unauthenticated
        # code-server session can ask a language model to do anything in the account.
        "--allow-write",
        "--allow-sensitive-data-access",
      ]
      env = {
        FASTMCP_LOG_LEVEL = "ERROR"
      }
    }
  }
  description = <<-DESC
    MCP servers written into the Q CLI's configuration, as the _monolithic template configured them.

    A typed map rather than the escaped JSON string that template embedded in an SSM parameter, so the
    structure is checked at plan time and a missing brace is not an apply-time surprise (rules.md E-3 makes the
    same argument for Kubernetes manifests).

    AWS_REGION is added to the EKS server's environment by main.tf rather than being written here, so it comes
    from the provider's region and cannot name a different one.
  DESC

  validation {
    condition     = alltrue([for name in keys(var.mcp_servers) : length(name) > 0])
    error_message = "mcp_servers keys must not be empty - the key is the server name Q shows in its tool list."
  }
  validation {
    condition     = alltrue([for server in values(var.mcp_servers) : length(server.args) > 0])
    error_message = "every mcp_servers entry must have at least one argument - uvx with no package name starts nothing."
  }
}
variable "q_cli_download_url" {
  type        = string
  default     = "https://desktop-release.q.us-east-1.amazonaws.com/latest/q-x86_64-linux.zip"
  description = "Where the Amazon Q CLI is downloaded from, as the _monolithic template had it. It resolves to the latest release, which is deliberate for a tool whose whole value is current model access - and means two applies weeks apart install different versions"

  validation {
    condition     = can(regex("^https://", var.q_cli_download_url))
    error_message = "q_cli_download_url must be an https URL."
  }
}
variable "nvm_version" {
  type        = string
  default     = "v0.40.3"
  description = "nvm release used to install Node, as the _monolithic template pinned it. Node is here because some MCP servers are distributed as npm packages rather than Python ones"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.nvm_version))
    error_message = "nvm_version must look like v0.40.3."
  }
}
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the workbench where each step drops its completion marker. Three associations run here in order - tooling, Q CLI, then the README - and they are sequenced by these markers rather than by depends_on (rules.md D-5/H-2)"

  validation {
    condition     = var.marker_file_path == null || can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/', or null."
  }
}
variable "kubernetes_tooling_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the kubectl, eksctl and helm association may take. The _monolithic template allowed 180 seconds for this, which has to cover waiting for cloud-init to finish installing code-server first - so it would report Failed while the work was still running"

  validation {
    condition     = var.kubernetes_tooling_timeout_seconds > 0
    error_message = "kubernetes_tooling_timeout_seconds must be positive."
  }
}
variable "q_cli_timeout_seconds" {
  type        = number
  default     = 1800
  description = "How long the Q CLI association may take. The _monolithic template allowed 180 seconds to install Python, uv, nvm, Node and the Q CLI - nowhere near enough, and the association would have reported Failed on every apply"

  validation {
    condition     = var.q_cli_timeout_seconds > 0
    error_message = "q_cli_timeout_seconds must be positive."
  }
  validation {
    # Both run on the same instance and the second waits for the first's marker, so its budget has to cover
    # both (rules.md B-1/D-5).
    condition     = var.q_cli_timeout_seconds > var.kubernetes_tooling_timeout_seconds
    error_message = "q_cli_timeout_seconds must be greater than kubernetes_tooling_timeout_seconds: the Q CLI association waits for the tooling association's marker, so a smaller budget makes it give up on a step that is still running."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 2400
  description = "How long the README association may take. It waits for the Q CLI association, so its budget has to cover the whole chain"

  validation {
    condition     = var.readme_timeout_seconds > 0
    error_message = "readme_timeout_seconds must be positive."
  }
  validation {
    condition     = var.readme_timeout_seconds > var.q_cli_timeout_seconds
    error_message = "readme_timeout_seconds must be greater than q_cli_timeout_seconds: the README association waits for it to finish, and SSM reports a timeout only as \"unexpected state 'Failed'\"."
  }
}
