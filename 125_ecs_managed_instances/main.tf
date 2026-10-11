data "aws_region" "current" {}
# The public zone, looked up by name unless its ID is given. In the root rather than inside the certificate
# module, so a depends_on on that module can never defer this read to apply (rules.md D-6).
data "aws_route53_zone" "default_domain" {
  count        = var.route53_hosted_zone_id == null ? 1 : 0
  name         = var.default_domain
  private_zone = false
}
locals {
  route53_zone_id = coalesce(var.route53_hosted_zone_id, one(data.aws_route53_zone.default_domain[*].zone_id))
  # One name for the certificate, the alias record, Shlink's DEFAULT_DOMAIN and the web client's server URL
  # (rules.md B-5). The _monolithic template spelled "shlink.${var.default_domain}" out four times.
  shlink_domain = "${var.shlink_subdomain}.${var.default_domain}"
}
module "network" {
  source = "./modules/network"

  vpc_cidr_block             = var.vpc_cidr_block
  availability_zone_suffixes = var.availability_zone_suffixes
}
module "ecs_cluster" {
  source = "./modules/ecs_cluster"

  name = "${var.project_name}-ecs-cluster"

  depends_on = [module.network]
}
module "capacity_provider" {
  source = "./modules/ecs_managed_instances_capacity_provider"

  name                 = "${var.project_name}-managed-instances-capacity-provider"
  cluster_name         = module.ecs_cluster.cluster_name
  vpc_id               = module.network.vpc_id
  subnet_ids           = module.network.private_subnet_ids
  capacity_option_type = var.capacity_option_type
  vcpu_count           = var.instance_vcpu_count
  memory_mib           = var.instance_memory_mib
  storage_size_gib     = var.instance_storage_size_gib

  # network for the uniform reason and because the instances' only way to the ECS endpoint is the NAT
  # gateways, which nothing above references (rules.md D-3).
  depends_on = [module.network, module.ecs_cluster]
}
# --- Shlink's state -----------------------------------------------------------------------------------------
module "shlink_efs" {
  source = "./modules/efs_file_system"

  vpc_id             = module.network.vpc_id
  subnet_ids_by_zone = module.network.private_subnet_ids_by_zone
  # The managed instances' group, as the _monolithic template allowed it. The Shlink tasks get in through the
  # module's client group instead of their own, which is what keeps this module and the service module from
  # each needing the other's output.
  ingress_source_security_groups = {
    managed_instances = module.capacity_provider.security_group_id
  }

  depends_on = [module.network]
}
module "shlink_configuration" {
  source = "./modules/shlink_configuration_secret"

  name_prefix  = "${var.project_name}-shlink-"
  short_domain = local.shlink_domain
  timezone     = var.timezone

  depends_on = [module.network]
}
# --- Shlink's front door ------------------------------------------------------------------------------------
module "shlink_certificate" {
  source = "./modules/dns_validated_certificate"

  domain_name     = local.shlink_domain
  route53_zone_id = local.route53_zone_id

  depends_on = [module.network]
}
module "shlink_alb" {
  source = "./modules/application_load_balancer"

  name                        = "${var.project_name}-shlink"
  vpc_id                      = module.network.vpc_id
  vpc_cidr_block              = module.network.vpc_cidr_block
  subnet_ids                  = module.network.public_subnet_ids
  security_group_name         = "shlink-alb-sg"
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  enable_https                = true
  # The validated ARN, so the HTTPS listener is created after ISSUED rather than racing it.
  certificate_arn      = module.shlink_certificate.certificate_arn
  target_port          = var.shlink_container_port
  health_check_path    = "/rest/health"
  health_check_matcher = "200"

  depends_on = [module.network]
}
resource "aws_route53_record" "shlink" {
  zone_id = local.route53_zone_id
  name    = local.shlink_domain
  type    = "A"
  alias {
    name                   = module.shlink_alb.dns_name
    zone_id                = module.shlink_alb.zone_id
    evaluate_target_health = false
  }
}
module "web_client_alb" {
  source = "./modules/application_load_balancer"

  name                        = "${var.project_name}-web-client"
  vpc_id                      = module.network.vpc_id
  vpc_cidr_block              = module.network.vpc_cidr_block
  subnet_ids                  = module.network.public_subnet_ids
  security_group_name         = "web-client-alb-sg"
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  # Plain HTTP on 80, as the _monolithic template had it. The web client is a static single-page app; the
  # API calls it makes go from the browser to the Shlink domain above, which is HTTPS.
  enable_https         = false
  target_port          = var.web_client_container_port
  health_check_path    = "/"
  health_check_matcher = "200-399"

  depends_on = [module.network]
}
# --- The two services ---------------------------------------------------------------------------------------
module "shlink_service" {
  source = "./modules/ecs_service"

  name                   = "${var.project_name}-shlink-service"
  cluster_name           = module.ecs_cluster.cluster_name
  capacity_provider_name = module.capacity_provider.capacity_provider_name
  region                 = data.aws_region.current.region
  vpc_id                 = module.network.vpc_id
  subnet_ids             = module.network.private_subnet_ids
  security_group_name    = "shlink-service-sg"
  ingress_source_security_groups = {
    alb = module.shlink_alb.security_group_id
  }
  # What lets the tasks reach the mount targets (see the EFS module).
  extra_security_group_ids = [module.shlink_efs.client_security_group_id]
  task_family              = "shlink"
  task_cpu                 = 512
  task_memory              = 1024
  container_name           = "shlink"
  container_image          = var.shlink_image
  container_port           = module.shlink_alb.target_port
  secret_arn               = module.shlink_configuration.secret_arn
  secrets = {
    DEFAULT_DOMAIN   = "DEFAULT_DOMAIN"
    IS_HTTPS_ENABLED = "IS_HTTPS_ENABLED"
    TIMEZONE         = "TIMEZONE"
    INITIAL_API_KEY  = "SHLINK_API_KEY"
  }
  container_health_check = {
    command      = ["CMD-SHELL", "wget --spider -q http://127.0.0.1:${module.shlink_alb.target_port}/rest/health || exit 1"]
    interval     = 30
    timeout      = 5
    retries      = 5
    start_period = 10
  }
  efs_volume = {
    name             = "shlink_data"
    file_system_id   = module.shlink_efs.file_system_id
    file_system_arn  = module.shlink_efs.file_system_arn
    access_point_id  = module.shlink_efs.access_point_id
    access_point_arn = module.shlink_efs.access_point_arn
    container_path   = "/etc/shlink/data"
  }
  log_group_name                    = "/ecs/task/shlink"
  log_retention_in_days             = var.log_retention_in_days
  target_group_arn                  = module.shlink_alb.target_group_arn
  health_check_grace_period_seconds = 60
  # At most one task at a time, as the _monolithic template had it. Shlink's default database is a SQLite
  # file in the EFS directory, and two tasks writing one SQLite file over NFS corrupt it - so a deployment
  # stops the old task before the new one starts, and accepts the minute of downtime.
  deployment_maximum_percent         = 100
  deployment_minimum_healthy_percent = 0
  wait_for_steady_state              = var.wait_for_steady_state

  # What the value references do not order this after (rules.md D-2):
  #   - shlink_efs as a whole, for the mount targets, which the _monolithic template waited for explicitly -
  #     a task placed before its zone's mount target exists fails to mount
  #   - shlink_alb as a whole, for the listener that attaches the target group, which ECS requires
  #   - shlink_configuration as a whole, for the secret's value, which the ARN exists before
  #   - capacity_provider as a whole, for the infrastructure role's policy and the instances' egress rule
  depends_on = [
    module.network,
    module.capacity_provider,
    module.shlink_efs,
    module.shlink_alb,
    module.shlink_configuration,
  ]
}
module "web_client_service" {
  source = "./modules/ecs_service"

  name                   = "${var.project_name}-web-client-service"
  cluster_name           = module.ecs_cluster.cluster_name
  capacity_provider_name = module.capacity_provider.capacity_provider_name
  region                 = data.aws_region.current.region
  vpc_id                 = module.network.vpc_id
  subnet_ids             = module.network.private_subnet_ids
  security_group_name    = "web-client-service-sg"
  ingress_source_security_groups = {
    alb = module.web_client_alb.security_group_id
  }
  task_family     = "shlink-web-client"
  task_cpu        = 256
  task_memory     = 512
  container_name  = "shlink-web-client"
  container_image = var.web_client_image
  container_port  = module.web_client_alb.target_port
  secret_arn      = module.shlink_configuration.secret_arn
  secrets = {
    SHLINK_SERVER_URL     = "SHLINK_SERVER_URL"
    SHLINK_SERVER_NAME    = "SHLINK_SERVER_NAME"
    SHLINK_SERVER_API_KEY = "SHLINK_API_KEY"
  }
  log_group_name        = "/ecs/task/web-client"
  log_retention_in_days = var.log_retention_in_days
  target_group_arn      = module.web_client_alb.target_group_arn
  wait_for_steady_state = var.wait_for_steady_state

  depends_on = [
    module.network,
    module.capacity_provider,
    module.web_client_alb,
    module.shlink_configuration,
  ]
}
# --- Destroy-time drain -------------------------------------------------------------------------------------
module "drain_on_destroy" {
  source = "./modules/ecs_drain_on_destroy"

  function_name = "${var.project_name}-ecs-lambda-function"
  cluster_name  = module.ecs_cluster.cluster_name
  cluster_arn   = module.ecs_cluster.cluster_arn
  # These references are the mechanism, not just the input: they put the invocation after both services in
  # the graph, so terraform destroy runs it - and waits for the instances to go - before it touches either.
  service_names = [module.shlink_service.service_name, module.web_client_service.service_name]
  service_arns  = [module.shlink_service.service_arn, module.web_client_service.service_arn]

  depends_on = [module.network]
}
