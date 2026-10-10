data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
# The workbench AMI, resolved here rather than inside the module that launches it, so no module declares a data
# source and none can be deferred to apply by a depends_on (rules.md D-6). insecure_value because the provider
# marks every parameter value sensitive, and a public AMI ID is not a secret.
data "aws_ssm_parameter" "vscode_ami_id" {
  name = var.ami_ssm_parameter_name
}
locals {
  region     = data.aws_region.current.region
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  # Where the workbench clones the game sample. Every step that touches the checkout names it through this.
  repository_directory = "/home/ec2-user/gomoku"

  # The six functions. The handlers are fixed by the package (the sample's Lambda/code.zip), not configuration.
  lambda_functions = {
    sqs_process   = { name = "${var.lambda_function_name_prefix}sqs-process", handler = "GameResultProcessing.lambda_handler" }
    rank_update   = { name = "${var.lambda_function_name_prefix}rank-update", handler = "Scoring.handler" }
    rank_reader   = { name = "${var.lambda_function_name_prefix}rank-reader", handler = "GetRank.handler" }
    match_request = { name = "${var.lambda_function_name_prefix}match-request", handler = "MatchRequest.lambda_handler" }
    match_status  = { name = "${var.lambda_function_name_prefix}match-status", handler = "MatchStatus.lambda_handler" }
    match_event   = { name = "${var.lambda_function_name_prefix}match-event", handler = "MatchEvent.lambda_handler" }
  }

  # The FlexMatch rule set, as an HCL object rendered with jsonencode: one typed source, valid JSON by
  # construction. It is the _monolithic template's unconverted RuleSetBody, and it is also identical - compared
  # as parsed JSON - to Ruleset/GomokuRuleSet.json in the sample repository at game_sample_repository_ref. That
  # file is not read: the workbench's clone exists only at apply time and only on the instance, and a variant
  # does not depend on a path outside its own folder (rules.md A-1).
  #
  # One player per team, two teams, and a skill-distance rule on the score attribute whose limit widens from 300
  # to 1000 over 30 seconds. default = 1000 matches the starting score MatchRequest.py gives a new player.
  matchmaking_rule_set = {
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

  # The configuration ARN the SNS topic policy admits as a publisher, built from the name rather than read from
  # the configuration. The configuration names the topic as its notification target, so reading the ARN back
  # into the topic's policy would make the policy wait for a configuration that itself waits for the fleet to
  # go ACTIVE. The account field is a wildcard because GameLift's API reference documents this ARN without an
  # account ID while the FlexMatch guide's policy example has one; aws:SourceAccount pins the account instead.
  # The check block at the end of this file compares the pattern with the real ARN.
  matchmaking_configuration_arn_pattern = "arn:${local.partition}:gamelift:${local.region}:*:matchmakingconfiguration/${var.matchmaking_configuration_name}"
}
# --- Network and the things that only need an account ---------------------------------------------------------
module "network" {
  source = "./modules/network"

  region                     = local.region
  vpc_cidr_block             = var.vpc_cidr_block
  availability_zone_suffixes = var.availability_zone_suffixes
  public_subnet_cidr_blocks  = var.public_subnet_cidr_blocks
  private_subnet_cidr_blocks = var.private_subnet_cidr_blocks
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name_prefix = "${var.project_name}-"
  rsa_bits        = var.key_rsa_bits

  # Needs nothing from network and waits anyway: a root with a network module has no module starting before it
  # finishes, so nobody has to decide per module whether an omission was reasoned (rules.md D-3).
  depends_on = [module.network]
}
module "game_source_bucket" {
  source = "./modules/game_source_bucket"

  bucket_prefix = "${var.project_name}-game-source-"
  force_destroy = var.bucket_force_destroy

  depends_on = [module.network]
}
module "leaderboard_website" {
  source = "./modules/leaderboard_website"

  bucket_prefix = "${var.project_name}-leaderboard-"
  force_destroy = var.bucket_force_destroy

  depends_on = [module.network]
}
module "player_table" {
  source = "./modules/player_table"

  name = var.player_table_name

  depends_on = [module.network]
}
module "game_result_queue" {
  source = "./modules/game_result_queue"

  name                       = var.game_result_queue_name
  visibility_timeout_seconds = var.game_result_queue_visibility_timeout_seconds

  depends_on = [module.network]
}
# Before the workbench, because its ARN is baked into server.zip - see the module.
module "gamelift_fleet_role" {
  source = "./modules/gamelift_fleet_role"

  role_name_prefix       = "${var.project_name}-gamelift-fleet-"
  game_result_queue_arn  = module.game_result_queue.arn
  additional_policy_arns = var.fleet_role_additional_policy_arns

  depends_on = [module.network]
}
# --- The workbench and the artifacts it uploads --------------------------------------------------------------
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name                        = var.vscode_instance_name
  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  ami_id                      = data.aws_ssm_parameter.vscode_ami_id.insecure_value
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  code_server_version         = var.code_server_version
  code_server_port            = var.code_server_port
  security_group_name         = var.vscode_security_group_name
  allow_inbound_from_anywhere = var.inbound_from_anywhere
  iam_role_name_prefix        = "${var.project_name}-vscode-"
  marker_file_path            = var.marker_file_path

  # No EKS cluster in this root, so rules.md H-1's five-tool list does not apply: zip for the two archives and
  # redis6 for the README's leaderboard command, nothing else. git comes from the module's bootstrap, and the
  # AWS CLI is on Amazon Linux 2023 already.
  #
  # The server's config.ini carries the queue URL and the fleet role ARN, so both have to exist before this
  # renders - and they do, because those two references are what order this module after them.
  #
  # Two uploads, not the _monolithic template's "aws s3 cp --recursive" of the whole checkout to the bucket root.
  # Nothing reads anything from that copy except Lambda/code.zip, and it was 140 MB of binaries, documentation and
  # .git. The commented-out block that rebuilt code.zip with a sed on the region is dropped too: the handlers in
  # the package use boto3's default region, which Lambda sets.
  additional_user_data = <<-EOT
    dnf install -yq zip redis6
    # A region for ec2-user, so the commands in the README work as written from the IDE terminal.
    runuser -u ec2-user -- env HOME=/home/ec2-user aws configure set default.region ${local.region}

    # HOME is set explicitly: userdata runs as root, and a preserved environment would point ~ at /root.
    sudo -u ec2-user bash << 'TFSETUP'
    set -ex
    export HOME=/home/ec2-user
    git clone --quiet ${var.game_sample_repository_url} ${local.repository_directory}
    git -C ${local.repository_directory} checkout --quiet ${var.game_sample_repository_ref}

    cat > ${local.repository_directory}/bin/FlexMatch/GomokuServer/Binaries/Win64/config.ini << 'TFSERVERCONFIG'
    [config]

    # GameResult SQS
    SQS_REGION = ${local.region}
    SQS_ENDPOINT = ${module.game_result_queue.url}
    ROLE_ARN = ${module.gamelift_fleet_role.role_arn}
    TFSERVERCONFIG

    # Zipped from inside GomokuServer/ so the archive's root holds Binaries/, which GameLift unpacks under
    # C:\game - the fleet's launch path depends on it.
    cd ${local.repository_directory}/bin/FlexMatch/GomokuServer
    rm -f /home/ec2-user/server.zip
    zip -qr /home/ec2-user/server.zip ./*
    aws s3 cp --quiet --region ${local.region} /home/ec2-user/server.zip s3://${module.game_source_bucket.bucket_name}/${var.server_build_s3_key}
    aws s3 cp --quiet --region ${local.region} ${local.repository_directory}/Lambda/code.zip s3://${module.game_source_bucket.bucket_name}/${var.lambda_code_s3_key}
    TFSETUP
  EOT

  depends_on = [module.network, module.key_pair]
}
# What the CloudFormation CreationPolicy used to do, in two halves.
#
# All six functions read Lambda/code.zip and the GameLift build reads server.zip, from a bucket nothing in
# Terraform writes to. The workbench uploads both during this same apply, minutes after RunInstances returns -
# and RunInstances returning is all the _monolithic template's depends_on = [aws_instance...] waited for. The
# template's CreationPolicy (PT7M) held the stack until cfn-signal; the conversion dropped it and said so.
#
# Without a wait the apply fails at the first CreateFunction - Lambda checks the object exists on the spot - and
# CreateBuild is refused with "Provided resource is not accessible", which the provider does not retry.
#
# This association is the half on the workbench: wait for the bootstrap's marker, ask S3 for each object, and
# leave the artifacts_uploaded marker client_config starts from. Separate loops so the failure says which one is
# missing. The marker alone is not proof: the upload runs under set -e in a sub-shell, but the bootstrap around
# it does not stop, so the marker appears whether or not the uploads happened.
#
# It is not the half that holds Terraform - module.artifact_waiter below is. The readers used to wait on this
# association through depends_on, trusting wait_for_success_timeout_seconds to hold its create until the script
# had finished. It did not. From CloudTrail and the association's history, 2026-10-10 (KST):
#
#   02:59:07  RunInstances             the workbench launches
#   02:59:21  RegisterManagedInstance  its SSM agent registers
#   02:59:22  CreateAssociation        artifacts_uploaded; the provider's waiter reads Overview Success and
#                                      returns within the same second
#   02:59:25  CreateFunction x4        game-sqs-process, -match-request, -match-status, -match-event: NoSuchKey
#   02:59:26  CreateBuild x4           retried on "cannot assume the role", then "Provided resource is not
#   - 02:59:32                         accessible" - the object, not the role or the region
#   02:59:32  SendCommand              the association's script reaches the workbench, 10 seconds after
#                                      Terraform was told it had succeeded
#   03:00:11  server.zip uploaded, and Lambda/code.zip at 03:00:12
#   03:00:14  the association's execution ends Success
#   03:02:06  CreateFunction x2        game-rank-reader and -rank-update, which also wait for the cache: created
#
# An association no target has picked up yet reports Success, and every first apply creates this one seconds
# after its instance. That is the provider issue rules.md D-5 warns about (hashicorp/terraform-provider-aws
# #31175), and 073_cognito_identity_pool met the same failure the same way.
resource "aws_ssm_association" "artifacts_uploaded" {
  name                             = "AWS-RunShellScript"
  association_name                 = "${var.project_name}-artifacts-uploaded"
  wait_for_success_timeout_seconds = var.artifact_wait_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # An until loop rather than a bare test, because a failing test at top level ends the script under -e with
    # no output, and a failing until condition never does (rules.md D-5). The marker path comes back out of the
    # module it was handed to, so this loop and the bootstrap cannot disagree about it (rules.md B-5).
    commands = <<-EOT
      set -u
      MARKER=${module.vscode_ec2.marker_file_path}/userdata
      waited=0
      until [ -f "$MARKER" ]; do
        waited=$((waited + 1))
        if [ "$waited" -gt ${var.artifact_wait_attempts} ]; then
          echo "The workbench bootstrap never finished: $MARKER is still absent. /var/log/cloud-init-output.log on this instance shows where it stopped." >&2
          exit 1
        fi
        sleep ${var.marker_wait_interval_seconds}
      done

      found=0
      for attempt in $(seq 1 ${var.artifact_head_attempts}); do
        if aws s3api head-object --region ${local.region} --bucket ${module.game_source_bucket.bucket_name} --key ${var.lambda_code_s3_key} > /dev/null 2>&1; then
          found=1
          break
        fi
        sleep ${var.marker_wait_interval_seconds}
      done
      if [ "$found" -ne 1 ]; then
        echo "s3://${module.game_source_bucket.bucket_name}/${var.lambda_code_s3_key} is absent although the bootstrap finished. All six functions are created from it and CreateFunction would fail on the missing object; the clone or the upload failed - /var/log/cloud-init-output.log has which." >&2
        exit 1
      fi

      found=0
      for attempt in $(seq 1 ${var.artifact_head_attempts}); do
        if aws s3api head-object --region ${local.region} --bucket ${module.game_source_bucket.bucket_name} --key ${var.server_build_s3_key} > /dev/null 2>&1; then
          found=1
          break
        fi
        sleep ${var.marker_wait_interval_seconds}
      done
      if [ "$found" -ne 1 ]; then
        echo "s3://${module.game_source_bucket.bucket_name}/${var.server_build_s3_key} is absent although the bootstrap finished. The GameLift build would be created FAILED and the fleet would never activate; the zip or the upload failed - /var/log/cloud-init-output.log has which." >&2
        exit 1
      fi

      touch ${module.vscode_ec2.marker_file_path}/artifacts_uploaded
      EOT
  }
  depends_on = [module.vscode_ec2, module.game_source_bucket]
}
# The half that holds Terraform: a function per object that asks S3 for it until it is there, invoked
# synchronously. It stops early only when the association above has failed - never on its Success, for the
# reason in the timeline. One per object so a timeout names the missing one. client.zip is not here: nothing
# Terraform creates reads it, and client_config waits for it on the workbench.
#
# The readers name the object through the waiter's result rather than through module.game_source_bucket and
# the key variables, and that is the whole ordering: the result is unknown until the invocation has returned,
# so a resource that takes it cannot be created before. No module-level depends_on on the readers, which would
# also hold their IAM roles and policies - the GameLift build role's grant in particular has to be in place
# before CreateBuild, not created in the same second.
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
  association_id  = aws_ssm_association.artifacts_uploaded.association_id
  association_arn = aws_ssm_association.artifacts_uploaded.arn
  partition       = local.partition
  # The same number as the association's own wait, so "how long the bootstrap may take" stays one value, capped
  # at the 900 seconds a Lambda function can run. Capped here rather than by lowering the variable: the
  # association's wait_for_success_timeout_seconds reads it too, and the provider sends any change to that as
  # an UpdateAssociation, which re-runs the check on the workbench. 900 is still twice the CreationPolicy's
  # PT7M, and a timeout is not recorded in state, so the next apply simply waits again.
  timeout_seconds = min(var.artifact_wait_timeout_seconds, 900)

  depends_on = [module.network]
}
# --- Data stores ------------------------------------------------------------------------------------------------
module "resource_security_group" {
  source = "./modules/resource_security_group"

  vpc_id = module.network.vpc_id
  name   = var.resource_security_group_name
  # The workbench, admitted on the Redis port so the README's redis6-cli command works from the IDE terminal. A
  # map with a literal key because the ID is another module's output (rules.md B-8).
  ingress_source_security_groups = {
    workbench = module.vscode_ec2.security_group_id
  }
  ingress_source_port = var.redis_port

  depends_on = [module.network]
}
module "ranking_cache" {
  source = "./modules/ranking_cache"

  cluster_id        = var.ranking_cache_cluster_id
  subnet_group_name = "${var.project_name}-ranking-subnet-group"
  # Private subnets only. The _monolithic template's subnet group also listed both public subnets, and that buys
  # nothing: ElastiCache never gives a node a public address, so a node placed in a public subnet is reachable
  # exactly as a private one is - through the security group, from inside the VPC. The "Use CloudShell in the
  # VPC" route the windows_rdp variant prints works the same way, since a CloudShell VPC environment reaches the
  # node through the security group from whichever subnet it is put in.
  subnet_ids         = module.network.private_subnet_ids
  security_group_ids = [module.resource_security_group.security_group_id]
  node_type          = var.ranking_cache_node_type
  engine_version     = var.ranking_cache_engine_version
  port               = var.redis_port

  depends_on = [module.network, module.resource_security_group]
}
# --- The six functions ------------------------------------------------------------------------------------------
#
# Every function is created from the uploaded package, so every one takes its bucket and key from
# module.artifact_waiter["lambda_code"] - that reference, not a depends_on, is what holds CreateFunction until
# the package is in S3. Each role carries only what its handler calls (rules.md A-5) - read from the handlers in the sample's Lambda/, which
# are the same files packaged in Lambda/code.zip. The _monolithic template's managed full-access policies and its
# gamelift:* inline policy are listed in each *_additional_policy_arns variable's description.
module "game_sqs_process" {
  source = "./modules/lambda_function"

  function_name    = local.lambda_functions.sqs_process.name
  handler          = local.lambda_functions.sqs_process.handler
  runtime          = var.lambda_runtime
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size
  s3_bucket        = module.artifact_waiter["lambda_code"].bucket
  s3_key           = module.artifact_waiter["lambda_code"].key
  partition        = local.partition
  role_name_prefix = "${var.project_name}-sqs-process-"
  # GameResultProcessing.py: update_item on the player table for each message. It also creates an SQS client
  # it never uses - the messages arrive through the event source mapping, which polls with the function's role
  # and needs the three queue actions below. The original's gamelift:* grant had no caller here.
  policy_statements = [
    { sid = "UpdatePlayerResults", actions = ["dynamodb:UpdateItem"], resources = [module.player_table.arn] },
    { sid = "ConsumeGameResults", actions = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], resources = [module.game_result_queue.arn] },
  ]
  additional_policy_arns = var.game_sqs_process_additional_policy_arns
  event_source_mappings = {
    game_results = { event_source_arn = module.game_result_queue.arn }
  }

  depends_on = [module.network]
}
module "game_rank_update" {
  source = "./modules/lambda_function"

  function_name    = local.lambda_functions.rank_update.name
  handler          = local.lambda_functions.rank_update.handler
  runtime          = var.lambda_runtime
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size
  s3_bucket        = module.artifact_waiter["lambda_code"].bucket
  s3_key           = module.artifact_waiter["lambda_code"].key
  partition        = local.partition
  role_name_prefix = "${var.project_name}-rank-update-"
  # Scoring.py: zadd/zrem on Redis for each stream record, no AWS call at all. What the role needs is the
  # stream read the event source mapping does with it. ListStreams takes no resource ARN.
  policy_statements = [
    { sid = "ReadPlayerTableStream", actions = ["dynamodb:DescribeStream", "dynamodb:GetRecords", "dynamodb:GetShardIterator"], resources = [module.player_table.stream_arn] },
    { sid = "ListStreams", actions = ["dynamodb:ListStreams"], resources = ["*"] },
  ]
  additional_policy_arns = var.game_rank_update_additional_policy_arns
  environment_variables = {
    REDIS = module.ranking_cache.address
  }
  # Private subnets only, for the reason given on ranking_cache: a Lambda ENI never has a public address either,
  # so the _monolithic template's public subnets added nothing but a subnet with no route out for it.
  vpc_subnet_ids         = module.network.private_subnet_ids
  vpc_security_group_ids = [module.resource_security_group.security_group_id]
  event_source_mappings = {
    player_table_stream = { event_source_arn = module.player_table.stream_arn, starting_position = var.player_stream_starting_position }
  }

  # resource_security_group for its egress rule, which nothing here references: without it the first stream
  # batch would be processed by a function that cannot open a connection to Redis.
  depends_on = [module.network, module.resource_security_group]
}
module "game_rank_reader" {
  source = "./modules/lambda_function"

  function_name    = local.lambda_functions.rank_reader.name
  handler          = local.lambda_functions.rank_reader.handler
  runtime          = var.lambda_runtime
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size
  s3_bucket        = module.artifact_waiter["lambda_code"].bucket
  s3_key           = module.artifact_waiter["lambda_code"].key
  partition        = local.partition
  role_name_prefix = "${var.project_name}-rank-reader-"
  # GetRank.py: zrevrange on Redis, no AWS call. The VPC execution policy the module attaches is all it needs.
  additional_policy_arns = var.game_rank_reader_additional_policy_arns
  environment_variables = {
    REDIS = module.ranking_cache.address
  }
  vpc_subnet_ids         = module.network.private_subnet_ids
  vpc_security_group_ids = [module.resource_security_group.security_group_id]

  depends_on = [module.network, module.resource_security_group]
}
module "game_match_request" {
  source = "./modules/lambda_function"

  function_name    = local.lambda_functions.match_request.name
  handler          = local.lambda_functions.match_request.handler
  runtime          = var.lambda_runtime
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size
  s3_bucket        = module.artifact_waiter["lambda_code"].bucket
  s3_key           = module.artifact_waiter["lambda_code"].key
  partition        = local.partition
  role_name_prefix = "${var.project_name}-match-request-"
  # MatchRequest.py: get_item and put_item on the player table, then start_matchmaking. StartMatchmaking has no
  # resource type in the service authorization reference, so it can only be granted on "*" - the configuration
  # it targets is fixed by the handler's literal ConfigurationName rather than by this policy.
  policy_statements = [
    { sid = "ReadCreatePlayers", actions = ["dynamodb:GetItem", "dynamodb:PutItem"], resources = [module.player_table.arn] },
    { sid = "StartMatchmaking", actions = ["gamelift:StartMatchmaking"], resources = ["*"] },
  ]
  additional_policy_arns = var.game_match_request_additional_policy_arns

  depends_on = [module.network]
}
module "game_match_status" {
  source = "./modules/lambda_function"

  function_name    = local.lambda_functions.match_status.name
  handler          = local.lambda_functions.match_status.handler
  runtime          = var.lambda_runtime
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size
  s3_bucket        = module.artifact_waiter["lambda_code"].bucket
  s3_key           = module.artifact_waiter["lambda_code"].key
  partition        = local.partition
  role_name_prefix = "${var.project_name}-match-status-"
  # MatchStatus.py: get_item for the player's ConnectionInfo, update_item to mark it complete. Despite the
  # original's gamelift:* grant it never calls GameLift - the match result reaches it through the table.
  policy_statements = [
    { sid = "ReadUpdateConnectionInfo", actions = ["dynamodb:GetItem", "dynamodb:UpdateItem"], resources = [module.player_table.arn] },
  ]
  additional_policy_arns = var.game_match_status_additional_policy_arns

  depends_on = [module.network]
}
module "game_match_event" {
  source = "./modules/lambda_function"

  function_name    = local.lambda_functions.match_event.name
  handler          = local.lambda_functions.match_event.handler
  runtime          = var.lambda_runtime
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size
  s3_bucket        = module.artifact_waiter["lambda_code"].bucket
  s3_key           = module.artifact_waiter["lambda_code"].key
  partition        = local.partition
  role_name_prefix = "${var.project_name}-match-event-"
  # MatchEvent.py: update_item writing ConnectionInfo for each matched player.
  policy_statements = [
    { sid = "WriteConnectionInfo", actions = ["dynamodb:UpdateItem"], resources = [module.player_table.arn] },
  ]
  additional_policy_arns = var.game_match_event_additional_policy_arns

  depends_on = [module.network]
}
# --- Match events and the API -------------------------------------------------------------------------------
module "match_event_topic" {
  source = "./modules/match_event_topic"

  name                 = var.match_event_topic_name
  account_id           = local.account_id
  publisher_source_arn = local.matchmaking_configuration_arn_pattern
  subscriber_function_arns = {
    match_event = module.game_match_event.function_arn
  }

  depends_on = [module.network]
}
module "gomoku_api" {
  source = "./modules/gomoku_api"

  name              = var.api_name
  stage_name        = var.api_stage_name
  cors_allow_origin = var.api_cors_allow_origin
  # Paths and methods are what the prebuilt clients and web/main.js call, so they are fixed here rather than
  # configurable.
  routes = {
    ranking = {
      path_part     = "ranking"
      http_method   = "GET"
      function_name = module.game_rank_reader.function_name
      invoke_arn    = module.game_rank_reader.invoke_arn
    }
    match_request = {
      path_part     = "matchrequest"
      http_method   = "POST"
      function_name = module.game_match_request.function_name
      invoke_arn    = module.game_match_request.invoke_arn
    }
    match_status = {
      path_part     = "matchstatus"
      http_method   = "POST"
      function_name = module.game_match_status.function_name
      invoke_arn    = module.game_match_status.invoke_arn
    }
  }

  depends_on = [module.network]
}
# --- GameLift and FlexMatch ---------------------------------------------------------------------------------
module "gamelift_fleet" {
  source = "./modules/gamelift_fleet"

  build_name             = var.gamelift_build_name
  build_operating_system = var.gamelift_build_operating_system
  build_role_name_prefix = "${var.project_name}-gamelift-build-"
  # The bucket name through the waiter's result and the other two straight from their sources, on purpose: the
  # module uses source_bucket_name for the build alone, and the ARN and the key for the build role's read grant
  # as well. So CreateBuild waits for server.zip while the grant is created early enough to have propagated. A
  # grant that has not propagated would get the same "Provided resource is not accessible" as a missing object -
  # the message names both causes - and the provider does not retry it. The key is the one the waiter was given.
  source_bucket_name  = module.artifact_waiter["server_build"].bucket
  source_bucket_arn   = module.game_source_bucket.bucket_arn
  server_build_s3_key = var.server_build_s3_key

  fleet_name        = var.gamelift_fleet_name
  fleet_role_arn    = module.gamelift_fleet_role.role_arn
  ec2_instance_type = var.gamelift_fleet_instance_type
  fleet_type        = var.gamelift_fleet_type
  inbound_from_port = var.gamelift_inbound_from_port
  inbound_to_port   = var.gamelift_inbound_to_port
  inbound_ip_range  = var.gamelift_inbound_ip_range

  concurrent_executions = var.gamelift_concurrent_executions
  alias_name            = var.gamelift_alias_name
  alias_description     = var.gamelift_alias_description
  queue_name            = var.gamelift_queue_name
  queue_timeout_seconds = var.gamelift_queue_timeout_seconds

  # gamelift_fleet_role because fleet_role_arn orders this after the role resource only, not after its
  # SendMessage grant (rules.md D-1/D-2). The wait for server.zip is source_bucket_name above, not an entry
  # here: a module-level depends_on would hold the build role's grant back with it.
  depends_on = [module.network, module.gamelift_fleet_role]
}
module "gamelift_matchmaking" {
  source = "./modules/gamelift_matchmaking"

  rule_set_name           = var.matchmaking_rule_set_name
  rule_set_body           = jsonencode(local.matchmaking_rule_set)
  configuration_name      = var.matchmaking_configuration_name
  request_timeout_seconds = var.matchmaking_request_timeout_seconds
  acceptance_required     = var.matchmaking_acceptance_required
  game_session_queue_arns = [module.gamelift_fleet.queue_arn]
  notification_topic_arn  = module.match_event_topic.arn

  # match_event_topic as a whole, not only the topic ARN the reference orders this after: the first event is
  # published as soon as the first ticket is, and it is lost unless the topic policy and the Lambda
  # subscription already exist.
  depends_on = [module.network, module.gamelift_fleet, module.match_event_topic]
}
# --- The bootstrap chain on the workbench -----------------------------------------------------------------------
#
# userdata -> artifacts_uploaded -> client_config -> vscode_readme. Each association waits for the previous
# stage's marker in an until loop, does its work and leaves its own marker (rules.md D-5): three until loops and
# three association markers. depends_on still orders the API calls that create them and reverses them on
# destroy; it is not what makes the remote commands run in order.
#
# client_config is the _monolithic template's ssm_association re-expressed. That one had no marker wait at all -
# only depends_on on the instance, which is satisfied while the clone it edits does not exist yet - and its
# commands were a single join("\n", [...]) string with literal \n escapes.
resource "aws_ssm_association" "client_config" {
  name                             = "AWS-RunShellScript"
  association_name                 = "${var.project_name}-client-config"
  wait_for_success_timeout_seconds = var.client_config_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The URL written into main.js and both clients is the stage's own invoke URL, not an ID spliced into a
    # template - the _monolithic template replaced the ID and the region in main.js and left /prod, so the page
    # only worked while the stage happened to be called prod.
    #
    # main.js is restored from git before the sed: this association runs again whenever its parameters change
    # (a new API ID, say), and by then the sample's placeholder is gone. The grep turns a placeholder that no
    # longer matches a newer checkout into a failed step instead of a page that silently calls the sample
    # author's API.
    #
    # The step runs under set -e and its status is checked before the marker, so a failed upload fails the
    # association rather than handing the README step a marker for work that did not happen.
    commands = <<-EOT
      set -u
      until [ -f ${module.vscode_ec2.marker_file_path}/artifacts_uploaded ]; do sleep ${var.marker_wait_interval_seconds}; done

      sudo -u ec2-user bash << 'TFSTEP'
      set -ex
      export HOME=/home/ec2-user
      cd ${local.repository_directory}

      git checkout -- web/main.js
      sed -i 's|https://niop6gw2v0.execute-api.us-east-1.amazonaws.com/prod|${module.gomoku_api.invoke_url}|g' web/main.js
      grep -q '${module.gomoku_api.invoke_url}/ranking' web/main.js
      aws s3 cp --quiet --region ${local.region} --recursive web/ s3://${module.leaderboard_website.bucket_name}/

      cd bin/FlexMatch
      cat > Client_player1/config.ini << 'TFCLIENT1'
      [config]
      MATCH_SERVER_API = ${module.gomoku_api.invoke_url}
      PLAYER_NAME = ${var.player1_name}
      PLAYER_PASSWD = ${var.player_password}
      TFCLIENT1
      cat > Client_player2/config.ini << 'TFCLIENT2'
      [config]
      MATCH_SERVER_API = ${module.gomoku_api.invoke_url}
      PLAYER_NAME = ${var.player2_name}
      PLAYER_PASSWD = ${var.player_password}
      TFCLIENT2
      rm -f /home/ec2-user/client.zip
      zip -qr /home/ec2-user/client.zip Client_player1/ Client_player2/
      aws s3 cp --quiet --region ${local.region} /home/ec2-user/client.zip s3://${module.game_source_bucket.bucket_name}/${var.client_archive_s3_key}
      TFSTEP
      status=$?
      if [ "$status" -ne 0 ]; then
        echo "Configuring the leaderboard page or the game clients failed; the trace above shows which command." >&2
        exit "$status"
      fi

      touch ${module.vscode_ec2.marker_file_path}/client_config
      EOT
  }
  depends_on = [
    aws_ssm_association.artifacts_uploaded,
    module.gomoku_api,
    module.leaderboard_website,
  ]
}
# --- The README on the workbench --------------------------------------------------------------------------------
locals {
  # Every output this root exposes, defined once. outputs.tf projects this map and the README association below
  # renders it, so no output can exist without also appearing in that README (rules.md H-2).
  #
  # The _monolithic template had three outputs - the code-server URL, the leaderboard URL and the client zip's
  # console page - which left the person in code-server without the API, the matchmaker, the fleet or any way
  # to tell whether the pieces in between were working.
  #
  # No secret is in here, and none is hidden: the player password is listed for what it is, a fixed demo value
  # written into a downloadable zip.
  outputs = {
    vs_code = {
      order       = 1
      title       = "VS Code URL"
      description = "code-server on the workbench. Every command below runs from its terminal"
      value       = module.vscode_ec2.vscode_url
    }
    gomoku_web = {
      order       = 2
      title       = "Gomoku leaderboard"
      description = "The S3 static website, calling the ranking API from the browser. Empty until games have been played"
      value       = module.leaderboard_website.website_url
    }
    client_zip_file_download = {
      order       = 3
      title       = "Game client download (console)"
      description = "client.zip holds two configured Windows clients, one per player. Run both on a Windows machine and press start in each - FlexMatch pairs the two"
      value       = "https://${local.region}.console.aws.amazon.com/s3/object/${module.game_source_bucket.bucket_name}?region=${local.region}&bucketType=general&prefix=${var.client_archive_s3_key}"
    }
    client_zip_presign_command = {
      order       = 4
      title       = "Game client download (link)"
      description = "A one-hour download link for the same zip, for a Windows machine that is not signed in to the console"
      value       = "aws s3 presign s3://${module.game_source_bucket.bucket_name}/${var.client_archive_s3_key} --region ${local.region} --expires-in 3600"
    }
    player_credentials = {
      order       = 5
      title       = "Player names and password in the clients"
      description = "What the two clients log in with. Not a secret and it protects nothing: game-match-request creates a player row with whatever password the first request for a name brings, compares it in plain text afterwards, and the API has no authorizer"
      value       = "${var.player1_name} / ${var.player2_name}, password ${var.player_password}"
    }
    api_invoke_url = {
      order       = 6
      title       = "Match and ranking API"
      description = "The stage both clients and the leaderboard page were configured with: POST /matchrequest, POST /matchstatus, GET /ranking"
      value       = module.gomoku_api.invoke_url
    }
    matchmaking_configuration_name = {
      order       = 7
      title       = "FlexMatch configuration"
      description = "The matchmaker game-match-request starts tickets against. Its rule set pairs two players whose scores are within 300, widening to 1000 over 30 seconds"
      value       = module.gamelift_matchmaking.configuration_name
    }
    fleet_id = {
      order       = 8
      title       = "GameLift fleet"
      description = "The Windows fleet game sessions are placed on, behind the alias and the queue below"
      value       = module.gamelift_fleet.fleet_id
    }
    fleet_status_command = {
      order       = 9
      title       = "Fleet status"
      description = "ACTIVE once the build has installed and its server processes have called ProcessReady. It says nothing about whether an instance is up now - a fleet whose instances have all been replaced stays ACTIVE. The capacity command below says that"
      value       = "aws gamelift describe-fleet-attributes --region ${local.region} --fleet-ids ${module.gamelift_fleet.fleet_id} --query 'FleetAttributes[0].Status' --output text"
    }
    # Added after the incident recorded on the fleet resource in modules/gamelift_fleet: the fleet stayed ACTIVE
    # while it had no instance to place on, so the status above cannot tell a placeable fleet from an empty one.
    fleet_capacity_command = {
      order       = 10
      title       = "Fleet capacity"
      description = "Matches are placed only while ACTIVE is at least 1. PENDING with ACTIVE 0 is an instance still booting - over ten minutes on Windows - and a match made meanwhile waits in the queue, up to its timeout"
      value       = "aws gamelift describe-fleet-capacity --region ${local.region} --fleet-ids ${module.gamelift_fleet.fleet_id} --query 'FleetCapacity[0].InstanceCounts' --output table"
    }
    fleet_events_command = {
      order       = 11
      title       = "Fleet events"
      description = "Where a fleet stuck in ACTIVATING or sent to ERROR says why - a server process that crashed or never called ProcessReady shows up here, and so does an instance GameLift replaced (INSTANCE_RECYCLED)"
      value       = "aws gamelift describe-fleet-events --region ${local.region} --fleet-id ${module.gamelift_fleet.fleet_id} --query 'Events[0:10].[EventTime,EventCode,Message]' --output table"
    }
    game_session_queue_name = {
      order       = 12
      title       = "Game session queue"
      description = "The queue the matchmaker places matches through, with the fleet's alias as its destination"
      value       = module.gamelift_fleet.queue_name
    }
    game_result_queue_url = {
      order       = 13
      title       = "Game result queue"
      description = "The game server sends each finished game here; game-sqs-process folds it into the player table, and the table's stream feeds the leaderboard"
      value       = module.game_result_queue.url
    }
    ranking_api_command = {
      order       = 14
      title       = "Leaderboard through the API"
      description = "The request the leaderboard page makes. [] before any game has finished; a 500 here with the function working means the integration, not the function"
      value       = "curl -s ${module.gomoku_api.invoke_url}/ranking"
    }
    rank_reader_invoke_command = {
      order       = 15
      title       = "Leaderboard from the function"
      description = "Invokes game-rank-reader directly, bypassing API Gateway. A timeout here is the function failing to reach Redis"
      value       = "aws lambda invoke --region ${local.region} --function-name ${module.game_rank_reader.function_name} /tmp/rank.json && cat /tmp/rank.json"
    }
    redis_ranking_command = {
      order       = 16
      title       = "Leaderboard in Redis"
      description = "The sorted set itself. Runs from this workbench, which the cache's security group admits on the Redis port; from elsewhere, a CloudShell VPC environment in this VPC with the GomokuDefault group works too"
      value       = "redis6-cli -h ${module.ranking_cache.address} -p ${module.ranking_cache.port} ZRANGE Rating 0 -1 WITHSCORES"
    }
  }
  # values() returns a map's values ordered by key, so re-keying by order makes the README read top to bottom.
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  readme_body = join("\n", concat(
    ["# ${var.project_name}", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  association_name                 = "${var.project_name}-readme"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # Last in the chain. SSM runs as root, hence the chown. The delimiter is quoted: Terraform has already
    # substituted every value, so the shell has no reason to touch the "$" and quotes in the commands.
    commands = <<-EOT
      set -u
      until [ -f ${module.vscode_ec2.marker_file_path}/client_config ]; do sleep ${var.marker_wait_interval_seconds}; done
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_readme
      EOT
  }
  depends_on = [aws_ssm_association.client_config]
}
# --- What plan cannot see ---------------------------------------------------------------------------------------
#
# In the root rather than in gamelift_matchmaking: a check holds its module open until the checks phase, after
# every managed resource - the README association included, which reads that module's outputs - so the first
# module to name gamelift_matchmaking in its depends_on would close a cycle (rules.md D-9).
#
# The topic policy admits a publisher by an ARN pattern built from the aws provider's region and the
# configuration name, while the configuration is created by the awscc provider. With aws_region null each
# provider resolves its own region, and if they differ the configuration publishes into a topic policy that
# does not name it: FlexMatch drops the event, game-match-event never runs and every client waits on
# matchstatus forever, with nothing failing anywhere.
check "matchmaking_configuration_matches_topic_policy" {
  assert {
    condition = (
      startswith(module.gamelift_matchmaking.configuration_arn, "arn:${local.partition}:gamelift:${local.region}:")
      && endswith(module.gamelift_matchmaking.configuration_arn, ":matchmakingconfiguration/${var.matchmaking_configuration_name}")
    )
    error_message = "The matchmaking configuration ${module.gamelift_matchmaking.configuration_arn} is not the one the SNS topic policy admits (${local.matchmaking_configuration_arn_pattern}). The awscc and aws providers resolved different regions - set aws_region explicitly so both use the same one."
  }
}
