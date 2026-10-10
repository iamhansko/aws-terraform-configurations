# Spirit of Kiro: a browser game whose client is a single-page app on CloudFront, whose server is a Fargate
# service behind an internet-facing ALB that only CloudFront and the VPC reach, and whose item images come from
# a second Fargate service behind an internal ALB, backed by MemoryDB and an S3 bucket on its own distribution.
# Players sign up in a Cognito user pool, through the server.
#
# The _monolithic template built the game in the workbench's user data and held the stack on a cfn-signal at
# the end of it (CreationPolicy), so the services were created after their images existed. Terraform has no
# signal; the build is an SSM association here, and the services pull images that are read back from ECR once
# a function has seen the build's tags there - see game_image_waiter below. Not once the association has
# succeeded: its Success arrives before the build has even been sent.
data "aws_region" "current" {}
# The CloudFront origin-facing prefix list, which admits CloudFront to the server's load balancer. This was a
# custom resource Lambda in the _monolithic template, there only because CloudFormation has no lookup by name;
# it never returned an ID under Terraform (providers.tf).
data "aws_ec2_managed_prefix_list" "cloudfront_origin_facing" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}
locals {
  region = data.aws_region.current.region
  # Read back out of the module it was passed into, so every step waits on the directory the bootstrap
  # actually writes to (rules.md B-5).
  marker   = module.vscode_ec2.marker_file_path
  repo_dir = "/home/ec2-user/spirit-of-kiro"
  # The two images, keyed by the same labels as their repositories, with the directory each is built from.
  # A literal map, so the ECR lookups below can for_each over it with keys known at plan (rules.md B-8).
  image_build_contexts = {
    server           = "server"
    image_generation = "item-images"
  }
}
module "network" {
  source = "./modules/network"
}
module "key_pair" {
  source = "./modules/key_pair"

  # Uses nothing from network and waits anyway, so the root has no exception to reason about (rules.md D-3).
  depends_on = [module.network]
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name                        = "vscode"
  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  code_server_version         = var.code_server_version
  security_group_name         = "vscode-sg"
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  marker_file_path            = var.marker_file_path
  # docker for the two image builds, and redis6 for inspecting MemoryDB from inside the VPC. git comes with
  # the module.
  #
  # docker with the group membership and a code-server restart rather than the chmod 666 on
  # /var/run/docker.sock the _monolithic template used, which handed the root-equivalent socket to every local
  # user (rules.md H-1 describes the same fix).
  #
  # The model list is the template's own last step, kept as it was. It lists the deploy region, a snapshot of
  # the day of the boot, and the game does not call Bedrock there - the bedrock_image_model_command output is
  # the check for item generation. Not changed here, since a user data change restarts the workbench.
  additional_user_data = <<-EOT
    dnf install -yq docker unzip redis6
    systemctl enable --now docker
    usermod -aG docker ec2-user
    systemctl restart code-server
    runuser -u ec2-user -- env HOME=/home/ec2-user aws configure set default.region ${local.region}
    runuser -u ec2-user -- env HOME=/home/ec2-user bash -c 'aws bedrock list-foundation-models --query "modelSummaries[*].modelId" --output text | tr "\t" "\n" > /home/ec2-user/bedrock_models.txt'
  EOT

  depends_on = [module.network, module.key_pair]
}
# --- Data ---------------------------------------------------------------------------------------------------
module "ecr" {
  source = "./modules/ecr_repositories"

  repositories = {
    server           = "${var.project_name}-server-repository"
    image_generation = "${var.project_name}-image-generation-repository"
  }

  depends_on = [module.network]
}
module "dynamodb_tables" {
  source = "./modules/dynamodb_tables"

  depends_on = [module.network]
}
module "user_pool" {
  source = "./modules/cognito_user_pool"

  name        = "${var.project_name}-user-pool"
  client_name = "${var.project_name}-user-pool-client"

  depends_on = [module.network]
}
module "image_distribution" {
  source = "./modules/s3_cloudfront_distribution"

  bucket_prefix              = "${var.project_name}-images-"
  origin_access_control_name = "ImageS3BucketOriginAccessControl"
  comment                    = "${var.project_name} item images"
  price_class                = "PriceClass_All"

  depends_on = [module.network]
}
module "memorydb" {
  source = "./modules/memorydb"

  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.private_subnet_ids
  # The whole VPC, as the _monolithic template had it - the workbench included, which is how the README's
  # ping reaches the cluster. The image service is admitted by the client group it carries.
  ingress_cidr_blocks = [module.network.vpc_cidr_block]
  node_type           = var.memorydb_node_type

  depends_on = [module.network]
}
# --- Services -----------------------------------------------------------------------------------------------
module "ecs_cluster" {
  source = "./modules/ecs_cluster"

  name = "${var.project_name}-ecs-cluster"

  depends_on = [module.network]
}
module "task_role" {
  source = "./modules/ecs_task_role"

  name_prefix         = "${var.project_name}-task-"
  dynamodb_table_arns = values(module.dynamodb_tables.table_arns)
  user_pool_arn       = module.user_pool.user_pool_arn
  image_bucket_arn    = module.image_distribution.bucket_arn

  depends_on = [module.network]
}
# Holds the apply until both of the build's tags are in ECR.
#
# The lookups below used to wait on game_build through depends_on, trusting wait_for_success_timeout_seconds to
# hold the association until the build had pushed. It cannot, in either of the two cases that matter:
#
#   - First apply. The association is created seconds after the workbench launches, before its SSM agent has
#     registered, and an association with no registered target reports Success at once. The provider's waiter
#     accepts it and returns. 073_cognito_identity_pool hit exactly this - its CloudTrail timeline has the
#     waiter returning 4 seconds after the association was created and the build being sent 10 seconds after
#     that - and it is reproducible against an instance ID that does not exist.
#   - A new spirit_of_kiro_ref. The association's commands change, it is updated in place, and the provider
#     does not wait on an update at all. The lookup of the new tag would run while the build was still cloning.
#
# Either way the lookup fails with the image not found, and the apply stops before the services.
#
# So the wait is a function that asks ECR for each tag until every one is there, and stops early only when the
# association's current run has failed - never on its Success. Its input carries the tag, so a new commit
# replaces it and the lookups wait again. It reaches network through depends_on, which is what D-3 asks for;
# the association and the repositories arrive through the values below.
module "game_image_waiter" {
  source = "./modules/ecr_image_waiter"

  function_name = "${var.project_name}-game-image-waiter"
  images = {
    for key in keys(local.image_build_contexts) : key => {
      repository_name = module.ecr.repository_names[key]
      repository_arn  = module.ecr.repository_arns[key]
      image_tag       = var.spirit_of_kiro_ref
    }
  }
  association_id  = aws_ssm_association.game_build.association_id
  association_arn = aws_ssm_association.game_build.arn
  # The same number as the association's own wait, so "how long the build may take" stays one value, capped at
  # the 900 seconds a Lambda function can run (game_build_timeout_seconds says what a slower build means).
  timeout_seconds = min(var.game_build_timeout_seconds, 900)

  depends_on = [module.network]
}
# The images the services run, read back from ECR after the build step has pushed them. This is what holds the
# services until the build is done: the task definitions take these URIs, so they cannot be registered before
# the lookup, and the lookup is named through the waiter's result, so it cannot run before the waiter has seen
# the tags - while the waiter is being invoked its result is unknown and the lookup is deferred to apply. No
# depends_on, which would defer the lookup on every change to the waiter's module (rules.md D-6).
#
# A depends_on on the service modules would say the same thing and close a cycle - the build uploads the
# client and invalidates its distribution, the distribution's websocket origin is the server's load balancer,
# and that load balancer is in the server's module. Ordering by these values holds back the task definitions
# only.
#
# The URI is by digest, so a service runs exactly what the build pushed, and a tag pushed over by hand shows
# up in the next plan as a new task definition rather than in the next task that happens to start - the
# lookup runs at plan whenever the waiter is unchanged, which is also why the digest is not simply taken from
# the waiter's result, fixed at its invoke.
data "aws_ecr_image" "game" {
  for_each = local.image_build_contexts

  repository_name = module.game_image_waiter.repository_names[each.key]
  image_tag       = module.game_image_waiter.image_tags[each.key]
}
locals {
  images = { for key, image in data.aws_ecr_image.game : key => "${module.ecr.repository_urls[key]}@${image.image_digest}" }
}
module "image_generation_service" {
  source = "./modules/ecs_alb_service"

  name   = "${var.project_name}-image-generation"
  region = local.region
  vpc_id = module.network.vpc_id
  # Internal, in the private subnets, admitting the VPC only - the server is its one caller. The _monolithic
  # template also admitted the CloudFront prefix list, which cannot reach an internal load balancer.
  vpc_cidr_block           = module.network.vpc_cidr_block
  internal                 = true
  load_balancer_subnet_ids = module.network.private_subnet_ids
  task_subnet_ids          = module.network.private_subnet_ids
  ingress_cidr_blocks      = [module.network.vpc_cidr_block]

  cluster_name   = module.ecs_cluster.cluster_name
  task_family    = "item-images-taskdef"
  task_cpu       = var.task_cpu
  task_memory    = var.task_memory
  task_role_arn  = module.task_role.role_arn
  repository_arn = module.ecr.repository_arns["image_generation"]
  image          = local.images["image_generation"]
  container_port = var.image_generation_container_port
  environment = {
    ENVIRONMENT       = var.environment
    S3_BUCKET_NAME    = module.image_distribution.bucket_name
    CLOUDFRONT_DOMAIN = module.image_distribution.domain_name
    REDIS_HOST        = module.memorydb.endpoint_address
    # Read by the game from the commit pinned in spirit_of_kiro_ref onwards; before it, the model and region
    # were hardcoded to Nova Canvas in us-east-1, which reached end of life.
    BEDROCK_IMAGE_MODEL_ID = var.bedrock_image_model_id
    BEDROCK_IMAGE_REGION   = var.bedrock_image_region
  }
  # The group MemoryDB admits, carried by the tasks rather than the cluster naming this module's group, which
  # would have each module wait on the other.
  extra_security_group_ids = [module.memorydb.client_security_group_id]
  log_group_name           = "/ecs/${module.ecs_cluster.cluster_name}/item-images"
  desired_count            = var.service_desired_count

  # The task role's policy is not ordered before the tasks by the role ARN, and the cluster's capacity
  # providers are not ordered by its name (rules.md D-1/D-2).
  depends_on = [module.network, module.ecs_cluster, module.task_role]
}
module "server_service" {
  source = "./modules/ecs_alb_service"

  name   = "${var.project_name}-server"
  region = local.region
  vpc_id = module.network.vpc_id
  # Internet-facing, but admitting CloudFront and the VPC only. Players reach it through the client's
  # distribution, under /ws*.
  vpc_cidr_block           = module.network.vpc_cidr_block
  internal                 = false
  load_balancer_subnet_ids = module.network.public_subnet_ids
  task_subnet_ids          = module.network.private_subnet_ids
  ingress_cidr_blocks      = [module.network.vpc_cidr_block]
  ingress_prefix_list_ids  = [data.aws_ec2_managed_prefix_list.cloudfront_origin_facing.id]

  cluster_name   = module.ecs_cluster.cluster_name
  task_family    = "server-taskdef"
  task_cpu       = var.task_cpu
  task_memory    = var.task_memory
  task_role_arn  = module.task_role.role_arn
  repository_arn = module.ecr.repository_arns["server"]
  image          = local.images["server"]
  container_port = var.server_container_port
  # The table names come from the tables module with their variable names, so the two cannot drift apart
  # (rules.md B-5).
  environment = merge(module.dynamodb_tables.environment, {
    ENVIRONMENT             = var.environment
    COGNITO_USER_POOL_ID    = module.user_pool.user_pool_id
    COGNITO_CLIENT_ID       = module.user_pool.client_id
    ITEM_IMAGES_SERVICE_URL = module.image_generation_service.url
  })
  log_group_name = "/ecs/${module.ecs_cluster.cluster_name}/server"
  desired_count  = var.service_desired_count

  depends_on = [module.network, module.ecs_cluster, module.task_role]
}
module "client_distribution" {
  source = "./modules/s3_cloudfront_distribution"

  bucket_prefix              = "${var.project_name}-client-"
  origin_access_control_name = "ClientS3BucketOriginAccessControl"
  comment                    = "${var.project_name} game client"
  price_class                = "PriceClass_100"
  default_root_object        = "index.html"
  spa_fallback               = true
  default_allowed_methods    = ["GET", "HEAD", "OPTIONS"]
  websocket_origin = {
    domain_name  = module.server_service.load_balancer_dns_name
    path_pattern = "/ws*"
    forwarded_headers = [
      "Origin",
      "Access-Control-Request-Headers",
      "Access-Control-Request-Method",
      "Sec-WebSocket-Key",
      "Sec-WebSocket-Version",
      "Sec-WebSocket-Protocol",
      "Sec-WebSocket-Accept",
      "Sec-WebSocket-Extensions",
    ]
  }

  depends_on = [module.network]
}
# --- Build --------------------------------------------------------------------------------------------------
#
# What the _monolithic template's user data did after code-server: clone the game, build the client with bun
# and upload it, and build and push both service images. It runs on the workbench because those are builds -
# bun and docker - which Terraform cannot run, and as an association rather than user data so it can re-run:
# parameters change with the commit, and a new commit rebuilds everything and rolls both services.
#
# Two differences from the template. It builds a pinned commit and tags the images with it, where the template
# took whatever the default branch held and pushed latest. And it no longer runs
# "aws iam create-service-linked-role" for ECS, which ECS creates itself the first time a cluster is made.
resource "aws_ssm_association" "game_build" {
  name                             = "AWS-RunShellScript"
  association_name                 = "${var.project_name}-game-build"
  wait_for_success_timeout_seconds = var.game_build_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    commands = <<-EOT
      set -euo pipefail
      until [ -f ${local.marker}/userdata ]; do sleep 10; done
      # The checkout and the client build as ec2-user, so the tree in code-server is the user's. git refuses a
      # repository owned by another user, so a root clone would also break every later run of this step.
      su - ec2-user << 'STEP'
      set -euo pipefail
      if [ ! -d ${local.repo_dir}/.git ]; then
        git clone --quiet ${var.spirit_of_kiro_repository_url} ${local.repo_dir}
      fi
      git -C ${local.repo_dir} fetch --quiet origin
      git -C ${local.repo_dir} checkout --quiet --force ${var.spirit_of_kiro_ref}
      if [ "$($HOME/.bun/bin/bun --version 2>/dev/null || true)" != "${var.bun_version}" ]; then
        curl -fsSL https://bun.sh/install | bash -s "bun-v${var.bun_version}"
      fi
      export PATH=$HOME/.bun/bin:$PATH
      cd ${local.repo_dir}/client
      # As the template did: the client's type check needs a declaration for .vue imports, which the repository
      # does not carry.
      echo "declare module '*.vue'" > ./src/shims-vue.d.ts
      bun install
      bun run build
      STEP
      # sync without --delete: a browser still holding the previous index.html asks for the previous hashed
      # assets, and they should still be there. The invalidation is for a re-run, when the edge holds the
      # previous index.html for up to a day.
      aws s3 sync ${local.repo_dir}/client/dist/ s3://${module.client_distribution.bucket_name} --region ${local.region} --only-show-errors
      aws s3api head-object --bucket ${module.client_distribution.bucket_name} --key index.html --region ${local.region} > /dev/null
      aws cloudfront create-invalidation --distribution-id ${module.client_distribution.distribution_id} --paths '/*' > /dev/null
      aws ecr get-login-password --region ${local.region} | docker login --username AWS --password-stdin ${module.ecr.registry}
      docker build --quiet --tag ${module.ecr.repository_urls["server"]}:${var.spirit_of_kiro_ref} ${local.repo_dir}/${local.image_build_contexts["server"]}
      docker push ${module.ecr.repository_urls["server"]}:${var.spirit_of_kiro_ref}
      docker build --quiet --tag ${module.ecr.repository_urls["image_generation"]}:${var.spirit_of_kiro_ref} ${local.repo_dir}/${local.image_build_contexts["image_generation"]}
      docker push ${module.ecr.repository_urls["image_generation"]}:${var.spirit_of_kiro_ref}
      touch ${local.marker}/game_build
      EOT
  }
  depends_on = [module.vscode_ec2]
}
# --- README on the workbench ------------------------------------------------------------------------------
locals {
  # Every output this root exposes, defined once. outputs.tf projects this map and the README on the
  # workbench renders it, so an output cannot exist without also appearing in that README (rules.md H-2).
  outputs = {
    vscode_url = {
      order       = 1
      title       = "VS Code URL"
      description = "The workbench. The game's source, at the commit that was built, is in ~/spirit-of-kiro"
      value       = module.vscode_ec2.vscode_url
    }
    game_client_url = {
      order       = 2
      title       = "Game client"
      description = "The _monolithic template's GameClient output. Sign up, then play - the server reaches the browser through this distribution under /ws*"
      value       = module.client_distribution.url
    }
    game_build_command = {
      order       = 3
      title       = "1. The build step"
      description = "How the clone, the client build and both image builds went. When it failed, aws ssm describe-association-execution-targets with the execution ID shown here gives the command ID, and aws ssm get-command-invocation on that command ID shows the script output"
      value       = "aws ssm describe-association-executions --association-id ${aws_ssm_association.game_build.association_id} --query 'AssociationExecutions[0].[ExecutionId,Status,DetailedStatus,CreatedTime]' --output table"
    }
    server_service_events_command = {
      order       = 4
      title       = "2. The game server service"
      description = "The service's own account of its tasks. A task that cannot pull, start or pass the health check is reported here first"
      value       = module.server_service.service_events_command
    }
    server_target_health_command = {
      order       = 5
      title       = "3. Whether the server's load balancer reaches its tasks"
      description = "healthy for both tasks once the service is steady"
      value       = module.server_service.target_health_command
    }
    server_log_command = {
      order       = 6
      title       = "4. The game server's log"
      description = "Sign-ups, websocket connections and the calls the server makes to Bedrock and the item image service"
      value       = module.server_service.log_tail_command
    }
    image_generation_service_events_command = {
      order       = 7
      title       = "5. The item image service"
      description = "Its load balancer is internal; the server is its only caller"
      value       = module.image_generation_service.service_events_command
    }
    image_generation_log_command = {
      order       = 8
      title       = "6. The item image service's log"
      description = "Image generation requests and their Bedrock calls"
      value       = module.image_generation_service.log_tail_command
    }
    list_users_command = {
      order       = 9
      title       = "7. Players who have signed up"
      description = "The user pool, read directly. The server confirms each sign-up itself, so a player stuck in UNCONFIRMED means the server failed partway"
      value       = module.user_pool.list_users_command
    }
    memorydb_ping_command = {
      order       = 10
      title       = "8. MemoryDB"
      description = "The item image service's store. PONG means the cluster answers on the address the service was given"
      value       = module.memorydb.ping_command
    }
    bedrock_image_model_command = {
      order       = 11
      title       = "9. The item image model"
      description = "Whether the model the item image service invokes is still ACTIVE, in the region it invokes it in. A model past end of life answers ResourceNotFoundException here and in the service's log, and items are then stored without an image. ~/bedrock_models.txt is the deploy region's list at boot, as the _monolithic template wrote it, which is not where the services call Bedrock"
      value       = "aws bedrock get-foundation-model --region ${var.bedrock_image_region} --model-identifier ${var.bedrock_image_model_id} --query 'modelDetails.[modelId,modelLifecycle.status]' --output text"
    }
    client_invalidate_command = {
      order       = 12
      title       = "After uploading the client by hand"
      description = "The edge keeps index.html for up to a day. The build step invalidates on its own; this is for a build run outside it"
      value       = module.client_distribution.invalidate_command
    }
    private_key_command = {
      order       = 13
      title       = "Workbench SSH key"
      description = "Retrieves the generated private key from Parameter Store. No security group opens port 22; this is for the case where the SSM agent is what is broken"
      value       = module.key_pair.private_key_command
    }
  }
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  readme_body = join("\n", concat(
    ["# Spirit of Kiro", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # Waits for the build step, the last thing the README describes (rules.md D-5).
    commands = <<-EOT
      until [ -f ${local.marker}/game_build ]; do sleep 10; done
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${local.marker}/vscode_readme
      EOT
  }
  depends_on = [aws_ssm_association.game_build]
}
