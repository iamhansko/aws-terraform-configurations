data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
# The AMI id from the public parameter AWS maintains per Windows release. In the
# root, and passed to the module as an id (rules.md B-6). insecure_value because
# the provider marks value sensitive for every parameter, and a public AMI id is
# not a secret.
data "aws_ssm_parameter" "windows_ami_id" {
  name = var.ami_ssm_parameter_name
}
locals {
  region     = data.aws_region.current.region
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  lambda_basic_execution_policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  # In place of the AmazonVPCFullAccess the _monolithic template gave the two
  # VPC-attached functions. A function in a VPC needs to create, describe and
  # delete its own network interfaces, which is this policy; full VPC access
  # also let either function rewrite the route tables and security groups.
  lambda_vpc_access_policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"

  # The FlexMatch configuration's ARN, assembled from its name instead of read
  # off the resource. The SNS topic policy needs it as aws:SourceArn, and the
  # configuration needs the topic as its notification target, so reading it
  # would make the topic and the configuration wait on each other. The check
  # block at the end of this file confirms the two agree after apply.
  matchmaking_configuration_arn = "arn:${local.partition}:gamelift:${local.region}:${local.account_id}:matchmakingconfiguration/${var.matchmaking_configuration_name}"

  # What each game function's handler actually calls, from the sample
  # repository's Lambda/*.py, the one git_clone_url names (identical to the
  # files inside Lambda/code.zip), in place of the _monolithic template's
  # AmazonDynamoDBFullAccess, AmazonSQSFullAccess, AmazonVPCFullAccess and inline
  # gamelift:* (rules.md A-5). The template's breadth for any one function is a
  # single entry in var.lambda_functions[*].additional_policy_arns.
  #
  #   GameResultProcessing  update_item on the table; SQS via its event source
  #   Scoring               nothing in AWS (Redis only); stream via its event source
  #   GetRank               nothing in AWS (Redis only)
  #   MatchRequest          get_item, put_item; gamelift start_matchmaking
  #   MatchStatus           get_item, update_item
  #   MatchEvent            update_item
  #
  # gamelift:* was on three roles in the template and only MatchRequest calls
  # GameLift at all. StartMatchmaking supports no resource-level permissions
  # (the Service Authorization Reference lists no resource type for it), so its
  # Resource has to be "*".
  sqs_process_policies = {
    ConsumeGameResults = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        # What the SQS event source mapping calls on the function's behalf; the
        # same three AWSLambdaSQSQueueExecutionRole grants, on one queue.
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = module.game_result_queue.queue_arn
      }]
    })
    WritePlayerResults = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem"]
        Resource = module.player_info_table.table_arn
      }]
    })
  }
  rank_update_policies = {
    ReadPlayerStream = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          # What the DynamoDB stream event source mapping calls; the stream half
          # of AWSLambdaDynamoDBExecutionRole, on one stream.
          Effect   = "Allow"
          Action   = ["dynamodb:DescribeStream", "dynamodb:GetRecords", "dynamodb:GetShardIterator"]
          Resource = module.player_info_table.stream_arn
        },
        {
          Effect   = "Allow"
          Action   = ["dynamodb:ListStreams"]
          Resource = "*"
        },
      ]
    })
  }
  match_request_policies = {
    ReadWritePlayers = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem"]
        Resource = module.player_info_table.table_arn
      }]
    })
    StartMatchmaking = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = ["gamelift:StartMatchmaking"]
        Resource = "*"
      }]
    })
  }
  match_status_policies = {
    ReadWritePlayers = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:UpdateItem"]
        Resource = module.player_info_table.table_arn
      }]
    })
  }
  match_event_policies = {
    WriteConnectionInfo = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem"]
        Resource = module.player_info_table.table_arn
      }]
    })
  }

  # S3 is read-after-write consistent, so once the marker exists an object
  # either is there or never will be; these retries only absorb the CLI's own
  # transient failures (throttling, an instance credential refresh).
  artifact_head_object_attempts = 4
}
module "network" {
  source = "./modules/network"

  name_prefix                 = var.project_name
  aws_region                  = local.region
  availability_zone_suffixes  = var.availability_zone_suffixes
  vpc_cidr_block              = var.vpc_cidr_block
  public_subnet_a_cidr_block  = var.subnet_cidr_blocks.public_a
  public_subnet_c_cidr_block  = var.subnet_cidr_blocks.public_c
  private_subnet_a_cidr_block = var.subnet_cidr_blocks.private_a
  private_subnet_c_cidr_block = var.subnet_cidr_blocks.private_c
}
# Every module below waits for the whole network module, directly or through a
# module that does, including the ones with no VPC attachment - so the root has
# no exceptions and destroy runs uniformly in reverse (rules.md D-3).
module "key_pair" {
  source = "./modules/key_pair"

  key_name_prefix = "${var.project_name}-"

  depends_on = [module.network]
}
module "app_secret" {
  source = "./modules/app_secret"

  name_prefix             = "${var.project_name}-workshop-user-"
  username                = var.workshop_username
  recovery_window_in_days = var.secret_recovery_window_in_days

  depends_on = [module.network]
}
module "game_source_bucket" {
  source = "./modules/game_source_bucket"

  bucket_prefix = "${var.project_name}-game-source-"
  force_destroy = var.bucket_force_destroy

  depends_on = [module.network]
}
module "web_bucket" {
  source = "./modules/static_website_bucket"

  bucket_prefix = "${var.project_name}-web-"
  force_destroy = var.bucket_force_destroy

  depends_on = [module.network]
}
module "player_info_table" {
  source = "./modules/player_info_table"

  table_name = var.player_table_name

  depends_on = [module.network]
}
module "gomoku_security_group" {
  source = "./modules/gomoku_security_group"

  vpc_id = module.network.vpc_id
  name   = var.gomoku_security_group_name

  depends_on = [module.network]
}
module "redis_cluster" {
  source = "./modules/redis_cluster"

  # Private subnets only; the module explains why the public pair the template
  # also listed is left out.
  subnet_ids         = module.network.private_subnet_ids
  security_group_ids = [module.gomoku_security_group.security_group_id]
  subnet_group_name  = "${var.project_name}-redis"
  cluster_id         = var.redis_cluster_id
  node_type          = var.redis_node_type
  engine_version     = var.redis_engine_version

  depends_on = [module.network, module.gomoku_security_group]
}
module "game_result_queue" {
  source = "./modules/game_result_queue"

  queue_name                 = var.game_result_queue_name
  visibility_timeout_seconds = var.game_result_queue_visibility_timeout_seconds

  depends_on = [module.network]
}
module "gamelift_fleet_role" {
  source = "./modules/gamelift_fleet_role"

  role_name_prefix       = "${var.project_name}-fleet-"
  game_result_queue_arn  = module.game_result_queue.queue_arn
  additional_policy_arns = var.fleet_role_additional_policy_arns

  depends_on = [module.network]
}
# The API carries depends_on = [module.network] and nothing else, deliberately.
# The instance below needs its id at boot - patched into the leaderboard page and
# built into both clients' MATCH_SERVER_API - while every route in it needs a
# function that cannot exist until that same instance has uploaded the code. A
# value reference to rest_api_id orders the instance after the API resource
# alone; a depends_on on any function module here, or on this module from the
# instance, would close that into a cycle.
module "gomoku_api" {
  source = "./modules/gomoku_api"

  api_name   = var.api_name
  stage_name = var.api_stage_name
  routes = {
    ranking = {
      path_part     = "ranking"
      http_method   = "GET"
      function_name = module.game_rank_reader.function_name
      invoke_arn    = module.game_rank_reader.invoke_arn
    }
    matchrequest = {
      path_part     = "matchrequest"
      http_method   = "POST"
      function_name = module.game_match_request.function_name
      invoke_arn    = module.game_match_request.invoke_arn
    }
    matchstatus = {
      path_part     = "matchstatus"
      http_method   = "POST"
      function_name = module.game_match_status.function_name
      invoke_arn    = module.game_match_status.invoke_arn
    }
  }

  depends_on = [module.network]
}
module "windows_ec2" {
  source = "./modules/windows_ec2"

  vpc_id    = module.network.vpc_id
  subnet_id = module.network.public_subnet_a_id
  ami_id    = data.aws_ssm_parameter.windows_ami_id.insecure_value
  key_name  = module.key_pair.key_name

  instance_name           = "${var.project_name}-windows"
  instance_type           = var.windows_instance_type
  root_volume_size        = var.windows_root_volume_size
  security_group_name     = "${var.project_name}-windows-sg"
  rdp_ingress_cidr_blocks = var.rdp_ingress_cidr_blocks

  aws_region        = local.region
  workshop_username = module.app_secret.username
  secret_id         = module.app_secret.secret_id
  git_clone_url     = var.git_clone_url

  # Everything the setup bakes into what it uploads. server.zip embeds the
  # queue URL and the fleet role ARN in its config.ini, so both have to exist
  # before this userdata renders - and they do, because these value references
  # order the instance after the queue and the role.
  game_source_bucket_name = module.game_source_bucket.bucket_name
  web_bucket_name         = module.web_bucket.bucket_name
  server_build_s3_key     = var.server_build_s3_key
  client_archive_s3_key   = var.client_archive_s3_key
  game_result_queue_url   = module.game_result_queue.queue_url
  fleet_role_arn          = module.gamelift_fleet_role.role_arn
  rest_api_id             = module.gomoku_api.rest_api_id
  # The variable, not module.gomoku_api.stage_name: that output reads the stage,
  # which waits on the functions, which wait on this instance.
  api_stage_name = var.api_stage_name

  # Value references order this after the resources that produced each value,
  # not after what has to be ready (rules.md D-2). The secret's version holds the
  # password the setup reads first; the fleet role's SQS grant is what the
  # server.zip it builds will use. gomoku_api is not listed - see above.
  depends_on = [
    module.network,
    module.key_pair,
    module.app_secret,
    module.game_source_bucket,
    module.web_bucket,
    module.game_result_queue,
    module.gamelift_fleet_role,
  ]
}
# What the CloudFormation CreationPolicy used to do.
#
# The template held the stack at the Windows instance until cfn-signal reported
# from the end of its userdata, and that is how the six functions and the
# GameLift build came to be created only after Lambda/code.zip and server.zip
# were in the bucket. The conversion dropped the CreationPolicy - its own
# comment says the wait is not reproduced - and gave every function and the
# build depends_on = [aws_instance.windows_ec2], which is satisfied when
# RunInstances returns: before PowerShell has even started. CreateFunction
# fails at once on a missing S3 object, so the apply failed there; the build
# would have failed too, or left the fleet waiting on a build that never
# became READY.
#
# This association is the half on the instance: wait for the setup's marker,
# then ask S3 for both objects - separately, because they fail apart and the
# message should say which. The marker alone is not enough: the setup runs with
# ErrorActionPreference Continue, so a failed clone or upload still runs on to
# the end and writes it (rules.md D-5 for the marker-and-loop shape).
#
# It is not the half that holds Terraform - module.artifact_waiter below is. The
# functions and the build used to wait on this association through depends_on,
# trusting wait_for_success_timeout_seconds to hold its create until the script
# had finished. That does not happen: an association no target has picked up
# yet reports Overview Success, the provider's waiter accepts it, and the create
# returns in about a second (hashicorp/terraform-provider-aws#31175). Every first
# apply is in that state, because this association is created as soon as the
# instance is. ../template met it on 2026-10-10 - CreateAssociation at 02:59:22,
# four CreateFunction calls failing NoSuchKey at 02:59:25, the script itself
# sent to the instance at 02:59:32 and the uploads at 03:00:11 (its main.tf has
# the CloudTrail timeline). Here the gap is the whole Windows setup.
#
# What this association still does: it is what the waiter consults to stop
# early, so a setup that fails in its catch block, or finishes without one of
# the uploads, ends the apply with this script's message instead of at the end
# of the wait.
#
# PowerShell, because the instance is Windows. The AWS CLI it polls with is
# installed by the setup itself, which is why the S3 checks come after the
# marker and why the script refreshes PATH first: SSM Agent started before
# Chocolatey put the CLI on the machine PATH.
resource "aws_ssm_association" "game_artifacts_uploaded" {
  name                             = "AWS-RunPowerShellScript"
  association_name                 = "${var.project_name}-game-artifacts-uploaded"
  wait_for_success_timeout_seconds = var.artifact_wait_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.windows_ec2.instance_id]
  }
  parameters = {
    executionTimeout = tostring(var.artifact_wait_timeout_seconds)
    commands         = <<-EOT
      $Marker = '${module.windows_ec2.marker_file}'
      $FailureMarker = '${module.windows_ec2.failure_marker_file}'
      $SetupLog = '${module.windows_ec2.setup_log_file}'
      $Bucket = '${module.game_source_bucket.bucket_name}'

      function Write-SetupLogTail {
          if (Test-Path $SetupLog) { Get-Content $SetupLog -Tail 20 }
      }

      # Phase one: the setup's own completion marker, or its failure marker.
      $Waited = 0
      while (-not (Test-Path $Marker)) {
          if (Test-Path $FailureMarker) {
              Write-Output "The setup stopped in its catch block: $(Get-Content $FailureMarker -Raw)"
              Write-SetupLogTail
              exit 1
          }
          $Waited++
          if ($Waited -gt ${var.artifact_wait_attempts}) {
              Write-Output "The setup never reached its end: $Marker is still absent. The last lines of $SetupLog say how far it got."
              Write-SetupLogTail
              exit 1
          }
          Start-Sleep -Seconds ${var.artifact_wait_interval_seconds}
      }

      $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
      if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
          Write-Output "The setup finished but the AWS CLI is not on the machine PATH, so none of its uploads can have run. Look for the choco install awscli step in $SetupLog."
          Write-SetupLogTail
          exit 1
      }

      function Test-S3Object([string]$Key) {
          for ($Attempt = 1; $Attempt -le ${local.artifact_head_object_attempts}; $Attempt++) {
              aws s3api head-object --region ${local.region} --bucket $Bucket --key $Key *> $null
              if ($LASTEXITCODE -eq 0) { return $true }
              Start-Sleep -Seconds ${var.artifact_wait_interval_seconds}
          }
          return $false
      }

      # Phase two: the Lambda package. Nothing uploads this key by name - it
      # arrives with the recursive copy of the whole clone.
      if (-not (Test-S3Object '${var.lambda_code_s3_key}')) {
          Write-Output "s3://$Bucket/${var.lambda_code_s3_key} is absent although the setup finished. It only arrives with the recursive upload of the clone, so the clone or that upload failed. All six game functions are created from it, and CreateFunction fails on a missing object."
          Write-SetupLogTail
          exit 1
      }

      # Phase three: the server build, uploaded on its own before the clone.
      if (-not (Test-S3Object '${var.server_build_s3_key}')) {
          Write-Output "s3://$Bucket/${var.server_build_s3_key} is absent although the setup finished, while the Lambda package is there - so the clone worked and the Compress-Archive or the upload of the server did not. The GameLift build copies this object at creation and fails without it."
          Write-SetupLogTail
          exit 1
      }

      Write-Output "s3://$Bucket/${var.lambda_code_s3_key} and s3://$Bucket/${var.server_build_s3_key} are both present."
      exit 0
      EOT
  }

  # The instance id orders this after the instance; the module boundary also
  # brings its security group rules, without which SSM Agent cannot register.
  depends_on = [module.windows_ec2]
}
# The half that holds Terraform: a function per object that asks S3 for it
# until it is there, invoked synchronously, in rounds of at most 900 seconds
# because that is the longest a Lambda function runs. It stops early only when
# the association above has failed - never on its Success. One per object so a
# timeout names the missing one; client.zip is not here, because nothing
# Terraform creates reads it.
#
# The readers name the object through the waiter's result rather than through
# module.game_source_bucket and the key variables, and that is the whole
# ordering: the result is unknown until the last round has returned, so a
# resource that takes it cannot be created before. No module-level depends_on
# on the readers, which would also hold back their IAM roles and policies - the
# GameLift build role's read grant in particular has to be in place before
# CreateBuild, not created in the same second.
locals {
  uploaded_artifacts = {
    lambda_code  = { key = var.lambda_code_s3_key, function_name = "${var.project_name}-lambda-code-waiter" }
    server_build = { key = var.server_build_s3_key, function_name = "${var.project_name}-server-build-waiter" }
  }
}
module "artifact_waiter" {
  source   = "./modules/s3_object_waiter"
  for_each = local.uploaded_artifacts

  function_name   = each.value.function_name
  bucket_name     = module.game_source_bucket.bucket_name
  bucket_arn      = module.game_source_bucket.bucket_arn
  object_key      = each.value.key
  association_id  = aws_ssm_association.game_artifacts_uploaded.association_id
  association_arn = aws_ssm_association.game_artifacts_uploaded.arn
  partition       = local.partition
  # The association's own timeout, so "how long the setup may take" stays one
  # value: 2400 by default, three rounds of 800 seconds. Capped at the module's
  # four rounds rather than by lowering the variable, which also sets the
  # association's executionTimeout - and a change there is an UpdateAssociation
  # that runs the check on the instance again.
  timeout_seconds = min(var.artifact_wait_timeout_seconds, 3600)

  depends_on = [module.network]
}
# --- The six game functions, all from Lambda/code.zip ------------------------
#
# Every one takes its bucket and key from module.artifact_waiter["lambda_code"],
# and that reference - not a depends_on - is what holds CreateFunction, which
# reads the package from S3 synchronously, until the package is there. It is
# the last of the two objects to arrive: it comes with the recursive upload of
# the whole clone, after server.zip.
module "game_sqs_process" {
  source = "./modules/lambda_function"

  function_name          = var.lambda_functions.sqs_process.function_name
  handler                = var.lambda_functions.sqs_process.handler
  runtime                = var.lambda_runtime
  timeout                = var.lambda_timeout_seconds
  s3_bucket              = module.artifact_waiter["lambda_code"].bucket
  s3_key                 = module.artifact_waiter["lambda_code"].key
  role_name_prefix       = "${var.project_name}-sqs-process-"
  managed_policy_arns    = [local.lambda_basic_execution_policy_arn]
  additional_policy_arns = var.lambda_functions.sqs_process.additional_policy_arns
  inline_policies        = local.sqs_process_policies
  event_source_mappings = {
    game_results = {
      event_source_arn = module.game_result_queue.queue_arn
    }
  }

  depends_on = [
    module.network,
    module.player_info_table,
    module.game_result_queue,
  ]
}
module "game_rank_update" {
  source = "./modules/lambda_function"

  function_name          = var.lambda_functions.rank_update.function_name
  handler                = var.lambda_functions.rank_update.handler
  runtime                = var.lambda_runtime
  timeout                = var.lambda_timeout_seconds
  s3_bucket              = module.artifact_waiter["lambda_code"].bucket
  s3_key                 = module.artifact_waiter["lambda_code"].key
  role_name_prefix       = "${var.project_name}-rank-update-"
  managed_policy_arns    = [local.lambda_basic_execution_policy_arn, local.lambda_vpc_access_policy_arn]
  additional_policy_arns = var.lambda_functions.rank_update.additional_policy_arns
  inline_policies        = local.rank_update_policies
  environment_variables = {
    REDIS = module.redis_cluster.address
  }
  # Private subnets only, where the template listed all four; see the
  # redis_cluster module.
  subnet_ids         = module.network.private_subnet_ids
  security_group_ids = [module.gomoku_security_group.security_group_id]
  event_source_mappings = {
    player_table_stream = {
      event_source_arn  = module.player_info_table.stream_arn
      starting_position = var.player_stream_starting_position
    }
  }

  # gomoku_security_group as a whole, not only its id: the egress rule in it is
  # what lets this function open a connection to Redis.
  depends_on = [
    module.network,
    module.player_info_table,
    module.gomoku_security_group,
    module.redis_cluster,
  ]
}
module "game_rank_reader" {
  source = "./modules/lambda_function"

  function_name          = var.lambda_functions.rank_reader.function_name
  handler                = var.lambda_functions.rank_reader.handler
  runtime                = var.lambda_runtime
  timeout                = var.lambda_timeout_seconds
  s3_bucket              = module.artifact_waiter["lambda_code"].bucket
  s3_key                 = module.artifact_waiter["lambda_code"].key
  role_name_prefix       = "${var.project_name}-rank-reader-"
  managed_policy_arns    = [local.lambda_basic_execution_policy_arn, local.lambda_vpc_access_policy_arn]
  additional_policy_arns = var.lambda_functions.rank_reader.additional_policy_arns
  environment_variables = {
    REDIS = module.redis_cluster.address
  }
  subnet_ids         = module.network.private_subnet_ids
  security_group_ids = [module.gomoku_security_group.security_group_id]

  depends_on = [
    module.network,
    module.gomoku_security_group,
    module.redis_cluster,
  ]
}
module "game_match_request" {
  source = "./modules/lambda_function"

  function_name          = var.lambda_functions.match_request.function_name
  handler                = var.lambda_functions.match_request.handler
  runtime                = var.lambda_runtime
  timeout                = var.lambda_timeout_seconds
  s3_bucket              = module.artifact_waiter["lambda_code"].bucket
  s3_key                 = module.artifact_waiter["lambda_code"].key
  role_name_prefix       = "${var.project_name}-match-request-"
  managed_policy_arns    = [local.lambda_basic_execution_policy_arn]
  additional_policy_arns = var.lambda_functions.match_request.additional_policy_arns
  inline_policies        = local.match_request_policies

  depends_on = [
    module.network,
    module.player_info_table,
  ]
}
module "game_match_status" {
  source = "./modules/lambda_function"

  function_name          = var.lambda_functions.match_status.function_name
  handler                = var.lambda_functions.match_status.handler
  runtime                = var.lambda_runtime
  timeout                = var.lambda_timeout_seconds
  s3_bucket              = module.artifact_waiter["lambda_code"].bucket
  s3_key                 = module.artifact_waiter["lambda_code"].key
  role_name_prefix       = "${var.project_name}-match-status-"
  managed_policy_arns    = [local.lambda_basic_execution_policy_arn]
  additional_policy_arns = var.lambda_functions.match_status.additional_policy_arns
  inline_policies        = local.match_status_policies

  depends_on = [
    module.network,
    module.player_info_table,
  ]
}
module "game_match_event" {
  source = "./modules/lambda_function"

  function_name          = var.lambda_functions.match_event.function_name
  handler                = var.lambda_functions.match_event.handler
  runtime                = var.lambda_runtime
  timeout                = var.lambda_timeout_seconds
  s3_bucket              = module.artifact_waiter["lambda_code"].bucket
  s3_key                 = module.artifact_waiter["lambda_code"].key
  role_name_prefix       = "${var.project_name}-match-event-"
  managed_policy_arns    = [local.lambda_basic_execution_policy_arn]
  additional_policy_arns = var.lambda_functions.match_event.additional_policy_arns
  inline_policies        = local.match_event_policies

  depends_on = [
    module.network,
    module.player_info_table,
  ]
}
# --- Matchmaking events -------------------------------------------------------
module "match_event_topic" {
  source = "./modules/match_event_topic"

  topic_name            = var.match_event_topic_name
  account_id            = local.account_id
  publisher_source_arns = [local.matchmaking_configuration_arn]
  lambda_subscribers = {
    match_event = {
      function_arn  = module.game_match_event.function_arn
      function_name = module.game_match_event.function_name
    }
  }

  depends_on = [module.network]
}
# --- GameLift -----------------------------------------------------------------
module "gamelift_fleet" {
  source = "./modules/gamelift_fleet"

  # The bucket name through the waiter's result and the other two straight
  # from their sources, on purpose: the module uses build_bucket_name for the
  # build alone, and the ARN and the key for the build role's read grant as
  # well. So CreateBuild waits for server.zip while the grant is created early
  # enough to have propagated. A grant that has not would get the same
  # "Provided resource is not accessible" as a missing object - the message
  # names both causes - and the provider does not retry it. The key is the one
  # the waiter was given.
  build_bucket_name      = module.artifact_waiter["server_build"].bucket
  build_bucket_arn       = module.game_source_bucket.bucket_arn
  build_object_key       = var.server_build_s3_key
  build_role_name_prefix = "${var.project_name}-build-"
  build_name             = var.gamelift_build_name
  operating_system       = var.gamelift_operating_system

  fleet_name              = var.gamelift_fleet_name
  ec2_instance_type       = var.gamelift_fleet_instance_type
  fleet_type              = var.gamelift_fleet_type
  instance_role_arn       = module.gamelift_fleet_role.role_arn
  ec2_inbound_permissions = var.gamelift_fleet_inbound_permissions
  alias_name              = var.gamelift_alias_name
  alias_description       = var.gamelift_alias_description
  queue_name              = var.gamelift_queue_name

  # gamelift_fleet_role as a module so the role's SQS grant is in place before
  # any server process can try to use it. The wait for server.zip, which
  # CreateBuild copies at the moment it is called, is build_bucket_name above,
  # not an entry here: a module-level depends_on would hold the build role's
  # grant back with it.
  depends_on = [
    module.network,
    module.gamelift_fleet_role,
  ]
}
module "gamelift_matchmaking" {
  source = "./modules/gamelift_matchmaking"

  rule_set_name           = var.matchmaking_rule_set_name
  rule_set                = var.matchmaking_rule_set
  configuration_name      = var.matchmaking_configuration_name
  acceptance_required     = var.matchmaking_acceptance_required
  request_timeout_seconds = var.matchmaking_request_timeout_seconds
  game_session_queue_arns = [module.gamelift_fleet.queue_arn]
  notification_target     = module.match_event_topic.topic_arn

  # match_event_topic as a module rather than through topic_arn: the ARN orders
  # this after the topic, and what has to exist before the first event is
  # published is the topic policy granting gamelift.amazonaws.com and the
  # subscription to game-match-event.
  depends_on = [
    module.network,
    module.gamelift_fleet,
    module.match_event_topic,
  ]
}
# The topic policy admits a publisher by an ARN assembled in locals rather than
# read from the configuration (see matchmaking_configuration_arn). If the two
# ever disagree, FlexMatch's publishes are refused, the subscription never
# fires, and every match request polls /matchstatus forever with no error
# anywhere. Unknown during the first plan; evaluated once the configuration
# exists. In the root because a check in a module delays that module's close
# (rules.md D-9).
check "topic_policy_admits_the_matchmaker" {
  assert {
    condition     = module.gamelift_matchmaking.configuration_arn == local.matchmaking_configuration_arn
    error_message = "The matchmaking configuration's ARN (${module.gamelift_matchmaking.configuration_arn}) differs from the aws:SourceArn the SNS topic policy admits (${local.matchmaking_configuration_arn}), so FlexMatch cannot publish match events."
  }
}
