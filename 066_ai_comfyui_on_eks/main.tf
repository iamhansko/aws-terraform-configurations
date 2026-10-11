data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# The addresses CloudFront makes origin requests from, looked up by name. The ALB's frontend group admits
# CloudFront's VPC origin through this list - the method CloudFront's documentation gives that can be written
# before the origin exists.
data "aws_ec2_managed_prefix_list" "cloudfront_origin_facing" {
  name = var.cloudfront_prefix_list_name
}
# The managed policies the blueprint's distribution used (CachePolicy.CACHING_DISABLED,
# OriginRequestPolicy.ALL_VIEWER), by name rather than by the UUIDs the console shows.
data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = var.cloudfront_cache_policy_name
}
data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = var.cloudfront_origin_request_policy_name
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  # Every bucket the blueprint created, under the blueprint's names. Fixed names are not a convenience here:
  # the ComfyUI image's auto model downloader builds the models and outputs bucket names itself, as
  # comfyui-<kind>-<account>-<region>, so any other name would leave it reading and writing buckets that do
  # not exist. The build source bucket is the one addition - the blueprint uploaded its build context into
  # the models bucket, where every upload also triggered the model sync Lambda.
  #
  # Keys are literals, because they become resource addresses and the values are computed (rules.md B-8).
  buckets = {
    models = {
      name            = "comfyui-models-${local.account_id}-${local.region}"
      expiration_days = null
    }
    models_access_logs = {
      name            = "comfyui-models-access-logs-${local.account_id}-${local.region}"
      expiration_days = var.models_access_log_expiration_days
    }
    inputs = {
      name            = "comfyui-inputs-${local.account_id}-${local.region}"
      expiration_days = null
    }
    outputs = {
      name            = "comfyui-outputs-${local.account_id}-${local.region}"
      expiration_days = null
    }
    build_source = {
      name            = "comfyui-build-source-${local.account_id}-${local.region}"
      expiration_days = null
    }
  }

  # The <namespace>/<name> the controller writes into ingress.k8s.aws/stack, derived once and handed to both
  # the pre-created ALB and the workload. A value rather than the workload module's output, so the ALB can be
  # created before the Ingress exists - taken from an output it would wait for the Ingress, and the controller
  # would reconcile an Ingress whose load balancer does not exist yet and build its own (rules.md B-5/G-3).
  comfyui_stack_tag = "${var.comfyui_namespace}/${var.comfyui_ingress_name}"

  # The build context: the blueprint's comfyui_image/ directory, kept in this project. Hashed from file names
  # and contents rather than from the zip, whose bytes also carry metadata such as file modes that differ
  # between platforms - so the same files checked out on another machine do not rebuild the image. One hash
  # re-uploads the context, reruns the build and rolls the pods (rules.md B-5).
  comfyui_image_dir = "${path.module}/comfyui_image"
  comfyui_image_source_hash = sha256(join("\n", [
    for file in sort(fileset(local.comfyui_image_dir, "**")) : "${file}:${filesha256("${local.comfyui_image_dir}/${file}")}"
  ]))

  # Folders the GPU node creates under the models path before copying - the blueprint's list, plus the folder
  # of every boot model, so editing gpu_node_boot_models cannot leave a copy without a destination.
  model_folders = distinct(concat(
    ["diffusion_models", "text_encoders", "vae", "upscale_models", "checkpoints", "loras", "controlnet", "clip_vision"],
    [for key in var.gpu_node_boot_models : dirname(key) if dirname(key) != "."],
  ))
  # The blueprint's EC2NodeClass user data, with the bucket and the path written in from here instead of
  # rebuilt on the node from aws sts get-caller-identity and the instance metadata (rules.md B-5).
  #
  # The instance store is what the models live on: g5 and g6 2xlarge carry one local NVMe disk, and the
  # models are copied onto it at boot with the CRT transfer client. A model not yet in the bucket fails its
  # copy and is skipped; the sync Lambda copies it in when it lands.
  #
  # The repeated lines are joined here and interpolated whole, rather than written with %{for} directives inside
  # the heredoc: a directive's ~ strip marker removes the newline the <<- dedent keys on, so every line after
  # the first loop kept the heredoc's indentation.
  model_folder_commands = join("\n", [for folder in local.model_folders : "mkdir -p ${var.models_host_path}/${folder}"])
  boot_model_commands = join("\n", [
    for key in var.gpu_node_boot_models : "aws s3 cp s3://${local.buckets.models.name}/${key} ${var.models_host_path}/${key} &"
  ])
  gpu_node_user_data = <<-EOT
    #!/bin/bash
    # Security patches at first boot, so a fresh node is current immediately; the daily patch association
    # keeps it patched afterwards. Kernel updates that need a reboot apply on the next node replacement.
    dnf upgrade --security -y || true
    mkfs -t xfs /dev/nvme1n1
    mkdir -p ${var.models_host_path}
    mount /dev/nvme1n1 ${var.models_host_path}
    aws configure set default.s3.preferred_transfer_client crt
    ${local.model_folder_commands}
    echo "Copying boot models from s3://${local.buckets.models.name}"
    ${local.boot_model_commands}
    wait
    EOT
}

module "network" {
  source = "./modules/network"

  region                         = local.region
  vpc_cidr_block                 = var.vpc_cidr_block
  availability_zone_suffixes     = var.availability_zone_suffixes
  nat_availability_zone_suffixes = var.nat_availability_zone_suffixes
  create_s3_gateway_endpoint     = true
  vpc_name                       = "${var.project_name}-vpc"
  internet_gateway_name          = "${var.project_name}-igw"
  public_subnet_name_prefix      = "${var.project_name}-public"
  private_subnet_name_prefix     = "${var.project_name}-private"
  public_route_table_name        = "${var.project_name}-public-rt"
  private_route_table_name       = "${var.project_name}-private-rt"
  nat_gateway_name               = "${var.project_name}-natgw"
  # The load balancer controller discovers subnets by these tags even for an ALB it adopts, and a scheme that
  # matches no tag fails with "couldn't auto-discover subnets" (rules.md G-1). The internal ALB lives in the
  # private tier.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name = var.key_name

  # Nothing here reads a network output, but every module in a root with a network module waits for all of
  # it (rules.md D-3).
  depends_on = [module.network]
}

# --- Cluster ---------------------------------------------------------------------------------------------

# The blueprint's GenericClusterProvider, minus its mastersRole: that was an IAM role any principal in the
# account could assume to become system:masters. Access here is granted by access entries - the identity
# running terraform as the cluster creator, and the workbench below (rules.md C-1).
module "eks_cluster" {
  source = "./modules/eks_cluster"

  name                   = var.cluster_name
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  depends_on = [module.network]
}
# vpc-cni, kube-proxy and the Pod Identity agent are DaemonSets, so they reach ACTIVE with zero nodes, and
# a node cannot join Ready without the first two (rules.md C-4).
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  depends_on = [module.network, module.eks_cluster]
}
# How the load balancer controller and the ComfyUI pod get their AWS credentials (rules.md C-4).
module "eks_pod_identity_agent_addon" {
  source = "./modules/eks_pod_identity_agent_addon"

  cluster_name = module.eks_cluster.cluster_name

  depends_on = [module.network, module.eks_cluster]
}
# The blueprint's comfyui-on-eks-mng-lw: the CPU nodes the cluster's own controllers run on.
module "eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name    = module.eks_cluster.cluster_name
  node_group_name = var.core_node_group_name
  instance_types  = var.core_node_instance_types
  desired_size    = var.core_node_desired_size
  min_size        = var.core_node_min_size
  max_size        = var.core_node_max_size
  key_name        = module.key_pair.key_name
  subnet_ids      = module.network.private_subnet_ids
  instance_tags = {
    Name = "${var.project_name}-lw-node"
  }

  depends_on = [module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}
# coredns is a Deployment, so it needs schedulable capacity to leave DEGRADED (rules.md C-4).
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name          = module.eks_cluster.cluster_name
  coredns_replica_count = var.coredns_replica_count

  depends_on = [module.network, module.eks_node_group]
}

# --- Controllers -----------------------------------------------------------------------------------------

# Not converted: the blueprint's SSMAgentAddOn. It ran a privileged DaemonSet that installed the SSM agent on
# every node from a 2022 image; EKS-optimized Amazon Linux AMIs ship the agent already, and the node roles
# carry AmazonSSMManagedInstanceCore - which is all the model sync Lambda and the patch association need.

module "karpenter" {
  source = "./modules/karpenter"

  cluster_name      = module.eks_cluster.cluster_name
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  chart_version     = var.karpenter_chart_version
  replica_count     = var.karpenter_replica_count

  # The controller runs on the core nodes and needs DNS to reach the EKS and EC2 APIs. Neither is expressed
  # by a value reference (rules.md D-2).
  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}
# The blueprint's manifests/Karpenter/karpenter_v1.yaml: one pool, g6.2xlarge or g5.2xlarge, spot first.
module "gpu_node_pool" {
  source = "./modules/karpenter_node_pool"

  name               = var.gpu_node_pool_name
  node_iam_role_name = module.karpenter.node_role_name
  subnet_ids         = module.network.private_subnet_ids
  security_group_ids = [module.eks_cluster.cluster_security_group_id]
  instance_families  = var.gpu_instance_families
  instance_sizes     = var.gpu_instance_sizes
  capacity_types     = var.gpu_capacity_types
  node_labels        = var.gpu_node_labels
  # For an al2023 alias Karpenter resolves the NVIDIA variant of the EKS AMI on a GPU instance, which is why
  # the GPU operator below is told not to install a driver or a toolkit.
  ami_alias = "al2023@latest"
  block_device_mappings = [{
    device_name = "/dev/xvda"
    volume_size = var.gpu_root_volume_size
    volume_type = "gp3"
  }]
  # No instance store policy: the user data formats the instance store for the models itself, and RAID0 would
  # hand the same disk to containerd.
  user_data = local.gpu_node_user_data
  # One, as the blueprint's metadataOptions had it. The ComfyUI pod has Pod Identity credentials of its own and
  # has no reason to reach the node role through the instance metadata service.
  metadata_hop_limit  = 1
  detailed_monitoring = false
  cpu_limit           = var.gpu_node_pool_cpu_limit
  # Derived from the CPU ceiling at twice the 4 GiB per vCPU a g5 or g6 has, so the CPU limit is always the
  # one that binds and there is a single number to reason about.
  memory_limit         = "${var.gpu_node_pool_cpu_limit * 8}Gi"
  consolidation_policy = var.gpu_consolidation_policy
  consolidate_after    = var.gpu_consolidate_after
  node_expire_after    = var.gpu_node_expire_after
  disruption_budgets   = var.gpu_disruption_budgets
  node_tags = {
    Name    = "${var.project_name}-gpu-node"
    Project = var.project_name
  }

  # The CRDs these instantiate ship with the Karpenter chart, and destroy has to remove the pool while the
  # controller is still there to drain it - so the module waits on the release, stated here rather than
  # injected into the module (rules.md D-2/D-4).
  depends_on = [module.network, module.karpenter]
}
# What GPU nodes read their boot models and the sync Lambda's copies with. The blueprint added the same
# inline policy (S3ModelsReadAccess) to the Karpenter node role from deploy_infra.sh. It joins the Karpenter
# module's role and the models bucket, so it lives in the root (rules.md C-1).
resource "aws_iam_role_policy" "gpu_node_models_read" {
  name = "models-read"
  role = module.karpenter.node_role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${module.s3_bucket["models"].bucket_arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [module.s3_bucket["models"].bucket_arn]
      },
    ]
  })
}
module "nvidia_gpu_operator" {
  source = "./modules/nvidia_gpu_operator"

  chart_version         = var.gpu_operator_chart_version
  device_plugin_version = var.gpu_operator_device_plugin_version
  # GPU Feature Discovery ships from the device plugin's image, so the two stay on one version.
  gfd_version = var.gpu_operator_device_plugin_version

  # The operator itself runs on the core nodes; its per-GPU DaemonSets wait for GPU nodes to exist.
  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}
module "aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"

  cluster_name                   = module.eks_cluster.cluster_name
  vpc_id                         = module.network.vpc_id
  aws_region                     = local.region
  chart_version                  = var.load_balancer_controller_chart_version
  enable_backend_security_group  = var.enable_backend_security_group
  enable_service_mutator_webhook = var.enable_service_mutator_webhook

  # The controller authenticates through Pod Identity, so the agent has to be running before its pods start.
  depends_on = [
    module.network,
    module.eks_node_group,
    module.eks_coredns_addon,
    module.eks_pod_identity_agent_addon,
  ]
}

# --- Storage ---------------------------------------------------------------------------------------------

module "s3_bucket" {
  source   = "./modules/s3_bucket"
  for_each = local.buckets

  bucket_name     = each.value.name
  force_destroy   = var.bucket_force_destroy
  expiration_days = each.value.expiration_days
  tags = {
    Project = var.project_name
  }

  depends_on = [module.network]
}
# S3 server access logging for the models bucket, as the blueprint configured it (serverAccessLogsBucket with
# the models-bucket/ prefix). The log bucket admits the logging service by bucket policy, which is the only
# way left once ACLs are disabled. Both halves join two buckets, so they are declared here (rules.md C-1).
resource "aws_s3_bucket_policy" "models_access_logs" {
  bucket = module.s3_bucket["models_access_logs"].bucket_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "S3ServerAccessLogsPolicy"
      Effect    = "Allow"
      Principal = { Service = "logging.s3.amazonaws.com" }
      Action    = "s3:PutObject"
      Resource  = "${module.s3_bucket["models_access_logs"].bucket_arn}/*"
      Condition = {
        ArnLike      = { "aws:SourceArn" = module.s3_bucket["models"].bucket_arn }
        StringEquals = { "aws:SourceAccount" = local.account_id }
      }
    }]
  })

  # The module's public access block and ownership controls are applied to the same bucket, and S3 rejects a
  # policy write that races them with OperationAborted. Referencing the bucket name alone does not wait for
  # them (rules.md D-1).
  depends_on = [module.s3_bucket]
}
resource "aws_s3_bucket_logging" "models" {
  bucket        = module.s3_bucket["models"].bucket_name
  target_bucket = module.s3_bucket["models_access_logs"].bucket_name
  target_prefix = "models-bucket/"

  # S3 checks that it may write to the target when logging is enabled (rules.md D-1).
  depends_on = [aws_s3_bucket_policy.models_access_logs]
}
# The blueprint's S3CSIDriverAddOn, as the EKS add-on rather than its Helm chart (rules.md C-4), with the
# driver's role scoped to the inputs and outputs buckets as the blueprint's bucketNames was.
module "eks_mountpoint_s3_csi_driver_addon" {
  source = "./modules/eks_mountpoint_s3_csi_driver_addon"

  cluster_name      = module.eks_cluster.cluster_name
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  addon_version     = var.mountpoint_s3_csi_driver_addon_version
  bucket_arns       = [module.s3_bucket["inputs"].bucket_arn, module.s3_bucket["outputs"].bucket_arn]
  allow_delete      = true

  # The add-on runs a node DaemonSet and needs nodes to report ACTIVE; ordering it after the node group also
  # keeps it alive on destroy until the volumes are unmounted (rules.md D-4).
  depends_on = [module.network, module.eks_node_group]
}

# --- Models ----------------------------------------------------------------------------------------------

module "model_download" {
  source = "./modules/model_download"

  buildspec             = file("${path.module}/buildspec/models.yml")
  models_bucket_name    = module.s3_bucket["models"].bucket_name
  models_bucket_arn     = module.s3_bucket["models"].bucket_arn
  model_tier            = var.model_download_tier
  build_timeout_minutes = var.model_download_timeout_minutes
  log_retention_days    = var.log_retention_days

  depends_on = [module.network]
}
# Starts the model download and returns without waiting for it.
#
# Not the build action the image uses below, and that difference is the point: an action is synchronous, and
# even triggered after its resource it still runs inside the apply, so the apply would last as long as the
# download - hours for the full set. The blueprint ran this download in the background for the same reason.
# Nothing in this configuration needs the models to have arrived: a GPU node copies what is in the bucket when
# it boots, and the sync Lambda copies the rest onto it as each file lands.
module "model_download_trigger" {
  source = "./modules/codebuild_start_trigger"

  name                 = "${var.project_name}-model-download-trigger"
  source_dir           = "${path.module}/lambda_src/trigger_function"
  project_name         = module.model_download.project_name
  project_arn          = module.model_download.project_arn
  start_build_on_apply = var.start_model_download_on_apply
  log_retention_days   = var.log_retention_days
  # A changed model list or tier starts a new download on the next apply (rules.md B-5).
  build_revision = module.model_download.build_revision

  depends_on = [module.network, module.model_download]
}
module "models_sync_lambda" {
  source = "./modules/models_sync_lambda"

  source_dir         = "${path.module}/lambda_src/model_sync"
  models_bucket_name = module.s3_bucket["models"].bucket_name
  models_bucket_arn  = module.s3_bucket["models"].bucket_arn
  node_models_path   = var.models_host_path
  cluster_name       = module.eks_cluster.cluster_name
  node_pool_name     = module.gpu_node_pool.name
  log_retention_days = var.log_retention_days

  depends_on = [module.network]
}
# What invokes the sync function, as the blueprint's S3EventSource did: every object created in or removed from
# the models bucket. It joins the bucket and the function (rules.md C-1).
resource "aws_s3_bucket_notification" "models" {
  bucket = module.s3_bucket["models"].bucket_name

  lambda_function {
    lambda_function_arn = module.models_sync_lambda.function_arn
    events              = ["s3:ObjectCreated:*", "s3:ObjectRemoved:*"]
  }

  # S3 test-invokes the function when the configuration is written and rejects it if the permission is not
  # there yet; the function ARN alone does not order this after the permission (rules.md D-1).
  depends_on = [module.models_sync_lambda, module.s3_bucket]
}

# --- Image -----------------------------------------------------------------------------------------------

# The build context, zipped for upload. A root-level data source so it is read at plan time, while the module
# that uploads it is ordered after the network (rules.md D-6).
data "archive_file" "comfyui_image_source" {
  type        = "zip"
  source_dir  = local.comfyui_image_dir
  output_path = "${path.module}/build/comfyui-image-source.zip"
}
module "comfyui_image" {
  source = "./modules/comfyui_image"

  image_tag                   = var.image_tag
  force_delete                = var.ecr_force_delete
  compute_type                = var.image_build_compute_type
  build_timeout_minutes       = var.image_build_timeout_minutes
  log_retention_days          = var.log_retention_days
  source_bucket_name          = module.s3_bucket["build_source"].bucket_name
  source_bucket_arn           = module.s3_bucket["build_source"].bucket_arn
  source_zip_path             = data.archive_file.comfyui_image_source.output_path
  source_zip_hash             = local.comfyui_image_source_hash
  rebuild_schedule_expression = var.image_rebuild_schedule

  depends_on = [module.network]
}
# Builds the image during the apply, and holds everything that needs it until the build has pushed.
#
# A build is not infrastructure, so there is no resource for it; the aws_codebuild_start_build action starts
# one and waits for it to finish. It is fired before_create and before_update deliberately: with those events
# the trigger resource completes only after the action does, so the ComfyUI workload - which depends on the
# trigger - is not created against an empty repository. With after_create the trigger completes first and
# dependents start while the build is still running (hashicorp/terraform-provider-aws#46484).
#
# input is the build context's hash, so the build runs on the first apply and again whenever the Dockerfile
# or a custom node changes - and the same hash, written into the pod template, rolls the pods onto the new
# image. A failed build fails the apply with the build's status.
action "aws_codebuild_start_build" "comfyui_image" {
  config {
    project_name = module.comfyui_image.project_name
    # The project's own timeout plus a margin for the build to be queued and provisioned, so the action
    # never gives up on a build CodeBuild is still allowed to run (rules.md B-5).
    timeout = (module.comfyui_image.build_timeout_minutes + 15) * 60
  }
}
resource "terraform_data" "comfyui_image_build" {
  count = var.build_image_on_apply ? 1 : 0

  input = local.comfyui_image_source_hash

  lifecycle {
    action_trigger {
      events  = [before_create, before_update]
      actions = [action.aws_codebuild_start_build.comfyui_image]
    }
  }

  # The build reads the uploaded context with the project's role, so the whole module - the object, the
  # role's policy and the repositories - has to exist before it starts (rules.md D-2).
  depends_on = [module.comfyui_image]
}

# --- Load balancer and the workload ----------------------------------------------------------------------

# The internal ALB's frontend group. It admits CloudFront through the origin-facing prefix list, which is how
# the VPC origin arrives, and the workbench, so the ALB can be tried from the IDE terminal without CloudFront
# in the path (rules.md G-1).
module "alb_security_group" {
  source = "./modules/load_balancer_security_group"

  vpc_id      = module.network.vpc_id
  name        = var.alb_security_group_name
  description = "Frontend security group for the internal ALB in front of ComfyUI, reached by CloudFront through a VPC origin"
  ports = {
    http = var.alb_listener_port
  }
  ingress_prefix_lists = {
    cloudfront = data.aws_ec2_managed_prefix_list.cloudfront_origin_facing.id
  }
  # A map with a literal key, because the ID is another module's output (rules.md B-8).
  ingress_source_security_groups = {
    vscode_ec2 = module.vscode_ec2.security_group_id
  }

  depends_on = [module.network]
}
# The path from the ALB to the pods. The Ingress names its own frontend group and sets no
# manage-backend-security-group-rules, so the controller writes no node-side rules at all and this is the only
# rule that lets traffic through - without it every target reports unhealthy while the ALB itself looks fine
# (rules.md G-2). target-type ip sends traffic and health checks to the container port, and pods carry the
# cluster security group. It modifies a group no module here owns outright, so it is declared in the root
# (rules.md C-1).
resource "aws_vpc_security_group_ingress_rule" "load_balancer_to_pods" {
  security_group_id            = module.eks_cluster.cluster_security_group_id
  description                  = "ComfyUI port from the internal ALB frontend security group"
  ip_protocol                  = "tcp"
  from_port                    = var.comfyui_port
  to_port                      = var.comfyui_port
  referenced_security_group_id = module.alb_security_group.security_group_id
}
# The ALB, created here and adopted by the controller when it reconciles the Ingress (rules.md G-3).
#
# The blueprint let the controller build it and then had its CloudFront stack look it up by tag, which is why
# that stack could only be deployed last. Created here, its ARN is known to the CloudFront VPC origin in the
# same apply.
module "comfyui_alb" {
  source = "./modules/synced_load_balancer"

  cluster_name       = module.eks_cluster.cluster_name
  load_balancer_type = "application"
  # internal, as the blueprint's scheme: internal annotation - which has to agree with the Ingress below, or
  # the controller builds a second ALB instead of adopting this one (rules.md G-3).
  internal            = true
  subnet_ids          = module.network.private_subnet_ids
  security_group_ids  = [module.alb_security_group.security_group_id]
  resource_tag_prefix = "ingress"
  stack               = local.comfyui_stack_tag
  idle_timeout        = var.alb_idle_timeout_seconds
  additional_tags = {
    Project = var.project_name
  }

  depends_on = [module.network]
}
module "comfyui_workload" {
  source = "./modules/comfyui_workload"

  cluster_name     = module.eks_cluster.cluster_name
  account_id       = local.account_id
  partition        = data.aws_partition.current.partition
  region           = local.region
  namespace        = var.comfyui_namespace
  ingress_name     = var.comfyui_ingress_name
  container_port   = var.comfyui_port
  replicas         = var.comfyui_replicas
  image            = module.comfyui_image.image_uri
  image_revision   = local.comfyui_image_source_hash
  node_selector    = module.gpu_node_pool.node_labels
  models_host_path = var.models_host_path
  rollout_timeout  = var.comfyui_rollout_timeout

  models_bucket_arn   = module.s3_bucket["models"].bucket_arn
  inputs_bucket_name  = module.s3_bucket["inputs"].bucket_name
  outputs_bucket_name = module.s3_bucket["outputs"].bucket_name
  outputs_bucket_arn  = module.s3_bucket["outputs"].bucket_arn
  s3_csi_driver       = module.eks_mountpoint_s3_csi_driver_addon.driver
  allow_delete        = module.eks_mountpoint_s3_csi_driver_addon.allow_delete

  # The blueprint's Ingress annotations, plus the two that tie it to the pre-created ALB: the frontend group
  # the ALB was created with, and an explicit listener port so the group, the listener and the CloudFront
  # origin are one number rather than the controller's default (rules.md B-5/G-1).
  ingress_annotations = {
    "alb.ingress.kubernetes.io/scheme"                   = "internal"
    "alb.ingress.kubernetes.io/target-type"              = "ip"
    "alb.ingress.kubernetes.io/listen-ports"             = jsonencode([{ HTTP = var.alb_listener_port }])
    "alb.ingress.kubernetes.io/security-groups"          = module.alb_security_group.security_group_id
    "alb.ingress.kubernetes.io/target-group-attributes"  = "stickiness.enabled=true,stickiness.lb_cookie.duration_seconds=${var.alb_stickiness_duration_seconds}"
    "alb.ingress.kubernetes.io/load-balancer-attributes" = "idle_timeout.timeout_seconds=${module.comfyui_alb.idle_timeout}"
    "alb.ingress.kubernetes.io/tags"                     = "Project=${var.project_name}"
  }

  # Where traffic to the pods comes from: the subnets the ALB was given (rules.md B-5).
  network_policy_ingress_cidr_blocks = module.network.private_subnet_cidr_blocks
  network_policy_dns_cidr_block      = module.network.vpc_cidr_block

  # Everything the first rollout needs: a GPU pool to land on, a device plugin to advertise the GPU, the CSI
  # driver for the volumes, the Pod Identity agent for the pod's credentials, the node role's read access to
  # the boot models, an image in ECR, and - before the Ingress - the controller and the ALB it will adopt.
  #
  # Ordering the module after these is also what makes destroy remove ComfyUI while they are still alive: the
  # Ingress before the controller that holds its finalizer, the pods before the driver that unmounts their
  # volumes, the pool's nodes after the pods on them (rules.md D-4/D-7).
  depends_on = [
    module.network,
    module.gpu_node_pool,
    module.nvidia_gpu_operator,
    module.aws_load_balancer_controller,
    module.eks_mountpoint_s3_csi_driver_addon,
    module.eks_pod_identity_agent_addon,
    module.comfyui_alb,
    aws_iam_role_policy.gpu_node_models_read,
    aws_vpc_security_group_ingress_rule.load_balancer_to_pods,
    terraform_data.comfyui_image_build,
  ]
}
# The public entry point, through a VPC origin to the internal ALB.
#
# After the workload rather than beside it, for destroy's sake: removing the Ingress makes the controller
# delete the ALB it adopted, and the ALB is not free to go while a VPC origin still points at it. Depending on
# the workload puts the distribution and its origin first in the destroy and the Ingress after them - the
# reverse of how they were built (rules.md D-4).
module "cloudfront" {
  source = "./modules/cloudfront_vpc_origin"

  name                     = var.project_name
  origin_arn               = module.comfyui_alb.arn
  origin_domain_name       = module.comfyui_alb.dns_name
  http_port                = var.alb_listener_port
  cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
  origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id
  price_class              = var.cloudfront_price_class

  depends_on = [module.network, module.comfyui_workload]
}

# --- Account-level and node-level settings ---------------------------------------------------------------

# deploy_infra.sh's configure_ssm_patching: AWS-RunPatchBaseline in Install mode with NoReboot, daily, on every
# instance tagged kubernetes.io/cluster/<cluster>=owned - which both the managed node group and Karpenter write,
# so GPU nodes launched later are enrolled as they boot. apply_only_at_cron_interval is false, so it also runs
# once on creation, which is what the blueprint's start-associations-once call did.
resource "aws_ssm_association" "node_patching" {
  count = var.enable_node_patching ? 1 : 0

  name                        = "AWS-RunPatchBaseline"
  association_name            = "${var.project_name}-nodes-autopatch"
  schedule_expression         = var.node_patching_schedule
  apply_only_at_cron_interval = false
  sync_compliance             = "AUTO"
  parameters = {
    Operation    = "Install"
    RebootOption = "NoReboot"
  }
  targets {
    key    = "tag:kubernetes.io/cluster/${module.eks_cluster.cluster_name}"
    values = ["owned"]
  }

  depends_on = [module.eks_node_group]
}
# Off by default. The blueprint enabled Inspector for ECR and switched the registry to enhanced continuous
# scanning; both are account-wide switches rather than resources of this project, so creating them here would
# also mean terraform destroy turning them off for every other repository in the account.
resource "aws_inspector2_enabler" "ecr" {
  count = var.enable_enhanced_ecr_scanning ? 1 : 0

  account_ids    = [local.account_id]
  resource_types = ["ECR"]
}
resource "aws_ecr_registry_scanning_configuration" "enhanced" {
  count = var.enable_enhanced_ecr_scanning ? 1 : 0

  scan_type = "ENHANCED"
  rule {
    scan_frequency = "CONTINUOUS_SCAN"
    repository_filter {
      filter      = "*"
      filter_type = "WILDCARD"
    }
  }

  depends_on = [aws_inspector2_enabler.ecr]
}

# --- Workbench -------------------------------------------------------------------------------------------

# The workbench is the _monolithic template's own resource, kept as the console for the cluster. It is Amazon
# Linux 2023 now rather than the template's Ubuntu 24.04: Ubuntu was chosen because the blueprint's
# env_prepare.sh, which ran on this instance, was written for apt and /home/ubuntu. Nothing runs that script
# any more, and on AL2023 this module, its tooling and its README association are the ones every other EKS
# project here uses (rules.md H-1/H-2).
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name                        = var.instance_name
  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_ids_by_zone[var.availability_zone_suffixes[0]]
  key_name                    = module.key_pair.key_name
  instance_type               = var.instance_type
  root_volume_size            = var.root_volume_size
  code_server_version         = var.code_server_version
  security_group_name         = var.security_group_name
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  marker_file_path            = var.marker_file_path
  # The cluster security group is what lets kubectl here reach the API server without leaving the VPC. The
  # module is handed an ID list and never learns what it belongs to (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]
  # An EKS cluster and this instance share a root module, so this is the workbench for that cluster and
  # carries all five tools (rules.md H-1). None of them creates anything - every object is a provider resource
  # (rules.md E-1).
  additional_user_data = <<-EOT
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server is already running and predates the docker group, so its terminals would not have it
    # without a restart.
    systemctl restart code-server
    sudo -Eu ec2-user bash << 'EOF'
    export HOME=/home/ec2-user
    cd /home/ec2-user
    mkdir -p /home/ec2-user/bin
    curl -sO https://s3.us-west-2.amazonaws.com/amazon-eks/${var.kubectl_download_version}/bin/linux/amd64/kubectl
    chmod +x kubectl
    mv kubectl /home/ec2-user/bin/kubectl
    export PATH=/home/ec2-user/bin:$PATH
    echo 'export PATH=/home/ec2-user/bin:$PATH' >> ~/.bashrc
    # bash_completion has to be sourced before kubectl's own completion, which defines __start_kubectl, and
    # that function has to exist before complete references it (rules.md H-1).
    echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
    echo 'source <(kubectl completion bash)' >> ~/.bashrc
    echo 'alias k=kubectl' >> ~/.bashrc
    echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
    PLATFORM=$(uname -s)_amd64
    curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
    tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
    sudo install -m 0755 /tmp/eksctl /usr/local/bin && rm /tmp/eksctl
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm -f get_helm.sh
    aws configure set default.region ${local.region}
    # Without this - and without the access entry below - kubectl is installed but every command answers
    # "You must be logged in to the server" (rules.md H-1).
    aws eks update-kubeconfig --region ${local.region} --name ${module.eks_cluster.cluster_name}
    EOF
  EOT

  depends_on = [module.network]
}
# Granting the workbench's role cluster access joins two modules that know nothing about each other
# (rules.md C-1).
resource "aws_eks_access_entry" "vscode_access_entry" {
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.vscode_ec2.iam_role_arn
  type          = "STANDARD"
}
resource "aws_eks_access_policy_association" "vscode_access_policy_association" {
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.vscode_ec2.iam_role_arn
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }

  # EKS rejects a policy association for a principal with no access entry yet, and the two share only literal
  # argument values (rules.md D-1).
  depends_on = [aws_eks_access_entry.vscode_access_entry]
}

# --- Outputs and the README ------------------------------------------------------------------------------

locals {
  # Every output this project exposes, defined once. outputs.tf projects these and the README below renders
  # them, so no value expression is written twice (rules.md B-5/H-2).
  outputs = {
    vscode_port_forward_command = {
      order       = 0
      title       = "Connect to code-server through SSM"
      description = "Run this on your own machine rather than here: it needs the AWS CLI and the Session Manager plugin installed locally, and it keeps running until you stop it. While it runs, http://localhost:${module.vscode_ec2.code_server_port} is this IDE. The tunnel rides the SSM agent's own outbound connection, so the security group needs no inbound rule for it. SessionManagerPlugin is not found means the plugin is missing locally; TargetNotConnected means the agent on the instance has not registered with Systems Manager"
      value       = "aws ssm start-session --region ${local.region} --target ${module.vscode_ec2.instance_id} --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"${module.vscode_ec2.code_server_port}\"],\"localPortNumber\":[\"${module.vscode_ec2.code_server_port}\"]}'"
    }
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here once the port forward above is running, and run the commands below from its terminal. The editor has no authentication and the instance role behind it is AdministratorAccess, which is why it is on the instance's public address only when allow_inbound_from_anywhere is set"
      value       = var.allow_inbound_from_anywhere ? module.vscode_ec2.vscode_url : "http://localhost:${module.vscode_ec2.code_server_port}"
    }
    comfyui_url = {
      order       = 2
      title       = "ComfyUI"
      description = "ComfyUI through CloudFront and the VPC origin. It answers once the ComfyUI pod is Running - the apply waits for that. There is no authentication in front of it, as in the blueprint: anyone with this URL can queue work on the GPU node, so do not leave it up longer than you need it"
      value       = module.cloudfront.url
    }
    cluster_name = {
      order       = 3
      title       = "EKS cluster name"
      description = "Name of the EKS cluster. Karpenter tags every GPU instance with it, and the model sync Lambda finds the nodes by that tag"
      value       = module.eks_cluster.cluster_name
    }
    image_build_status_command = {
      order       = 4
      title       = "1. The image build"
      description = "The apply already waited for this build. Worth reading when it failed - the status and phase say where - and after a weekly rebuild"
      value       = module.comfyui_image.build_status_command
    }
    model_download_status_command = {
      order       = 5
      title       = "2. The model download"
      description = "Started by the apply and not waited for: the full set is several hundred gigabytes and takes hours. ComfyUI works before it finishes - the default workflow's models come first, and every file is copied onto the running GPU node as it lands"
      value       = module.model_download.build_status_command
    }
    models_in_bucket_command = {
      order       = 6
      title       = "3. What has landed in the models bucket"
      description = "Total objects and size so far. The access logs for this bucket go to a separate bucket, so they do not show up here"
      value       = "aws s3 ls s3://${module.s3_bucket["models"].bucket_name}/ --recursive --summarize --human-readable | tail -2"
    }
    gpu_nodes_command = {
      order       = 7
      title       = "4. The GPU node"
      description = "Karpenter launches a g6 or g5 2xlarge once the ComfyUI pod is pending, spot when it can. Nothing here means the pod is not pending yet, or the pool cannot find capacity - the Karpenter log below says which"
      value       = "kubectl get nodes -L node.kubernetes.io/instance-type,karpenter.sh/capacity-type,karpenter.sh/nodepool"
    }
    gpu_capacity_command = {
      order       = 8
      title       = "5. The GPU is advertised"
      description = "The GPU operator's device plugin is what turns a GPU node into nvidia.com/gpu capacity. <none> on a GPU node means the plugin is not running there yet"
      value       = module.nvidia_gpu_operator.advertised_gpu_command
    }
    comfyui_pods_command = {
      order       = 9
      title       = "6. The ComfyUI pod"
      description = "Pending is GPU capacity or the device plugin; ImagePullBackOff is the image, which the build status above explains"
      value       = module.comfyui_workload.pods_command
    }
    comfyui_logs_command = {
      order       = 10
      title       = "7. ComfyUI's log"
      description = "Where a missing model, an auto model download and an S3 upload of a result show up"
      value       = module.comfyui_workload.logs_command
    }
    alb_dns_name = {
      order       = 11
      title       = "Pre-created ALB"
      description = "The internal ALB Terraform created and the load balancer controller adopted. Known from state, which is what lets CloudFront point at it in the same apply"
      value       = module.comfyui_alb.dns_name
    }
    alb_stack_tag = {
      order       = 12
      title       = "Adoption stack tag"
      description = "The ingress.k8s.aws/stack value the ALB carries. The controller adopts it only when this matches the Ingress's namespace/name - a mismatch makes it build a second ALB instead (rules.md G-3)"
      value       = module.comfyui_alb.stack
    }
    ingress_address_command = {
      order       = 13
      title       = "8. The Ingress is on the pre-created ALB"
      description = "Should print the pre-created ALB's DNS name above. A different name means the ALB was not adopted, and CloudFront is pointing at a load balancer with no listener"
      value       = module.comfyui_workload.load_balancer_hostname_command
    }
    comfyui_port_forward_command = {
      order       = 14
      title       = "ComfyUI without CloudFront or the ALB"
      description = "From this IDE's terminal: forwards the Service to localhost:${var.comfyui_port} on the workbench, which tells a problem in the pod apart from one in front of it"
      value       = module.comfyui_workload.port_forward_command
    }
    model_sync_logs_command = {
      order       = 15
      title       = "The model sync Lambda"
      description = "Each model it saw land, and the GPU instances it sent the copy to"
      value       = module.models_sync_lambda.recent_logs_command
    }
    karpenter_log_command = {
      order       = 16
      title       = "Karpenter's log"
      description = "Where an unschedulable pod is explained - no capacity for the instance types, a limit reached, or a subnet without capacity"
      value       = "kubectl -n ${module.karpenter.namespace} logs deploy/${module.karpenter.release_name} --tail 100"
    }
    controller_log_command = {
      order       = 17
      title       = "The load balancer controller's log"
      description = "Where to look if the Ingress never gets an address, or the ALB was not adopted"
      value       = "kubectl -n ${module.aws_load_balancer_controller.namespace} logs deploy/${module.aws_load_balancer_controller.release_name} --tail 100"
    }
    rebuild_image_command = {
      order       = 18
      title       = "Rebuild the image by hand"
      description = "Changing anything under comfyui_image/ and applying rebuilds and rolls out on its own; this is for picking up base image patches between the weekly rebuilds. Running pods keep their image until they restart"
      value       = module.comfyui_image.start_build_command
    }
    update_kubeconfig_command = {
      order       = 19
      title       = "Re-point kubectl"
      description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${local.region} --name ${module.eks_cluster.cluster_name}"
    }
    teardown_command = {
      order       = 20
      title       = "Tearing this down"
      description = "One terraform destroy removes everything, CloudFront first and the VPC last, and takes a while - the distribution has to be disabled before it can be deleted. With bucket_force_destroy true, which is the default, it deletes every generated image in the outputs bucket and every model in the models bucket along with the buckets. If the VPC's deletion reports DependencyViolation, CloudFront's service-managed network interfaces for the VPC origin are still being released; run destroy again a few minutes later"
      value       = "terraform destroy   # from your own machine, in this directory"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the order field and taking
  # values() sorts by that instead, so the README reads in the order the checks are run.
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
# The work happens inside code-server in a browser, where terraform output is not available, so every output
# above is also written to a README in the home directory the IDE opens (rules.md H-2).
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on, is what orders this after the instance bootstrap (rules.md D-5), and the
    # marker path comes back out of the module it was passed into (rules.md B-5). SSM runs as root, hence the
    # chown. The heredoc delimiter is quoted, so the shell leaves the "$" and backticks in the commands alone.
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/userdata ]; do sleep 10; done
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_readme
      EOT
  }
}
