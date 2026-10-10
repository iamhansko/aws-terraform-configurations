variable "aws_region" {
  type        = string
  default     = null
  description = "Region to deploy into, for both the aws and the awscc provider. Null follows the provider chain (AWS_REGION / AWS_DEFAULT_REGION), which is how the _monolithic template was run"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a region code such as ap-northeast-2, or null to follow the provider chain."
  }
}
variable "project_name" {
  type        = string
  default     = "gamelift-flexmatch"
  description = <<-DESC
    Prefix for generated names and Name tags - the key pair, the secret, the two buckets, the IAM roles,
    the ElastiCache subnet group, the instance and its security group, the association.

    This is the _monolithic template's stack_name variable under the name the rest of this repository
    uses. Names the template wrote as literals - GomokuDefault, game-result-queue, the game-* functions,
    GomokuAPI, GomokuPlayerInfo, the GameLift and FlexMatch names - are their own variables below with
    the original values as defaults, because some of them are read by code this configuration does not
    own.
  DESC

  validation {
    # 20 because the longest derived IAM role prefix, <project_name>-match-request-, has to fit IAM's
    # 38 character name_prefix limit, and <project_name>-game-source- the 37 of an S3 bucket_prefix.
    condition     = can(regex("^[a-z][a-z0-9-]{0,18}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 2-20 characters of lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen. It is used in S3 bucket and IAM role name prefixes, which are the tightest limits here."
  }
}
variable "ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/ami-windows-latest/Windows_Server-2025-Korean-Full-Base"
  description = "Public SSM parameter holding the Windows AMI id, as the _monolithic template had it. Full Base rather than Core, because the point of the instance is an RDP desktop to run the game clients on"

  validation {
    condition     = startswith(var.ami_ssm_parameter_name, "/aws/service/ami-windows-latest/")
    error_message = "ami_ssm_parameter_name must be an AWS public Windows AMI parameter path under /aws/service/ami-windows-latest/."
  }
}
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC, as the _monolithic template had it"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
}
variable "subnet_cidr_blocks" {
  type = object({
    public_a  = string
    private_a = string
    public_c  = string
    private_c = string
  })
  default = {
    public_a  = "10.0.0.0/24"
    private_a = "10.0.1.0/24"
    public_c  = "10.0.4.0/24"
    private_c = "10.0.5.0/24"
  }
  description = "The four subnets, as the _monolithic template's AzMapping had them. Its mapping also held a b row (10.0.2.0/24, 10.0.3.0/24) that no resource used - this variant builds in zones a and c"

  validation {
    condition     = alltrue([for cidr in values(var.subnet_cidr_blocks) : can(cidrhost(cidr, 0))])
    error_message = "subnet_cidr_blocks must contain valid IPv4 CIDR blocks (e.g. 10.0.0.0/24)."
  }
}
variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "c"]
  description = "The two AZ letters, as the _monolithic template had them: a and c. The sibling template variant uses a and b; the difference is in the originals and is kept"

  validation {
    condition     = length(var.availability_zone_suffixes) == 2 && alltrue([for s in var.availability_zone_suffixes : can(regex("^[a-z]$", s))])
    error_message = "availability_zone_suffixes must be exactly two single lowercase letters."
  }
}
variable "windows_instance_type" {
  type        = string
  default     = "m5.2xlarge"
  description = "Instance type of the Windows desktop, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]+[a-z0-9-]*\\.[a-z0-9]+$", var.windows_instance_type))
    error_message = "windows_instance_type must be a valid EC2 instance type (e.g. m5.2xlarge)."
  }
}
variable "windows_root_volume_size" {
  type        = number
  default     = 100
  description = "Root volume size of the Windows desktop in GiB, as the _monolithic template had it"

  validation {
    condition     = var.windows_root_volume_size >= 30
    error_message = "windows_root_volume_size must be at least 30 GiB."
  }
}
variable "rdp_ingress_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = <<-DESC
    Source CIDRs allowed to reach RDP on the Windows desktop. An empty list creates no ingress rule,
    leaving the instance reachable only through SSM.

    This replaces the _monolithic template's inbound_from_anywhere parameter, a "True"/"False" string
    because CloudFormation parameters have no boolean: ["0.0.0.0/0"] is True, [] is False. The default is
    the whole internet because that is what the template defaulted to; narrowing it to your own address
    is the most useful change to make here.
  DESC

  validation {
    condition     = alltrue([for cidr in var.rdp_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "rdp_ingress_cidr_blocks must contain valid IPv4 CIDR blocks (e.g. 203.0.113.0/24)."
  }
}
variable "workshop_username" {
  type        = string
  default     = "gamelift"
  description = "Windows local account the RDP login uses, as the _monolithic template's username parameter had it. One variable feeds both the secret and the account the instance creates"

  validation {
    condition     = can(regex("^[^\"/\\\\\\[\\]:;|=,+*?<>@ ]{1,20}$", var.workshop_username))
    error_message = "workshop_username must be 1-20 characters and must not contain a space, @, or any of \" / \\ [ ] : ; | = , + * ? < >, because New-LocalUser rejects those on the instance and the failure never reaches Terraform."
  }
}
variable "secret_recovery_window_in_days" {
  type        = number
  default     = 0
  description = "Recovery window of the workshop password secret after destroy. Zero deletes it at once, so a re-apply does not trip over a name scheduled for deletion"

  validation {
    condition     = var.secret_recovery_window_in_days == 0 || (var.secret_recovery_window_in_days >= 7 && var.secret_recovery_window_in_days <= 30)
    error_message = "secret_recovery_window_in_days must be 0 or between 7 and 30."
  }
}
variable "git_clone_url" {
  type        = string
  default     = "https://github.com/iamhansko/aws-gamelift-sample.git"
  description = "Repository the instance clones, as the _monolithic template had it. Everything that is not infrastructure comes from it: Lambda/code.zip, the prebuilt GomokuServer and both game clients, and the leaderboard page"

  validation {
    condition     = can(regex("^https://", var.git_clone_url)) && !strcontains(var.git_clone_url, "'")
    error_message = "git_clone_url must be an https URL without a single quote."
  }
}
variable "bucket_force_destroy" {
  type        = bool
  default     = true
  description = "Whether destroy deletes the game source and website buckets with their contents. True, because every object in both was uploaded by the instance rather than created by Terraform, and without it destroy stops at BucketNotEmpty. The uploads go with the buckets - server.zip with this deployment's config.ini, client.zip, Lambda/code.zip and the rest of the clone, and the patched leaderboard page"
}
variable "lambda_code_s3_key" {
  type        = string
  default     = "Lambda/code.zip"
  description = "Key of the package all six game functions are created from, as the _monolithic template had it. Load-bearing in an unusual way: no step uploads this key by name. It exists because the instance copies the whole clone into the bucket and the sample repository keeps its package at Lambda/code.zip"

  validation {
    condition     = endswith(var.lambda_code_s3_key, ".zip") && !startswith(var.lambda_code_s3_key, "/")
    error_message = "lambda_code_s3_key must be a .zip key without a leading slash."
  }
}
variable "server_build_s3_key" {
  type        = string
  default     = "server.zip"
  description = "Key the instance uploads the game server build to and the GameLift build reads, as the _monolithic template had it"

  validation {
    condition     = endswith(var.server_build_s3_key, ".zip") && !startswith(var.server_build_s3_key, "/") && var.server_build_s3_key != var.lambda_code_s3_key
    error_message = "server_build_s3_key must be a .zip key without a leading slash, different from lambda_code_s3_key."
  }
}
variable "client_archive_s3_key" {
  type        = string
  default     = "client.zip"
  description = "Key the instance uploads the two game clients to, as the _monolithic template had it"

  validation {
    condition     = endswith(var.client_archive_s3_key, ".zip") && !startswith(var.client_archive_s3_key, "/")
    error_message = "client_archive_s3_key must be a .zip key without a leading slash."
  }
}
variable "lambda_runtime" {
  type        = string
  default     = "python3.13"
  description = "Runtime of all six game functions, as the _monolithic template had it"

  validation {
    condition     = can(regex("^python3\\.[0-9]+$", var.lambda_runtime))
    error_message = "lambda_runtime must be a Python 3 runtime such as python3.13."
  }
}
variable "lambda_timeout_seconds" {
  type        = number
  default     = 60
  description = "Timeout of all six game functions, as the _monolithic template had it"

  validation {
    condition     = var.lambda_timeout_seconds >= 1 && var.lambda_timeout_seconds <= 900
    error_message = "lambda_timeout_seconds must be between 1 and 900."
  }
}
variable "lambda_functions" {
  type = map(object({
    function_name          = string
    handler                = string
    additional_policy_arns = optional(list(string), [])
  }))
  default = {
    sqs_process   = { function_name = "game-sqs-process", handler = "GameResultProcessing.lambda_handler" }
    rank_update   = { function_name = "game-rank-update", handler = "Scoring.handler" }
    rank_reader   = { function_name = "game-rank-reader", handler = "GetRank.handler" }
    match_request = { function_name = "game-match-request", handler = "MatchRequest.lambda_handler" }
    match_status  = { function_name = "game-match-status", handler = "MatchStatus.lambda_handler" }
    match_event   = { function_name = "game-match-event", handler = "MatchEvent.lambda_handler" }
  }
  description = <<-DESC
    Name, handler and extra managed policies of each game function. Names as the _monolithic template
    had them; nothing reads them by name - API Gateway and SNS are wired to the functions by ARN.
    Handlers are load-bearing: each names a file and function inside Lambda/code.zip.

    additional_policy_arns is empty for every function. The template gave the six roles
    AmazonDynamoDBFullAccess, AmazonSQSFullAccess, AmazonVPCFullAccess and an inline gamelift:* in
    various combinations; main.tf scopes each to what its handler calls (rules.md A-5). If a scoped grant
    turns out to be short, the template's breadth for one function is one entry here, e.g.
    additional_policy_arns = ["arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"].

    Overriding this replaces the whole map, so an override has to list all six.
  DESC

  validation {
    condition     = length(setsubtract(keys(var.lambda_functions), ["sqs_process", "rank_update", "rank_reader", "match_request", "match_status", "match_event"])) == 0 && length(var.lambda_functions) == 6
    error_message = "lambda_functions must have exactly the keys sqs_process, rank_update, rank_reader, match_request, match_status and match_event - main.tf wires each one to its own trigger and grants by key."
  }
  validation {
    condition     = alltrue([for f in values(var.lambda_functions) : can(regex("^[a-zA-Z0-9_-]{1,64}$", f.function_name)) && can(regex("^[A-Za-z_][A-Za-z0-9_]*\\.[A-Za-z_][A-Za-z0-9_]*$", f.handler))])
    error_message = "lambda_functions entries need a function_name of 1-64 letters, digits, hyphens and underscores, and a handler of the form <module>.<function>."
  }
  validation {
    condition     = alltrue(flatten([for f in values(var.lambda_functions) : [for arn in f.additional_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))]]))
    error_message = "lambda_functions additional_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "player_stream_starting_position" {
  type        = string
  default     = "TRIM_HORIZON"
  description = "Where game-rank-update starts reading the player table's stream, as the _monolithic template had it. TRIM_HORIZON so a score written before the mapping existed still reaches Redis"

  validation {
    condition     = contains(["TRIM_HORIZON", "LATEST"], var.player_stream_starting_position)
    error_message = "player_stream_starting_position must be TRIM_HORIZON or LATEST."
  }
}
variable "player_table_name" {
  type        = string
  default     = "GomokuPlayerInfo"
  description = "Name of the player table. Load-bearing - four handlers open it by this literal name; the module validates it stays so"

  validation {
    condition     = length(var.player_table_name) >= 3 && length(var.player_table_name) <= 255
    error_message = "player_table_name must be 3-255 characters."
  }
}
variable "gomoku_security_group_name" {
  type        = string
  default     = "GomokuDefault"
  description = "Name of the security group the Redis node and the two VPC-attached functions share, as the _monolithic template had it"

  validation {
    condition     = length(var.gomoku_security_group_name) > 0 && !startswith(var.gomoku_security_group_name, "sg-")
    error_message = "gomoku_security_group_name must be non-empty and must not start with sg-."
  }
}
variable "redis_cluster_id" {
  type        = string
  default     = "gomokuranking"
  description = "ElastiCache cluster id, as the _monolithic template had it. Unique per account and region"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,39}$", var.redis_cluster_id))
    error_message = "redis_cluster_id must be 1-40 characters of lowercase letters, digits and hyphens, starting with a letter."
  }
}
variable "redis_node_type" {
  type        = string
  default     = "cache.r7g.large"
  description = "ElastiCache node type, as the _monolithic template had it. Expensive for what it holds - a memory-optimised node for one sorted set of a few players; cache.t4g.micro does the same job for a small fraction of the hourly price. Kept because changing it is a cost decision, not a conversion"

  validation {
    condition     = can(regex("^cache\\.[a-z0-9]+\\.[a-z0-9]+$", var.redis_node_type))
    error_message = "redis_node_type must be an ElastiCache node type such as cache.t4g.micro."
  }
}
variable "redis_engine_version" {
  type        = string
  default     = "7.1"
  description = "Redis engine version, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9x]+(\\.[0-9]+)?$", var.redis_engine_version))
    error_message = "redis_engine_version must look like 7.1 or 6.x."
  }
}
variable "game_result_queue_name" {
  type        = string
  default     = "game-result-queue"
  description = "Name of the SQS queue the game server reports results to, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,80}$", var.game_result_queue_name))
    error_message = "game_result_queue_name must be 1-80 characters of letters, digits, hyphens and underscores."
  }
}
variable "game_result_queue_visibility_timeout_seconds" {
  type        = number
  default     = 60
  description = "Visibility timeout of the result queue, as the _monolithic template had it"

  validation {
    # Lambda refuses an SQS event source mapping whose queue visibility timeout
    # is shorter than the function timeout - at apply, after the queue and the
    # function exist. A pair constraint, so it is a cross-variable condition.
    condition     = var.game_result_queue_visibility_timeout_seconds >= var.lambda_timeout_seconds && var.game_result_queue_visibility_timeout_seconds <= 43200
    error_message = "game_result_queue_visibility_timeout_seconds must be at least lambda_timeout_seconds (Lambda rejects the event source mapping otherwise) and at most 43200."
  }
}
variable "fleet_role_additional_policy_arns" {
  type        = list(string)
  default     = []
  description = "Managed policies attached to the GameLift fleet role on top of its sqs:SendMessage grant. Empty by default; [\"arn:aws:iam::aws:policy/AmazonSQSFullAccess\"] is what the _monolithic template attached instead"

  validation {
    condition     = alltrue([for arn in var.fleet_role_additional_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "fleet_role_additional_policy_arns must contain valid IAM policy ARNs."
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
  description = "Stage the API is published to. Read in two places from this one variable: the API module creates the stage, and the instance writes the same name into both clients' MATCH_SERVER_API and into the leaderboard's main.js. The instance cannot take it from the stage itself - see main.tf"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,128}$", var.api_stage_name))
    error_message = "api_stage_name must be 1-128 characters of letters, digits, hyphens and underscores."
  }
}
variable "match_event_topic_name" {
  type        = string
  default     = "gomoku-match-topic"
  description = "Name of the SNS topic FlexMatch publishes matchmaking events to, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,256}$", var.match_event_topic_name))
    error_message = "match_event_topic_name must be 1-256 characters of letters, digits, hyphens and underscores."
  }
}
variable "gamelift_build_name" {
  type        = string
  default     = "GomokuServer-Build-1"
  description = "Name of the GameLift build, as the _monolithic template had it"

  validation {
    condition     = length(var.gamelift_build_name) > 0 && length(var.gamelift_build_name) <= 1024
    error_message = "gamelift_build_name must be 1-1024 characters."
  }
}
variable "gamelift_operating_system" {
  type        = string
  default     = "WINDOWS_2016"
  description = "Operating system of the GameLift build, as the _monolithic template had it. Still accepted, with end of support announced for 2027-01-12; moving to WINDOWS_2022 needs the server rebuilt on server SDK 5.x first - see the gamelift_fleet module"

  validation {
    condition     = startswith(var.gamelift_operating_system, "WINDOWS_")
    error_message = "gamelift_operating_system must be a Windows value - GomokuServer.exe is a Windows executable."
  }
}
variable "gamelift_fleet_name" {
  type        = string
  default     = "GomokuGameServerFleet-1"
  description = "Name of the GameLift fleet, as the _monolithic template had it"

  validation {
    condition     = length(var.gamelift_fleet_name) > 0 && length(var.gamelift_fleet_name) <= 1024
    error_message = "gamelift_fleet_name must be 1-1024 characters."
  }
}
variable "gamelift_fleet_instance_type" {
  type        = string
  default     = "c5.large"
  description = "Instance type of the GameLift fleet, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.gamelift_fleet_instance_type))
    error_message = "gamelift_fleet_instance_type must be an EC2 instance type such as c5.large."
  }
}
variable "gamelift_fleet_type" {
  type        = string
  default     = "ON_DEMAND"
  description = "Capacity type of the GameLift fleet: ON_DEMAND, where the _monolithic template had SPOT. The game session queue has this one fleet as its only destination, and GameLift drains a Spot fleet it judges non-viable: the fleet stays ACTIVE with no instance, so every match times out in the queue and the clients wait on matchstatus. Changing this replaces the fleet"

  validation {
    condition     = var.gamelift_fleet_type == "ON_DEMAND"
    error_message = "gamelift_fleet_type must be ON_DEMAND in this variant. The game session queue has this one fleet as its only destination, and GameLift drains a Spot fleet whose instance type and location it judges non-viable - the fleet stays ACTIVE with no instance, matches time out in the queue and nothing fails in Terraform. To use SPOT, the gamelift_fleet module has to give its queue an ON_DEMAND fleet as a second destination for backup capacity."
  }
}
variable "gamelift_fleet_inbound_permissions" {
  type = list(object({
    from_port = number
    to_port   = number
    ip_range  = string
    protocol  = string
  }))
  default = [{
    from_port = 49152
    to_port   = 60000
    ip_range  = "0.0.0.0/0"
    protocol  = "TCP"
  }]
  description = "Ports the fleet's instances accept game clients on, as the _monolithic template had them"

  validation {
    condition     = length(var.gamelift_fleet_inbound_permissions) > 0 && alltrue([for p in var.gamelift_fleet_inbound_permissions : can(cidrhost(p.ip_range, 0))])
    error_message = "gamelift_fleet_inbound_permissions must contain at least one entry, each with a valid CIDR ip_range. Without one no game client can reach a server."
  }
}
variable "gamelift_alias_name" {
  type        = string
  default     = "GomokuAlias"
  description = "Name of the GameLift alias, as the _monolithic template had it"

  validation {
    condition     = length(var.gamelift_alias_name) > 0 && length(var.gamelift_alias_name) <= 1024
    error_message = "gamelift_alias_name must be 1-1024 characters."
  }
}
variable "gamelift_alias_description" {
  type        = string
  default     = "Routes the game session queue to the Gomoku game server fleet"
  description = "Description of the GameLift alias. The _monolithic template set none, which the provider accepts on create; UpdateAlias then rejects the empty value the first time the fleet is replaced and the alias has to follow it"

  validation {
    condition     = length(var.gamelift_alias_description) > 0 && length(var.gamelift_alias_description) <= 1024
    error_message = "gamelift_alias_description must be 1-1024 characters - UpdateAlias rejects an empty description, so an alias without one cannot be moved to a replacement fleet."
  }
}
variable "gamelift_queue_name" {
  type        = string
  default     = "gomoku-queue"
  description = "Name of the GameLift game session queue, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,128}$", var.gamelift_queue_name))
    error_message = "gamelift_queue_name must be 1-128 characters of letters, digits and hyphens."
  }
}
variable "matchmaking_rule_set_name" {
  type        = string
  default     = "gomoku-matchmaking-rule"
  description = "Name of the FlexMatch rule set, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9.-]{1,128}$", var.matchmaking_rule_set_name))
    error_message = "matchmaking_rule_set_name must be 1-128 characters of letters, digits, dots and hyphens."
  }
}
variable "matchmaking_configuration_name" {
  type        = string
  default     = "GomokuMatchConfig"
  description = "Name of the FlexMatch configuration. Load-bearing: MatchRequest.py passes this literal to StartMatchmaking; the module validates it stays so"

  validation {
    condition     = can(regex("^[a-zA-Z0-9.-]{1,128}$", var.matchmaking_configuration_name))
    error_message = "matchmaking_configuration_name must be 1-128 characters of letters, digits, dots and hyphens."
  }
}
variable "matchmaking_acceptance_required" {
  type        = bool
  default     = false
  description = "Whether players must accept a proposed match, as the _monolithic template had it"
}
variable "matchmaking_request_timeout_seconds" {
  type        = number
  default     = 60
  description = "How long a matchmaking ticket searches before timing out, as the _monolithic template had it"

  validation {
    condition     = var.matchmaking_request_timeout_seconds >= 1 && var.matchmaking_request_timeout_seconds <= 43200
    error_message = "matchmaking_request_timeout_seconds must be between 1 and 43200."
  }
}
variable "matchmaking_rule_set" {
  type = object({
    ruleLanguageVersion = string
    playerAttributes = list(object({
      name    = string
      type    = string
      default = number
    }))
    teams = list(object({
      name       = string
      minPlayers = number
      maxPlayers = number
    }))
    rules = list(object({
      name           = string
      type           = string
      measurements   = list(string)
      referenceValue = string
      operation      = optional(string)
      maxDistance    = optional(number)
    }))
    expansions = list(object({
      target = string
      steps = list(object({
        waitTimeSeconds = number
        value           = number
      }))
    }))
  })
  default = {
    ruleLanguageVersion = "1.0"
    playerAttributes = [
      { name = "score", type = "number", default = 1000 },
    ]
    teams = [
      { name = "blue", maxPlayers = 1, minPlayers = 1 },
      { name = "red", maxPlayers = 1, minPlayers = 1 },
    ]
    rules = [
      {
        name           = "EqualTeamSizes"
        type           = "comparison"
        measurements   = ["count(teams[red].players)"]
        referenceValue = "count(teams[blue].players)"
        operation      = "="
      },
      {
        name           = "FairTeamSkill"
        type           = "distance"
        measurements   = ["avg(teams[*].players.attributes[score])"]
        referenceValue = "avg(flatten(teams[*].players.attributes[score]))"
        maxDistance    = 300
      },
    ]
    expansions = [
      {
        target = "rules[FairTeamSkill].maxDistance"
        steps = [
          { waitTimeSeconds = 10, value = 500 },
          { waitTimeSeconds = 20, value = 800 },
          { waitTimeSeconds = 30, value = 1000 },
        ]
      },
    ]
  }
  description = <<-DESC
    The FlexMatch rule set: one player per team, blue against red, matched on the score attribute
    (default 1000) within 300 points, widening to 500, 800 and 1000 after 10, 20 and 30 seconds.

    This is the _monolithic template's RuleSetBody as a typed object, and it is the only copy the
    configuration reads. It agrees exactly with Ruleset/GomokuRuleSet.json in the sample repository
    git_clone_url names when both are parsed; that file is outside this variant and is not read
    (rules.md A-1). The gamelift_matchmaking module's rule_set_body output shows the JSON as sent.
  DESC

  validation {
    condition     = var.matchmaking_rule_set.ruleLanguageVersion == "1.0"
    error_message = "matchmaking_rule_set.ruleLanguageVersion must be 1.0."
  }
}
variable "artifact_wait_attempts" {
  type        = number
  default     = 120
  description = "How many times the artifact association checks for the setup's completion marker before giving up. With the default interval this is 30 minutes, the PT30M the template's CreationPolicy allowed the same setup"

  validation {
    condition     = var.artifact_wait_attempts >= 1
    error_message = "artifact_wait_attempts must be at least 1."
  }
}
variable "artifact_wait_interval_seconds" {
  type        = number
  default     = 15
  description = "Seconds between the artifact association's checks"

  validation {
    condition     = var.artifact_wait_interval_seconds >= 1 && var.artifact_wait_interval_seconds <= 300
    error_message = "artifact_wait_interval_seconds must be between 1 and 300."
  }
}
variable "artifact_wait_timeout_seconds" {
  type        = number
  default     = 2400
  description = "How long the artifact association may take, and the execution timeout of the script it runs. Must exceed the marker wait (attempts x interval) so the script's own message, naming what is missing, is what you see - not the provider's timeout. The waiter functions that hold the game functions and the GameLift build use the same value, capped at 3600 seconds - four 900 second rounds"

  validation {
    condition     = var.artifact_wait_timeout_seconds > var.artifact_wait_attempts * var.artifact_wait_interval_seconds && var.artifact_wait_timeout_seconds <= 172800
    error_message = "artifact_wait_timeout_seconds must be greater than artifact_wait_attempts * artifact_wait_interval_seconds (the script's own marker wait), and at most 172800 (the AWS-RunPowerShellScript execution timeout limit)."
  }
}
