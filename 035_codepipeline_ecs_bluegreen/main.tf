data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
# Both AMI lookups are here rather than inside the modules that use them.
#
# insecure_value rather than value: the provider marks every parameter's value sensitive whatever its
# type, and a sensitive value cannot be used for an instance's ami or a launch template's image_id
# without nonsensitive(). insecure_value is the provider's own accessor for a parameter that is not a
# secret, and a public AMI id is not one.
#
# Reading them in the root also keeps them out of modules that carry depends_on, which would defer them
# to apply (rules.md D-6). Neither result reaches a for_each or a resource name, so deferring them would
# be harmless here - but the D-6 question is about where a data source lives, and the root is the answer
# that does not have to be re-examined when a module grows a for_each. No module in this project
# declares a data source at all; region, account and partition arrive as variables for the same reason.
data "aws_ssm_parameter" "bastion_ami_id" {
  name = var.bastion_ami_ssm_parameter_name
}
data "aws_ssm_parameter" "container_instance_ami_id" {
  name = var.container_instance_ami_ssm_parameter_name
}
locals {
  region     = data.aws_region.current.region
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  # The ECS cluster name, defined here rather than taken from the cluster module's output, because the
  # container instance launch template writes it into /etc/ecs/ecs.config and the cluster module creates
  # it - and the service, the capacity provider association and the CodeDeploy deployment group all name
  # it too. One value, four readers (rules.md B-5).
  cluster_name = "${var.project_name}-cluster"

  # The task definition family, which two things register revisions into: this apply registers the
  # first, and every CodeBuild run registers another. Shared rather than restated so a deployment always
  # moves the service forward inside one family.
  task_family = "${var.project_name}-td"

  # The log group both of those revisions write to. The _monolithic template had Terraform create the
  # group and then named it as a literal string inside the buildspec, so renaming the group would have
  # left the pipeline's revisions pointing at one that does not exist.
  log_group_name = "/ecs/${local.task_family}"
}
module "network" {
  source = "./modules/network"

  region                     = local.region
  availability_zone_suffixes = var.availability_zone_suffixes
  vpc_cidr_block             = var.vpc_cidr_block
  subnet_newbits             = var.subnet_newbits

  vpc_name                 = "${var.project_name}-vpc"
  internet_gateway_name    = "${var.project_name}-igw"
  nat_gateway_name         = "${var.project_name}-natgw"
  public_subnet_name       = "${var.project_name}-pub"
  private_subnet_name      = "${var.project_name}-priv"
  public_route_table_name  = "${var.project_name}-pub-rt"
  private_route_table_name = "${var.project_name}-priv-rt"
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name_prefix = "${var.project_name}-key-"
  rsa_bits        = var.key_rsa_bits

  # This module uses nothing from network and does not need a VPC to create a key pair. It waits anyway,
  # because the rule is that a root with a network module has no module starting before that module
  # finishes - an exception here would mean the next reader has to decide per module whether the
  # omission was reasoned or forgotten (rules.md D-3).
  depends_on = [module.network]
}
module "ecr_repository" {
  source = "./modules/ecr_repository"

  name           = "${var.project_name}-ecr"
  seed_image_tag = var.seed_image_tag
  force_delete   = var.ecr_force_delete
  scan_on_push   = var.ecr_scan_on_push

  # Also uses nothing from network, and also waits, for the reason above (rules.md D-3).
  depends_on = [module.network]
}
module "code_pipeline_source_bucket" {
  source = "./modules/code_pipeline_source_bucket"

  bucket_prefix = "${var.project_name}-pipeline-source-"
  object_key    = var.source_object_key
  force_destroy = var.bucket_force_destroy

  depends_on = [module.network]
}
module "code_pipeline_artifact_bucket" {
  source = "./modules/code_pipeline_artifact_bucket"

  bucket_prefix = "${var.project_name}-pipeline-artifact-"
  force_destroy = var.bucket_force_destroy

  depends_on = [module.network]
}
module "ecs_cluster" {
  source = "./modules/ecs_cluster"

  name                    = local.cluster_name
  container_insights      = var.container_insights
  execute_command_logging = var.execute_command_logging

  depends_on = [module.network]
}
# The load balancer, both target groups and the listener, which CodeDeploy treats as one unit - see the
# module for why they are not split up.
module "application_load_balancer" {
  source = "./modules/application_load_balancer"

  name = "${var.project_name}-alb"
  # Public subnets, which is what an internet-facing scheme requires and what the demo URL needs.
  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.public_subnet_ids
  internal   = var.load_balancer_internal

  listener_port       = var.listener_port
  idle_timeout        = var.load_balancer_idle_timeout
  ingress_cidr_blocks = var.load_balancer_ingress_cidr_blocks

  security_group_name = "${var.project_name}-alb-sg"

  blue_target_group_name  = "${var.project_name}-tg1"
  green_target_group_name = "${var.project_name}-tg2"
  # The container port, not a separate target port: with awsvpc the load balancer connects to the
  # task's own interface on the port the container listens on, so the two cannot differ (rules.md B-5).
  target_port       = var.container_port
  health_check_path = var.health_check_path

  health_check_interval            = var.target_group_health_check_interval
  health_check_timeout             = var.target_group_health_check_timeout
  health_check_healthy_threshold   = var.target_group_health_check_healthy_threshold
  health_check_unhealthy_threshold = var.target_group_health_check_unhealthy_threshold
  health_check_matcher             = var.target_group_health_check_matcher

  create_user_agent_rule   = var.create_user_agent_rule
  user_agent_rule_priority = var.user_agent_rule_priority
  user_agent_rule_values   = var.user_agent_rule_values

  depends_on = [module.network]
}
# The builder. This is the only thing in this root that produces the image the service pulls and the
# archive the pipeline reads, and it is not a workbench - see the module and the note in outputs.tf.
module "bastion_ec2" {
  source = "./modules/bastion_ec2"

  region   = local.region
  vpc_id   = module.network.vpc_id
  ami_id   = data.aws_ssm_parameter.bastion_ami_id.insecure_value
  key_name = module.key_pair.key_name
  # The first public subnet: everything the userdata does is outbound.
  subnet_id                   = module.network.public_subnet_a_id
  associate_public_ip_address = var.bastion_associate_public_ip_address

  instance_name    = "${var.project_name}-bastion"
  instance_type    = var.bastion_instance_type
  root_volume_size = var.bastion_root_volume_size

  security_group_name     = "${var.project_name}-bastion-sg"
  ssh_ingress_cidr_blocks = var.bastion_ssh_ingress_cidr_blocks

  role_name_prefix             = "${var.project_name}-bastion-"
  instance_profile_name_prefix = "${var.project_name}-bastion-"

  # Both the name and the ARN of each target, because the userdata needs the name and the inline policy
  # needs the ARN, and reassembling one from the other is how a policy comes to point somewhere else
  # (rules.md A-5).
  source_bucket_name = module.code_pipeline_source_bucket.bucket_name
  source_bucket_arn  = module.code_pipeline_source_bucket.bucket_arn
  source_object_key  = module.code_pipeline_source_bucket.object_key
  ecr_repository_arn = module.ecr_repository.arn
  ecr_registry_url   = module.ecr_repository.registry_url
  ecr_image_uri      = module.ecr_repository.seed_image_uri

  go_base_image        = var.go_base_image
  container_port       = var.container_port
  health_check_path    = var.health_check_path
  health_response_body = var.health_response_body
  dummy_path           = var.dummy_path
  dummy_response_body  = var.dummy_response_body
  # The completion marker the association below polls for (rules.md B-4).
  marker_file_path = var.marker_file_path

  # network for the uniform reason, and here it is load bearing rather than only uniform: subnet_id
  # orders this after that one subnet, and the route to the internet gateway is exactly the sort of
  # resource that ordering misses. cloud-init runs dnf within seconds of the launch, so losing that
  # race means no docker and no image at all (rules.md D-3).
  depends_on = [
    module.network,
    module.key_pair,
    module.ecr_repository,
    module.code_pipeline_source_bucket,
  ]
}
# What the CloudFormation CreationPolicy used to do.
#
# The template held the stack at this instance until cfn-signal reported from inside its userdata, which
# is how the task definition and the service came to be created only after an image existed. The
# conversion dropped it - its own comment says the CreationPolicy is not reproduced - and left the task
# definition with depends_on on the instance, which in Terraform is satisfied as soon as RunInstances
# returns. That is minutes before docker is even installed.
#
# Without something here the service starts immediately and its tasks stop with CannotPullContainerError
# against an image that does not exist yet. ECS keeps replacing them, so it does eventually recover on
# its own once the push lands - which is worse than failing, because the demo looks broken for ten
# minutes and then silently is not.
#
# So: wait for the marker, then ask ECR and S3 directly. Three phases rather than one because they fail
# for different reasons and the message should say which (rules.md D-5 for the marker-and-loop shape,
# which this repository uses instead of trusting depends_on or a provider timeout to mean that a remote
# command has finished).
#
# The two checks after the marker are the part that matters even though the builder script runs with
# errexit. The marker means every command returned zero; it does not mean the push produced an image or
# that the archive is readable, and those are the two facts everything downstream depends on.
resource "aws_ssm_association" "image_pushed" {
  name                             = "AWS-RunShellScript"
  association_name                 = "${var.project_name}-image-pushed"
  wait_for_success_timeout_seconds = var.image_wait_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.bastion_ec2.instance_id]
  }
  parameters = {
    commands = <<-EOT
      set -u

      MARKER=${module.bastion_ec2.marker_file}

      # Phase one: the marker. An until loop rather than "[ -f ... ] && break" inside a for, because a
      # bare test that fails is a non-zero statement at top level - and if the shell SSM runs this with
      # has -e set, that ends the script on the first pass with no output. A failing until condition
      # never triggers -e, which is why rules.md D-5's shape is an until loop and not a test.
      waited=0
      until [ -f "$MARKER" ]; do
        waited=$((waited + 1))
        if [ "$waited" -gt ${var.image_wait_attempts} ]; then
          echo "builder userdata never reached its end: $MARKER is still absent. The script runs with errexit, so one of its steps failed - read /var/log/cloud-init-output.log on this instance for which one." >&2
          exit 1
        fi
        sleep ${var.image_wait_interval_seconds}
      done

      # Phase two: the repository. A command that fails as an if condition is also exempt from -e.
      pushed=0
      for attempt in $(seq 1 ${var.image_wait_attempts}); do
        if aws ecr describe-images --region ${local.region} --repository-name ${module.ecr_repository.name} --image-ids imageTag=${module.ecr_repository.seed_image_tag} > /dev/null 2>&1; then
          pushed=1
          break
        fi
        sleep ${var.image_wait_interval_seconds}
      done
      if [ "$pushed" -ne 1 ]; then
        echo "${module.ecr_repository.seed_image_uri} is not in the repository although the builder script finished. Without it every task this service starts stops with CannotPullContainerError; /var/log/cloud-init-output.log on this instance has the reason." >&2
        exit 1
      fi

      # Phase three: the archive. Checked separately from the image because the two fail apart - the
      # upload happens before the push, so an archive with no image means the build failed, and an image
      # with no archive means the S3 permissions did.
      for attempt in $(seq 1 ${var.image_wait_attempts}); do
        if aws s3api head-object --region ${local.region} --bucket ${module.code_pipeline_source_bucket.bucket_name} --key ${module.code_pipeline_source_bucket.object_key} > /dev/null 2>&1; then
          exit 0
        fi
        sleep ${var.image_wait_interval_seconds}
      done

      echo "s3://${module.code_pipeline_source_bucket.bucket_name}/${module.code_pipeline_source_bucket.object_key} is absent although the builder script finished. The pipeline's source stage has nothing to read, and because no write happened there is also no CloudTrail event for the EventBridge rule to act on." >&2
      exit 1
      EOT
  }
}
module "ecs_asg_capacity_provider" {
  source = "./modules/ecs_asg_capacity_provider"

  vpc_id = module.network.vpc_id
  # Private subnets, so outbound goes through the zonal NAT gateways. The ECS agent cannot register an
  # instance it cannot reach the ECS endpoint from, and an instance that never registers is absent
  # rather than broken - see the module for what that looks like.
  subnet_ids   = module.network.private_subnet_ids
  cluster_name = module.ecs_cluster.cluster_name
  ami_id       = data.aws_ssm_parameter.container_instance_ami_id.insecure_value
  key_name     = module.key_pair.key_name

  capacity_provider_name       = "${var.project_name}-capacity-provider"
  instance_name                = "${var.project_name}-container-instance"
  instance_name_prefix         = "${var.project_name}-ci-"
  role_name_prefix             = "${var.project_name}-ci-"
  instance_profile_name_prefix = "${var.project_name}-ci-"
  security_group_name          = "${var.project_name}-asg-sg"

  instance_types                           = var.container_instance_types
  min_size                                 = var.container_instance_min_size
  max_size                                 = var.container_instance_max_size
  desired_capacity                         = var.container_instance_desired_capacity
  default_cooldown                         = var.container_instance_default_cooldown
  on_demand_base_capacity                  = var.container_instance_on_demand_base_capacity
  on_demand_percentage_above_base_capacity = var.container_instance_on_demand_percentage
  managed_scaling_target_capacity          = var.managed_scaling_target_capacity
  managed_scaling_instance_warmup_period   = var.managed_scaling_instance_warmup_period

  # Keyed by a label, because the value is another module's output and unknown at plan time
  # (rules.md B-8). This is the one inline rule the _monolithic template gave this group.
  ssh_ingress_source_security_groups = {
    bastion = module.bastion_ec2.security_group_id
  }

  # The cluster has to exist before an instance tries to join it, and before the association in this
  # module can attach a capacity provider to it. The cluster name arrives as a variable and is
  # interpolated into the launch template userdata, so that part is already ordered; module-level
  # depends_on is what covers the rest of the cluster module (rules.md D-2, D-3).
  depends_on = [module.network, module.ecs_cluster, module.key_pair, module.bastion_ec2]
}
module "ecs_service" {
  source = "./modules/ecs_service"

  region       = local.region
  vpc_id       = module.network.vpc_id
  subnet_ids   = module.network.private_subnet_ids
  cluster_name = module.ecs_cluster.cluster_name

  service_name   = "${var.project_name}-svc"
  task_family    = local.task_family
  container_name = var.container_name
  container_port = var.container_port
  # The seed tag. Every revision after this one is registered by CodeBuild under a timestamped tag and
  # is not a Terraform resource at all (rules.md B-5).
  image_uri         = module.ecr_repository.seed_image_uri
  health_check_path = var.health_check_path

  task_cpu      = var.task_cpu
  task_memory   = var.task_memory
  desired_count = var.service_desired_count

  capacity_provider_name = module.ecs_asg_capacity_provider.capacity_provider_name
  blue_target_group_arn  = module.application_load_balancer.blue_target_group_arn

  log_group_name        = local.log_group_name
  log_retention_in_days = var.log_retention_in_days

  execution_role_name_prefix = "${var.project_name}-task-exec-"
  security_group_name        = "${var.project_name}-ecs-sg"
  # The load balancer's group as the allowed source, keyed by a label because the ID is another
  # module's output and unknown at plan time (rules.md B-8).
  ingress_source_security_groups = {
    alb = module.application_load_balancer.security_group_id
  }
  additional_ingress_ports = var.task_additional_ingress_ports

  # Four things have to be true before this service can place a task, and only two are implied by a
  # value reference.
  #
  #   - the capacity provider has to be attached to the cluster, which is the association inside
  #     ecs_asg_capacity_provider, and container instances have to have registered.
  #     capacity_provider_name orders this after the provider resource alone, not after either of those
  #     (rules.md D-2)
  #   - the listener has to exist, because a service with a load balancer configuration is accepted
  #     before the listener routes to it. blue_target_group_arn orders this after the target group and
  #     not after the listener or the group's own rules (rules.md D-1)
  #   - the image has to be in the repository, which is what the association above establishes. This is
  #     the edge the CloudFormation CreationPolicy used to provide
  #   - network, for the uniform reason and because the private route to a NAT gateway is what lets a
  #     task pull at all (rules.md D-3)
  #
  # The order also matters in reverse. On destroy this module goes before the capacity provider, which
  # is what lets ECS delete it - ECS refuses while a service's strategy still names it.
  depends_on = [
    module.network,
    module.ecs_asg_capacity_provider,
    module.application_load_balancer,
    aws_ssm_association.image_pushed,
  ]
}
module "code_deploy" {
  source = "./modules/code_deploy"

  application_name      = "${var.project_name}-app"
  deployment_group_name = "${var.project_name}-dg"
  role_name_prefix      = "${var.project_name}-cd-"

  cluster_name = module.ecs_cluster.cluster_name
  service_name = module.ecs_service.service_name
  # One listener, whose default rule is the field a deployment rewrites.
  listener_arns           = [module.application_load_balancer.listener_arn]
  blue_target_group_name  = module.application_load_balancer.blue_target_group_name
  green_target_group_name = module.application_load_balancer.green_target_group_name

  deployment_config_name             = var.deployment_config_name
  deployment_ready_action_on_timeout = var.deployment_ready_action_on_timeout
  termination_wait_time_in_minutes   = var.termination_wait_time_in_minutes
  auto_rollback_events               = var.auto_rollback_events

  artifact_bucket_arn     = module.code_pipeline_artifact_bucket.bucket_arn
  task_execution_role_arn = module.ecs_service.execution_role_arn

  # CodeDeploy validates at CreateDeploymentGroup that the service exists and that its deployment
  # controller is CODE_DEPLOY, so the service has to be finished rather than merely started - and the
  # listener has to exist because load_balancer_info names it (rules.md D-2).
  depends_on = [module.ecs_service, module.application_load_balancer]
}
module "code_build_project" {
  source = "./modules/code_build_project"

  name             = "${var.project_name}-build"
  region           = local.region
  account_id       = local.account_id
  partition        = local.partition
  role_name_prefix = "${var.project_name}-cb-"

  ecr_repository_name = module.ecr_repository.name
  ecr_repository_arn  = module.ecr_repository.arn
  artifact_bucket_arn = module.code_pipeline_artifact_bucket.bucket_arn
  # The name, not the ARN - see the module and the buildspec for what the _monolithic template's ARN
  # did to the appspec.
  capacity_provider_name = module.ecs_asg_capacity_provider.capacity_provider_name

  task_execution_role_arn = module.ecs_service.execution_role_arn
  task_family             = module.ecs_service.task_definition_family
  container_name          = module.ecs_service.container_name
  container_port          = module.ecs_service.container_port
  log_group_name          = module.ecs_service.log_group_name
  health_check_path       = var.health_check_path
  task_cpu                = var.task_cpu
  task_memory             = var.task_memory

  go_base_image     = var.go_base_image
  timezone          = var.build_timezone
  compute_type      = var.build_compute_type
  environment_image = var.build_environment_image
  build_timeout     = var.build_timeout

  # The task family, the container name and the log group all come from the service module, so the
  # revision this build registers lands in the same family and logs to the same group as the one this
  # apply registered (rules.md B-5). That is also the ordering edge; the rest is uniform (rules.md D-3).
  depends_on = [
    module.network,
    module.ecr_repository,
    module.ecs_service,
    module.ecs_asg_capacity_provider,
    module.code_pipeline_artifact_bucket,
  ]
}
module "code_pipeline" {
  source = "./modules/code_pipeline"

  name             = "${var.project_name}-pipeline"
  region           = local.region
  account_id       = local.account_id
  partition        = local.partition
  pipeline_type    = var.pipeline_type
  role_name_prefix = "${var.project_name}-cp-"
  allow_self_start = var.pipeline_allow_self_start

  source_bucket_name = module.code_pipeline_source_bucket.bucket_name
  source_bucket_arn  = module.code_pipeline_source_bucket.bucket_arn
  source_object_key  = module.code_pipeline_source_bucket.object_key

  artifact_bucket_name = module.code_pipeline_artifact_bucket.bucket_name
  artifact_bucket_arn  = module.code_pipeline_artifact_bucket.bucket_arn

  code_build_project_name = module.code_build_project.project_name
  code_build_project_arn  = module.code_build_project.project_arn

  code_deploy_application_name = module.code_deploy.application_name
  # The declared name, not the resource's generated deployment group id, which is what the _monolithic
  # template passed to the deploy action.
  code_deploy_deployment_group_name = module.code_deploy.deployment_group_name
  deployment_config_name            = var.deployment_config_name

  # CodePipeline starts an execution as soon as the pipeline is created, so everything the first run
  # touches has to exist by then: the build project, the deployment group, and both buckets
  # (rules.md D-2).
  depends_on = [
    module.network,
    module.code_build_project,
    module.code_deploy,
    module.code_pipeline_source_bucket,
    module.code_pipeline_artifact_bucket,
  ]
}
module "cloudtrail" {
  source = "./modules/cloudtrail"

  trail_name         = "${var.project_name}-codepipeline-source-trail"
  region             = local.region
  account_id         = local.account_id
  partition          = local.partition
  logs_bucket_prefix = "${var.project_name}-cloudtrail-logs-"
  # One object, assembled in the bucket module so the bucket and the key stay together (rules.md B-5).
  data_resource_object_arns = [module.code_pipeline_source_bucket.object_arn]
  include_management_events = var.cloudtrail_include_management_events
  force_destroy             = var.bucket_force_destroy

  # After the bucket, because the selector names an object in it. Worth knowing that this is only a
  # Terraform ordering: at run time the trail has to be recording before a write can produce an event,
  # and the bastion's upload happens asynchronously inside its userdata during this same apply. So the
  # first archive may well land before this trail is logging and trigger nothing. Re-running the upload
  # is the fix, and it is also the demo - see the reupload command in the outputs (rules.md D-3).
  depends_on = [module.network, module.code_pipeline_source_bucket]
}
module "s3_upload_pipeline_trigger" {
  source = "./modules/s3_upload_pipeline_trigger"

  name        = "${var.project_name}-codepipeline-event-rule"
  description = "Starts the ${module.code_pipeline.pipeline_name} pipeline when ${module.code_pipeline_source_bucket.object_key} is written to ${module.code_pipeline_source_bucket.bucket_name}. Managed here rather than created by the CodePipeline console, which writes an equivalent rule of its own"

  bucket_name = module.code_pipeline_source_bucket.bucket_name
  object_key  = module.code_pipeline_source_bucket.object_key
  event_names = var.trigger_event_names
  enabled     = var.trigger_enabled

  pipeline_arn     = module.code_pipeline.pipeline_arn
  role_name_prefix = "${var.project_name}-ev-"

  # The pipeline has to exist before a rule can target it, and the trail has to exist before the rule
  # has anything to match - the second edge is the one a value reference does not create, because this
  # module uses nothing from the trail (rules.md D-2).
  depends_on = [module.code_pipeline, module.cloudtrail]
}
