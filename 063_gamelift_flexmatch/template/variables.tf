variable "aws_region" {
  type        = string
  default     = null
  description = "Region to deploy into, given to both the aws and the awscc provider. Null follows each provider's chain (AWS_REGION / AWS_DEFAULT_REGION), which is how the _monolithic template was run - the root's check block reports it if the two providers resolve different regions"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", coalesce(var.aws_region, "-")))
    error_message = "aws_region must be a region code such as ap-northeast-2, or null to follow the provider chain."
  }
}
variable "project_name" {
  type        = string
  default     = "gomoku"
  description = "Prefix for the names CloudFormation used to generate - the buckets, the IAM roles, the key pair, the ElastiCache subnet group and the SSM associations. The names the _monolithic template spelled out literally are separate variables below, defaulting to those literals"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.project_name)) && length(var.project_name) <= 16
    error_message = "project_name must be 1-16 lowercase letters, digits and hyphens starting with a letter, so the derived bucket prefixes (37 characters) and IAM name prefixes (38) stay inside their limits."
  }
}
# --- Network --------------------------------------------------------------------------------------------------
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
  default     = ["a", "b"]
  description = "The two AZ letters the subnet pairs are placed in, as the _monolithic template's AzMapping used them"

  validation {
    condition     = length(var.availability_zone_suffixes) == 2 && alltrue([for suffix in var.availability_zone_suffixes : can(regex("^[a-z]$", suffix))])
    error_message = "availability_zone_suffixes must be two single lowercase letters."
  }
}
variable "public_subnet_cidr_blocks" {
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.2.0/24"]
  description = "CIDR blocks of the public subnets in zone order, the _monolithic template's AzMapping values"

  validation {
    condition     = length(var.public_subnet_cidr_blocks) == 2 && alltrue([for cidr in var.public_subnet_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "public_subnet_cidr_blocks must be two valid IPv4 CIDR blocks."
  }
}
variable "private_subnet_cidr_blocks" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.3.0/24"]
  description = "CIDR blocks of the private subnets in zone order, the _monolithic template's AzMapping values"

  validation {
    condition     = length(var.private_subnet_cidr_blocks) == 2 && alltrue([for cidr in var.private_subnet_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "private_subnet_cidr_blocks must be two valid IPv4 CIDR blocks."
  }
}
# --- Workbench ------------------------------------------------------------------------------------------------
variable "ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "Public SSM parameter holding the workbench AMI ID, as the _monolithic template resolved it"

  validation {
    condition     = startswith(var.ami_ssm_parameter_name, "/")
    error_message = "ami_ssm_parameter_name must be an SSM parameter path starting with '/'."
  }
}
variable "vscode_instance_name" {
  type        = string
  default     = "vscode"
  description = "Name tag of the workbench instance, as the _monolithic template had it"

  validation {
    condition     = length(var.vscode_instance_name) > 0
    error_message = "vscode_instance_name must not be empty."
  }
}
variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type of the workbench, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9-]+\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must be an EC2 instance type such as t3.medium."
  }
}
variable "vscode_security_group_name" {
  type        = string
  default     = "vscode-sg"
  description = "Name of the workbench's security group, as the _monolithic template had it. Unique per VPC only, so it does not collide across deployments"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]+$", var.vscode_security_group_name)) && length(var.vscode_security_group_name) <= 255 && !startswith(var.vscode_security_group_name, "sg-")
    error_message = "vscode_security_group_name must be 1-255 characters from the set AWS accepts for a security group name, with no apostrophe, and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "code_server_version" {
  type        = string
  default     = "4.102.3"
  description = "code-server release installed on the workbench, as the _monolithic template pinned it"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a semantic version such as 4.102.3."
  }
}
variable "code_server_port" {
  type        = number
  default     = 8000
  description = "Port code-server listens on and the workbench's security group opens"

  validation {
    condition     = var.code_server_port > 0 && var.code_server_port <= 65535
    error_message = "code_server_port must be a valid TCP port."
  }
}
variable "inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether code-server is reachable from 0.0.0.0/0. The _monolithic template's InboundFromAnywhere parameter was the string \"True\"/\"False\"; a bool says the same thing. code-server runs with auth: none on an instance whose role has AdministratorAccess - set false and use Session Manager port forwarding for anything but a short demo"
}
variable "key_rsa_bits" {
  type        = number
  default     = 4096
  description = "Size of the generated key pair, as the _monolithic template had it"

  validation {
    condition     = contains([2048, 3072, 4096], var.key_rsa_bits)
    error_message = "key_rsa_bits must be 2048, 3072 or 4096."
  }
}
variable "game_sample_repository_url" {
  type        = string
  default     = "https://github.com/iamhansko/aws-gamelift-sample.git"
  description = "Repository the workbench clones: the prebuilt GameLift server and clients, the Lambda package and the leaderboard page. Everything this project runs that is not an AWS resource comes from here"

  validation {
    condition     = can(regex("^https://", var.game_sample_repository_url))
    error_message = "game_sample_repository_url must be an https URL."
  }
}
variable "game_sample_repository_ref" {
  type        = string
  default     = "11fd7f9aacb630779c24c49de5ddfd887be36699"
  description = "Commit (or branch) checked out after the clone. The _monolithic template cloned the default branch, so what it deployed depended on the day; this is the master commit the conversion was checked against. The client_config step rewrites a placeholder URL that is specific to this content (niop6gw2v0 in web/main.js)"

  validation {
    condition     = can(regex("^[A-Za-z0-9._/-]+$", var.game_sample_repository_ref))
    error_message = "game_sample_repository_ref must be a commit SHA or a branch or tag name."
  }
}
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the workbench where the bootstrap and each association drop their completion markers. Every association waits for the previous one's marker in an until loop rather than trusting depends_on (rules.md D-5)"

  validation {
    condition     = startswith(var.marker_file_path, "/")
    error_message = "marker_file_path must be an absolute path starting with '/'."
  }
}
variable "marker_wait_interval_seconds" {
  type        = number
  default     = 10
  description = "Seconds each until loop sleeps between checks"

  validation {
    condition     = var.marker_wait_interval_seconds >= 1 && var.marker_wait_interval_seconds <= 60
    error_message = "marker_wait_interval_seconds must be between 1 and 60."
  }
}
variable "artifact_wait_timeout_seconds" {
  type        = number
  default     = 1800
  description = "How long the artifacts_uploaded association may take. It waits out the whole workbench bootstrap - dnf update, the code-server download, the clone and both uploads - which is what the CloudFormation CreationPolicy (PT7M) used to wait for. The waiter functions that hold the Lambda functions and the GameLift build use the same value capped at 900 seconds, the longest a Lambda function runs"

  validation {
    condition     = var.artifact_wait_timeout_seconds >= 300
    error_message = "artifact_wait_timeout_seconds must be at least 300; the bootstrap it waits for runs dnf update and clones a 140 MB repository."
  }
}
variable "artifact_wait_attempts" {
  type        = number
  default     = 150
  description = "How many times the artifacts_uploaded association checks for the bootstrap marker before giving up with a message that names the bootstrap"

  validation {
    # Below the association's own timeout, so this script's explanation is what fails the apply rather than an
    # unexplained SSM timeout (rules.md B-1).
    condition     = var.artifact_wait_attempts >= 1 && var.artifact_wait_attempts * var.marker_wait_interval_seconds < var.artifact_wait_timeout_seconds
    error_message = "artifact_wait_attempts * marker_wait_interval_seconds must be less than artifact_wait_timeout_seconds, so the script reports which step is missing before SSM gives up on it."
  }
}
variable "artifact_head_attempts" {
  type        = number
  default     = 6
  description = "How many times each uploaded object is looked up after the marker appears. The uploads happen before the marker, so the first lookup normally succeeds"

  validation {
    condition     = var.artifact_head_attempts >= 1 && var.artifact_head_attempts <= 60
    error_message = "artifact_head_attempts must be between 1 and 60."
  }
}
variable "client_config_timeout_seconds" {
  type        = number
  default     = 600
  description = "How long the client_config association may take, as the _monolithic template's association had it"

  validation {
    condition     = var.client_config_timeout_seconds >= 60
    error_message = "client_config_timeout_seconds must be at least 60."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 300
  description = "How long the README association may take"

  validation {
    condition     = var.readme_timeout_seconds >= 60
    error_message = "readme_timeout_seconds must be at least 60."
  }
}
# --- Game client --------------------------------------------------------------------------------------------
variable "player1_name" {
  type        = string
  default     = "Amazonian"
  description = "Player name written into Client_player1/config.ini, as the _monolithic template wrote it"

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]+$", var.player1_name))
    error_message = "player1_name must be letters, digits, hyphens and underscores - it is written into an ini file and used as the table's partition key."
  }
}
variable "player2_name" {
  type        = string
  default     = "Ahro"
  description = "Player name written into Client_player2/config.ini, as the _monolithic template wrote it"

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]+$", var.player2_name)) && var.player2_name != var.player1_name
    error_message = "player2_name must be letters, digits, hyphens and underscores, and differ from player1_name - the two clients would otherwise be one player, and a one-player-per-team rule set cannot match a player against itself."
  }
}
variable "player_password" {
  type        = string
  default     = "simplepw00"
  description = "The password both prebuilt clients send, as the _monolithic template wrote it. Not a secret and not a protection: game-match-request creates a player row with whatever password the first request for that name brings and compares it in plain text afterwards, the API has no authorizer, and the value is written into a downloadable zip"

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]+$", var.player_password))
    error_message = "player_password must be letters, digits, hyphens and underscores, because it is written into an ini file."
  }
}
# --- Buckets and artifacts --------------------------------------------------------------------------------------
variable "bucket_force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy empties both buckets first. Every object in them was uploaded by the workbench rather than created by Terraform - the Lambda package, the server build, the client archive and the leaderboard page - so without this destroy stops at BucketNotEmpty. Those uploads are deleted with the buckets (rules.md I-4)"
}
variable "lambda_code_s3_key" {
  type        = string
  default     = "Lambda/code.zip"
  description = "Key the workbench uploads the sample's Lambda/code.zip to and all six functions read. The _monolithic template's key, which it got by copying the whole repository to the bucket root"

  validation {
    condition     = endswith(var.lambda_code_s3_key, ".zip") && !startswith(var.lambda_code_s3_key, "/")
    error_message = "lambda_code_s3_key must be a .zip object key without a leading slash."
  }
}
variable "server_build_s3_key" {
  type        = string
  default     = "server.zip"
  description = "Key the workbench uploads the zipped game server to and the GameLift build reads"

  validation {
    condition     = endswith(var.server_build_s3_key, ".zip") && !startswith(var.server_build_s3_key, "/")
    error_message = "server_build_s3_key must be a .zip object key without a leading slash."
  }
}
variable "client_archive_s3_key" {
  type        = string
  default     = "client.zip"
  description = "Key the two configured game clients are uploaded to, for the person playing to download"

  validation {
    condition     = endswith(var.client_archive_s3_key, ".zip") && !startswith(var.client_archive_s3_key, "/")
    error_message = "client_archive_s3_key must be a .zip object key without a leading slash."
  }
}
# --- Player table, queue, cache -----------------------------------------------------------------------------
variable "player_table_name" {
  type        = string
  default     = "GomokuPlayerInfo"
  description = "Name of the DynamoDB player table. Load bearing: GameResultProcessing.py, MatchRequest.py, MatchStatus.py and MatchEvent.py all call dynamodb.Table('GomokuPlayerInfo') literally"

  validation {
    condition     = var.player_table_name == "GomokuPlayerInfo"
    error_message = "player_table_name must stay GomokuPlayerInfo, because four of the six Lambda handlers in the sample's Lambda/code.zip name that table literally. Another name creates a table nothing reads; to change it, repackage the handlers with the new name and point lambda_code_s3_key at that package."
  }
}
variable "game_result_queue_name" {
  type        = string
  default     = "game-result-queue"
  description = "Name of the SQS queue game results go to, as the _monolithic template had it. Unique per account and region; nothing hard-codes it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.game_result_queue_name)) && length(var.game_result_queue_name) <= 80
    error_message = "game_result_queue_name must be 1-80 letters, digits, hyphens and underscores."
  }
}
variable "game_result_queue_visibility_timeout_seconds" {
  type        = number
  default     = 60
  description = "Visibility timeout of the game result queue, as the _monolithic template had it"

  validation {
    # Lambda refuses to create an SQS event source mapping when the queue's visibility timeout is shorter than
    # the function's timeout, and that refusal comes at apply.
    condition     = var.game_result_queue_visibility_timeout_seconds >= var.lambda_timeout && var.game_result_queue_visibility_timeout_seconds <= 43200
    error_message = "game_result_queue_visibility_timeout_seconds must be at least lambda_timeout (and at most 43200), or Lambda rejects game-sqs-process's event source mapping."
  }
}
variable "resource_security_group_name" {
  type        = string
  default     = "GomokuDefault"
  description = "Name of the security group shared by ElastiCache and the VPC-attached functions, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]+$", var.resource_security_group_name)) && length(var.resource_security_group_name) <= 255 && !startswith(var.resource_security_group_name, "sg-")
    error_message = "resource_security_group_name must be 1-255 characters from the set AWS accepts for a security group name, with no apostrophe, and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "ranking_cache_cluster_id" {
  type        = string
  default     = "gomokuranking"
  description = "ElastiCache cluster ID, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.ranking_cache_cluster_id)) && length(var.ranking_cache_cluster_id) <= 40
    error_message = "ranking_cache_cluster_id must be 1-40 lowercase letters, digits and hyphens starting with a letter."
  }
}
variable "ranking_cache_node_type" {
  type        = string
  default     = "cache.r7g.large"
  description = "ElastiCache node type, reproduced from the _monolithic template - and expensive for what it holds: a memory-optimized node billed by the hour for a sorted set of a handful of players. cache.t4g.micro is enough for the demo"

  validation {
    condition     = can(regex("^cache\\.[a-z0-9-]+\\.[a-z0-9]+$", var.ranking_cache_node_type))
    error_message = "ranking_cache_node_type must be an ElastiCache node type such as cache.t4g.micro."
  }
}
variable "ranking_cache_engine_version" {
  type        = string
  default     = "7.1"
  description = "Redis engine version, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9x]+(\\.[0-9]+)?$", var.ranking_cache_engine_version))
    error_message = "ranking_cache_engine_version must be a Redis version such as 7.1."
  }
}
variable "redis_port" {
  type        = number
  default     = 6379
  description = "Port of the Redis node. Load bearing: GetRank.py and Scoring.py connect with redis.Redis(host=..., port=6379) and take only the host from their environment"

  validation {
    condition     = var.redis_port == 6379
    error_message = "redis_port must stay 6379, because both ranking handlers in the sample's Lambda/code.zip connect on 6379 literally - the REDIS environment variable carries only the host."
  }
}
# --- Lambda ---------------------------------------------------------------------------------------------------
variable "lambda_function_name_prefix" {
  type        = string
  default     = "game-"
  description = "Prefix of the six function names. With the default the names are the _monolithic template's (game-sqs-process, game-rank-update, ...); nothing calls a function by name, so another prefix lets two copies of this project share an account"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.lambda_function_name_prefix)) && length(var.lambda_function_name_prefix) <= 40
    error_message = "lambda_function_name_prefix must be 1-40 letters, digits, hyphens and underscores, so the longest function name stays within 64 characters."
  }
}
variable "lambda_runtime" {
  type        = string
  default     = "python3.13"
  description = "Runtime of all six functions, as the _monolithic template had it"

  validation {
    condition     = can(regex("^python3\\.[0-9]+$", var.lambda_runtime))
    error_message = "lambda_runtime must be a Python 3 runtime such as python3.13."
  }
}
variable "lambda_timeout" {
  type        = number
  default     = 60
  description = "Timeout of all six functions in seconds, as the _monolithic template had it"

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "lambda_timeout must be between 1 and 900."
  }
}
variable "lambda_memory_size" {
  type        = number
  default     = 128
  description = "Memory of all six functions in MB - Lambda's default, which the _monolithic template got by not setting one"

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "lambda_memory_size must be between 128 and 10240."
  }
}
variable "game_sqs_process_additional_policy_arns" {
  type        = list(string)
  default     = []
  description = "Managed policies added to game-sqs-process's role on top of its scoped grants. The _monolithic template's breadth was AmazonSQSFullAccess, AmazonDynamoDBFullAccess and gamelift:*"

  validation {
    condition     = alltrue([for arn in var.game_sqs_process_additional_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "game_sqs_process_additional_policy_arns must contain IAM policy ARNs."
  }
}
variable "game_rank_update_additional_policy_arns" {
  type        = list(string)
  default     = []
  description = "Managed policies added to game-rank-update's role. The _monolithic template's breadth was AmazonVPCFullAccess and AmazonDynamoDBFullAccess"

  validation {
    condition     = alltrue([for arn in var.game_rank_update_additional_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "game_rank_update_additional_policy_arns must contain IAM policy ARNs."
  }
}
variable "game_rank_reader_additional_policy_arns" {
  type        = list(string)
  default     = []
  description = "Managed policies added to game-rank-reader's role. The _monolithic template's breadth was AmazonVPCFullAccess"

  validation {
    condition     = alltrue([for arn in var.game_rank_reader_additional_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "game_rank_reader_additional_policy_arns must contain IAM policy ARNs."
  }
}
variable "game_match_request_additional_policy_arns" {
  type        = list(string)
  default     = []
  description = "Managed policies added to game-match-request's role. The _monolithic template's breadth was AmazonDynamoDBFullAccess and gamelift:*"

  validation {
    condition     = alltrue([for arn in var.game_match_request_additional_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "game_match_request_additional_policy_arns must contain IAM policy ARNs."
  }
}
variable "game_match_status_additional_policy_arns" {
  type        = list(string)
  default     = []
  description = "Managed policies added to game-match-status's role. The _monolithic template's breadth was AmazonDynamoDBFullAccess and gamelift:*"

  validation {
    condition     = alltrue([for arn in var.game_match_status_additional_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "game_match_status_additional_policy_arns must contain IAM policy ARNs."
  }
}
variable "game_match_event_additional_policy_arns" {
  type        = list(string)
  default     = []
  description = "Managed policies added to game-match-event's role. The _monolithic template's breadth was AmazonDynamoDBFullAccess"

  validation {
    condition     = alltrue([for arn in var.game_match_event_additional_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "game_match_event_additional_policy_arns must contain IAM policy ARNs."
  }
}
# --- SNS and API Gateway --------------------------------------------------------------------------------------
variable "match_event_topic_name" {
  type        = string
  default     = "gomoku-match-topic"
  description = "Name of the SNS topic FlexMatch publishes to, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.match_event_topic_name)) && length(var.match_event_topic_name) <= 256
    error_message = "match_event_topic_name must be 1-256 letters, digits, hyphens and underscores."
  }
}
variable "api_name" {
  type        = string
  default     = "GomokuAPI"
  description = "Name of the REST API, as the _monolithic template had it"

  validation {
    condition     = length(var.api_name) > 0 && length(var.api_name) <= 1024
    error_message = "api_name must be 1-1024 characters."
  }
}
variable "api_stage_name" {
  type        = string
  default     = "prod"
  description = "Stage the API is published on. prod is what both prebuilt clients' config.ini and web/main.js were written against; the client_config step writes the stage's real invoke URL into all three, so another name works too"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.api_stage_name)) && length(var.api_stage_name) <= 128
    error_message = "api_stage_name must be 1-128 letters, digits, hyphens or underscores."
  }
}
variable "api_cors_allow_origin" {
  type        = string
  default     = "*"
  description = "Access-Control-Allow-Origin the API returns. * because the leaderboard page is served from an S3 website endpoint, a different origin"

  validation {
    condition     = length(var.api_cors_allow_origin) > 0 && !strcontains(var.api_cors_allow_origin, "'")
    error_message = "api_cors_allow_origin must be non-empty and contain no single quote."
  }
}
# --- GameLift -------------------------------------------------------------------------------------------------
variable "gamelift_build_name" {
  type        = string
  default     = "GomokuServer-Build-1"
  description = "Name of the GameLift build, as the _monolithic template had it"

  validation {
    condition     = length(var.gamelift_build_name) > 0 && length(var.gamelift_build_name) <= 1024
    error_message = "gamelift_build_name must be 1-1024 characters."
  }
}
variable "gamelift_build_operating_system" {
  type        = string
  default     = "WINDOWS_2016"
  description = "Operating system of the build, as the _monolithic template had it. Time-limited: GameLift stops accepting WINDOWS_2016 from accounts without an active WINDOWS_2016 fleet on 2026-12-12 and retires it on 2027-01-12. WINDOWS_2022 needs the server rebuilt against server SDK 5, which the sample's prebuilt GomokuServer.exe is not"

  validation {
    condition     = contains(["WINDOWS_2016", "WINDOWS_2022"], var.gamelift_build_operating_system)
    error_message = "gamelift_build_operating_system must be WINDOWS_2016 or WINDOWS_2022 - the server is a Windows executable and WINDOWS_2012 is retired. WINDOWS_2022 only works with a server rebuilt against GameLift server SDK 5."
  }
}
variable "gamelift_fleet_name" {
  type        = string
  default     = "GomokuGameServerFleet-1"
  description = "Name of the fleet, as the _monolithic template had it"

  validation {
    condition     = length(var.gamelift_fleet_name) > 0 && length(var.gamelift_fleet_name) <= 1024
    error_message = "gamelift_fleet_name must be 1-1024 characters."
  }
}
variable "gamelift_fleet_instance_type" {
  type        = string
  default     = "c5.large"
  description = "Instance type of the fleet, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9-]+\\.[a-z0-9]+$", var.gamelift_fleet_instance_type))
    error_message = "gamelift_fleet_instance_type must be an EC2 instance type such as c5.large."
  }
}
variable "gamelift_fleet_type" {
  type        = string
  default     = "ON_DEMAND"
  description = "ON_DEMAND, where the _monolithic template had SPOT. The game session queue has this one fleet as its only destination, and GameLift drains a Spot fleet it judges non-viable: the fleet stays ACTIVE with no instance, so every match times out in the queue and the clients wait on matchstatus. Changing this replaces the fleet"

  validation {
    condition     = var.gamelift_fleet_type == "ON_DEMAND"
    error_message = "gamelift_fleet_type must be ON_DEMAND in this variant. The game session queue has this one fleet as its only destination, and GameLift drains a Spot fleet whose instance type and location it judges non-viable - the fleet stays ACTIVE with no instance, matches time out in the queue and nothing fails in Terraform. To use SPOT, the gamelift_fleet module has to give its queue an ON_DEMAND fleet as a second destination for backup capacity."
  }
}
variable "gamelift_inbound_from_port" {
  type        = number
  default     = 49152
  description = "Lowest port open to players on the fleet, as the _monolithic template had it"

  validation {
    condition     = var.gamelift_inbound_from_port >= 1026 && var.gamelift_inbound_from_port <= 60000
    error_message = "gamelift_inbound_from_port must be between 1026 and 60000."
  }
}
variable "gamelift_inbound_to_port" {
  type        = number
  default     = 60000
  description = "Highest port open to players on the fleet, as the _monolithic template had it"

  validation {
    condition     = var.gamelift_inbound_to_port >= var.gamelift_inbound_from_port && var.gamelift_inbound_to_port <= 60000
    error_message = "gamelift_inbound_to_port must be no lower than gamelift_inbound_from_port and no higher than 60000."
  }
}
variable "gamelift_inbound_ip_range" {
  type        = string
  default     = "0.0.0.0/0"
  description = "Addresses players may connect to the fleet from, as the _monolithic template had it"

  validation {
    condition     = can(cidrhost(var.gamelift_inbound_ip_range, 0))
    error_message = "gamelift_inbound_ip_range must be a valid IPv4 CIDR block."
  }
}
variable "gamelift_concurrent_executions" {
  type        = number
  default     = 50
  description = "Server processes per fleet instance, as the _monolithic template had it"

  validation {
    condition     = var.gamelift_concurrent_executions >= 1 && var.gamelift_concurrent_executions <= 50
    error_message = "gamelift_concurrent_executions must be between 1 and 50."
  }
}
variable "gamelift_alias_name" {
  type        = string
  default     = "GomokuAlias"
  description = "Name of the alias in front of the fleet, as the _monolithic template had it"

  validation {
    condition     = length(var.gamelift_alias_name) > 0 && length(var.gamelift_alias_name) <= 1024
    error_message = "gamelift_alias_name must be 1-1024 characters."
  }
}
variable "gamelift_alias_description" {
  type        = string
  default     = "Routes the game session queue to the Gomoku game server fleet"
  description = "Description of the alias. The _monolithic template set none, which the provider accepts on create; UpdateAlias then rejects the empty value the first time the fleet is replaced and the alias has to follow it"

  validation {
    condition     = length(var.gamelift_alias_description) > 0 && length(var.gamelift_alias_description) <= 1024
    error_message = "gamelift_alias_description must be 1-1024 characters - UpdateAlias rejects an empty description, so an alias without one cannot be moved to a replacement fleet."
  }
}
variable "gamelift_queue_name" {
  type        = string
  default     = "gomoku-queue"
  description = "Name of the game session queue, as the _monolithic template had it. Unique per account and region"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.gamelift_queue_name)) && length(var.gamelift_queue_name) <= 128
    error_message = "gamelift_queue_name must be 1-128 letters, digits and hyphens."
  }
}
variable "gamelift_queue_timeout_seconds" {
  type        = number
  default     = 600
  description = "How long a placement may wait in the queue, as the _monolithic template had it"

  validation {
    condition     = var.gamelift_queue_timeout_seconds >= 1 && var.gamelift_queue_timeout_seconds <= 600
    error_message = "gamelift_queue_timeout_seconds must be between 1 and 600."
  }
}
variable "fleet_role_additional_policy_arns" {
  type        = list(string)
  default     = []
  description = "Managed policies added to the fleet role on top of its sqs:SendMessage grant. The _monolithic template's breadth was AmazonSQSFullAccess"

  validation {
    condition     = alltrue([for arn in var.fleet_role_additional_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "fleet_role_additional_policy_arns must contain IAM policy ARNs."
  }
}
# --- FlexMatch ------------------------------------------------------------------------------------------------
variable "matchmaking_rule_set_name" {
  type        = string
  default     = "gomoku-matchmaking-rule"
  description = "Name of the matchmaking rule set, as the _monolithic template's unconverted definition had it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9.-]+$", var.matchmaking_rule_set_name)) && length(var.matchmaking_rule_set_name) <= 128
    error_message = "matchmaking_rule_set_name must be 1-128 letters, digits, hyphens and dots."
  }
}
variable "matchmaking_configuration_name" {
  type        = string
  default     = "GomokuMatchConfig"
  description = "Name of the matchmaking configuration. Load bearing: MatchRequest.py calls start_matchmaking(ConfigurationName='GomokuMatchConfig') literally"

  validation {
    condition     = var.matchmaking_configuration_name == "GomokuMatchConfig"
    error_message = "matchmaking_configuration_name must stay GomokuMatchConfig, because game-match-request's handler starts matchmaking against that name literally - any other name leaves every client with TicketId MatchError. To change it, repackage MatchRequest.py and point lambda_code_s3_key at that package."
  }
}
variable "matchmaking_request_timeout_seconds" {
  type        = number
  default     = 60
  description = "How long a matchmaking ticket may stay in progress, as the _monolithic template's unconverted definition had it"

  validation {
    # The rule set's last expansion fires at 30 seconds; a ticket that times out first never sees it.
    condition     = var.matchmaking_request_timeout_seconds > 30 && var.matchmaking_request_timeout_seconds <= 43200
    error_message = "matchmaking_request_timeout_seconds must be above 30 (the rule set's last expansion step) and at most 43200."
  }
}
variable "matchmaking_acceptance_required" {
  type        = bool
  default     = false
  description = "Whether matched players must accept the match. False as the _monolithic template's unconverted definition had it"

  validation {
    # Constant on purpose: nothing in this project calls AcceptMatch - not the prebuilt client, not any of the six
    # handlers - so with true every ticket stops in REQUIRES_ACCEPTANCE and times out, and plan cannot tell.
    condition     = var.matchmaking_acceptance_required == false
    error_message = "matchmaking_acceptance_required must stay false: neither the prebuilt game client nor any Lambda handler calls AcceptMatch, so every match would wait for an acceptance that never comes and time out."
  }
}
variable "player_stream_starting_position" {
  type        = string
  default     = "TRIM_HORIZON"
  description = "Where game-rank-update starts reading the player table's stream, as the _monolithic template had it. TRIM_HORIZON means a mapping created after the first games still scores them"

  validation {
    condition     = contains(["TRIM_HORIZON", "LATEST"], var.player_stream_starting_position)
    error_message = "player_stream_starting_position must be TRIM_HORIZON or LATEST."
  }
}
