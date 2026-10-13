variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. Null falls through to the provider chain (AWS_REGION / AWS_DEFAULT_REGION). The region has to offer g5 or g6 capacity in the zones below, and Bedrock for the image's Bedrock nodes - whose default model IDs are US cross-region inference profiles"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", coalesce(var.aws_region, "xx-none-0")))
    error_message = "aws_region must be a valid AWS region name (e.g. ap-northeast-2), or null."
  }
}
variable "project_name" {
  type        = string
  default     = "comfyui-on-eks"
  description = "Prefix for resource names that have to be unique inside the account, and the title of the README written onto the workbench. comfyui-on-eks, the Project tag the blueprint put on everything"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 3-32 lowercase letters, digits or hyphens and must not start or end with a hyphen."
  }
}
variable "log_retention_days" {
  type        = number
  default     = 14
  description = "How long the build and Lambda logs are kept"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of the retention periods CloudWatch Logs accepts."
  }
}

# --- Network ---

variable "vpc_cidr_block" {
  type        = string
  default     = "10.2.0.0/16"
  description = "CIDR block of the VPC, 10.2.0.0/16 as the blueprint's ComfyuiVPC had it"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block."
  }
}
variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "c", "d"]
  description = "Availability zones the subnets are placed in, by suffix. Three, as the blueprint's maxAzs: 3 - named here rather than taken as the region's first three, so the zones are in the plan. These are also the only zones Karpenter can put a GPU node in"

  validation {
    condition     = length(var.availability_zone_suffixes) >= 2
    error_message = "availability_zone_suffixes must name at least two zones, because an EKS cluster requires subnets in two."
  }
}
variable "nat_availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "c", "d"]
  description = "Zones the regional NAT gateway has an address in. Every zone, which is what the blueprint's three NAT gateways amounted to: no private subnet takes a cross-zone hop to get out"

  validation {
    # The pair is what can be wrong (rules.md B-1).
    condition     = length(setsubtract(var.nat_availability_zone_suffixes, var.availability_zone_suffixes)) == 0
    error_message = "nat_availability_zone_suffixes must be drawn from availability_zone_suffixes; an address in a zone with no subnet routes nothing."
  }
}

# --- EKS cluster ---

variable "cluster_name" {
  type        = string
  default     = "ComfyUI-on-EKS-Cluster"
  description = "Name of the EKS cluster, ComfyUI-on-EKS-Cluster as the blueprint named it. Karpenter tags every GPU instance with it (eks:eks-cluster-name), which is how the model sync Lambda finds them, and the pre-created ALB carries it as elbv2.k8s.aws/cluster"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,99}$", var.cluster_name))
    error_message = "cluster_name must start with a letter or digit and contain only letters, digits, hyphens and underscores."
  }
}
variable "kubernetes_version" {
  type        = string
  default     = "1.35"
  description = "EKS Kubernetes version, 1.35 as the blueprint's KubernetesVersion.V1_35. Keep kubectl_download_version within one minor of this"

  validation {
    condition     = can(regex("^1\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must look like 1.XX; the cluster module holds the list of versions it accepts."
  }
}
variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the cluster's API server has a public endpoint. True and pinned true, because every Kubernetes object and Helm release here is applied by providers running on the machine executing terraform (rules.md E-9)"

  validation {
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this project, because its manifests and Helm releases are applied by the kubectl and helm providers from the machine running terraform. To run with a private endpoint, apply them from the workbench through SSM Associations instead, as 041_eks_private_cluster does."
  }
}
variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDRs allowed to reach the public API server endpoint. Narrow this to the address you run terraform from for anything longer lived than a demo"

  validation {
    condition     = length(var.public_access_cidrs) > 0 && alltrue([for cidr in var.public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "public_access_cidrs must contain at least one valid IPv4 CIDR block."
  }
}
variable "coredns_replica_count" {
  type        = number
  default     = 2
  description = "Number of CoreDNS replicas"

  validation {
    condition     = var.coredns_replica_count >= 1
    error_message = "coredns_replica_count must be at least 1."
  }
}

# --- Core managed node group ---

variable "core_node_group_name" {
  type        = string
  default     = "comfyui-on-eks-mng-lw"
  description = "Name of the managed node group that runs the cluster's own controllers - Karpenter, the load balancer controller, the GPU operator - as the blueprint's comfyui-on-eks-mng-lw. Karpenter runs here because a controller that provisions nodes cannot depend on the nodes it provisions"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,62}$", var.core_node_group_name))
    error_message = "core_node_group_name must start with a letter or digit and contain only letters, digits, hyphens and underscores."
  }
}
variable "core_node_instance_types" {
  type        = list(string)
  default     = ["t3a.xlarge"]
  description = "Instance types for the core node group, t3a.xlarge as the blueprint had it"

  validation {
    condition     = length(var.core_node_instance_types) > 0 && alltrue([for t in var.core_node_instance_types : can(regex("^[a-z0-9-]+\\.[a-z0-9]+$", t))])
    error_message = "core_node_instance_types must contain at least one valid EC2 instance type."
  }
}
variable "core_node_min_size" {
  type        = number
  default     = 1
  description = "Minimum core node count, 1 as the blueprint had it"

  validation {
    condition     = var.core_node_min_size >= 1
    error_message = "core_node_min_size must be at least 1 - Karpenter itself runs on these nodes."
  }
}
variable "core_node_desired_size" {
  type        = number
  default     = 2
  description = "Desired core node count, 2 as the blueprint had it"

  validation {
    # Cross-variable, because the constraint is about the three together (rules.md B-1).
    condition     = var.core_node_desired_size >= var.core_node_min_size && var.core_node_desired_size <= var.core_node_max_size
    error_message = "core_node_desired_size must lie between core_node_min_size and core_node_max_size."
  }
}
variable "core_node_max_size" {
  type        = number
  default     = 5
  description = "Maximum core node count, 5 as the blueprint had it. Nothing scales this group automatically - Karpenter only provisions the GPU pool - so this is a ceiling for manual scaling"

  validation {
    condition     = var.core_node_max_size >= var.core_node_min_size
    error_message = "core_node_max_size must be at least core_node_min_size."
  }
}

# --- Karpenter and the GPU pool ---

variable "karpenter_chart_version" {
  type        = string
  default     = "1.9.0"
  description = "Pinned Karpenter chart version, 1.9.0 as the blueprint's KarpenterV1AddOn pinned it (rules.md E-10). The chart also installs the v1 NodePool and EC2NodeClass CRDs the GPU pool instantiates"

  validation {
    condition     = can(regex("^1\\.[0-9]+\\.[0-9]+$", var.karpenter_chart_version))
    error_message = "karpenter_chart_version must be a 1.x semantic version - the GPU pool is written against the karpenter.sh/v1 and karpenter.k8s.aws/v1 APIs those charts install."
  }
}
variable "karpenter_replica_count" {
  type        = number
  default     = 1
  description = "Karpenter controller replicas, one as the blueprint's values: { replicas: 1 }"

  validation {
    condition     = var.karpenter_replica_count >= 1
    error_message = "karpenter_replica_count must be at least 1."
  }
}
variable "gpu_node_pool_name" {
  type        = string
  default     = "karpenter-nodepool"
  description = "Name of the Karpenter NodePool and its EC2NodeClass, karpenter-nodepool as the blueprint named the pool. It is the karpenter.sh/nodepool tag on every GPU instance, which the model sync Lambda filters on - so it is handed to both from here (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.gpu_node_pool_name))
    error_message = "gpu_node_pool_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "gpu_instance_families" {
  type        = list(string)
  default     = ["g6", "g5"]
  description = "GPU instance families the pool may launch. With gpu_instance_sizes this is the blueprint's instance list, g6.2xlarge and g5.2xlarge"

  validation {
    condition     = length(var.gpu_instance_families) > 0
    error_message = "gpu_instance_families must name at least one family."
  }
}
variable "gpu_instance_sizes" {
  type        = list(string)
  default     = ["2xlarge"]
  description = "Sizes within those families. 2xlarge, as the blueprint had it: one GPU, and one local NVMe disk the node's user data formats for the models"

  validation {
    condition     = length(var.gpu_instance_sizes) > 0
    error_message = "gpu_instance_sizes must name at least one size."
  }
}
variable "gpu_capacity_types" {
  type        = list(string)
  default     = ["spot", "on-demand"]
  description = "Purchase options for the GPU nodes, both as the blueprint had it. Karpenter prefers spot. There is no interruption queue - the blueprint ran without one too - so a reclaimed spot node takes the ComfyUI pod with it and Karpenter replaces both"

  validation {
    condition     = length(var.gpu_capacity_types) > 0 && length(setsubtract(var.gpu_capacity_types, ["spot", "on-demand"])) == 0
    error_message = "gpu_capacity_types entries must be spot or on-demand, and at least one is required."
  }
}
variable "gpu_root_volume_size" {
  type        = string
  default     = "200Gi"
  description = "Root EBS volume of each GPU node, 200Gi gp3 as the blueprint's EC2NodeClass had it. It holds the ComfyUI image, which is several gigabytes; the models live on the instance store instead"

  validation {
    condition     = can(regex("^[0-9]+Gi$", var.gpu_root_volume_size))
    error_message = "gpu_root_volume_size must be a quantity in Gi, such as 200Gi."
  }
}
variable "gpu_node_pool_cpu_limit" {
  type        = number
  default     = 32
  description = "Total vCPUs the GPU pool may provision. The blueprint's pool had no limit at all. 32 is four 2xlarge nodes: one for ComfyUI, one for the replacement pod a rolling update starts beside it, and headroom - and a hard stop after that"

  validation {
    condition     = var.gpu_node_pool_cpu_limit >= 8
    error_message = "gpu_node_pool_cpu_limit must be at least 8, or not even one 2xlarge GPU node fits."
  }
}
variable "gpu_consolidation_policy" {
  type        = string
  default     = "WhenEmptyOrUnderutilized"
  description = "When Karpenter may remove a GPU node, WhenEmptyOrUnderutilized as the blueprint had it"

  validation {
    condition     = contains(["WhenEmpty", "WhenEmptyOrUnderutilized"], var.gpu_consolidation_policy)
    error_message = "gpu_consolidation_policy must be either WhenEmpty or WhenEmptyOrUnderutilized."
  }
}
variable "gpu_consolidate_after" {
  type        = string
  default     = "30m"
  description = "How long a GPU node has to stay a consolidation candidate before Karpenter acts, 30m as the blueprint had it"

  validation {
    condition     = can(regex("^[0-9]+(s|m|h)$", var.gpu_consolidate_after))
    error_message = "gpu_consolidate_after must be a duration such as 30m."
  }
}
variable "gpu_node_expire_after" {
  type        = string
  default     = "168h"
  description = "Maximum GPU node lifetime, 168h (a week) as the blueprint had it - which is also how kernel patches that need a reboot reach the nodes"

  validation {
    condition     = var.gpu_node_expire_after == "Never" || can(regex("^[0-9]+(s|m|h)$", var.gpu_node_expire_after))
    error_message = "gpu_node_expire_after must be a duration such as 168h, or Never."
  }
}
variable "gpu_disruption_budgets" {
  type        = list(string)
  default     = ["1"]
  description = "How many GPU nodes Karpenter may disrupt at once, one as the blueprint had it"

  validation {
    condition     = length(var.gpu_disruption_budgets) > 0 && alltrue([for b in var.gpu_disruption_budgets : can(regex("^[0-9]+%?$", b))])
    error_message = "gpu_disruption_budgets entries must be a node count or a percentage."
  }
}
variable "gpu_node_labels" {
  type = map(string)
  default = {
    "node-role" = "comfyui-gpu"
  }
  description = "Labels on the GPU nodes, handed to the ComfyUI pod as its nodeSelector. The blueprint's pool had none and relied on the GPU request alone; a label makes the placement explicit"

  validation {
    condition     = length(var.gpu_node_labels) > 0
    error_message = "gpu_node_labels must not be empty - it becomes the ComfyUI pod's nodeSelector."
  }
}
variable "models_host_path" {
  type        = string
  default     = "/comfyui-models"
  description = "Where the GPU node mounts its instance store and keeps the models: formatted and filled by the node's user data, written to by the sync Lambda, and mounted into the ComfyUI pod. One value for all three (rules.md B-5)"

  validation {
    condition     = can(regex("^/[A-Za-z0-9/_.-]+$", var.models_host_path)) && !strcontains(var.models_host_path, "..")
    error_message = "models_host_path must be an absolute path of plain characters - it is written into shell commands on the nodes."
  }
}
variable "gpu_node_boot_models" {
  type = list(string)
  default = [
    "diffusion_models/z_image_turbo_bf16.safetensors",
    "text_encoders/qwen_3_4b.safetensors",
    "vae/ae.safetensors",
    "upscale_models/RealESRGAN_x4plus.safetensors",
    "checkpoints/DreamShaper_8_pruned.safetensors",
    "diffusion_models/flux2_dev_fp8mixed.safetensors",
    "text_encoders/mistral_3_small_flux2_bf16.safetensors",
    "vae/full_encoder_small_decoder.safetensors",
    "loras/Flux_2-Turbo-LoRA_comfyui.safetensors",
  ]
  description = "Models every GPU node copies from the models bucket at boot, as keys in the bucket - the nine the blueprint's EC2NodeClass user data copied. A model missing from the bucket at boot is skipped and arrives later through the sync Lambda; anything not listed here is fetched on demand by the image's auto model downloader"

  validation {
    condition     = alltrue([for key in var.gpu_node_boot_models : can(regex("^[A-Za-z0-9_][A-Za-z0-9/_.-]*$", key)) && !strcontains(key, "..")])
    error_message = "gpu_node_boot_models entries must be plain object keys (letters, digits, / _ . -) - they are written into the node's boot script."
  }
}

# --- NVIDIA GPU Operator ---

variable "gpu_operator_chart_version" {
  type        = string
  default     = "v26.3.2"
  description = "Pinned gpu-operator chart version, v26.3.2 as the blueprint pinned it (rules.md E-10)"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.gpu_operator_chart_version))
    error_message = "gpu_operator_chart_version must look like v26.3.2 - NVIDIA's chart versions carry a leading v."
  }
}
variable "gpu_operator_device_plugin_version" {
  type        = string
  default     = "v0.17.0"
  description = "Device plugin version the operator deploys, v0.17.0 as the blueprint pinned it. Null takes the version the chart ships"

  validation {
    condition     = var.gpu_operator_device_plugin_version == null || can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", coalesce(var.gpu_operator_device_plugin_version, "v0.0.0")))
    error_message = "gpu_operator_device_plugin_version must look like v0.17.0, or be null."
  }
}

# --- AWS Load Balancer Controller ---

variable "load_balancer_controller_chart_version" {
  type        = string
  default     = "3.1.0"
  description = "Pinned aws-load-balancer-controller chart version, 3.1.0 as the blueprint's AwsLoadBalancerControllerAddOn installed by default (rules.md E-10). Checked with helm template against this module's values: enableBackendSecurityGroup and enableServiceMutatorWebhook still render as before"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.load_balancer_controller_chart_version))
    error_message = "load_balancer_controller_chart_version must be a three-part semantic version."
  }
}
variable "enable_backend_security_group" {
  type        = bool
  default     = false
  description = "Whether the controller uses one shared backend security group as the source of the node-side rules it writes"

  validation {
    # The Ingress names its own frontend security group and does not set manage-backend-security-group-rules,
    # so the controller writes no node-side rules and load_balancer_to_pods in main.tf is the path from the ALB
    # to the pods. That is the second row of the table in rules.md G-2, the row that requires false.
    condition     = var.enable_backend_security_group == false
    error_message = "enable_backend_security_group must be false in this project. The Ingress names its own frontend security group and does not set manage-backend-security-group-rules, so the node-side rule is declared in Terraform (load_balancer_to_pods). To let the controller manage it instead, add that annotation and set this to true (rules.md G-2)."
  }
}
variable "enable_service_mutator_webhook" {
  type        = bool
  default     = false
  description = "Whether the controller's chart installs its mservice.elbv2.k8s.aws webhook, which intercepts every Service created in the cluster"

  validation {
    condition     = var.enable_service_mutator_webhook == false
    error_message = "enable_service_mutator_webhook must stay false in this project. No Service here is of type LoadBalancer, so the webhook serves nothing, while its failurePolicy: Fail rejects every Service created while the controller has no Ready pod - including the GPU operator's (rules.md G-4)."
  }
}

# --- Storage ---

variable "mountpoint_s3_csi_driver_addon_version" {
  type        = string
  default     = null
  description = "aws-mountpoint-s3-csi-driver add-on version, or null for the version EKS marks default for the cluster's Kubernetes version"

  validation {
    condition     = var.mountpoint_s3_csi_driver_addon_version == null || can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+-eksbuild\\.[0-9]+$", coalesce(var.mountpoint_s3_csi_driver_addon_version, "v0.0.0-eksbuild.0")))
    error_message = "mountpoint_s3_csi_driver_addon_version must look like v2.0.0-eksbuild.1, or be null."
  }
}
variable "bucket_force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy empties and deletes the buckets - models, inputs, outputs, the access logs and the build source. True for a demo, which means destroy deletes every generated image and every downloaded model with them. The blueprint retained its buckets and deleted them only when its destroy script was given --delete-data (rules.md I-4)"
}
variable "models_access_log_expiration_days" {
  type        = number
  default     = 90
  description = "Days the models bucket's access logs are kept, 90 as the blueprint's lifecycle rule had it"

  validation {
    condition     = var.models_access_log_expiration_days >= 1
    error_message = "models_access_log_expiration_days must be at least 1."
  }
}

# --- ComfyUI image ---

variable "image_tag" {
  type        = string
  default     = "latest"
  description = "Tag the image build pushes and the Deployment pulls, latest as the blueprint had it"

  validation {
    condition     = can(regex("^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", var.image_tag))
    error_message = "image_tag must be a valid image tag."
  }
}
variable "ecr_force_delete" {
  type        = bool
  default     = true
  description = "Whether terraform destroy deletes the ECR repositories while they still hold the images the builds pushed"
}
variable "image_build_compute_type" {
  type        = string
  default     = "BUILD_GENERAL1_LARGE"
  description = "CodeBuild compute type for the image build, LARGE as the blueprint had it"

  validation {
    condition     = startswith(var.image_build_compute_type, "BUILD_GENERAL1_")
    error_message = "image_build_compute_type must be a BUILD_GENERAL1_* compute type."
  }
}
variable "image_build_timeout_minutes" {
  type        = number
  default     = 60
  description = "How long an image build may run, 60 minutes as the blueprint had it. The apply waits for the build on this same number"

  validation {
    condition     = var.image_build_timeout_minutes >= 5 && var.image_build_timeout_minutes <= 2160
    error_message = "image_build_timeout_minutes must be between 5 and 2160."
  }
}
variable "image_rebuild_schedule" {
  type        = string
  default     = "cron(0 3 ? * MON *)"
  description = "EventBridge schedule for the periodic image rebuild, Mondays 03:00 UTC as the blueprint's WeeklyImageRebuild. Null drops the schedule"

  validation {
    condition     = var.image_rebuild_schedule == null || can(regex("^(cron|rate)\\(.+\\)$", coalesce(var.image_rebuild_schedule, "rate(1 day)")))
    error_message = "image_rebuild_schedule must be a cron(...) or rate(...) expression, or null."
  }
}
variable "build_image_on_apply" {
  type        = bool
  default     = true
  description = "Whether the apply builds the image and waits for the build before rolling ComfyUI out. False creates the project and the workload without building: the pod then waits in ImagePullBackOff until an image is pushed by hand"
}

# --- Models ---

variable "model_download_tier" {
  type        = string
  default     = "all"
  description = "Which models the download build fetches into the models bucket: tier1 (the four the default workflow needs, about 20 GB) or all (several hundred GB), as the blueprint's MODEL_TIER. all, which is what the blueprint's project defaulted to"

  validation {
    condition     = contains(["tier1", "all"], var.model_download_tier)
    error_message = "model_download_tier must be tier1 or all."
  }
}
variable "model_download_timeout_minutes" {
  type        = number
  default     = 240
  description = "How long the model download may run, four hours as the blueprint had it"

  validation {
    condition     = var.model_download_timeout_minutes >= 5 && var.model_download_timeout_minutes <= 2160
    error_message = "model_download_timeout_minutes must be between 5 and 2160."
  }
}
variable "start_model_download_on_apply" {
  type        = bool
  default     = true
  description = "Whether the apply starts the model download. The apply does not wait for it - see the model_download_trigger module in main.tf"
}

# --- ComfyUI workload ---

variable "comfyui_namespace" {
  type        = string
  default     = "comfyui"
  description = "Namespace ComfyUI runs in. Its own rather than the blueprint's default, because Terraform owns the namespace object and default cannot be deleted. Part of the stack tag the pre-created ALB carries"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.comfyui_namespace))
    error_message = "comfyui_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "comfyui_ingress_name" {
  type        = string
  default     = "comfyui-ingress"
  description = "Name of the ComfyUI Ingress, comfyui-ingress as the blueprint named it. With comfyui_namespace it makes the ingress.k8s.aws/stack tag on the pre-created ALB (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.comfyui_ingress_name))
    error_message = "comfyui_ingress_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "comfyui_port" {
  type        = number
  default     = 8848
  description = "Port ComfyUI listens on, 8848 as the image's CMD sets it. Reaches the container, the Service, the NetworkPolicy and the ALB-to-pod security group rule from here (rules.md B-5)"

  validation {
    condition     = var.comfyui_port > 0 && var.comfyui_port <= 65535
    error_message = "comfyui_port must be a valid TCP port."
  }
}
variable "comfyui_replicas" {
  type        = number
  default     = 1
  description = "ComfyUI replicas, one as the blueprint had it. Each holds a GPU node"

  validation {
    condition     = var.comfyui_replicas >= 0
    error_message = "comfyui_replicas must be zero or greater."
  }
}
variable "comfyui_rollout_timeout" {
  type        = string
  default     = "30m"
  description = "How long the apply waits for ComfyUI to roll out, 30 minutes as the blueprint's wait_for_comfyui_ready. The first rollout includes launching a GPU node, copying its boot models and pulling a multi-gigabyte image"

  validation {
    condition     = can(regex("^[0-9]+(s|m|h)$", var.comfyui_rollout_timeout))
    error_message = "comfyui_rollout_timeout must be a duration such as 30m."
  }
}
variable "alb_listener_port" {
  type        = number
  default     = 80
  description = "Port the internal ALB listens on. One value for the Ingress's listen-ports annotation, the ALB's frontend security group and the CloudFront VPC origin (rules.md B-5)"

  validation {
    condition     = var.alb_listener_port > 0 && var.alb_listener_port <= 65535
    error_message = "alb_listener_port must be a valid TCP port."
  }
}
variable "alb_idle_timeout_seconds" {
  type        = number
  default     = 4000
  description = "ALB idle timeout, 4000 seconds (the ALB maximum) as the blueprint's Ingress set it so ComfyUI's progress WebSocket is not torn down between generations. Written both onto the pre-created ALB and into the Ingress annotation, from this one value (rules.md B-5)"

  validation {
    condition     = var.alb_idle_timeout_seconds >= 1 && var.alb_idle_timeout_seconds <= 4000
    error_message = "alb_idle_timeout_seconds must be between 1 and 4000."
  }
}
variable "alb_stickiness_duration_seconds" {
  type        = number
  default     = 300
  description = "Load balancer cookie stickiness duration, 300 seconds as the blueprint had it - what keeps one browser on one ComfyUI replica's queue"

  validation {
    condition     = var.alb_stickiness_duration_seconds >= 1 && var.alb_stickiness_duration_seconds <= 604800
    error_message = "alb_stickiness_duration_seconds must be between 1 and 604800."
  }
}
variable "alb_security_group_name" {
  type        = string
  default     = "comfyui-alb-sg"
  description = "Name of the internal ALB's frontend security group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.alb_security_group_name)) && !startswith(var.alb_security_group_name, "sg-")
    error_message = "alb_security_group_name must be 1-255 characters from the set AWS accepts for a security group name (no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}

# --- CloudFront ---

variable "cloudfront_prefix_list_name" {
  type        = string
  default     = "com.amazonaws.global.cloudfront.origin-facing"
  description = "Managed prefix list the ALB's frontend group admits CloudFront from, looked up by name. CloudFront's documentation names it as a way to admit a VPC origin, and the only one that can be written before the origin exists"

  validation {
    condition     = length(var.cloudfront_prefix_list_name) > 0
    error_message = "cloudfront_prefix_list_name must not be empty."
  }
}
variable "cloudfront_cache_policy_name" {
  type        = string
  default     = "Managed-CachingDisabled"
  description = "Managed cache policy for the distribution, by name - CachingDisabled as the blueprint had it"

  validation {
    condition     = length(var.cloudfront_cache_policy_name) > 0
    error_message = "cloudfront_cache_policy_name must not be empty."
  }
}
variable "cloudfront_origin_request_policy_name" {
  type        = string
  default     = "Managed-AllViewer"
  description = "Managed origin request policy for the distribution, by name - AllViewer as the blueprint had it, so the WebSocket upgrade reaches ComfyUI"

  validation {
    condition     = length(var.cloudfront_origin_request_policy_name) > 0
    error_message = "cloudfront_origin_request_policy_name must not be empty."
  }
}
variable "cloudfront_price_class" {
  type        = string
  default     = "PriceClass_All"
  description = "CloudFront price class. PriceClass_All, which the blueprint's distribution got by not setting one"

  validation {
    condition     = contains(["PriceClass_All", "PriceClass_200", "PriceClass_100"], var.cloudfront_price_class)
    error_message = "cloudfront_price_class must be one of: PriceClass_All, PriceClass_200, PriceClass_100."
  }
}

# --- Node patching and image scanning ---

variable "enable_node_patching" {
  type        = bool
  default     = true
  description = "Whether a State Manager association applies security updates to the cluster's nodes, as deploy_infra.sh's configure_ssm_patching set up: AWS-RunPatchBaseline Install with NoReboot, on every instance tagged kubernetes.io/cluster/<cluster>=owned - the managed group and the Karpenter nodes alike"
}
variable "node_patching_schedule" {
  type        = string
  default     = "cron(0 3 * * ? *)"
  description = "When the patch association runs, daily at 03:00 UTC as the blueprint had it. It also runs once when created, which is what the blueprint's start-associations-once did"

  validation {
    condition     = can(regex("^(cron|rate)\\(.+\\)$", var.node_patching_schedule))
    error_message = "node_patching_schedule must be a cron(...) or rate(...) expression."
  }
}
variable "enable_enhanced_ecr_scanning" {
  type        = bool
  default     = false
  description = "Whether to turn on Amazon Inspector for ECR and switch the registry to enhanced continuous scanning, as deploy_infra.sh did. False here: both are account-wide settings, not this project's resources - enabling them covers every repository in the region and is billed per image, and terraform destroy would then turn them off for everything else in the account too"
}

# --- Workbench ---

variable "instance_name" {
  type        = string
  default     = "comfyui-vscode"
  description = "Name tag for the workbench instance"

  validation {
    condition     = length(var.instance_name) > 0
    error_message = "instance_name must not be empty."
  }
}
variable "key_name" {
  type        = string
  default     = "comfyui-key"
  description = "Name of the EC2 key pair created for the workbench and the core nodes"

  validation {
    condition     = can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be a non-empty string of printable ASCII characters, 255 characters or fewer."
  }
}
variable "security_group_name" {
  type        = string
  default     = "comfyui-vscode-sg"
  description = "Name of the workbench instance's security group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "instance_type" {
  type        = string
  default     = "t3.xlarge"
  description = "EC2 instance type for the workbench, t3.xlarge as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. t3.xlarge)."
  }
}
variable "root_volume_size" {
  type        = number
  default     = 80
  description = "Workbench root volume size in GiB, 80 as the _monolithic template had it"

  validation {
    condition     = var.root_volume_size >= 20
    error_message = "root_volume_size must be at least 20 GiB."
  }
}
variable "code_server_version" {
  type        = string
  default     = "4.105.1"
  description = "code-server release installed on the workbench, as the _monolithic template pinned it"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a semantic version (e.g. 4.105.1)."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = false
  description = "Whether the controlled inbound rules use 0.0.0.0/0. When false (the default), they use only the public IPv4 /32 dynamically returned by my_ip_lookup_url"
}
variable "kubectl_download_version" {
  type        = string
  default     = "1.35.8/2026-09-27"
  description = "kubectl build downloaded onto the workbench, as <version>/<release-date> from the amazon-eks bucket. Kept within one minor of kubernetes_version"

  validation {
    condition     = can(regex("^1\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.35.8/2026-09-27."
  }
}
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the workbench where the bootstrap drops its completion marker, which the README association waits on (rules.md D-5/H-2)"

  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/'."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 1800
  description = "How long the README association waits for success. It only has to outlast the workbench bootstrap it chains behind"

  validation {
    condition     = var.readme_timeout_seconds > 0
    error_message = "readme_timeout_seconds must be greater than zero."
  }
}

variable "my_ip_lookup_url" {
  type        = string
  default     = "https://checkip.amazonaws.com/"
  description = "Trusted HTTPS endpoint that returns the public IPv4 address of the machine running Terraform. The address is converted to a /32 and used when an allow_inbound_from_anywhere switch is false"

  validation {
    condition     = startswith(var.my_ip_lookup_url, "https://")
    error_message = "my_ip_lookup_url must be an HTTPS URL because its response controls which source address the security groups admit."
  }
}
