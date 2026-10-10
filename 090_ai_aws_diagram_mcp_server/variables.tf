variable "aws_region" {
  type        = string
  default     = null
  description = "Region to deploy into. Null follows the provider chain (AWS_REGION / AWS_DEFAULT_REGION), which is how the _monolithic template was run"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a region code such as ap-northeast-2, or null to follow the provider chain."
  }
}
variable "project_name" {
  type        = string
  default     = "q-cli-diagram"
  description = "Prefix for the generated names - the cache policy, the security group, the key pair and the Name tags. Stands in for the _monolithic template's stack_name, whose default q-cli it shared with 091_ai_ecs_mcp_server. Both derive the account-unique cache policy name VSCode-<project_name> from it, so with one default the two projects could not be applied side by side in one account; 091 keeps q-cli and this one does not"

  validation {
    # The cache policy name is VSCode-<project_name> and is unique per account, so this is also what keeps two
    # copies of the project apart.
    condition     = can(regex("^[a-z][a-z0-9-]{1,29}$", var.project_name))
    error_message = "project_name must be 2-30 characters of lowercase letters, digits and hyphens, starting with a letter."
  }
}
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC, as the _monolithic template had it. The public subnet is its first /24, which is the template's AzMapping a.PublicSubnetCidr"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0)) && tonumber(split("/", var.vpc_cidr_block)[1]) <= 24
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block of /24 or shorter, because the subnet is carved out of it as a /24."
  }
}
variable "availability_zone_suffix" {
  type        = string
  default     = "a"
  description = "AZ letter the public subnet and the workbench are placed in, appended to the region name, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z]$", var.availability_zone_suffix))
    error_message = "availability_zone_suffix must be a single lowercase letter."
  }
}
variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type for the workbench, as the _monolithic template had it. It runs code-server, the Q CLI, and every MCP server Q starts as a child process - each a separate Python process fetched with uvx, and the diagram server renders with GraphViz on top of that"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must be a valid EC2 instance type, e.g. t3.medium."
  }
}
variable "vscode_ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "SSM public parameter resolved to the workbench AMI, as the _monolithic template's ami_id parameter. x86_64 because the code-server tarball and the Q CLI zip the bootstrap downloads are the x86_64 builds"

  validation {
    condition     = can(regex("^/", var.vscode_ami_ssm_parameter_name))
    error_message = "vscode_ami_ssm_parameter_name must be an absolute SSM parameter path starting with '/'."
  }
}
variable "code_server_version" {
  type        = string
  default     = "4.102.3"
  description = "code-server release installed on the workbench, pinned as the _monolithic template pinned it"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a semantic version, e.g. 4.102.3."
  }
}
variable "cloudfront_prefix_list_name" {
  type        = string
  default     = "com.amazonaws.global.cloudfront.origin-facing"
  description = "Managed prefix list whose addresses the workbench accepts on the code-server port. Looked up by name, where the _monolithic template carried a 17-region mapping of hardcoded prefix list IDs - a table that goes stale silently and has no entry at all for a region not in it"

  validation {
    condition     = can(regex("^com\\.amazonaws\\.", var.cloudfront_prefix_list_name))
    error_message = "cloudfront_prefix_list_name must be an AWS managed prefix list name, which all begin com.amazonaws."
  }
}
variable "cloudfront_origin_request_policy_name" {
  type        = string
  default     = "Managed-AllViewer"
  description = "Managed origin request policy the distribution uses, looked up by name. The _monolithic template wrote the bare uuid 216adef6-5c7f-47e4-b989-5492eafa07d3, which is this policy and says so nowhere. AllViewer forwards every header, cookie and query string, which is what the WebSocket the code-server terminal runs over needs"

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
      # Pinned, where the _monolithic template ran @latest: uvx resolves @latest at every start of the server, so
      # the tool list Q sees could change between two sessions on the same instance.
      args = ["awslabs.aws-documentation-mcp-server@1.2.2"]
      env = {
        FASTMCP_LOG_LEVEL           = "ERROR"
        AWS_DOCUMENTATION_PARTITION = "aws"
      }
    }
    "awslabs.aws-diagram-mcp-server" = {
      command = "uvx"
      # Pinned to 1.0.23, the last release. The package is deprecated upstream in favour of an agent skill and
      # will not be updated again, so the pin is also the version every future install would get. It needs
      # GraphViz's dot on the PATH, which the _monolithic template never installed - the Q CLI association
      # installs it now (main.tf).
      args = ["awslabs.aws-diagram-mcp-server@1.0.23"]
      env = {
        FASTMCP_LOG_LEVEL = "ERROR"
      }
    }
  }
  description = <<-DESC
    MCP servers written into the Q CLI's configuration, as the _monolithic template configured them.

    A typed map rather than the escaped JSON string that template embedded in an SSM parameter. That string was
    not valid JSON - it closed one more brace than it opened, after the diagram server's entry - so Q would
    have found a configuration file it could not parse. Built from this map with jsonencode, the file cannot be
    malformed, and its structure is checked at plan time.

    Both servers are pinned rather than @latest; see the comments on each.
  DESC

  validation {
    condition     = alltrue([for name in keys(var.mcp_servers) : can(regex("^[a-zA-Z0-9._-]+$", name))])
    error_message = "mcp_servers keys must be non-empty names of letters, digits, dots, underscores and hyphens - the key is the server name Q shows in its tool list."
  }
  validation {
    condition     = alltrue([for server in values(var.mcp_servers) : length(server.command) > 0 && length(server.args) > 0])
    error_message = "every mcp_servers entry needs a command and at least one argument - uvx with no package name starts nothing."
  }
}
variable "uv_version" {
  type        = string
  default     = "0.12.23"
  description = "uv release installed for the workbench user. uv provides uvx, which is how every MCP server above is started. Pinned through the versioned installer URL, where the _monolithic template installed whatever astral.sh served that day"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.uv_version))
    error_message = "uv_version must be a semantic version, e.g. 0.12.23."
  }
}
variable "nvm_version" {
  type        = string
  default     = "v0.40.3"
  description = "nvm release used to install Node, as the _monolithic template pinned it. Neither default MCP server needs Node; it is there for MCP servers distributed as npm packages, which a user may add"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.nvm_version))
    error_message = "nvm_version must look like v0.40.3."
  }
}
variable "node_version" {
  type        = string
  default     = "24"
  description = "Node release line nvm installs. The _monolithic template ran nvm install --lts, which installs whichever line is LTS on the day of the boot; a major version here resolves to that line's newest release, so two boots months apart get the same major"

  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+){0,2}$", var.node_version))
    error_message = "node_version must be a Node version or release line, e.g. 24 or 24.11.1."
  }
}
variable "q_cli_download_url" {
  type        = string
  default     = "https://desktop-release.q.us-east-1.amazonaws.com/latest/q-x86_64-linux.zip"
  description = "Where the Amazon Q CLI is downloaded from, as the _monolithic template had it. Left at latest on purpose: the CLI updates itself after install - it has since become the Kiro CLI, with q and q chat kept working - so pinning the zip would pin only the first few minutes"

  validation {
    condition     = can(regex("^https://", var.q_cli_download_url))
    error_message = "q_cli_download_url must be an https URL."
  }
}
variable "marker_file_path" {
  type        = string
  default     = "/var/lib/terraform"
  description = "Directory on the workbench where each step drops its completion marker: the bootstrap, then the Q CLI association, then the README association, each waiting for the previous one's marker (rules.md D-5/H-2). Under /var/lib rather than the /run used elsewhere in this repository, because /run is emptied on every boot - the Q CLI association re-runs when mcp_servers changes, and after a stop and start of the workbench it would wait for a userdata marker that was gone and fail at its timeout"

  validation {
    # Interpolated into shell commands unquoted, so whitespace or shell metacharacters would split or change them.
    condition     = can(regex("^/[A-Za-z0-9._/-]+$", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path of letters, digits, dots, underscores, hyphens and slashes."
  }
}
variable "q_cli_timeout_seconds" {
  type        = number
  default     = 1800
  description = "How long the Q CLI association may take, including its wait for the bootstrap to finish. The _monolithic template allowed 180 seconds to install Python, docker, uv, nvm, Node and the Q CLI, while its association also started concurrently with a bootstrap that runs dnf update and installs Development Tools - so it reported Failed while the work was still running"

  validation {
    condition     = var.q_cli_timeout_seconds >= 300
    error_message = "q_cli_timeout_seconds must be at least 300."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 2400
  description = "How long the README association may take. It waits for the Q CLI association's marker, so its budget has to cover that whole step"

  validation {
    condition     = var.readme_timeout_seconds > 0
    error_message = "readme_timeout_seconds must be positive."
  }
  validation {
    condition     = var.readme_timeout_seconds > var.q_cli_timeout_seconds
    error_message = "readme_timeout_seconds must be greater than q_cli_timeout_seconds: the README association waits for that step to finish, and SSM reports a timeout only as \"unexpected state 'Failed'\"."
  }
}
