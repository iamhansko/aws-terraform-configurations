variable "aws_region" {
  type        = string
  default     = null
  description = "Region to deploy into. Null follows the provider chain (AWS_REGION / AWS_DEFAULT_REGION), which is how the _monolithic template was run. It is also the AWS_REGION the ECS MCP server runs with, so the region Q operates in is the region the cluster is in"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a region code such as ap-northeast-2, or null to follow the provider chain."
  }
}
variable "project_name" {
  type        = string
  default     = "q-cli"
  description = "Prefix for the generated names - the ECS cluster, the capacity provider, the cache policy, the security groups, the key pair and the Name tags. Stands in for the _monolithic template's stack_name and keeps its default, so the cluster, capacity provider and cache policy carry exactly the names the template gave them. 090_ai_aws_diagram_mcp_server had the same default and now uses q-cli-diagram: both derive the account-unique cache policy name from this value, so the two could not otherwise be applied side by side in one account"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,29}$", var.project_name))
    error_message = "project_name must be 2-30 characters of lowercase letters, digits and hyphens, starting with a letter."
  }
  validation {
    # The capacity provider is named <project_name>-ecs-ec2-capacity-provider, and ECS rejects a capacity
    # provider name starting with aws, ecs or fargate - at apply, after the cluster and the Auto Scaling group
    # exist. ecs-mcp is the name this project would most naturally get, and it is exactly the one that fails.
    condition     = !can(regex("^(aws|ecs|fargate)", var.project_name))
    error_message = "project_name must not start with aws, ecs or fargate, because it prefixes the capacity provider name and ECS reserves those prefixes - keep something like the default q-cli instead."
  }
}
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC, as the _monolithic template had it. Zone letter n gets public /24 number 2n and private /24 number 2n+1, which for zones a and b is exactly the template's AzMapping"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0)) && tonumber(split("/", var.vpc_cidr_block)[1]) <= 24
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block of /24 or shorter, because the subnets are carved out of it as /24s."
  }
}
variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "b"]
  description = "The two AZ letters the subnets, the NAT gateways and the container instances are placed in, as the _monolithic template used them. The workbench goes into the first"

  validation {
    condition     = length(var.availability_zone_suffixes) == 2 && alltrue([for suffix in var.availability_zone_suffixes : can(regex("^[a-z]$", suffix))])
    error_message = "availability_zone_suffixes must contain exactly two single lowercase letters."
  }
  validation {
    condition     = var.availability_zone_suffixes[0] != var.availability_zone_suffixes[1]
    error_message = "availability_zone_suffixes entries must differ - the Auto Scaling group is balanced across two zones."
  }
}
variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type for the workbench, as the _monolithic template had it. It runs code-server, the Q CLI, every MCP server Q starts as a child process, and the docker builds the ECS MCP server runs when asked to containerize an application"

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
variable "ecs_ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
  description = "SSM public parameter resolved to the container instance AMI, as the _monolithic template's ecs_ami_id parameter. It has to be an ECS-optimized image - the agent comes from the AMI - and its architecture has to match container_instance_type; this one is x86_64"

  validation {
    condition     = can(regex("^/aws/service/ecs/", var.ecs_ami_ssm_parameter_name))
    error_message = "ecs_ami_ssm_parameter_name must be one of the ECS-optimized AMI public parameters under /aws/service/ecs/ - a plain Amazon Linux AMI launches, has no ECS agent, and never joins the cluster."
  }
}
variable "container_insights" {
  type        = string
  default     = "enhanced"
  description = "containerInsights setting of the cluster, enhanced as the _monolithic template set it. It bills per observed resource"

  validation {
    condition     = contains(["enhanced", "enabled", "disabled"], var.container_insights)
    error_message = "container_insights must be enhanced, enabled or disabled."
  }
}
variable "container_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type of the ECS container instances, as the _monolithic template had it. x86_64, to match ecs_ami_ssm_parameter_name and the images docker builds on the x86_64 workbench"

  validation {
    condition     = can(regex("^[a-z0-9]+[a-z0-9-]*\\.[a-z0-9]+$", var.container_instance_type))
    error_message = "container_instance_type must be a valid EC2 instance type, e.g. t3.medium."
  }
}
variable "container_instance_min_size" {
  type        = number
  default     = 1
  description = "Minimum container instances, as the _monolithic template had it. Managed scaling settles here while nothing is running"

  validation {
    condition     = var.container_instance_min_size >= 0
    error_message = "container_instance_min_size must be zero or greater."
  }
}
variable "container_instance_desired_capacity" {
  type        = number
  default     = 2
  description = "Container instances launched up front, as the _monolithic template had it. ECS managed scaling owns the group's desired count once the capacity provider is attached, so this is the starting point only"

  validation {
    condition     = var.container_instance_desired_capacity >= var.container_instance_min_size && var.container_instance_desired_capacity <= var.container_instance_max_size
    error_message = "container_instance_desired_capacity must be between container_instance_min_size and container_instance_max_size inclusive."
  }
}
variable "container_instance_max_size" {
  type        = number
  default     = 6
  description = "Maximum container instances, as the _monolithic template had it - the headroom managed scaling has when Q deploys a service onto the EC2 capacity provider"

  validation {
    condition     = var.container_instance_max_size >= 1 && var.container_instance_max_size >= var.container_instance_min_size
    error_message = "container_instance_max_size must be at least 1 and at least container_instance_min_size."
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
    "awslabs.ecs-mcp-server" = {
      command = "uvx"
      # Pinned, where the _monolithic template took whatever version was current at each start. --from because
      # the package's command is ecs-mcp-server rather than its own name.
      args = ["--from", "awslabs-ecs-mcp-server==0.1.36", "ecs-mcp-server"]
      # AWS_REGION, FASTMCP_LOG_FILE, ALLOW_WRITE and ALLOW_SENSITIVE_DATA are merged in by main.tf rather than
      # written here, so each comes from the one variable or provider setting that owns it (rules.md B-5).
      env = {
        FASTMCP_LOG_LEVEL = "ERROR"
      }
    }
  }
  description = <<-DESC
    MCP servers written into the Q CLI's configuration, as the _monolithic template configured them.

    A typed map rather than the escaped JSON string that template embedded in an SSM parameter, so the structure
    is checked at plan time and the file Q reads is produced by jsonencode rather than assembled by hand.

    The awslabs.ecs-mcp-server entry is required: main.tf merges the region, the log file and the two
    permission switches into its environment by that name, and without it this project has no reason to exist.
  DESC

  validation {
    condition     = alltrue([for name in keys(var.mcp_servers) : can(regex("^[a-zA-Z0-9._-]+$", name))])
    error_message = "mcp_servers keys must be non-empty names of letters, digits, dots, underscores and hyphens - the key is the server name Q shows in its tool list."
  }
  validation {
    condition     = alltrue([for server in values(var.mcp_servers) : length(server.command) > 0 && length(server.args) > 0])
    error_message = "every mcp_servers entry needs a command and at least one argument - uvx with no package name starts nothing."
  }
  validation {
    condition     = contains(keys(var.mcp_servers), "awslabs.ecs-mcp-server")
    error_message = "mcp_servers must keep the awslabs.ecs-mcp-server entry. main.tf merges AWS_REGION, FASTMCP_LOG_FILE, ALLOW_WRITE and ALLOW_SENSITIVE_DATA into it by that key, so renaming it would silently drop all four."
  }
}
variable "ecs_mcp_server_allow_write" {
  type        = bool
  default     = true
  description = "ALLOW_WRITE for the ECS MCP server, a bool where the _monolithic template wrote the string \"true\". True as it had it: Q may build and push images, create ECR repositories through CloudFormation, and deploy and delete ECS services - using the workbench role, which is AdministratorAccess. The server's own documentation says to turn this off against any account that matters"
}
variable "ecs_mcp_server_allow_sensitive_data" {
  type        = bool
  default     = true
  description = "ALLOW_SENSITIVE_DATA for the ECS MCP server, a bool where the _monolithic template wrote the string \"true\". True as it had it: the troubleshooting tools return container logs, service events and task failure details, and container environment values and secret references come back unredacted - which is where an application's configuration, and often its credentials, are"
}
variable "ecs_mcp_server_log_dir" {
  type        = string
  default     = "/home/ec2-user/ecs"
  description = "Directory the ECS MCP server writes its log file into, as the _monolithic template had it. The Q CLI association creates it - the server opens the file at start and does not create a missing directory - and FASTMCP_LOG_FILE is derived from it, so the two cannot disagree"

  validation {
    # Interpolated into a shell command unquoted, and written by ec2-user.
    condition     = can(regex("^/home/ec2-user/[A-Za-z0-9._/-]+$", var.ecs_mcp_server_log_dir))
    error_message = "ecs_mcp_server_log_dir must be a path under /home/ec2-user/ of letters, digits, dots, underscores, hyphens and slashes, because ec2-user runs the server and has to be able to write it."
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
