variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.)"
}
variable "prefix" {
  type        = string
  default     = "eks"
  description = "Prefix for the network resources' Name tags (\"eks\" produces eks-vpc, eks-igw, eks-public-a, ...)"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.prefix))
    error_message = "prefix must be lowercase alphanumeric, optionally with hyphens."
  }
}
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
}
variable "cluster_name" {
  type        = string
  default     = "eks-cluster"
  description = "Name of the EKS cluster"

  validation {
    condition     = can(regex("^[0-9A-Za-z][A-Za-z0-9\\-_]{0,99}$", var.cluster_name))
    error_message = "cluster_name must start with a letter or digit and contain only letters, digits, hyphens and underscores (100 characters or fewer)."
  }
}
variable "kubernetes_version" {
  type        = string
  default     = "1.33"
  description = "EKS cluster Kubernetes version (1.XX)"

  validation {
    condition     = contains(["1.31", "1.32", "1.33"], var.kubernetes_version)
    error_message = "kubernetes_version must be one of: 1.31, 1.32, 1.33."
  }
}
variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the EKS cluster API server endpoint is reachable from the public internet. Needed because the helm and kubectl providers run from the machine executing terraform apply rather than from inside the VPC (rules.md E-1/E-2). Restrict access with public_access_cidrs rather than leaving it open to 0.0.0.0/0"
}
variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDR blocks allowed to reach the EKS API server's public endpoint when endpoint_public_access is true. Set this to your own address in CIDR form (e.g. [\"203.0.113.4/32\"]) instead of leaving the default: bootstrap_cluster_creator_admin_permissions grants anyone who can reach this endpoint with the creating AWS identity full cluster admin"

  validation {
    condition     = alltrue([for cidr in var.public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "public_access_cidrs must contain valid IPv4 CIDR blocks."
  }
}
variable "key_name" {
  type        = string
  default     = "eks-key"
  description = "Name of the EC2 key pair created for the VS Code instance and the managed node group"

  validation {
    condition     = can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be a non-empty string of printable ASCII characters, 255 characters or fewer."
  }
}
variable "node_group_name" {
  type        = string
  default     = "nodegroup"
  description = "Name of the managed node group that hosts the Karpenter controller itself. Karpenter cannot provision the nodes its own controller runs on, so this group is a prerequisite rather than a duplicate of it"

  validation {
    condition     = length(var.node_group_name) > 0
    error_message = "node_group_name must not be empty."
  }
}
variable "node_group_instance_types" {
  type        = list(string)
  default     = ["t3.medium"]
  description = "EC2 instance types for the managed node group hosting the Karpenter controller"

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "node_group_instance_types must contain at least one instance type."
  }
}
variable "node_group_desired_size" {
  type        = number
  default     = 2
  description = "Desired node count for the managed node group. Two nodes let the Karpenter controller's leader-elected replica pair spread across availability zones"

  validation {
    condition     = var.node_group_desired_size >= 0
    error_message = "node_group_desired_size must be zero or greater."
  }
}
variable "node_group_min_size" {
  type        = number
  default     = 2
  description = "Minimum node count for the managed node group"

  validation {
    condition     = var.node_group_min_size >= 0
    error_message = "node_group_min_size must be zero or greater."
  }
}
variable "node_group_max_size" {
  type        = number
  default     = 4
  description = "Maximum node count for the managed node group. Kept small on purpose: application scale-out is Karpenter's job, not this group's"

  validation {
    condition     = var.node_group_max_size >= 0
    error_message = "node_group_max_size must be zero or greater."
  }
}
variable "karpenter_chart_version" {
  type        = string
  default     = "1.8.3"
  description = "Version of the Karpenter Helm chart. It also installs the NodePool and EC2NodeClass CRDs, so a major version change may also change the apiVersions the karpenter module writes"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.karpenter_chart_version))
    error_message = "karpenter_chart_version must be a semantic version (e.g. 1.8.3)."
  }
}
variable "karpenter_capacity_types" {
  type        = list(string)
  default     = ["on-demand", "spot"]
  description = "Capacity types Karpenter may provision. Includes spot by default so consolidation has a cheaper option to pick; drop it if you would rather not handle interruptions"

  validation {
    condition     = length(var.karpenter_capacity_types) > 0 && alltrue([for c in var.karpenter_capacity_types : contains(["on-demand", "spot", "reserved"], c)])
    error_message = "karpenter_capacity_types must be a non-empty subset of: on-demand, spot, reserved."
  }
}
variable "karpenter_instance_categories" {
  type        = list(string)
  default     = ["c", "m", "r", "t"]
  description = "EC2 instance categories Karpenter may pick from. Keeping this broad is the point: Karpenter chooses the cheapest shape that fits the pending pods"

  validation {
    condition     = length(var.karpenter_instance_categories) > 0
    error_message = "karpenter_instance_categories must contain at least one category."
  }
}
variable "karpenter_instance_types" {
  type        = list(string)
  default     = ["t3.small"]
  description = "Exact instance types Karpenter's NodePool is pinned to, intersected with karpenter_instance_categories. A single small type keeps the stress demo legible: at a 1 vCPU request per pod, one pod fills a t3.small, so each replica forces another node instead of six replicas landing on one large instance. Set to [] to hand the choice back to Karpenter"

  validation {
    condition     = alltrue([for type in var.karpenter_instance_types : can(regex("^[a-z0-9]+\\.[a-z0-9]+$", type))])
    error_message = "karpenter_instance_types must contain valid EC2 instance types (e.g. t3.small)."
  }
}
variable "karpenter_node_labels" {
  type        = map(string)
  default     = { "node-auto-scaling" = "karpenter" }
  description = "Labels every Karpenter-provisioned node carries. The stress demo's nodeSelector is filled from this same map, so it is what separates Karpenter capacity from the managed node group hosting the controller"

  validation {
    condition     = length(var.karpenter_node_labels) > 0
    error_message = "karpenter_node_labels must contain at least one label, since the stress demo selects on it."
  }
}
variable "karpenter_cpu_limit" {
  type        = number
  default     = 1000
  description = "Maximum total vCPU Karpenter's NodePool may provision, a hard ceiling on runaway scale-up"

  validation {
    condition     = var.karpenter_cpu_limit > 0
    error_message = "karpenter_cpu_limit must be greater than zero."
  }
}
variable "karpenter_discovery_tag_key" {
  type        = string
  default     = "karpenter.sh/discovery"
  description = "Tag key written onto the private subnets and used in the EC2NodeClass subnet selector, so Karpenter launches nodes only into this cluster's private subnets"

  validation {
    condition     = length(var.karpenter_discovery_tag_key) > 0
    error_message = "karpenter_discovery_tag_key must not be empty."
  }
}
variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "EC2 instance type for the VS Code EC2 instance"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must be a valid EC2 instance type (e.g. t3.medium)."
  }
}
variable "enable_cloudfront" {
  type        = bool
  default     = true
  description = "Whether to front the VS Code instance with a CloudFront distribution, so the editor is reached over HTTPS and the instance's own port stays closed to the internet. When false, reach code-server directly (see allow_inbound_from_anywhere) or through SSM Session Manager port forwarding"
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether to allow inbound access to the code-server port (8000) on the instance from 0.0.0.0/0. Unnecessary when enable_cloudfront is true, because the instance's security group then admits only the CloudFront origin-facing prefix list"
}
variable "cloudfront_origin_facing_prefix_list_name" {
  type        = string
  default     = "com.amazonaws.global.cloudfront.origin-facing"
  description = "Name of the AWS managed prefix list covering CloudFront's origin-facing address ranges. Looked up per region with a data source rather than carried in a hardcoded region-to-prefix-list map like the _monolithic template's AWSRegions2PrefixListId mapping, which went stale as AWS added regions"

  validation {
    condition     = length(var.cloudfront_origin_facing_prefix_list_name) > 0
    error_message = "cloudfront_origin_facing_prefix_list_name must not be empty."
  }
}
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory holding the bootstrap marker files, shared between the vscode_ec2 module (which touches <path>/userdata as the last step of its user data) and the SSM association that polls for it before writing the README (rules.md D-5/H-2). Under /run so the markers vanish on reboot rather than making a stale file look like a completed bootstrap"

  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/'."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the SSM association waits for the README command to report success. It has to cover the whole instance bootstrap, since the command's first act is to wait for the user data marker file"

  validation {
    condition     = var.readme_timeout_seconds > 0
    error_message = "readme_timeout_seconds must be greater than zero."
  }
}
variable "kubectl_download_version" {
  type        = string
  default     = "1.33.3/2025-08-03"
  description = "Version and release-date path segment of the kubectl binary downloaded onto the VS Code EC2 instance, from the amazon-eks S3 bucket layout (<version>/<date>)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.33.3/2025-08-03."
  }
}
variable "load_balancer_controller_chart_version" {
  type        = string
  default     = "1.14.1"
  description = "Version of the aws-load-balancer-controller Helm chart. Pinned rather than whatever the _monolithic template's cloned install script happened to fetch"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.load_balancer_controller_chart_version))
    error_message = "load_balancer_controller_chart_version must be a semantic version (e.g. 1.14.1)."
  }
}
variable "enable_backend_security_group" {
  type        = bool
  default     = false
  description = "Whether the AWS Load Balancer Controller uses a shared backend security group. False, as in every project in this repository: no workload here sets the manage-backend-security-group-rules annotation, so the controller writes no node-side rules and needs no shared group as their source. The load balancer carries the EKS cluster security group, which already reaches pod IPs (rules.md G-2)"
}
variable "enable_service_mutator_webhook" {
  type        = bool
  default     = false
  description = "Whether the controller installs the mservice.elbv2.k8s.aws mutating webhook, which claims new Services of type LoadBalancer that do not name the controller themselves. False, because no Service here is of that type at all: the blue/green workload's active and preview Services are both ClusterIP, and the load balancer is a Terraform resource the controller adopts. So the webhook has nothing to mutate, while the chart gives it failurePolicy: Fail and no namespaceSelector, which makes it a gate on every Service created anywhere in the cluster. That gate is live in this project: module.karpenter and module.argo_rollouts are ordered only after the network and CoreDNS, so they install in parallel with the controller, and a Service created between the webhook being registered and the controller's Deployment becoming Available is rejected with \"no endpoints available for service aws-load-balancer-webhook-service\" (rules.md G-4)"

  validation {
    # The constraint is real rather than stylistic, so it belongs here and not in the
    # description (rules.md B-1). The failure it prevents names the webhook rather than
    # the release that tripped over it, which is a long way from the cause.
    condition     = var.enable_service_mutator_webhook == false
    error_message = "enable_service_mutator_webhook must stay false in this variant. No Service here is of type LoadBalancer, so the webhook has nothing to mutate, while its failurePolicy: Fail applies to every Service created in the cluster and makes karpenter and argo_rollouts - which install in parallel with the controller - fail whenever it has no Ready pod. To run with it true, order every module that creates a Service after module.aws_load_balancer_controller, and note that only covers the apply, not a later controller rollout (rules.md G-4)."
  }
}
variable "argo_rollouts_chart_version" {
  type        = string
  default     = "2.40.4"
  description = "Version of the argo-rollouts Helm chart"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.argo_rollouts_chart_version))
    error_message = "argo_rollouts_chart_version must be a semantic version (e.g. 2.40.4)."
  }
}
variable "argo_rollouts_plugin_version" {
  type        = string
  default     = "v1.8.3"
  description = <<-DESC
    Version of the kubectl-argo-rollouts plugin installed on the workbench.

    Six of the README steps this project writes onto the instance are "kubectl argo rollouts ..." commands -
    watching the rollout, starting one, promoting it, and the dashboard. Without the plugin every one of them
    answers

      error: unknown command "argo" for "kubectl"

    and the demo has no steps left. kubectl finds subcommands it does not know by looking for an executable
    named kubectl-<subcommand> on PATH, so this is a separate binary, not part of kubectl.

    It must match the controller the chart installs, which is the chart's appVersion rather than its version -
    chart 2.40.4 carries controller v1.8.3. The plugin and the controller share the Rollout CRD, so a mismatch
    across minor versions shows up as fields the plugin does not render or cannot set. The pairing cannot be
    enforced here, because this is interpolated into user data that runs before the Helm release exists; what
    is possible is making both versions visible side by side, which the rollouts_versions output does.

      helm show chart argo-rollouts --repo https://argoproj.github.io/argo-helm \
        --version <argo_rollouts_chart_version> | grep appVersion
  DESC

  validation {
    # The leading v matters: it is part of the release tag in the download URL, and without it the curl 404s
    # and user data continues - leaving an instance whose README is full of commands that do not exist
    # (rules.md B-1).
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.argo_rollouts_plugin_version))
    error_message = "argo_rollouts_plugin_version must be a release tag of the form vX.Y.Z (e.g. v1.8.3) - the leading v is part of the GitHub release tag the binary is downloaded from."
  }
}
variable "argo_rollouts_namespace" {
  type        = string
  default     = "argo-rollouts"
  description = "Namespace the Argo Rollouts controller runs in"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.argo_rollouts_namespace))
    error_message = "argo_rollouts_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "alb_name" {
  type        = string
  default     = "alb"
  description = "Name of the Application Load Balancer, as the _monolithic template's create-load-balancer call had it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,32}$", var.alb_name))
    error_message = "alb_name must be 32 characters or fewer of letters, digits and hyphens."
  }
}
variable "alb_target_group_name" {
  type        = string
  default     = "active-tg"
  description = "Name of the target group the Rollout's active Service is bound to"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,32}$", var.alb_target_group_name))
    error_message = "alb_target_group_name must be 32 characters or fewer of letters, digits and hyphens."
  }
}
variable "bluegreen_namespace" {
  type        = string
  default     = "bluegreen"
  description = "Namespace the Rollout and its two Services live in"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.bluegreen_namespace))
    error_message = "bluegreen_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "bluegreen_rollout_name" {
  type        = string
  default     = "bluegreen-rollout"
  description = "Name of the Rollout object"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.bluegreen_rollout_name))
    error_message = "bluegreen_rollout_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "bluegreen_image" {
  type        = string
  default     = "public.ecr.aws/docker/library/nginx:1.27"
  description = "Container image for the first version. A pinned tag rather than latest, so changing it is what starts a rollout"

  validation {
    condition     = length(var.bluegreen_image) > 0
    error_message = "bluegreen_image must not be empty."
  }
}
variable "bluegreen_replica_count" {
  type        = number
  default     = 3
  description = "Replicas per version. More than one makes the target group membership change visible during a promotion"

  validation {
    condition     = var.bluegreen_replica_count > 0
    error_message = "bluegreen_replica_count must be greater than zero."
  }
}
