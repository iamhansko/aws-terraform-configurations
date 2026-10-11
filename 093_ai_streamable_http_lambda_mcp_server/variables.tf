variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.). samconfig.toml pinned us-east-1 for sam deploy; nothing here depends on a particular region, so the provider chain decides"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region such as ap-northeast-2, or null to fall back to the provider default chain."
  }
}
variable "project_name" {
  type        = string
  default     = "mcp-lambda-handler"
  description = "Base for every name this root gives an account-wide resource: the functions, the table, the layer and its bucket, the token parameter, the API and the CloudFront cache policy. mcp-lambda-handler, the stack name samconfig.toml deployed under - the _monolithic template stood in a stack_name of q-cli for it"

  validation {
    # Lower case because it prefixes an S3 bucket name, and 30 characters so <name>-mcp-authorizer-function
    # stays inside Lambda's 64.
    condition     = can(regex("^[a-z][a-z0-9-]{0,28}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 2-30 characters of lower-case letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}
variable "vpc_cidr_block" {
  type        = string
  default     = "10.1.0.0/16"
  description = "CIDR block for the VPC, 10.1.0.0/16 as the _monolithic template had it"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0)) && tonumber(split("/", var.vpc_cidr_block)[1]) <= 24
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block of /24 or shorter, because the public subnet is carved out of it as a /24."
  }
}
variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "EC2 instance type for the workbench, as the _monolithic template had it. It runs code-server, builds the layer, and runs the Q CLI with the MCP servers it starts as child processes"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must be a valid EC2 instance type, e.g. t3.medium."
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
variable "vscode_iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/PowerUserAccess"]
  description = "Managed policies on the workbench role. PowerUserAccess, as the _monolithic template attached. It is broad on purpose - this is a person's workbench (rules.md A-5) - and it is also what Q acts with when started with --trust-all-tools. It covers the S3 upload of the layer package and the read of the token parameter"

  validation {
    condition     = length(var.vscode_iam_policy_arns) > 0 && alltrue([for arn in var.vscode_iam_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "vscode_iam_policy_arns must contain at least one valid IAM policy ARN."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = false
  description = "Whether the workbench security group also accepts the code-server port from 0.0.0.0/0. False: the instance is reached through CloudFront, and its only ingress rule is CloudFront's origin-facing prefix list, as the _monolithic template had it. True adds a second, wider rule beside that one - a way to bypass CloudFront while debugging, not a replacement for it"
}
variable "cloudfront_prefix_list_name" {
  type        = string
  default     = "com.amazonaws.global.cloudfront.origin-facing"
  description = "Managed prefix list whose addresses the workbench accepts, looked up by name. The _monolithic template carried a 17-region table of hardcoded prefix list ids, which has no entry at all for a region outside it"

  validation {
    condition     = can(regex("^com\\.amazonaws\\.", var.cloudfront_prefix_list_name))
    error_message = "cloudfront_prefix_list_name must be an AWS managed prefix list name, which all begin com.amazonaws."
  }
}
variable "cloudfront_origin_request_policy_name" {
  type        = string
  default     = "Managed-AllViewer"
  description = "Managed origin request policy the distribution uses, looked up by name. The _monolithic template wrote the bare uuid 216adef6-5c7f-47e4-b989-5492eafa07d3, which is this policy and says so nowhere"

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
variable "marker_file_path" {
  type        = string
  default     = "/var/lib/terraform"
  description = "Directory on the workbench where each step drops its completion marker. Three associations run in order - the layer build, the Q CLI, then the README - each waiting for the previous marker rather than relying on depends_on (rules.md D-5/H-2). Under /var/lib rather than the /run most of this repository uses, as 122_eks_multi_cluster_application_management_with_karmada explains: /run is a tmpfs emptied on every boot, so after a stop and start of the workbench an association re-run by a parameter change would wait for a userdata marker that is gone and fail at its timeout"

  validation {
    condition     = can(regex("^/[a-zA-Z0-9/._-]*$", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path of letters, digits and /._- characters."
  }
}
variable "lambda_python_version" {
  type        = string
  default     = "3.13"
  description = "Python version of both functions, of the layer's build and of the runtime the layer declares. One value, because a layer built for one Python and attached to another is the mismatch that only an import error at the first invocation reports. 3.13, as the _monolithic template had it"

  validation {
    # It has to be a Lambda runtime and an Amazon Linux 2023 package (the build runs python3.X -m pip), and at
    # least 3.11 because the server code imports datetime.UTC.
    condition     = contains(["3.11", "3.12", "3.13"], var.lambda_python_version)
    error_message = "lambda_python_version must be 3.11, 3.12 or 3.13."
  }
}
variable "lambda_architecture" {
  type        = string
  default     = "x86_64"
  description = "Instruction set architecture of both functions, and the platform the layer's packages are fetched for. The _monolithic template declared the layer compatible with x86_64 and arm64 while fetching manylinux2014_x86_64 wheels only - true of today's pure-Python dependencies by accident, and not of the next one that ships a compiled extension"

  validation {
    condition     = contains(["x86_64", "arm64"], var.lambda_architecture)
    error_message = "lambda_architecture must be x86_64 or arm64."
  }
}
variable "mcp_lambda_handler_version" {
  type        = string
  default     = "0.1.15"
  description = "Version of awslabs.mcp_lambda_handler built into the layer. The _monolithic template installed whatever was latest on the day the association ran; the upstream sample pinned 0.1.6. Pinned to the release the server code was checked against"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.mcp_lambda_handler_version))
    error_message = "mcp_lambda_handler_version must be a three-part version, e.g. 0.1.15."
  }
}
variable "authorizer_timeout_seconds" {
  type        = number
  default     = 10
  description = "Seconds the authorizer may take. It compares a header with a value read once per execution environment; the _monolithic template gave it the SAM Globals 60, which only makes a hung invocation slower to fail"

  validation {
    condition     = var.authorizer_timeout_seconds >= 3 && var.authorizer_timeout_seconds <= 29 && floor(var.authorizer_timeout_seconds) == var.authorizer_timeout_seconds
    error_message = "authorizer_timeout_seconds must be an integer between 3 and 29."
  }
}
variable "mcp_server_timeout_seconds" {
  type        = number
  default     = 29
  description = "Seconds the MCP server function may take. 29 rather than the _monolithic template's 60, because API Gateway stops waiting for a Lambda proxy integration after 29 seconds by default - past that the client has its 504 and the function runs on for nobody"

  validation {
    condition     = var.mcp_server_timeout_seconds >= 3 && var.mcp_server_timeout_seconds <= 29 && floor(var.mcp_server_timeout_seconds) == var.mcp_server_timeout_seconds
    error_message = "mcp_server_timeout_seconds must be an integer between 3 and 29 - API Gateway gives up on the integration after 29 seconds."
  }
}
variable "log_retention_in_days" {
  type        = number
  default     = 7
  description = "Days both functions' log groups keep events. The _monolithic template created no log groups, so Lambda made them on first invocation with no expiry"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365], var.log_retention_in_days)
    error_message = "log_retention_in_days must be one of 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180 or 365."
  }
}
variable "mcp_auth_token_length" {
  type        = number
  default     = 32
  description = "Length of the generated bearer token, letters and digits only. The _monolithic template used a fixed word, Peccy, as the default of a plain variable"

  validation {
    condition     = var.mcp_auth_token_length >= 20 && var.mcp_auth_token_length <= 128 && floor(var.mcp_auth_token_length) == var.mcp_auth_token_length
    error_message = "mcp_auth_token_length must be an integer between 20 and 128."
  }
}
variable "authorizer_result_ttl_in_seconds" {
  type        = number
  default     = 300
  description = "How long API Gateway caches the authorizer's answer for a token - 300, the ReauthorizeEvery the SAM template set. It is also how long a rotated-out token keeps working"

  validation {
    condition     = var.authorizer_result_ttl_in_seconds >= 0 && var.authorizer_result_ttl_in_seconds <= 3600 && floor(var.authorizer_result_ttl_in_seconds) == var.authorizer_result_ttl_in_seconds
    error_message = "authorizer_result_ttl_in_seconds must be an integer between 0 and 3600."
  }
}
variable "api_stage_name" {
  type        = string
  default     = "Prod"
  description = "Stage the API is deployed to, the first path segment of the MCP URL. Prod, the StageName the SAM template set"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_]{1,128}$", var.api_stage_name))
    error_message = "api_stage_name must be 1-128 characters of letters, digits and underscores."
  }
}
variable "mcp_server_name" {
  type        = string
  default     = "streamable-http-mcp-server"
  description = "Name the Lambda MCP server is listed under in the Q CLI configuration, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.mcp_server_name))
    error_message = "mcp_server_name must contain only letters, digits, dots, underscores and hyphens - it is also the header file's name on the workbench."
  }
  validation {
    # Both end up as keys of the same mcpServers object, and the later one would silently replace the other.
    condition     = !contains(keys(var.mcp_servers), var.mcp_server_name)
    error_message = "mcp_server_name must not also be a key of mcp_servers - both are entries of one mcpServers object, and one would silently replace the other."
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
  }
  description = "MCP servers written into the Q CLI configuration besides the Lambda one, which main.tf adds from the API's URL. A typed map rather than the escaped JSON string the _monolithic template embedded in its SSM command, so a missing brace is a plan error and not a file Q silently fails to parse"

  validation {
    condition     = alltrue([for name in keys(var.mcp_servers) : length(name) > 0])
    error_message = "mcp_servers keys must not be empty - the key is the server name Q shows."
  }
  validation {
    condition     = alltrue([for server in values(var.mcp_servers) : length(server.command) > 0 && length(server.args) > 0])
    error_message = "every mcp_servers entry needs a command and at least one argument - uvx with no package starts nothing."
  }
}
variable "mcp_remote_version" {
  type        = string
  default     = "0.14.3"
  description = "mcp-remote release installed on the workbench to bridge Q's stdio to the streamable HTTP endpoint. The _monolithic template ran it unpinned through npx, which downloaded it during the first Q start - the likely reason its README says to restart Q when a server fails to load. The release has to support --header-file, which is how the token reaches it without being in its arguments; 0.14.3 does. The npm package's repository moved from geelen/mcp-remote to punkpeye/mcp-remote in 2026 (a GitHub transfer), so review a newer release before raising this"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.mcp_remote_version))
    error_message = "mcp_remote_version must be a three-part version, e.g. 0.14.3."
  }
}
variable "q_cli_download_url" {
  type        = string
  default     = "https://desktop-release.q.us-east-1.amazonaws.com/latest/q-x86_64-linux.zip"
  description = "Where the Amazon Q CLI is downloaded from, as the _monolithic template had it. latest, so two applies weeks apart install different versions"

  validation {
    condition     = can(regex("^https://", var.q_cli_download_url))
    error_message = "q_cli_download_url must be an https URL."
  }
}
variable "nvm_version" {
  type        = string
  default     = "v0.40.3"
  description = "nvm release used to install Node, which mcp-remote runs on, as the _monolithic template pinned it"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.nvm_version))
    error_message = "nvm_version must look like v0.40.3."
  }
}
variable "lambda_layer_build_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the layer build association may take, including its wait for the workbench bootstrap - a dnf update and the Development Tools group. The _monolithic template gave the build 180 seconds and started it alongside that bootstrap, racing it for the dnf lock. It is the build association's wait, and the timeout of the function that waits for the package, which is the wait that actually holds the apply. That function is capped at 900 seconds, the longest Lambda runs; a build slower than that fails the apply without failing the build, and the next terraform apply waits again"

  validation {
    # An integer because the waiting function's timeout is min(this, 900), and Lambda takes whole seconds.
    condition     = var.lambda_layer_build_timeout_seconds >= 60 && floor(var.lambda_layer_build_timeout_seconds) == var.lambda_layer_build_timeout_seconds
    error_message = "lambda_layer_build_timeout_seconds must be an integer of at least 60."
  }
}
variable "q_cli_timeout_seconds" {
  type        = number
  default     = 1200
  description = "How long the Q CLI association may take: uv, nvm, Node, mcp-remote and the Q CLI. The _monolithic template allowed 180 seconds for that, running at the same time as the layer build"

  validation {
    condition     = var.q_cli_timeout_seconds >= 60
    error_message = "q_cli_timeout_seconds must be at least 60."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 600
  description = "How long the README association may take. It waits for the Q CLI association's marker"

  validation {
    condition     = var.readme_timeout_seconds >= 60
    error_message = "readme_timeout_seconds must be at least 60."
  }
}
