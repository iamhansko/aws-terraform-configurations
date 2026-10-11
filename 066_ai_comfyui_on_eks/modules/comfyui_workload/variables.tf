variable "cluster_name" {
  type        = string
  description = "EKS cluster the Pod Identity association is created in"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "account_id" {
  type        = string
  description = "Account the workload runs in, for the pod role's Bedrock ARNs and the container's AWS_ACCOUNT_ID. Passed in rather than read by a data source here: this module is ordered after half the root with depends_on, which would defer such a read to every apply that changes any of those modules and leave the Deployment's manifest unknown in each of those plans (rules.md D-6)"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}
variable "partition" {
  type        = string
  default     = "aws"
  description = "AWS partition of the ARNs written into the pod role's policy"

  validation {
    condition     = contains(["aws", "aws-cn", "aws-us-gov"], var.partition)
    error_message = "partition must be aws, aws-cn or aws-us-gov."
  }
}
variable "region" {
  type        = string
  description = "Region the workload runs in. Set as AWS_REGION and AWS_DEFAULT_REGION on the ComfyUI container, because the image's custom nodes read AWS_DEFAULT_REGION and fall back to us-west-2 - and the auto model downloader builds the models and outputs bucket names from it, so outside us-west-2 an unset value points it at buckets that do not exist"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.region))
    error_message = "region must be a valid AWS region such as ap-northeast-2."
  }
}
variable "namespace" {
  type        = string
  default     = "comfyui"
  description = "Namespace everything here lives in, created by this module. A namespace of its own rather than the blueprint's default: the blueprint labelled default for Pod Security warnings, and a Terraform-owned Namespace object named default could never be destroyed - the API server refuses to delete it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace)) && length(var.namespace) <= 63
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "name" {
  type        = string
  default     = "comfyui"
  description = "Name of the Deployment and the app label its pods carry, comfyui as the blueprint named them"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "service_account_name" {
  type        = string
  default     = "comfyui-sa"
  description = "Service account the ComfyUI pod runs as, comfyui-sa as the blueprint named it. The Pod Identity association binds the pod role to exactly this name in exactly this namespace"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.service_account_name))
    error_message = "service_account_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "service_name" {
  type        = string
  default     = "comfyui-service"
  description = "Name of the Service the Ingress routes to, comfyui-service as the blueprint named it"

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", var.service_name))
    error_message = "service_name must be a valid DNS-1035 label (lowercase, starting with a letter)."
  }
}
variable "ingress_name" {
  type        = string
  default     = "comfyui-ingress"
  description = "Name of the Ingress, comfyui-ingress as the blueprint named it. Together with namespace it is the ingress.k8s.aws/stack value the pre-created ALB has to carry for the controller to adopt it - the caller derives both from the same variables (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.ingress_name))
    error_message = "ingress_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "ingress_class_name" {
  type        = string
  default     = "alb"
  description = "IngressClass that hands the Ingress to the AWS Load Balancer Controller. Without it nothing reconciles the Ingress at all (rules.md G-1)"

  validation {
    condition     = length(var.ingress_class_name) > 0
    error_message = "ingress_class_name must not be empty."
  }
}
variable "ingress_annotations" {
  type        = map(string)
  default     = {}
  description = "Annotations on the Ingress - the scheme, target type, security group and load balancer attributes the controller reads. Decided by the caller, which owns the pre-created ALB these have to agree with (rules.md G-3)"
}
variable "container_port" {
  type        = number
  default     = 8848
  description = "Port ComfyUI listens on, 8848 as the image's CMD sets it. One value for the container, the Service, the NetworkPolicy and - through the caller - the ALB-to-pod security group rule (rules.md B-5)"

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port must be a valid TCP port."
  }
}
variable "replicas" {
  type        = number
  default     = 1
  description = "ComfyUI replicas, one as the blueprint had it. Each replica holds a whole GPU, and the ALB's sticky sessions are what keep one browser on one replica's queue"

  validation {
    condition     = var.replicas >= 0
    error_message = "replicas must be zero or greater."
  }
}
variable "image" {
  type        = string
  description = "Full image reference the ComfyUI container runs, from the image module"

  validation {
    condition     = length(var.image) > 0
    error_message = "image must not be empty."
  }
}
variable "image_revision" {
  type        = string
  description = "Hash of the build context the image was built from, written into a pod template annotation. The tag is mutable (latest), so a rebuild changes nothing in the Deployment on its own; this is what makes an apply that rebuilt the image also roll the pods onto it"

  validation {
    condition     = length(var.image_revision) > 0
    error_message = "image_revision must not be empty."
  }
}
variable "gpu_count" {
  type        = number
  default     = 1
  description = "GPUs each ComfyUI pod requests, one as the blueprint had it. The request is what makes Karpenter launch a GPU node, and what the device plugin satisfies"

  validation {
    condition     = var.gpu_count >= 1
    error_message = "gpu_count must be at least 1."
  }
}
variable "node_selector" {
  type        = map(string)
  default     = {}
  description = "nodeSelector for the ComfyUI pod. The caller passes the GPU pool's labels rather than restating them, so the selector cannot drift from the pool (rules.md B-5)"
}
variable "models_host_path" {
  type        = string
  default     = "/comfyui-models"
  description = "Directory on the node mounted into the pod as ComfyUI's models directory - the instance-store mount the GPU node's user data prepares and the sync Lambda copies into (rules.md B-5)"

  validation {
    condition     = can(regex("^/[A-Za-z0-9/_.-]+$", var.models_host_path)) && !strcontains(var.models_host_path, "..")
    error_message = "models_host_path must be an absolute path of plain characters."
  }
}
variable "models_bucket_arn" {
  type        = string
  description = "ARN of the models bucket. The image's auto model downloader reads missing models from it and writes back the ones it had to fetch from HuggingFace, with the pod's own credentials"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:s3:::", var.models_bucket_arn))
    error_message = "models_bucket_arn must be an S3 bucket ARN."
  }
}
variable "inputs_bucket_name" {
  type        = string
  description = "Bucket mounted at ComfyUI's input directory through Mountpoint for S3"

  validation {
    condition     = length(var.inputs_bucket_name) >= 3
    error_message = "inputs_bucket_name must be a bucket name."
  }
}
variable "outputs_bucket_name" {
  type        = string
  description = "Bucket mounted at ComfyUI's output directory, and the bucket the image uploads results to and the video sidecar syncs into"

  validation {
    condition     = length(var.outputs_bucket_name) >= 3
    error_message = "outputs_bucket_name must be a bucket name."
  }
}
variable "outputs_bucket_arn" {
  type        = string
  description = "ARN of outputs_bucket_name, for the pod role's write access"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:s3:::", var.outputs_bucket_arn))
    error_message = "outputs_bucket_arn must be an S3 bucket ARN."
  }
}
variable "s3_csi_driver" {
  type        = string
  default     = "s3.csi.aws.com"
  description = "CSI driver name the volumes use. The caller passes the Mountpoint add-on module's output rather than the literal (rules.md B-5)"

  validation {
    condition     = length(var.s3_csi_driver) > 0
    error_message = "s3_csi_driver must not be empty."
  }
}
variable "allow_delete" {
  type        = bool
  default     = true
  description = "Whether the volumes are mounted with allow-delete, as the blueprint's PersistentVolumes were. Has to agree with the driver role's s3:DeleteObject, so the caller passes the add-on module's output (rules.md B-5)"
}
variable "volume_capacity" {
  type        = string
  default     = "1200Gi"
  description = "Capacity written on the PersistentVolumes and claims, 1200Gi as the blueprint had it. Ignored by Mountpoint - a bucket has no size - but required by the API"

  validation {
    condition     = can(regex("^[0-9]+(Ki|Mi|Gi|Ti|Pi)$", var.volume_capacity))
    error_message = "volume_capacity must be a Kubernetes quantity such as 1200Gi."
  }
}
variable "video_sync_image" {
  type        = string
  default     = "public.ecr.aws/aws-cli/aws-cli:latest"
  description = "Image of the sidecar that copies finished videos from the pod's scratch directory to the outputs bucket, as the blueprint had it"

  validation {
    condition     = length(var.video_sync_image) > 0
    error_message = "video_sync_image must not be empty."
  }
}
variable "video_sync_interval_seconds" {
  type        = number
  default     = 30
  description = "How often the video sidecar syncs, 30 seconds as the blueprint had it"

  validation {
    condition     = var.video_sync_interval_seconds >= 1
    error_message = "video_sync_interval_seconds must be at least 1."
  }
}
variable "labels" {
  type = map(string)
  default = {
    project = "comfyui-on-eks"
  }
  description = "Labels on every object here, project=comfyui-on-eks as the blueprint's manifests carried"

  validation {
    condition     = alltrue([for key in keys(var.labels) : length(key) > 0])
    error_message = "labels keys must not be empty."
  }
}
variable "pod_security_labels" {
  type = map(string)
  default = {
    "pod-security.kubernetes.io/warn"  = "baseline"
    "pod-security.kubernetes.io/audit" = "baseline"
  }
  description = "Pod Security Admission labels on the namespace, warn and audit at baseline as the blueprint's manifests/PodSecurity put on default. Not enforce: the ComfyUI pod mounts its models through a hostPath, which baseline does not allow, so the apply prints a warning for it and admits it"

  validation {
    condition     = alltrue([for key in keys(var.pod_security_labels) : startswith(key, "pod-security.kubernetes.io/")])
    error_message = "pod_security_labels keys must be pod-security.kubernetes.io/ labels."
  }
}
variable "create_network_policy" {
  type        = bool
  default     = true
  description = "Whether to create the blueprint's NetworkPolicy. It is only enforced when the VPC CNI's network policy agent is on, which it is not by default - so it documents intent until then, and is written to be correct the moment it is enforced (rules.md B-4)"
}
variable "network_policy_ingress_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "Where ComfyUI's port may be reached from under the NetworkPolicy. The caller passes the subnets the internal ALB is placed in, since that is the only source of traffic to the pods"

  validation {
    condition     = alltrue([for cidr in var.network_policy_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "network_policy_ingress_cidr_blocks must contain valid IPv4 CIDR blocks."
  }
}
variable "network_policy_dns_cidr_block" {
  type        = string
  default     = "10.0.0.0/8"
  description = "Where DNS may be reached under the NetworkPolicy - the VPC's CIDR, as the blueprint had it"

  validation {
    condition     = can(cidrhost(var.network_policy_dns_cidr_block, 0))
    error_message = "network_policy_dns_cidr_block must be a valid IPv4 CIDR block."
  }
}
variable "rollout_timeout" {
  type        = string
  default     = "30m"
  description = "How long the apply waits for the Deployment to roll out, 30 minutes as deploy_infra.sh's wait_for_comfyui_ready allowed. The first rollout includes Karpenter launching a GPU node, that node copying its models at boot, and a multi-gigabyte image pull - well past the ten-minute default"

  validation {
    condition     = can(regex("^[0-9]+(s|m|h)$", var.rollout_timeout))
    error_message = "rollout_timeout must be a duration such as 30m."
  }
}
