data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
# The ECS-optimized Amazon Linux 2 GPU AMI, from the parameter CDK's EcsOptimizedImage.amazon_linux2(GPU)
# resolved. Read here rather than in the capacity module, which waits on the network, so it is read at plan
# (rules.md D-6). A new AMI updates the launch template and reaches the next instance the group launches; the
# running one keeps its own.
data "aws_ssm_parameter" "ecs_gpu_ami" {
  name = var.ecs_gpu_ami_parameter
}
# "My IP", in the sense the console's security group editor means it: the address this machine appears as from
# outside. It is the source the load balancer's security group admits, so by default nothing but the machine
# that ran the apply can reach ComfyUI at all - where the blueprint opened 80 and 443 to 0.0.0.0/0 and left
# Cognito as the only thing in front of it.
#
# Read at the root, which is where a plan-time read has to live: the load balancer module waits for the whole
# network module, and a data source inside it would be deferred to apply with everything derived from it
# (rules.md D-6). Not read at all when the caller names the addresses itself, so this is also the one thing
# here that makes terraform plan reach something other than AWS - hence the overridable URL.
data "http" "my_ip" {
  count = var.alb_ingress_cidr_blocks == null ? 1 : 0

  url = var.my_ip_lookup_url

  lifecycle {
    # A captive portal or a proxy answers this with a web page, and that page would otherwise be written into
    # a security group rule - where EC2 rejects it with InvalidParameterValue naming the CIDR, several
    # resources into the apply. This fails the plan instead, saying what answered.
    postcondition {
      condition     = can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$", trimspace(self.response_body)))
      error_message = "my_ip_lookup_url did not answer with a bare IPv4 address. Something between here and it is answering instead - a proxy or a captive portal - so set alb_ingress_cidr_blocks explicitly."
    }
  }
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
  partition  = data.aws_partition.current.partition

  # The blueprint's suffix: the first ten hex digits of sha256("<account>-<region>-<stack name>"). It keeps the
  # Cognito domain prefix unique - those are shared by every account in a region - and names the Docker volume.
  # The project name stands where the stack name was, so two copies of this project with different names can
  # share an account and a region.
  resource_suffix = substr(sha256("${local.account_id}-${local.region}-${var.project_name}"), 0, 10)

  # ComfyUI's port, fixed by the Dockerfile's CMD (--port 8181). A local rather than a variable: the image
  # decides it, and changing it here alone would point the target group, the health check and the security
  # group at a port nothing listens on (rules.md B-1).
  comfyui_port = 8181

  # The blueprint's memory reservation: 90% of the smallest listed instance type's memory, from its own table,
  # with 16 GiB assumed for a type the table does not list - 14745 MiB for the default types.
  instance_memory_mib = {
    "g4dn.xlarge" = 16384, "g4dn.2xlarge" = 32768, "g4dn.4xlarge" = 65536,
    "g5.xlarge"   = 16384, "g5.2xlarge" = 32768, "g5.4xlarge" = 65536,
    "g6.xlarge"   = 16384, "g6.2xlarge" = 32768, "g6.4xlarge" = 65536,
    "g6e.xlarge"  = 32768, "g6e.2xlarge" = 65536, "g6e.4xlarge" = 131072,
  }
  memory_reservation_mib = floor(0.9 * min([
    for type in module.ecs_gpu_capacity.instance_types : lookup(local.instance_memory_mib, type, 16384)
  ]...))

  # The image build context: the blueprint's comfyui_aws_stack/docker directory, kept in this project. Hashed
  # from file names and contents rather than from the zip, whose bytes also carry metadata that differs
  # between platforms. The hash is the image tag, as CDK's asset hash was, so one value uploads the context,
  # runs the build and rolls the task onto the new image (rules.md B-5).
  comfyui_image_dir = "${path.module}/comfyui_image"
  comfyui_image_hash = sha256(join("\n", [
    for file in sort(fileset(local.comfyui_image_dir, "**")) : "${file}:${filesha256("${local.comfyui_image_dir}/${file}")}"
  ]))

  # The blueprint created its web ACL only when there was something for it to do.
  web_acl_enabled = length(var.allowed_ipv4_address_ranges) > 0 || length(var.allowed_ipv6_address_ranges) > 0 || var.waf_rate_limit_enabled

  # What the load balancer's security group admits: the detected address as a /32, or exactly what the caller
  # named. Derived rather than a second variable, so the two cannot be set to different things (rules.md B-1).
  alb_ingress_cidr_blocks = coalesce(
    var.alb_ingress_cidr_blocks,
    [for body in data.http.my_ip[*].response_body : "${trimspace(body)}/32"],
  )
}

# The code packages, zipped at the root so they are read at plan while the modules that use them are ordered
# after the network (rules.md D-6). A fixed file mode, so the same files zip to the same bytes - and the same
# source_code_hash - on Windows and on Linux.
data "archive_file" "comfyui_image_source" {
  type             = "zip"
  source_dir       = local.comfyui_image_dir
  output_path      = "${path.module}/build/comfyui-image-source.zip"
  output_file_mode = "0644"
}
data "archive_file" "admin_functions" {
  type             = "zip"
  source_dir       = "${path.module}/lambda_src/admin"
  output_path      = "${path.module}/build/admin-functions.zip"
  output_file_mode = "0644"
}
data "archive_file" "check_email_domain" {
  type             = "zip"
  source_dir       = "${path.module}/lambda_src/check_email_domain"
  output_path      = "${path.module}/build/check-email-domain.zip"
  output_file_mode = "0644"
}

# Not converted, because nothing in this project's configuration could ever reach them - the blueprint's
# app.py was edited by the old build only for sign-up, the sign-up domains and the two address lists:
#   - cheap_vpc=False, NAT gateways instead of NAT instances
#   - host_name/domain_name/hosted_zone_id, a Route 53 name with a DNS-validated ACM certificate
#   - slack_workspace_id/slack_channel_id, AWS Chatbot with its two SNS topics, alarms and monitor Lambda
#   - saml_auth_enabled, which only turned self sign-up and required MFA off; the identity provider itself was
#     always configured by hand in the console
# The cheap switches of the blueprint's DEPLOY_OPTION.md - spot, the instance types, idle scale-down, the
# work-hour schedule, MFA, the WAF rate limit - are variables.

# --- Network --------------------------------------------------------------------------------------------

module "network" {
  source = "./modules/network"

  name                       = var.project_name
  region                     = local.region
  vpc_cidr_block             = var.vpc_cidr_block
  availability_zone_suffixes = var.availability_zone_suffixes
  nat_instance_type          = var.nat_instance_type
  nat_security_group_name    = "${var.project_name}-nat"
  flow_log_retention_days    = var.log_retention_days
}

# --- Load balancer and its protection -------------------------------------------------------------------

module "load_balancer" {
  source = "./modules/load_balancer"

  name                     = var.project_name
  vpc_id                   = module.network.vpc_id
  subnet_ids               = module.network.public_subnet_ids
  security_group_name      = "${var.project_name}-alb"
  ingress_cidr_blocks      = local.alb_ingress_cidr_blocks
  ssl_policy               = var.alb_ssl_policy
  target_group_name        = "${var.project_name}-comfyui"
  target_port              = local.comfyui_port
  certificate_import_delay = var.certificate_import_delay
  certificate_version      = var.certificate_version

  # Nothing here reads the NAT instances or the route tables, but every module waits for all of the network
  # (rules.md D-3).
  depends_on = [module.network]
}
module "web_acl" {
  source = "./modules/web_acl"
  count  = local.web_acl_enabled ? 1 : 0

  name                        = var.project_name
  resource_arn                = module.load_balancer.arn
  allowed_ipv4_address_ranges = var.allowed_ipv4_address_ranges
  allowed_ipv6_address_ranges = var.allowed_ipv6_address_ranges
  rate_limit_enabled          = var.waf_rate_limit_enabled
  rate_limit_requests         = var.waf_rate_limit_requests
  rate_limit_interval_seconds = var.waf_rate_limit_interval_seconds

  depends_on = [module.network]
}

# --- Authentication -------------------------------------------------------------------------------------

module "cognito" {
  source = "./modules/cognito_user_pool"

  name      = var.project_name
  region    = local.region
  partition = local.partition
  # The blueprint's comfyui-alb-auth-<suffix>.
  domain_prefix                 = "comfyui-alb-auth-${local.resource_suffix}"
  application_dns_name          = module.load_balancer.dns_name
  self_sign_up_enabled          = var.self_sign_up
  allowed_sign_up_email_domains = var.allowed_sign_up_email_domains
  mfa_required                  = var.mfa_required
  advanced_security_mode        = var.cognito_advanced_security_mode
  sms_external_id               = "${var.project_name}-${local.resource_suffix}-sms"
  pre_sign_up_source_zip_path   = data.archive_file.check_email_domain.output_path
  pre_sign_up_source_code_hash  = data.archive_file.check_email_domain.output_base64sha256
  log_retention_days            = var.log_retention_days

  depends_on = [module.network]
}
# Everything else behind the login: ComfyUI itself. The /admin and /signout routes, at priorities 5 to 25, are
# in modules/admin_functions with the functions they invoke; this one is last and catches every other path.
# It joins the load balancer and the user pool, so it is declared here (rules.md C-1).
resource "aws_lb_listener_rule" "comfyui" {
  listener_arn = module.load_balancer.https_listener_arn
  priority     = 30

  action {
    type = "authenticate-cognito"
    authenticate_cognito {
      user_pool_arn       = module.cognito.user_pool_arn
      user_pool_client_id = module.cognito.client_id
      user_pool_domain    = module.cognito.domain
    }
  }
  action {
    type             = "forward"
    target_group_arn = module.load_balancer.target_group_arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}

# --- Image ----------------------------------------------------------------------------------------------

module "comfyui_image" {
  source = "./modules/comfyui_image"

  repository_name       = var.project_name
  image_tag             = local.comfyui_image_hash
  force_delete          = var.ecr_force_delete
  project_name          = "${var.project_name}-image"
  compute_type          = var.image_build_compute_type
  build_timeout_minutes = var.image_build_timeout_minutes
  buildspec             = file("${path.module}/buildspec/comfyui_image.yml")
  log_retention_days    = var.log_retention_days
  source_zip_path       = data.archive_file.comfyui_image_source.output_path
  source_hash           = local.comfyui_image_hash

  depends_on = [module.network]
}
# Builds the image during the apply, and holds the task definition until the build has pushed it.
#
# A build is not infrastructure, so there is no resource for it; the aws_codebuild_start_build action starts
# one and waits for it to finish. It fires before_create and before_update on purpose: with those events the
# trigger completes only after the action does, so its output - which is what the task definition reads - is
# not available until the image is in ECR. With after_create the trigger would complete first and the task
# would be defined against a tag that does not exist yet (hashicorp/terraform-provider-aws#46484).
#
# input is the image reference, whose tag is the build context's hash, so the build runs on the first apply
# and again whenever a file under comfyui_image/ changes. A failed build fails the apply with the build's
# status. This replaces the old trigger Lambda and its aws_lambda_invocation, which started a build and
# returned without knowing how it ended.
action "aws_codebuild_start_build" "comfyui_image" {
  config {
    project_name = module.comfyui_image.project_name
    # The project's own timeout plus a margin for queueing and provisioning, so the action never gives up on
    # a build CodeBuild is still allowed to run (rules.md B-5).
    timeout = (module.comfyui_image.build_timeout_minutes + 15) * 60
  }
}
resource "terraform_data" "comfyui_image_build" {
  count = var.build_image_on_apply ? 1 : 0

  input = module.comfyui_image.image_uri

  lifecycle {
    action_trigger {
      events  = [before_create, before_update]
      actions = [action.aws_codebuild_start_build.comfyui_image]
    }
  }

  # The build reads the uploaded context with the project's role, so the whole module - the object, the
  # role's policy and the repository - has to exist before it starts (rules.md D-2).
  depends_on = [module.comfyui_image]
}

# --- ECS ------------------------------------------------------------------------------------------------

module "ecs_cluster" {
  source = "./modules/ecs_cluster"

  name = var.project_name

  depends_on = [module.network]
}
module "ecs_gpu_capacity" {
  source = "./modules/ecs_gpu_capacity"

  name                   = "${var.project_name}-gpu"
  region                 = local.region
  cluster_name           = module.ecs_cluster.name
  cluster_arn            = module.ecs_cluster.arn
  vpc_id                 = module.network.vpc_id
  subnet_ids             = module.network.private_subnet_ids
  ami_id                 = data.aws_ssm_parameter.ecs_gpu_ami.insecure_value
  instance_types         = var.instance_types
  use_spot               = var.use_spot
  spot_max_price         = var.spot_max_price
  root_volume_size       = var.root_volume_size_gib
  security_group_name    = "${var.project_name}-gpu-host"
  capacity_provider_name = "${var.project_name}-gpu"
  auto_scale_down        = var.auto_scale_down
  schedule_auto_scaling  = var.schedule_auto_scaling
  schedule_timezone      = var.schedule_timezone
  schedule_scale_up      = var.schedule_scale_up
  schedule_scale_down    = var.schedule_scale_down

  depends_on = [module.network]
}
module "comfyui_service" {
  source = "./modules/comfyui_service"

  name      = var.project_name
  region    = local.region
  partition = local.partition
  # Taken from the capacity module's output, which waits for the cluster to have the provider - ECS rejects a
  # strategy naming one it does not have yet.
  cluster_arn            = module.ecs_cluster.arn
  capacity_provider_name = module.ecs_gpu_capacity.capacity_provider_name
  vpc_id                 = module.network.vpc_id
  subnet_ids             = module.network.private_subnet_ids
  # Through the build trigger when the apply builds the image, which is what keeps the task definition from
  # naming a tag that is not pushed yet.
  image                  = var.build_image_on_apply ? terraform_data.comfyui_image_build[0].output : module.comfyui_image.image_uri
  container_port         = local.comfyui_port
  memory_reservation_mib = local.memory_reservation_mib
  # The blueprint's container environment, as it passed it. ComfyUI itself reads none of the three.
  environment = {
    AWS_REGION           = local.region
    COGNITO_USER_POOL_ID = module.cognito.user_pool_id
    COGNITO_CLIENT_ID    = module.cognito.client_id
  }
  # The blueprint's ComfyUIVolume-<suffix>. REX-Ray finds the EBS volume by this name, so it must not change
  # while the volume holds the installation.
  volume_name     = "ComfyUIVolume-${local.resource_suffix}"
  volume_driver   = module.ecs_gpu_capacity.docker_volume_plugin
  volume_size_gib = var.comfyui_volume_size_gib
  volume_type     = var.comfyui_volume_type
  # A map with a literal key, because the ID is another module's output (rules.md B-8).
  ingress_source_security_groups = {
    load_balancer = module.load_balancer.security_group_id
  }
  target_group_arn    = module.load_balancer.target_group_arn
  security_group_name = "${var.project_name}-service"
  log_retention_days  = var.log_retention_days

  # ECS refuses to create a service on a target group no listener routes to, and the /* rule is the only
  # thing that routes to this one - the listener's own default is a fixed 403 (modules/load_balancer). On
  # destroy the same edge removes the service before the rule.
  depends_on = [module.network, aws_lb_listener_rule.comfyui]
}

# --- Admin pages ----------------------------------------------------------------------------------------

module "admin_functions" {
  source = "./modules/admin_functions"

  name                        = var.project_name
  source_zip_path             = data.archive_file.admin_functions.output_path
  source_code_hash            = data.archive_file.admin_functions.output_base64sha256
  log_retention_days          = var.log_retention_days
  auto_scaling_group_name     = module.ecs_gpu_capacity.auto_scaling_group_name
  cluster_name                = module.ecs_cluster.name
  cluster_arn                 = module.ecs_cluster.arn
  service_name                = module.comfyui_service.service_name
  listener_arn                = module.load_balancer.https_listener_arn
  cognito_user_pool_arn       = module.cognito.user_pool_arn
  cognito_user_pool_client_id = module.cognito.client_id
  cognito_user_pool_domain    = module.cognito.domain
  logout_redirect_url         = module.cognito.logout_url

  depends_on = [module.network]
}
