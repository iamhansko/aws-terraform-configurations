data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
# Both AMI lookups are here rather than inside the modules that use them.
#
# insecure_value rather than value: the provider marks every parameter's value sensitive whatever
# its type, and a sensitive value cannot be used for an instance's ami or a launch template's
# image_id without nonsensitive(). insecure_value is the provider's own accessor for a parameter
# that is not a secret, and a public AMI id is not one.
#
# Reading them in the root keeps them out of modules that carry depends_on, which would defer them
# to apply (rules.md D-6). Neither result reaches a for_each or a resource name, so deferring them
# would be harmless - but the D-6 check is about where a data source lives, and the root is the
# answer that does not have to be re-examined when a module grows a for_each.
data "aws_ssm_parameter" "workbench_ami_id" {
  name = var.workbench_ami_ssm_parameter_name
}
data "aws_ssm_parameter" "container_instance_ami_id" {
  name = var.container_instance_ami_ssm_parameter_name
}
locals {
  region     = data.aws_region.current.region
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  # The ECS cluster name, defined here rather than taken from the cluster module's output, because
  # two things need it and one of them would otherwise be a cycle: the cluster module creates it,
  # and the KMS key policy statements that ECS managed storage encryption requires have to name it
  # in a condition. One value, two readers (rules.md B-5). See encrypt_ecs_managed_storage.
  ecs_cluster_name = "${var.project_name}-ecs-cluster"

  # Log group names and the ARN patterns the task roles are scoped to.
  #
  # Patterns rather than real ARNs, and that is forced rather than chosen: the groups belong to the
  # application stacks, and each stack's task definition names the two shared task roles - so
  # taking the ARNs from the stacks would make the roles depend on every stack and every stack
  # depend on the roles. Building both from project_name keeps them one value anyway.
  app_log_group_prefix = "/${var.project_name}/logs"
  task_log_group_arn_patterns = [
    "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:${local.app_log_group_prefix}/*",
    "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:${local.app_log_group_prefix}/*:*",
    "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:${var.fluent_bit_log_group_name}",
    "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:${var.fluent_bit_log_group_name}:*",
  ]

  # The alarm descriptions, derived from the threshold and the period rather than written out. The
  # _monolithic template had them as prose - "an alarm when 10 or more 4xx occur within 5 minutes" -
  # next to the numbers they described, so changing a threshold left the description wrong and
  # nothing said so.
  alarm_window_minutes  = var.alarm_period * var.alarm_evaluation_periods / 60
  alarm_4xx_description = "Fires when the application load balancer returns ${var.alarm_4xx_threshold} or more 4xx responses within ${local.alarm_window_minutes} minutes"
  alarm_5xx_description = "Fires when the application load balancer returns ${var.alarm_5xx_threshold} or more 5xx responses within ${local.alarm_window_minutes} minutes"
}
module "network" {
  source = "./modules/network"

  region = local.region

  hub_vpc_name                  = "${var.project_name}-hub-vpc"
  hub_vpc_cidr_block            = var.hub_vpc_cidr_block
  hub_public_subnet_cidr_blocks = var.hub_public_subnet_cidr_blocks
  hub_internet_gateway_name     = "${var.project_name}-hub-igw"
  hub_public_subnet_name_prefix = "${var.project_name}-hub-pub"
  hub_public_route_table_name   = "${var.project_name}-hub-pub-rt"

  app_vpc_name                         = "${var.project_name}-app-vpc"
  app_vpc_cidr_block                   = var.app_vpc_cidr_block
  app_public_subnet_cidr_blocks        = var.app_public_subnet_cidr_blocks
  app_private_subnet_cidr_blocks       = var.app_private_subnet_cidr_blocks
  app_internal_subnet_cidr_blocks      = var.app_internal_subnet_cidr_blocks
  app_internet_gateway_name            = "${var.project_name}-app-igw"
  app_public_subnet_name_prefix        = "${var.project_name}-app-pub"
  app_private_subnet_name_prefix       = "${var.project_name}-app-pri"
  app_internal_subnet_name_prefix      = "${var.project_name}-app-db"
  app_public_route_table_name          = "${var.project_name}-app-pub-rt"
  app_private_route_table_name_prefix  = "${var.project_name}-app-pri-rt"
  app_internal_route_table_name_prefix = "${var.project_name}-app-db-rt"
  app_nat_gateway_name_prefix          = "${var.project_name}-app-ngw"

  peering_connection_name = "${var.project_name}-peering"

  hub_flow_log_group_name           = "/${var.project_name}/flow/hub"
  app_flow_log_group_name           = "/${var.project_name}/flow/app"
  flow_log_retention_in_days        = var.flow_log_retention_in_days
  flow_log_max_aggregation_interval = var.flow_log_max_aggregation_interval
  flow_log_role_name_prefix         = "${var.project_name}-flow-log-"

  app_ecr_endpoint_security_group_name        = "${var.project_name}-ecr-vpce-sg"
  app_ecr_endpoint_security_group_description = "HTTPS from inside the app VPC to the ECR interface endpoints"
  https_port                                  = var.https_port
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name_prefix = "${var.project_name}-key-"
  rsa_bits        = var.key_rsa_bits

  # This module uses nothing from network and does not need a VPC to create a key pair. It waits
  # anyway, because the rule is that a root with a network module has no module starting before
  # that module finishes - an exception here would mean the next reader has to decide per module
  # whether the omission was reasoned or forgotten (rules.md D-3).
  depends_on = [module.network]
}
module "kms_key" {
  source = "./modules/kms_key"

  description             = "Encrypts the Aurora cluster, its credential secret and the red container repository"
  alias_name              = "alias/${var.project_name}-kms"
  enable_key_rotation     = var.kms_enable_key_rotation
  rotation_period_in_days = var.kms_rotation_period_in_days
  deletion_window_in_days = var.kms_deletion_window_in_days

  # Also uses nothing from network, and also waits (rules.md D-3).
  depends_on = [module.network]
}
# --- The load balancer chain, built from the outside in. ---
#
# A request arrives at the hub load balancer in the hub VPC, crosses the peering connection to the
# app load balancer in the app VPC, is handed to the application load balancer, and is routed by
# path to one of the two stacks. Each hop names the previous hop's security group as its allowed
# source, which is what fixes the order these three modules are declared in.
module "hub_network_load_balancer" {
  source = "./modules/network_load_balancer"

  name       = "${var.project_name}-hub-nlb"
  vpc_id     = module.network.hub_vpc_id
  subnet_ids = module.network.hub_public_subnet_ids
  internal   = false

  listener_port = var.load_balancer_listener_port
  # target_type ip, and the targets are addresses in the other VPC. Nothing registers them here:
  # they are the app load balancer's network interfaces, which do not exist until that load
  # balancer is provisioned, so the workbench bootstrap registers them. That is the one step in
  # this project that cannot be a Terraform resource.
  target_group_name = "${var.project_name}-hub-nlb-tg"
  target_port       = var.load_balancer_listener_port
  target_type       = "ip"
  # TCP, with no path: these targets are raw addresses, and a path-based check is not valid on a
  # TCP target group.
  health_check_protocol            = "TCP"
  health_check_path                = null
  health_check_port                = "traffic-port"
  health_check_interval            = var.nlb_health_check_interval
  health_check_healthy_threshold   = var.nlb_health_check_healthy_threshold
  health_check_unhealthy_threshold = var.nlb_health_check_unhealthy_threshold
  deregistration_delay             = var.nlb_deregistration_delay
  enable_cross_zone_load_balancing = var.nlb_enable_cross_zone_load_balancing

  ingress_cidr_blocks = var.hub_nlb_ingress_cidr_blocks
  # Keyed by a label, because the value is another module's output and unknown at plan time
  # (rules.md B-8).
  all_traffic_source_security_groups = {
    hub_vpc_default = module.network.hub_default_security_group_id
  }

  security_group_name        = "${var.project_name}-hub-nlb-sg"
  security_group_description = "Public entry point for the hub network load balancer"

  depends_on = [module.network]
}
module "app_network_load_balancer" {
  source = "./modules/network_load_balancer"

  name       = "${var.project_name}-app-nlb"
  vpc_id     = module.network.app_vpc_id
  subnet_ids = module.network.app_private_subnet_ids
  internal   = true

  listener_port = var.load_balancer_listener_port
  # target_type alb: its one target is the internal application load balancer, registered by the
  # root below. The registration is in the root rather than in this module because the application
  # load balancer's security group names this module's group as its source - putting the
  # registration here would make the two modules depend on each other (rules.md C-1).
  target_group_name = "${var.project_name}-app-nlb-tg"
  target_port       = var.load_balancer_listener_port
  target_type       = "alb"
  # HTTP, which is required for an alb target group - a TCP health check cannot evaluate a path and
  # elbv2 rejects the pair. The _monolithic template set only the path here and left the provider
  # to fill the protocol from the target group's TCP protocol, which fails at CreateTargetGroup.
  health_check_protocol            = "HTTP"
  health_check_path                = var.health_check_path
  health_check_port                = "traffic-port"
  health_check_interval            = var.nlb_health_check_interval
  health_check_healthy_threshold   = var.nlb_health_check_healthy_threshold
  health_check_unhealthy_threshold = var.nlb_health_check_unhealthy_threshold
  deregistration_delay             = var.nlb_deregistration_delay
  enable_cross_zone_load_balancing = var.nlb_enable_cross_zone_load_balancing

  ingress_source_security_groups = {
    hub_nlb = module.hub_network_load_balancer.security_group_id
  }
  all_traffic_source_security_groups = {
    app_vpc_default = module.network.app_default_security_group_id
  }

  security_group_name        = "${var.project_name}-app-nlb-sg"
  security_group_description = "Listener port from the hub network load balancer across the peering connection"

  depends_on = [module.network, module.hub_network_load_balancer]
}
module "application_load_balancer" {
  source = "./modules/application_load_balancer"

  name       = "${var.project_name}-app-alb"
  vpc_id     = module.network.app_vpc_id
  subnet_ids = module.network.app_private_subnet_ids

  listener_port = var.load_balancer_listener_port
  idle_timeout  = var.alb_idle_timeout

  fixed_response_content_type = var.alb_fixed_response_content_type
  not_found_status_code       = var.alb_not_found_status_code
  not_found_message_body      = var.alb_not_found_message_body
  error_path                  = var.alb_error_path
  error_rule_priority         = var.alb_error_rule_priority
  error_status_code           = var.alb_error_status_code
  error_message_body          = var.alb_error_message_body

  ingress_source_security_groups = {
    app_nlb = module.app_network_load_balancer.security_group_id
  }
  all_traffic_source_security_groups = {
    app_vpc_default = module.network.app_default_security_group_id
  }

  security_group_name        = "${var.project_name}-app-alb-sg"
  security_group_description = "Listener port from the app network load balancer"

  depends_on = [module.network, module.app_network_load_balancer]
}
# The one target of the app network load balancer's target group, wired in the root because it
# joins two modules that already have an ordering between them (rules.md C-1). An alb-type target
# group takes the load balancer ARN as its target id.
#
# port comes from the listener resource, not from var.load_balancer_listener_port. elbv2 refuses to
# register an application load balancer that has no listener on the target port ("the target must
# have at least one listener that matches the target group port"), and the load balancer ARN alone
# orders this after aws_lb but not after aws_lb_listener - the two are created back to back, and
# the registration raced the listener and lost. The listener's own port attribute is the edge that
# was missing, and it also keeps the registered port equal to the port actually listening.
resource "aws_lb_target_group_attachment" "app_network_load_balancer_target" {
  target_group_arn = module.app_network_load_balancer.target_group_arn
  target_id        = module.application_load_balancer.load_balancer_arn
  port             = module.application_load_balancer.listener_port
}
locals {
  # The tool installation and the one registration step the workbench performs, injected into the
  # module through additional_user_data so the module does not have to know what this project needs
  # (rules.md B-4).
  #
  # rules.md H-1's five-tool list does not apply: it is conditional on the root declaring an EKS
  # cluster, and there is none here. So no kubectl, no eksctl and no helm - they would be three
  # downloads this demo never uses. What it does need is docker (the image build genuinely requires
  # a daemon, which is the one thing that cannot become a provider resource), git for the sources,
  # jq and zip for the CodePipeline artefact, and a mysql client for the schema step.
  #
  # jq and zip are worth singling out. The _monolithic template used both - jq to rewrite the task
  # definition and zip inside the helper script it wrote - and installed neither. AL2023 ships
  # neither. The association that used jq had no "set -e", so the jq failure was silent and the
  # artefact it produced was empty; the zip failure arrived later, when a person ran the helper
  # script by hand and the upload had nothing to upload.
  workbench_user_data = <<-EOT
    dnf install -yq docker git jq zip unzip mariadb105
    systemctl enable --now docker
    # Adds ec2-user to the docker group rather than the _monolithic template's
    # "chmod 666 /var/run/docker.sock", which hands every local user root-equivalent control of the
    # daemon. The build steps in the SSM associations run as root, so they do not need either.
    usermod -aG docker ec2-user
    # code-server is already running, so its process predates the docker group and its terminals
    # inherit the groups it started with. Restarting is what makes docker usable from the IDE.
    systemctl restart code-server

    # Registering the app network load balancer's private addresses as targets of the hub load
    # balancer's target group. This is the step that makes the project cross-VPC, and it cannot be
    # a Terraform resource: the addresses belong to elastic network interfaces that elbv2 creates
    # for the load balancer, so they are not an attribute of anything Terraform declares.
    #
    # AvailabilityZone=all is required because the addresses are outside the hub VPC - a target
    # group will not accept an off-VPC address pinned to a zone.
    #
    # The retry loop is the part the _monolithic template did not have. It read the interfaces once,
    # immediately after the load balancer was created, and they appear a little later: an empty
    # result left the register-targets call with no targets, so the public entry point reset every
    # connection with nothing logged anywhere.
    NLB_IPS=""
    for attempt in $(seq 1 ${var.load_balancer_interface_wait_attempts}); do
      NLB_IPS=$(aws ec2 describe-network-interfaces --region ${local.region} --filters Name=description,Values="ELB ${module.app_network_load_balancer.load_balancer_arn_suffix}" --query 'NetworkInterfaces[*].PrivateIpAddresses[*].PrivateIpAddress' --output text)
      if [ -n "$NLB_IPS" ]; then
        break
      fi
      sleep ${var.load_balancer_interface_wait_interval_seconds}
    done
    if [ -z "$NLB_IPS" ]; then
      echo "no network interfaces found for ELB ${module.app_network_load_balancer.load_balancer_arn_suffix}; the hub target group has no targets" >&2
    else
      TARGETS=""
      for IP in $NLB_IPS; do
        TARGETS="$TARGETS Id=$IP,AvailabilityZone=all"
      done
      aws elbv2 register-targets --region ${local.region} --target-group-arn ${module.hub_network_load_balancer.target_group_arn} --targets $TARGETS
    fi
    EOT
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  instance_name = "${var.project_name}-ec2-bastion"
  vpc_id        = module.network.hub_vpc_id
  # One hub public subnet. The workbench is the public side of this project: it reaches the app VPC
  # across the peering connection, which every hub route table carries a route for.
  subnet_id                   = module.network.hub_public_subnet_ids_by_zone[sort(keys(var.hub_public_subnet_cidr_blocks))[0]]
  ami_id                      = data.aws_ssm_parameter.workbench_ami_id.insecure_value
  instance_type               = var.workbench_instance_type
  key_name                    = module.key_pair.key_name
  root_volume_size            = var.workbench_root_volume_size
  associate_public_ip_address = true

  code_server_version = var.code_server_version
  code_server_port    = var.code_server_port
  ssh_port            = var.ssh_port
  python_version      = var.python_version

  ingress_cidr_blocks        = var.workbench_ingress_cidr_blocks
  security_group_name        = "${var.project_name}-bastion-sg"
  security_group_description = "code-server and SSH access to the workbench instance"

  iam_role_name_prefix = "${var.project_name}-ec2-admin-"
  iam_policy_arns      = var.workbench_iam_policy_arns

  # Lets the four associations below know when the bootstrap has finished (rules.md B-4, H-2). The
  # module touches <path>/userdata as its very last step, after the script above has run.
  marker_file_path     = var.marker_file_path
  additional_user_data = local.workbench_user_data

  # network for the uniform reason, and here it is load-bearing as well: the bootstrap starts
  # calling AWS within seconds of the launch, and the route to the hub internet gateway is exactly
  # the sort of resource a value reference misses (rules.md D-3).
  #
  # Both load balancers because the script above names them. Those references already order this
  # after the two resources it reads, and the module-level edge covers the rest of each module -
  # the target group a registration writes into included (rules.md D-2).
  depends_on = [
    module.network,
    module.key_pair,
    module.hub_network_load_balancer,
    module.app_network_load_balancer,
  ]
}
# The security group every task's network interface gets. Before both stacks, because Aurora names
# it as an allowed source and a stack attaches it.
module "ecs_service_security_group" {
  source = "./modules/ecs_service_security_group"

  name           = "${var.project_name}-ecs-service-sg"
  description    = "Container port from the application load balancer and from the workbench"
  vpc_id         = module.network.app_vpc_id
  container_port = var.container_port

  ingress_source_security_groups = {
    app_alb   = module.application_load_balancer.security_group_id
    workbench = module.vscode_ec2.security_group_id
  }
  all_traffic_source_security_groups = {
    app_vpc_default = module.network.app_default_security_group_id
  }

  depends_on = [module.network, module.application_load_balancer, module.vscode_ec2]
}
module "rds_cluster" {
  source = "./modules/rds_cluster"

  cluster_identifier = "${var.project_name}-rdb-cluster"
  engine             = var.rds_engine
  engine_version     = var.rds_engine_version
  database_name      = var.rds_database_name
  port               = var.rds_port
  master_username    = var.rds_username
  master_password    = var.rds_password

  vpc_id = module.network.app_vpc_id
  # The internal tier, which has no route to the internet in either direction.
  subnet_ids               = module.network.app_internal_subnet_ids
  subnet_group_name        = "${var.project_name}-rds-subnet-group"
  subnet_group_description = "Internal subnets with no route to the internet"
  kms_key_arn              = module.kms_key.key_arn

  instance_class             = var.rds_instance_class
  instance_identifier_prefix = "${var.project_name}-rds-instance"
  # Keyed by zone suffix, with the full zone name as the value. The keys are configuration values,
  # so they are known at plan time and usable as for_each keys (rules.md B-8).
  instance_availability_zones = {
    for suffix in var.rds_instance_zone_suffixes : suffix => "${local.region}${suffix}"
  }
  availability_zones = [for suffix in var.rds_instance_zone_suffixes : "${local.region}${suffix}"]

  backup_retention_period               = var.rds_backup_retention_period
  backtrack_window                      = var.rds_backtrack_window
  enabled_cloudwatch_logs_exports       = var.rds_cloudwatch_logs_exports
  database_insights_mode                = var.rds_database_insights_mode
  performance_insights_retention_period = var.rds_performance_insights_retention_period
  monitoring_interval                   = var.rds_monitoring_interval
  monitoring_role_name_prefix           = "${var.project_name}-rds-monitoring-"
  monitoring_policy_arns                = var.rds_monitoring_policy_arns
  auto_minor_version_upgrade            = var.rds_auto_minor_version_upgrade
  apply_immediately                     = var.rds_apply_immediately
  skip_final_snapshot                   = var.rds_skip_final_snapshot

  secret_name                    = "${var.project_name}/secret/key"
  secret_description             = "Aurora connection document read by both application task definitions"
  secret_recovery_window_in_days = var.rds_secret_recovery_window_in_days

  ingress_source_security_groups = {
    ecs_service = module.ecs_service_security_group.security_group_id
    workbench   = module.vscode_ec2.security_group_id
  }
  all_traffic_source_security_groups = {
    app_vpc_default = module.network.app_default_security_group_id
  }

  security_group_name        = "${var.project_name}-rds-sg"
  security_group_description = "Database port from the ECS tasks and from the workbench"

  depends_on = [
    module.network,
    module.kms_key,
    module.vscode_ec2,
    module.ecs_service_security_group,
  ]
}
module "ecs_cluster_capacity" {
  source = "./modules/ecs_cluster_capacity"

  cluster_name       = local.ecs_cluster_name
  container_insights = var.container_insights
  # Null unless the key policy has been extended to let the ECS service principal use the key - see
  # the variable, and modules/kms_key. The _monolithic template passed the key here without that,
  # which breaks the Fargate stack at task launch rather than at apply.
  managed_storage_kms_key_id = var.encrypt_ecs_managed_storage ? module.kms_key.key_arn : null

  vpc_id = module.network.app_vpc_id
  # Private subnets: the ECS agent has to reach the ECS and ECR endpoints to register, and it does
  # that through the per-zone NAT gateways and the two ECR interface endpoints.
  subnet_ids = module.network.app_private_subnet_ids
  ami_id     = data.aws_ssm_parameter.container_instance_ami_id.insecure_value
  key_name   = module.key_pair.key_name

  instance_name      = "${var.project_name}-ecs-container-instance"
  instance_type      = var.container_instance_type
  root_device_name   = var.container_instance_root_device_name
  root_volume_size   = var.container_instance_root_volume_size
  ecs_config_options = var.ecs_config_options

  launch_template_name_prefix    = "${var.project_name}-asg-lt-"
  auto_scaling_group_name_prefix = "${var.project_name}-ecs-asg-"
  min_size                       = var.container_instance_min_size
  max_size                       = var.container_instance_max_size
  desired_capacity               = var.container_instance_desired_capacity
  capacity_distribution_strategy = var.capacity_distribution_strategy

  capacity_provider_name                 = "${var.project_name}-ec2-capacity-provider"
  managed_scaling_status                 = var.managed_scaling_status
  managed_scaling_target_capacity        = var.managed_scaling_target_capacity
  managed_scaling_minimum_step_size      = var.managed_scaling_minimum_step_size
  managed_scaling_maximum_step_size      = var.managed_scaling_maximum_step_size
  managed_scaling_instance_warmup_period = var.managed_scaling_instance_warmup_period
  additional_capacity_providers          = var.additional_capacity_providers

  iam_role_name_prefix = "${var.project_name}-container-instance-"
  iam_policy_arns      = var.container_instance_iam_policy_arns

  all_traffic_source_security_groups = {
    app_vpc_default = module.network.app_default_security_group_id
  }
  security_group_name        = "${var.project_name}-ecs-container-instance-sg"
  security_group_description = "All traffic from the app VPC default security group"

  depends_on = [module.network, module.kms_key, module.key_pair]
}
# The two roles both task definitions name. After Aurora, because the execution role policy is
# scoped to that cluster's credential secret.
module "ecs_task_iam_roles" {
  source = "./modules/ecs_task_iam_roles"

  task_role_name_prefix      = "${var.project_name}-ecs-task-"
  execution_role_name_prefix = "${var.project_name}-ecs-task-exec-"

  secret_arns            = [module.rds_cluster.secret_arn]
  kms_key_arn            = module.kms_key.key_arn
  log_group_arn_patterns = local.task_log_group_arn_patterns

  execution_policy_arns       = var.task_execution_policy_arns
  additional_task_policy_arns = var.additional_task_policy_arns

  depends_on = [module.network, module.kms_key, module.rds_cluster]
}
# One repository per stack, created before the images are built into it and well before the task
# definitions that reference a tag in it. for_each over the same map the stacks come from, so the
# keys are literals in configuration and known at plan time (rules.md B-8).
module "ecr_repository" {
  source   = "./modules/ecr_repository"
  for_each = var.app_stacks

  name            = "${var.project_name}/${each.key}"
  encryption_type = each.value.ecr_encryption_type
  # Only used when the type is KMS, which for these two stacks means only the red one - that
  # asymmetry is in the _monolithic template and is one of the few real differences between them.
  kms_key_arn          = each.value.ecr_encryption_type == "KMS" ? module.kms_key.key_arn : null
  scan_on_push         = var.ecr_scan_on_push
  image_tag_mutability = var.ecr_image_tag_mutability
  force_delete         = var.ecr_force_delete

  depends_on = [module.network, module.kms_key]
}
locals {
  # The four image builds, generated from the stack map and the version list rather than written
  # out. The _monolithic template had these as four near-identical blocks inside one long
  # single-quoted shell string, each with its own inline Dockerfile.
  #
  # Every line here sits at the same indentation on purpose. Terraform's <<- strips the smallest
  # indentation of any line in the heredoc, so with nothing indented further, every line - the
  # quoted heredoc terminator included - lands at column 0. A heredoc terminator with leading
  # whitespace is not recognised, the heredoc swallows the rest of the script, and the whole thing
  # fails to parse with a syntax error at the last line (rules.md A-4 describes the same failure
  # arriving from a CRLF line ending).
  image_build_commands = flatten([
    for key, stack in var.app_stacks : [
      for version in var.image_versions : <<-EOT
      IMAGE=${module.ecr_repository[key].repository_url}:v${version}
      BINARY=${key}_${version}
      if aws ecr describe-images --region ${local.region} --repository-name ${module.ecr_repository[key].name} --image-ids imageTag=v${version} > /dev/null 2>&1; then
      echo "$IMAGE is already in the repository, skipping"
      else
      if [ ! -f "/home/ec2-user/$BINARY" ]; then
      echo "$BINARY is missing from the clone: ${var.source_repository_path} in ${var.source_repository_url} does not contain it" >&2
      exit 1
      fi
      cat > /home/ec2-user/Dockerfile.$BINARY <<'TFDOCKERFILE'
      FROM ${var.image_base_image}
      ENV CGO_ENABLED 0
      WORKDIR /app
      COPY ./${key}_${version} ./${key}_${version}
      RUN apt-get update && apt-get install -y curl
      RUN chmod +x ./${key}_${version}
      RUN useradd -u ${var.container_user_uid} ${key}
      USER ${key}
      EXPOSE ${var.container_port}
      CMD ["./${key}_${version}"]
      TFDOCKERFILE
      docker build -f /home/ec2-user/Dockerfile.$BINARY -t "$IMAGE" /home/ec2-user
      docker push "$IMAGE"
      fi
      EOT
    ]
  ])
}
# Step one: build and push the application images.
#
# This is what the task definitions wait for. Without it the services start, their tasks stop with
# CannotPullContainerError against a tag that does not exist, and ECS keeps replacing them - which
# is worse than failing, because it recovers on its own once a push eventually lands and the demo
# looks broken for ten minutes and then silently is not.
#
# The marker-and-loop shape rather than depends_on or the provider's own timeout, because
# wait_for_success_timeout_seconds does not reliably mean the remote command finished
# (rules.md D-5). An until loop rather than a bare test: a failing test is a non-zero statement at
# top level, which ends the script immediately if the shell SSM runs it with has -e set, while a
# failing until condition never triggers it.
resource "aws_ssm_association" "container_images" {
  name                             = "AWS-RunShellScript"
  association_name                 = "${var.project_name}-container-images"
  wait_for_success_timeout_seconds = var.ssm_wait_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    commands = <<-EOT
      set -u
      waited=0
      until [ -f ${module.vscode_ec2.marker_file_path}/userdata ]; do
      waited=$((waited + 1))
      if [ "$waited" -gt ${var.marker_wait_attempts} ]; then
      echo "the workbench bootstrap never finished: ${module.vscode_ec2.marker_file_path}/userdata is still absent. Read /var/log/cloud-init-output.log on the instance." >&2
      exit 1
      fi
      sleep ${var.marker_wait_interval_seconds}
      done

      if [ ! -d /home/ec2-user/sources ]; then
      git clone --depth 1 ${var.source_repository_url} /home/ec2-user/sources
      fi
      # Checked before the copy because this script has no set -e: a failed cp is otherwise only
      # the first line of stderr, and the step goes on to log in to ECR and fail later at the first
      # binary, under a message that names the binary rather than the path.
      if [ ! -d /home/ec2-user/sources/${var.source_repository_path} ]; then
      echo "${var.source_repository_path} does not exist in ${var.source_repository_url}. The upstream repository has renumbered its projects before - list its top-level directories and update source_repository_path." >&2
      exit 1
      fi
      cp -r /home/ec2-user/sources/${var.source_repository_path}/. /home/ec2-user/
      chown -R ec2-user:ec2-user /home/ec2-user

      aws ecr get-login-password --region ${local.region} | docker login --username AWS --password-stdin ${module.ecr_repository[keys(var.app_stacks)[0]].registry_url}

      ${join("\n", local.image_build_commands)}

      touch ${module.vscode_ec2.marker_file_path}/container_images
      EOT
  }

  # The repositories have to exist before a push, and the workbench before anything runs on it.
  # Nothing in the command above references the instance other than through the target block, which
  # does not create an ordering edge (rules.md D-1).
  depends_on = [module.ecr_repository, module.vscode_ec2]
}
module "app_stack" {
  source   = "./modules/app_stack"
  for_each = var.app_stacks

  stack_key  = each.key
  region     = local.region
  account_id = local.account_id
  partition  = local.partition

  vpc_id             = module.network.app_vpc_id
  subnet_ids         = module.network.app_private_subnet_ids
  security_group_ids = [module.ecs_service_security_group.security_group_id]
  cluster_name       = module.ecs_cluster_capacity.cluster_name
  listener_arn       = module.application_load_balancer.listener_arn

  task_definition_family = "${var.project_name}-ecs-${each.key}-taskdef"
  service_name           = "${var.project_name}-ecs-${each.key}"
  container_name         = each.key

  image_uri      = module.ecr_repository[each.key].repository_url
  image_tag      = var.image_tag
  container_port = var.container_port

  # The five fields the two stacks actually differ by arrive here; everything else is shared or
  # derived from the key. See the app_stacks variable.
  task_cpu                      = each.value.task_cpu
  task_memory                   = var.task_memory
  cpu_architecture              = var.cpu_architecture
  launch_type                   = each.value.launch_type
  availability_zone_rebalancing = var.availability_zone_rebalancing
  desired_count                 = var.service_desired_count
  listener_rule_priority        = each.value.listener_rule_priority
  health_check_rule_priority    = each.value.health_check_rule_priority

  task_role_arn             = module.ecs_task_iam_roles.task_role_arn
  execution_role_arn        = module.ecs_task_iam_roles.execution_role_arn
  task_definition_role_arns = module.ecs_task_iam_roles.role_arns_for_pass_role
  secret_arn                = module.rds_cluster.secret_arn

  log_group_name            = "${local.app_log_group_prefix}/${each.key}"
  log_retention_in_days     = var.app_log_retention_in_days
  log_exclude_pattern       = var.log_exclude_pattern
  fluent_bit_image          = var.fluent_bit_image
  fluent_bit_log_group_name = var.fluent_bit_log_group_name

  target_group_blue_name           = "${var.project_name}-${each.key}-tg-blue"
  target_group_green_name          = "${var.project_name}-${each.key}-tg-green"
  health_check_path                = var.health_check_path
  health_check_interval            = var.target_group_health_check_interval
  health_check_timeout             = var.target_group_health_check_timeout
  health_check_healthy_threshold   = var.target_group_health_check_healthy_threshold
  health_check_unhealthy_threshold = var.target_group_health_check_unhealthy_threshold
  health_check_matcher             = var.target_group_health_check_matcher
  deregistration_delay             = var.target_group_deregistration_delay

  container_health_check_interval     = var.container_health_check_interval
  container_health_check_timeout      = var.container_health_check_timeout
  container_health_check_retries      = var.container_health_check_retries
  container_health_check_start_period = var.container_health_check_start_period

  code_deploy_application_name       = "${var.project_name}-cd-${each.key}-app"
  code_deploy_deployment_group_name  = "${var.project_name}-cd-${each.key}-dg"
  deployment_config_name             = var.deployment_config_name
  deployment_ready_action_on_timeout = var.deployment_ready_action_on_timeout
  termination_wait_time_in_minutes   = var.termination_wait_time_in_minutes
  auto_rollback_events               = var.auto_rollback_events

  code_deploy_role_name_prefix   = "${var.project_name}-cd-${each.key}-"
  code_deploy_policy_arns        = var.code_deploy_policy_arns
  code_pipeline_role_name_prefix = "${var.project_name}-cp-${each.key}-"
  event_rule_role_name_prefix    = "${var.project_name}-ev-${each.key}-"

  pipeline_name                 = "${var.project_name}-cd-${each.key}-pipeline"
  execution_mode                = var.pipeline_execution_mode
  source_object_key             = var.source_object_key
  task_definition_template_path = var.task_definition_template_path
  app_spec_template_path        = var.app_spec_template_path
  image_detail_file_name        = var.image_detail_file_name
  image_placeholder_name        = var.image_placeholder_name
  source_bucket_prefix          = "${var.project_name}-cd-${each.key}-source-"
  artifact_store_bucket_prefix  = "${var.project_name}-cd-${each.key}-artifact-"
  force_destroy                 = var.bucket_force_destroy

  event_rule_name        = "${var.project_name}-${each.key}-codepipeline-event-rule"
  event_rule_description = "Starts the ${each.key} pipeline when its source artefact is written. Managed here rather than created by the CodePipeline console, which writes an equivalent rule of its own"

  # Five edges, and only two of them would exist from value references alone.
  #
  #   network                     the uniform rule, and load-bearing: the tasks reach ECR through
  #                               the NAT gateways and the interface endpoints (rules.md D-3)
  #   ecs_cluster_capacity        the cluster name orders this after the cluster resource, not
  #                               after the capacity provider's attachment to it or after any
  #                               instance registering. An EC2-launch-type task has nowhere to go
  #                               until one has. The reverse direction matters more: on destroy
  #                               this module goes first, which is what lets ECS delete the
  #                               capacity provider - it refuses while a service still names it
  #   application_load_balancer   the listener ARN orders this after the listener but not after
  #                               the load balancer's security group rules
  #   ecs_task_iam_roles          the role ARNs order this after the roles but not after their
  #                               policies, and a task definition naming a role with no policy is
  #                               accepted - the failure arrives as a stopped task (rules.md D-1)
  #   container_images            the image has to be in the repository before a service starts
  #                               pulling it. This is the edge the CloudFormation CreationPolicy
  #                               used to provide and the conversion dropped
  depends_on = [
    module.network,
    module.ecs_cluster_capacity,
    module.application_load_balancer,
    module.ecs_task_iam_roles,
    aws_ssm_association.container_images,
  ]
}
locals {
  # The per-stack artefact assembly, generated from the stack map. Flat indentation for the same
  # reason as the image builds above: the quoted heredoc terminator has to reach the shell at
  # column 0.
  pipeline_artifact_commands = [
    for key, stack in var.app_stacks : <<-EOT
    mkdir -p /home/ec2-user/pipeline/artifact/${key}
    cd /home/ec2-user/pipeline/artifact/${key}

    printf '{"ImageURI": "%s"}\n' "${module.app_stack[key].repository_url}:v${var.deploy_image_version}" > ${var.image_detail_file_name}

    cat > ${var.task_definition_template_path} <<'TFTASKDEF'
    ${module.app_stack[key].task_definition_template}
    TFTASKDEF

    cat > ${var.app_spec_template_path} <<'TFAPPSPEC'
    ${module.app_stack[key].app_spec_template}
    TFAPPSPEC

    cat > /home/ec2-user/pipeline/${key}.sh <<'TFDEPLOYSCRIPT'
    #!/bin/bash
    set -euo pipefail
    cd /home/ec2-user/pipeline/artifact/${key}
    rm -f ${var.source_object_key}
    zip -q ${var.source_object_key} ${var.image_detail_file_name} ${var.task_definition_template_path} ${var.app_spec_template_path}
    aws s3 cp ${var.source_object_key} s3://${module.app_stack[key].source_bucket_name}/${var.source_object_key}
    rm -f ${var.source_object_key}
    TFDEPLOYSCRIPT
    chmod +x /home/ec2-user/pipeline/${key}.sh
    EOT
  ]
}
# Step two: assemble the CodePipeline artefact for each stack, and write the one-line script that
# uploads it.
#
# Uploading that artefact is the demo: it starts a pipeline, which starts a CodeDeploy blue/green
# deployment, which shifts the listener rule from whichever of the stack's two target groups is
# live to the other one. After the seed deployment that is green to blue - the first deployment is
# the pipeline's own, not the demo's.
#
# taskdef.json and appspec.yaml are the stack module's templates written out as they are - the
# same text the seed artefact the module uploads for the pipeline's first execution carries. Only
# imageDetail.json differs: the seed names image_tag, which the service already runs, and this one
# names deploy_image_version, which is the switch. The _monolithic template produced taskdef.json
# here with ecs describe-task-definition and a jq filter, inside "su - ec2-user << EOF" with no
# set -e, so a failed describe or a missing jq produced an empty artefact and a successful
# association.
resource "aws_ssm_association" "pipeline_artifacts" {
  name                             = "AWS-RunShellScript"
  association_name                 = "${var.project_name}-pipeline-artifacts"
  wait_for_success_timeout_seconds = var.ssm_wait_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    commands = <<-EOT
      set -eu
      waited=0
      until [ -f ${module.vscode_ec2.marker_file_path}/container_images ]; do
      waited=$((waited + 1))
      if [ "$waited" -gt ${var.marker_wait_attempts} ]; then
      echo "the image build step never finished: ${module.vscode_ec2.marker_file_path}/container_images is still absent." >&2
      exit 1
      fi
      sleep ${var.marker_wait_interval_seconds}
      done

      ${join("\n", local.pipeline_artifact_commands)}

      chown -R ec2-user:ec2-user /home/ec2-user/pipeline
      touch ${module.vscode_ec2.marker_file_path}/pipeline_artifacts
      EOT
  }

  depends_on = [module.app_stack]
}
# Step three: create the schema.
#
# The database is in the internal tier, which has no route to the internet, so the only thing that
# can reach it is something inside the VPCs - which is this workbench, across the peering
# connection. That is rules.md E-9's shape applied to a database rather than to a cluster API
# server: when the thing that has to be configured is only reachable from inside, an SSM
# association on an instance in there is the way to do it.
#
# Two changes from the _monolithic template, both about the same thing - it put the password on a
# command line.
#
#   it interpolated var.rds_password straight into the mysql invocation, which writes the password
#   into the association's parameters. Those are readable in the console and in
#   ssm describe-association by anyone who can read SSM. The password is fetched from Secrets
#   Manager at run time here instead, which is where it already lives.
#
#   MYSQL_PWD rather than -p"$PASSWORD", so it does not appear in the process list on the instance
#   either.
#
# And the wait is a connection retry rather than its "sleep 300" - a guess that was both too short
# when the cluster was slow and five wasted minutes when it was not.
resource "aws_ssm_association" "database_schema" {
  name                             = "AWS-RunShellScript"
  association_name                 = "${var.project_name}-database-schema"
  wait_for_success_timeout_seconds = var.ssm_wait_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    commands = <<-EOT
      set -eu
      waited=0
      until [ -f ${module.vscode_ec2.marker_file_path}/pipeline_artifacts ]; do
      waited=$((waited + 1))
      if [ "$waited" -gt ${var.marker_wait_attempts} ]; then
      echo "the artefact step never finished: ${module.vscode_ec2.marker_file_path}/pipeline_artifacts is still absent." >&2
      exit 1
      fi
      sleep ${var.marker_wait_interval_seconds}
      done

      SQL_FILE=/home/ec2-user/${var.sql_file_name}
      if [ ! -f "$SQL_FILE" ]; then
      echo "$SQL_FILE is missing: the clone of ${var.source_repository_path} should have placed it there in step one" >&2
      exit 1
      fi

      SECRET=$(aws secretsmanager get-secret-value --region ${local.region} --secret-id ${module.rds_cluster.secret_name} --query SecretString --output text)
      DB_USER=$(printf '%s' "$SECRET" | jq -r .DB_USER)
      MYSQL_PWD=$(printf '%s' "$SECRET" | jq -r .DB_PASSWD)
      export MYSQL_PWD
      DB_HOST=${module.rds_cluster.cluster_endpoint}

      ready=0
      for attempt in $(seq 1 ${var.database_wait_attempts}); do
      if mysqladmin ping -h "$DB_HOST" -P ${module.rds_cluster.port} -u "$DB_USER" > /dev/null 2>&1; then
      ready=1
      break
      fi
      sleep ${var.database_wait_interval_seconds}
      done
      if [ "$ready" -ne 1 ]; then
      echo "Aurora at $DB_HOST:${module.rds_cluster.port} did not accept a connection. Check that the cluster has instances - a cluster with none resolves and refuses - and that the workbench security group is an allowed source." >&2
      exit 1
      fi

      mysql -h "$DB_HOST" -P ${module.rds_cluster.port} -u "$DB_USER" ${module.rds_cluster.database_name} < "$SQL_FILE"
      mysql -h "$DB_HOST" -P ${module.rds_cluster.port} -u "$DB_USER" ${module.rds_cluster.database_name} -e 'SHOW TABLES;'

      touch ${module.vscode_ec2.marker_file_path}/database_schema
      EOT
  }

  depends_on = [module.rds_cluster, aws_ssm_association.pipeline_artifacts]
}
module "cloudtrail" {
  source = "./modules/cloudtrail"

  trail_name         = "${var.project_name}-codepipeline-source-trail"
  region             = local.region
  account_id         = local.account_id
  partition          = local.partition
  logs_bucket_prefix = "${var.project_name}-cloudtrail-logs-"
  # One object per stack, each assembled in the stack module so the bucket and the key stay
  # together (rules.md B-5).
  data_resource_object_arns = [for stack in module.app_stack : stack.source_object_arn]
  include_management_events = var.cloudtrail_include_management_events
  force_destroy             = var.bucket_force_destroy

  # After the stacks, because the selector names their buckets. Worth knowing that this is only a
  # Terraform ordering: at run time the trail has to be recording before an upload can start a
  # pipeline, so the first artefact uploaded in the few minutes after apply may not trigger
  # anything. Re-running the helper script is the fix, and it is also the demo.
  depends_on = [module.network, module.app_stack]
}
module "observability" {
  source = "./modules/observability"

  dashboard_name = "${var.project_name}-metrics"
  region         = local.region
  # Passed in because the flow log widget filters on the @log field, which is
  # "<account>:<log group>". The _monolithic template had a literal account number there, so that
  # widget rendered empty in every account but the one it was written in.
  account_id               = local.account_id
  load_balancer_arn_suffix = module.application_load_balancer.load_balancer_arn_suffix

  hub_vpc_name            = "${var.project_name}-hub-vpc"
  app_vpc_name            = "${var.project_name}-app-vpc"
  hub_flow_log_group_name = module.network.hub_flow_log_group_name
  app_flow_log_group_name = module.network.app_flow_log_group_name
  # One log widget per stack, taken from the stacks rather than written out as literal JSON
  # (rules.md B-5).
  app_log_widgets = {
    for key, stack in module.app_stack : key => {
      log_group_name = stack.log_group_name
      path_prefix    = stack.path_prefix
    }
  }

  metric_period               = var.metric_period
  high_utilization_annotation = var.high_utilization_annotation

  alarm_period             = var.alarm_period
  alarm_evaluation_periods = var.alarm_evaluation_periods
  alarm_4xx_name           = "${var.project_name}-app-alb-4xx-alarm"
  alarm_4xx_description    = local.alarm_4xx_description
  alarm_4xx_threshold      = var.alarm_4xx_threshold
  alarm_5xx_name           = "${var.project_name}-app-alb-5xx-alarm"
  alarm_5xx_description    = local.alarm_5xx_description
  alarm_5xx_threshold      = var.alarm_5xx_threshold

  depends_on = [module.network, module.application_load_balancer, module.app_stack]
}
locals {
  # Every output this project exposes, defined once. outputs.tf projects these and the README
  # association below renders them, so no value is written twice (rules.md B-5, H-2). Adding an
  # entry here is what makes an output possible, which is what keeps the README from falling behind
  # outputs.tf - there were no outputs at all in the _monolithic template, so everything a person
  # needs to drive this demo had to be found in the console.
  #
  # Nothing sensitive appears as a value. The database password, the generated secret document and
  # the SSH private key are all exposed as the command that retrieves them, which is the form this
  # repository prefers - a README written to disk on an instance running code-server with
  # authentication disabled is not a place to put a password.
  stack_keys = sort(keys(var.app_stacks))
  outputs = {
    application_urls = {
      order       = 1
      title       = "The application, through the whole chain"
      description = "Each path goes public network load balancer in the hub VPC, across the peering connection to the internal network load balancer in the app VPC, to the internal application load balancer, to the task. A 404 body here means the request reached the listener and matched no rule; a connection reset means the hub target group has no registered targets"
      value = join("\n", [
        for key in local.stack_keys : "${module.hub_network_load_balancer.url}${module.app_stack[key].path_prefix}"
      ])
    }
    error_path_url = {
      order       = 2
      title       = "The 5xx path"
      description = "Answered with a fixed 500 by the application load balancer listener, so the 5xx alarm and the dashboard widget can be made to fire without breaking an application"
      value       = "${module.hub_network_load_balancer.url}${var.alb_error_path}"
    }
    vscode_url = {
      order       = 3
      title       = "code-server on the workbench"
      description = "Every step of this demo is run from here. code-server runs with authentication disabled, so treat this URL as the credential"
      value       = module.vscode_ec2.vscode_url
    }
    deploy_commands = {
      order       = 4
      title       = "1. Trigger a blue/green deployment"
      description = "Run one of these in a code-server terminal. The script zips the artefact the second bootstrap step assembled and uploads it to the stack's source bucket, which is what starts the pipeline. The artefact deploys image v${var.deploy_image_version} while the service is running v${trimprefix(var.image_tag, "v")}, so the switch is visible in the response body"
      value = join("\n", [
        for key in local.stack_keys : "/home/ec2-user/pipeline/${key}.sh"
      ])
    }
    pipeline_status_commands = {
      order       = 5
      title       = "2. Watch the pipeline"
      description = "The Source stage picks the artefact up within a minute of the upload, through the EventBridge rule and the CloudTrail data event. The Deploy stage hands it to CodeDeploy. Each pipeline also has one earlier execution of its own, triggered by its creation, which deployed the seed artefact Terraform uploads - the image the service was already running - so it succeeds without changing the response"
      value = join("\n", [
        for key in local.stack_keys : module.app_stack[key].pipeline_status_command
      ])
    }
    deployment_status_commands = {
      order       = 6
      title       = "3. Watch the traffic shift"
      description = "List the deployments, then run aws deploy get-deployment --deployment-id <id> to see the task sets and the traffic weighting. This is where the blue and green target groups swap"
      value = join("\n", [
        for key in local.stack_keys : module.app_stack[key].deployment_status_command
      ])
    }
    listener_rules_command = {
      order       = 7
      title       = "4. See what the switch changed"
      description = "Each deployment moves a stack's path rule from the target group that is live to the other one. The pipeline's first execution, which deploys the seed artefact at creation, already made one move from blue to green, so the demo deployment moves it back to blue. CodeDeploy owns that field, which is why the rules and the services ignore changes to it - a Terraform apply that reverted it would move live traffic to a drained task set (rules.md E-8)"
      value       = module.application_load_balancer.listener_rules_command
    }
    hub_target_health_command = {
      order       = 8
      title       = "Is the cross-VPC path wired up"
      description = "The targets here are the app VPC network load balancer's private addresses, registered by the workbench bootstrap because they are not an attribute of any Terraform resource. An empty table means that step did not run, and the public URL will reset every connection"
      value       = module.hub_network_load_balancer.target_health_command
    }
    peering_connection = {
      order       = 9
      title       = "Peering connection"
      description = "Accept status included because it is the failure the _monolithic template would have produced: without auto_accept a same-account connection is created in pending-acceptance, and nothing crosses between the VPCs"
      value       = "${module.network.peering_connection_id} (${module.network.peering_accept_status})"
    }
    route_tables_command = {
      order       = 10
      title       = "Every route in both VPCs"
      description = "This is where the design is visible: each of the eight route tables carries one route to the peering connection, the private tables add a NAT gateway, and the internal tables have nothing else at all"
      value       = module.network.route_tables_command
    }
    ecs_cluster_name = {
      order       = 11
      title       = "ECS cluster"
      description = "Holds both services. One runs on the EC2 capacity provider and one on Fargate, which is one of the five things the two stacks differ by"
      value       = module.ecs_cluster_capacity.cluster_name
    }
    container_instances_command = {
      order       = 12
      title       = "Are the container instances registered"
      description = "An empty list with a healthy Auto Scaling group means the instances cannot reach the ECS endpoint. That is what the _monolithic template's missing egress rule produced on all nine of its security groups (rules.md F-2)"
      value       = module.ecs_cluster_capacity.container_instances_command
    }
    service_status_command = {
      order       = 13
      title       = "Both services and their task counts"
      description = "Running count below desired count, with tasks cycling, is the signature of an image or a permission problem rather than a load balancer one"
      value       = "aws ecs describe-services --cluster ${module.ecs_cluster_capacity.cluster_name} --services ${join(" ", [for key in local.stack_keys : module.app_stack[key].service_name])} --query 'services[].[serviceName,launchType,desiredCount,runningCount,deployments[0].rolloutState]' --output table"
    }
    image_list_command = {
      order       = 14
      title       = "What is in the repositories"
      description = "Both tags should be present in both repositories after the first bootstrap step. The tags are immutable, so the step checks before pushing rather than pushing again"
      value = join("\n", [
        for key in local.stack_keys : "aws ecr describe-images --repository-name ${module.ecr_repository[key].name} --query 'imageDetails[].imageTags' --output table"
      ])
    }
    rds_endpoint = {
      order       = 15
      title       = "Aurora writer endpoint"
      description = "In the internal tier, which has no route to the internet in either direction. Reachable from the workbench across the peering connection and from the tasks, and from nowhere else"
      value       = "${module.rds_cluster.cluster_endpoint}:${module.rds_cluster.port}/${module.rds_cluster.database_name}"
    }
    rds_secret_command = {
      order       = 16
      title       = "Database credentials"
      description = "The retrieval command rather than the password: the tasks read the same document through their execution role, and a password written into this README would be readable through code-server, which runs without authentication (rules.md H-2)"
      value       = module.rds_cluster.secret_command
    }
    database_tables_command = {
      order       = 17
      title       = "Did the schema load"
      description = "Run from a code-server terminal. Two tables, one per stack, created by the third bootstrap step from the SQL file in the cloned sources"
      value       = "MYSQL_PWD=$(aws secretsmanager get-secret-value --secret-id ${module.rds_cluster.secret_name} --query SecretString --output text | jq -r .DB_PASSWD) mysql -h ${module.rds_cluster.cluster_endpoint} -P ${module.rds_cluster.port} -u ${module.rds_cluster.master_username} ${module.rds_cluster.database_name} -e 'SHOW TABLES;'"
    }
    rds_instance_status_command = {
      order       = 18
      title       = "Aurora cluster members"
      description = "An empty list is the shape of the bug in the original: its two Aurora instances were converted to aws_db_instance without a cluster identifier, which cannot be created at all - leaving a cluster with an endpoint that refuses every connection"
      value       = module.rds_cluster.instance_status_command
    }
    dashboard_url = {
      order       = 19
      title       = "CloudWatch dashboard"
      description = "Seven widgets: the two VPCs' accepted flow log counts, one GET and POST count per stack, service, task and container CPU, and the load balancer error counts. The per-task and per-container widgets need Container Insights in enhanced mode, which the cluster is set to"
      value       = module.observability.dashboard_url
    }
    alarm_state_command = {
      order       = 20
      title       = "Both load balancer alarms"
      description = "INSUFFICIENT_DATA for both no matter what the load balancer returns is the signature of the _monolithic template's empty dimension map - there is no dimensionless AWS/ApplicationELB metric to alarm on. The dimension is set here, so a quiet period reads OK"
      value       = module.observability.alarm_state_command
    }
    trail_status_command = {
      order       = 21
      title       = "Is the trail delivering"
      description = "The EventBridge rules that start the pipelines depend entirely on this trail recording a write to each source object - S3 does not publish data events to EventBridge on its own. Check this first when an upload does not start a pipeline"
      value       = module.cloudtrail.trail_status_command
    }
    private_key_command = {
      order       = 22
      title       = "SSH private key"
      description = "The command rather than the key. The same key pair is attached to the container instances, which have no inbound rule and are reachable only through Session Manager"
      value       = module.key_pair.private_key_command
    }
    workbench_ssh_command = {
      order       = 23
      title       = "SSH to the workbench"
      description = "On the port the bootstrap moved sshd to. Port 22 is closed in the security group, so the default port does not connect"
      value       = module.vscode_ec2.ssh_command
    }
    bootstrap_log_command = {
      order       = 24
      title       = "Read the bootstrap log"
      description = "The workbench user data runs with set -x, so this is the first place to look when a tool is missing. The four ordered steps after it are SSM associations - aws ssm describe-association-executions is where those report"
      value       = "sudo tail -n 200 /var/log/cloud-init-output.log"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the order field and
  # taking values() sorts by that instead - values() returns a map's values ordered by key - so the
  # README reads top to bottom in demo order, still fully determined by the configuration rather
  # than shuffling between applies.
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
# Step four: write the README.
#
# The work happens inside code-server in a browser, where "terraform output" does not exist, so
# every output above is also written into the home directory the IDE opens (rules.md H-2). Last in
# the chain, so the file appears only once everything it describes is real.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  association_name                 = "${var.project_name}-readme"
  wait_for_success_timeout_seconds = var.ssm_wait_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The quoted heredoc delimiter is a string that cannot occur in the body - the README contains
    # kubectl-style commands, markdown fences and SQL, so EOF or MD would not be safe. SSM runs as
    # root, hence the chown: without it the file is not editable from the IDE.
    commands = <<-EOT
      set -eu
      waited=0
      until [ -f ${module.vscode_ec2.marker_file_path}/database_schema ]; do
      waited=$((waited + 1))
      if [ "$waited" -gt ${var.marker_wait_attempts} ]; then
      echo "the schema step never finished: ${module.vscode_ec2.marker_file_path}/database_schema is still absent." >&2
      exit 1
      fi
      sleep ${var.marker_wait_interval_seconds}
      done
      cat > /home/ec2-user/README.md <<'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_readme
      EOT
  }

  depends_on = [
    aws_ssm_association.database_schema,
    module.cloudtrail,
    module.observability,
  ]
}
