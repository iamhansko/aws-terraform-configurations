variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. Null falls through to the provider chain (AWS_REGION / AWS_DEFAULT_REGION)"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region name (e.g. ap-northeast-2), or null."
  }
}

variable "project_name" {
  type        = string
  default     = "rayserve-on-eks"
  description = "Prefix for resource names that have to be unique inside the account, and the title of the README written onto the bastion"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 3-32 lowercase letters, digits or hyphens and must not start or end with a hyphen."
  }
}

# --- Network ---

variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block of the VPC"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block."
  }
}

# --- EKS cluster ---

variable "cluster_name" {
  type        = string
  default     = "eks-cluster"
  description = "Name of the EKS cluster. Karpenter is given this as settings.clusterName, which is how its controller finds the cluster it provisions for"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,99}$", var.cluster_name))
    error_message = "cluster_name must start with a letter or digit and contain only letters, digits, hyphens and underscores."
  }
}

variable "kubernetes_version" {
  type        = string
  default     = "1.34"
  description = "EKS cluster Kubernetes version. Keep kubectl_download_version within one minor of this"

  validation {
    condition     = can(regex("^1\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must look like 1.XX; the cluster module holds the list of versions this project is verified against."
  }
}

variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the cluster's API server has a public endpoint. True here, and pinned true, because every Kubernetes object and Helm release in this project is applied by providers running on the machine executing terraform"

  validation {
    # Not a free choice: this root declares kubectl and helm providers, and those run
    # wherever terraform runs. With a private-only endpoint they cannot connect, plan
    # still passes, and the failure appears mid-apply as a dial timeout that looks
    # exactly like the destroy-ordering problem rules.md D-4 describes (rules.md E-9).
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because its manifests and Helm releases are applied by providers running on the machine executing terraform. To run with a private endpoint, drop those providers and apply everything from the bastion through SSM Associations instead, as 041_eks_private_cluster does."
  }
}

variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDRs allowed to reach the public API server endpoint. Narrow this for anything longer lived than a demo"

  validation {
    condition     = alltrue([for cidr in var.public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "public_access_cidrs must contain valid IPv4 CIDR blocks."
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
  default     = "core"
  description = "Name of the managed node group that runs the cluster's own controllers, as the _monolithic template named it. Karpenter itself runs here: a controller that provisions nodes cannot depend on the nodes it provisions"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,62}$", var.core_node_group_name))
    error_message = "core_node_group_name must start with a letter or digit and contain only letters, digits, hyphens and underscores."
  }
}

variable "core_node_instance_types" {
  type        = list(string)
  default     = ["t3.medium"]
  description = "Instance types for the core node group"

  validation {
    condition     = length(var.core_node_instance_types) > 0
    error_message = "core_node_instance_types must contain at least one instance type."
  }
}

variable "core_node_labels" {
  type = map(string)
  default = {
    "node-type" = "core"
  }
  description = "Labels on the core nodes, as the _monolithic template set them"

  validation {
    condition     = alltrue([for key in keys(var.core_node_labels) : length(key) > 0])
    error_message = "core_node_labels keys must not be empty."
  }
}

variable "core_node_desired_size" {
  type        = number
  default     = 2
  description = "Desired core node count"

  validation {
    condition     = var.core_node_desired_size >= 1
    error_message = "core_node_desired_size must be at least 1."
  }
}

variable "core_node_min_size" {
  type        = number
  default     = 2
  description = "Minimum core node count"

  validation {
    condition     = var.core_node_min_size >= 1
    error_message = "core_node_min_size must be at least 1."
  }
}

variable "core_node_max_size" {
  type        = number
  default     = 4
  description = "Maximum core node count"

  validation {
    condition     = var.core_node_max_size >= 1
    error_message = "core_node_max_size must be at least 1."
  }
}

# --- Karpenter ---

variable "karpenter_chart_version" {
  type        = string
  default     = "1.8.3"
  description = "Pinned Karpenter chart version. The _monolithic template pinned 1.6.0 inside a shell script it wrote on the bastion"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.karpenter_chart_version))
    error_message = "karpenter_chart_version must be a three-part semantic version."
  }
}

variable "karpenter_node_pools" {
  type = map(object({
    instance_families = list(string)
    instance_sizes    = list(string)
    node_labels       = map(string)
    capacity_types    = optional(list(string), ["spot", "on-demand"])
    ami_alias         = optional(string, "bottlerocket@latest")
    block_device_mappings = list(object({
      device_name           = string
      volume_size           = string
      volume_type           = optional(string, "gp3")
      encrypted             = optional(bool, true)
      delete_on_termination = optional(bool, true)
    }))
    instance_store_policy = optional(string)
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
    cpu_limit    = optional(number, 1000)
    memory_limit = optional(string, "1000Gi")
  }))
  default = {
    x86-cpu-karpenter = {
      instance_families = ["m5"]
      instance_sizes    = ["xlarge", "2xlarge", "4xlarge", "8xlarge"]
      node_labels       = { nodegroup = "x86-cpu", type = "karpenter" }
      block_device_mappings = [
        { device_name = "/dev/xvda", volume_size = "100Gi" },
        { device_name = "/dev/xvdb", volume_size = "300Gi" },
      ]
      # No instance store policy: the m5 family has no local NVMe disks, and Karpenter
      # rejects the field on a shape that has none. The _monolithic template's x86 node
      # class left it out too - the only one of its three that did.
    }
    g5-gpu-karpenter = {
      instance_families = ["g5"]
      instance_sizes    = ["2xlarge", "4xlarge", "8xlarge", "12xlarge", "16xlarge", "24xlarge", "48xlarge"]
      node_labels       = { nodegroup = "g5-gpu", type = "karpenter" }
      block_device_mappings = [
        { device_name = "/dev/xvda", volume_size = "50Gi" },
        { device_name = "/dev/xvdb", volume_size = "300Gi" },
      ]
      instance_store_policy = "RAID0"
      taints                = [{ key = "nvidia.com/gpu", value = "Exists", effect = "NoSchedule" }]
    }
    g6-gpu-karpenter = {
      instance_families = ["g6"]
      instance_sizes    = ["2xlarge", "4xlarge", "8xlarge", "12xlarge", "16xlarge", "24xlarge", "48xlarge"]
      node_labels       = { nodegroup = "g6-gpu", type = "karpenter" }
      # One volume, as the _monolithic template's g6 class had it - and worth noticing
      # next to g5's two: the g6 nodes get a 50Gi root and nothing else, so container
      # images share the OS volume unless the instance store is used, which it is.
      block_device_mappings = [
        { device_name = "/dev/xvda", volume_size = "50Gi" },
      ]
      instance_store_policy = "RAID0"
      taints                = [{ key = "nvidia.com/gpu", value = "Exists", effect = "NoSchedule" }]
    }
  }
  description = <<-DESC
    The Karpenter pools, keyed by name. Three, as the _monolithic template defined them: a CPU pool the Ray
    head runs on, and two GPU pools the workers can be provisioned from.

    A map rather than three module blocks, because the pools differ only in their values. The keys are
    literals from this configuration, so they are safe as for_each keys - nothing here comes from another
    module's output (rules.md B-7, and the reason B-8 does not apply).
  DESC

  validation {
    condition     = length(var.karpenter_node_pools) > 0
    error_message = "karpenter_node_pools must define at least one pool."
  }

  validation {
    condition     = alltrue([for name in keys(var.karpenter_node_pools) : can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", name))])
    error_message = "karpenter_node_pools keys become Kubernetes object names, so each must be a valid lowercase RFC 1123 subdomain."
  }

  validation {
    condition     = alltrue([for pool in values(var.karpenter_node_pools) : length(pool.node_labels) > 0])
    error_message = "every pool needs node_labels. With three pools in one cluster, a pool with no labels can only be selected by accident, and a workload that selects nothing lands on whichever pool fits first."
  }
}

variable "head_node_pool" {
  type        = string
  default     = "x86-cpu-karpenter"
  description = "Which pool the Ray head is pinned to. Its labels become the head pod's nodeSelector, so this is a key of karpenter_node_pools rather than a repeated label map (rules.md B-5)"
}

variable "worker_node_pool" {
  type        = string
  default     = "g5-gpu-karpenter"
  description = "Which pool the Ray GPU workers are pinned to. Its labels become the worker pods' nodeSelector and its taints become their tolerations. g5 by default, as the _monolithic template's RayService selected - the g6 pool exists as the alternative, and switching is one value here"
}

# --- NVIDIA device plugin ---

variable "nvidia_device_plugin_chart_version" {
  type        = string
  default     = "0.17.3"
  description = "Pinned nvidia-device-plugin chart version. The _monolithic template applied the plugin's static DaemonSet manifest from a GitHub raw URL at v0.17.1 instead, so it was neither versioned by Helm nor upgradeable"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.nvidia_device_plugin_chart_version))
    error_message = "nvidia_device_plugin_chart_version must be a three-part semantic version."
  }
}

# --- AWS Load Balancer Controller ---

variable "load_balancer_controller_chart_version" {
  type        = string
  default     = "1.14.1"
  description = "Pinned aws-load-balancer-controller chart version. The _monolithic template ran `helm install` with no --version"

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
    # The Ingress names its own frontend security group and does not set
    # manage-backend-security-group-rules, so the controller writes no node-side rules at
    # all and this project declares them itself
    # (aws_vpc_security_group_ingress_rule.load_balancer_to_pods). That is the second row
    # of the table in rules.md G-2, and it is the row that requires false (rules.md B-1).
    condition     = var.enable_backend_security_group == false
    error_message = "enable_backend_security_group must be false in this variant. The Ingress names its own frontend security group and does not set manage-backend-security-group-rules, so the node-side rule is declared in Terraform (load_balancer_to_pods). To let the controller manage it instead, add that annotation and set this to true (rules.md G-2)."
  }
}

variable "enable_service_mutator_webhook" {
  type        = bool
  default     = false
  description = "Whether the AWS Load Balancer Controller installs the mservice.elbv2.k8s.aws mutating webhook, which claims new Services of type LoadBalancer that do not name the controller themselves. False, because no Service here is of that type: the ALB comes from the Ray Serve Ingress, and every Service this project creates - the Karpenter and KubeRay operator charts' own, and the head and serve Services KubeRay builds for the RayService - is ClusterIP. So the webhook has nothing to mutate, while the chart gives it failurePolicy: Fail and no namespaceSelector, which makes it a gate on every Service created anywhere in the cluster. That gate is live in this project: module.karpenter and module.kuberay_operator are ordered only after the node group and CoreDNS, so they install in parallel with the controller, and a Service created between the webhook being registered and the controller's Deployment becoming Available is rejected with \"no endpoints available for service aws-load-balancer-webhook-service\" (rules.md G-4)"

  validation {
    # The constraint is real rather than stylistic, so it belongs here and not in the
    # description (rules.md B-1). The failure it prevents names the webhook rather than
    # the release that tripped over it, which is a long way from the cause - both the
    # Karpenter and the KubeRay operator releases failed this way.
    condition     = var.enable_service_mutator_webhook == false
    error_message = "enable_service_mutator_webhook must stay false in this variant. No Service here is of type LoadBalancer - the ALB comes from an Ingress - so the webhook has nothing to mutate, while its failurePolicy: Fail applies to every Service created in the cluster and makes karpenter and kuberay_operator, which install in parallel with the controller, fail whenever it has no Ready pod. To run with it true, order every module that creates a Service after module.aws_load_balancer_controller, and note that only covers the apply, not a later controller rollout (rules.md G-4)."
  }
}

variable "alb_security_group_name" {
  type        = string
  default     = "alb-sg"
  description = "Name of the frontend security group the Ray Serve ALB carries, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.alb_security_group_name)) && !startswith(var.alb_security_group_name, "sg-")
    error_message = "alb_security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\"."
  }
}

variable "alb_allow_inbound_from_anywhere" {
  type        = bool
  default     = false
  description = <<-DESC
    Whether the Ray Serve ALB is open to the internet. It decides two things together: the frontend security
    group's 0.0.0.0/0 rule, and the Ingress scheme - internet-facing when true, internal when false.

    False. The endpoint has no authentication in front of it and every request it serves runs on a GPU
    instance, so an open address is an open invitation to spend on that capacity. Internal is the scheme
    that makes false usable rather than merely closed: an internet-facing ALB sees the bastion's public
    address, which no security group reference matches, so with the 0.0.0.0/0 rule gone nothing could reach
    it at all. Internal, it is reached from the IDE terminal over private addresses, which the frontend
    group admits by naming the bastion's security group.

    Changing this replaces the ALB: ELB cannot change a load balancer's scheme in place, so the controller
    builds a new one and the address changes.
  DESC
}

variable "serve_port" {
  type        = number
  default     = 8000
  description = "Port Ray Serve's HTTP proxy listens on. One value reaching the RayService container port, the Ingress backend, the ALB listener, the ALB frontend security group and the node-side rule, so none of the five can disagree (rules.md B-5)"

  validation {
    condition     = var.serve_port > 0 && var.serve_port <= 65535
    error_message = "serve_port must be a valid TCP port."
  }
}

# --- KubeRay and the Ray workload ---

variable "kuberay_chart_version" {
  type        = string
  default     = "1.4.2"
  description = "Pinned kuberay-operator chart version, as the _monolithic template pinned it"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.kuberay_chart_version))
    error_message = "kuberay_chart_version must be a three-part semantic version."
  }
}

variable "ray_service_name" {
  type        = string
  default     = "stablediffusion"
  description = "Name of the RayService, which also decides the head Service name the Ingress points at"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.ray_service_name))
    error_message = "ray_service_name must be a valid lowercase RFC 1123 label."
  }
}

variable "ray_service_namespace" {
  type        = string
  default     = "stablediffusion"
  description = "Namespace the RayService and its Ingress live in"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.ray_service_namespace))
    error_message = "ray_service_namespace must be a valid lowercase RFC 1123 label."
  }
}

variable "ray_image" {
  type        = string
  default     = "public.ecr.aws/data-on-eks/ray2.11.0-py310-gpu-stablediffusion:latest"
  description = "Container image for the Ray head and workers, as the _monolithic template referenced it"

  validation {
    condition     = length(var.ray_image) > 0
    error_message = "ray_image must not be empty."
  }
}

variable "ray_version" {
  type        = string
  default     = "2.48.0"
  description = "Ray version the cluster reports, which has to match the Ray inside ray_image"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.ray_version))
    error_message = "ray_version must be a three-part semantic version."
  }
}

variable "model_id" {
  type        = string
  default     = "sd2-community/stable-diffusion-2-1"
  description = "Model the Serve application loads, passed into the runtime environment as MODEL_ID"

  validation {
    condition     = length(var.model_id) > 0
    error_message = "model_id must not be empty."
  }
}

variable "serve_min_replicas" {
  type        = number
  default     = 1
  description = "Minimum Serve replicas, each holding one GPU"

  validation {
    condition     = var.serve_min_replicas >= 0
    error_message = "serve_min_replicas must be zero or greater."
  }
}

variable "serve_max_replicas" {
  type        = number
  default     = 4
  description = "Maximum Serve replicas. Each one holds a GPU, so this is the ceiling on the GPU instances Karpenter is asked for - and the number worth checking before leaving this running"

  validation {
    condition     = var.serve_max_replicas >= 1
    error_message = "serve_max_replicas must be at least 1."
  }
}

# --- Bastion and CloudFront ---

variable "bastion_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type of the code-server bastion, as the _monolithic template sized it"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.bastion_instance_type))
    error_message = "bastion_instance_type must look like an EC2 instance type (e.g. t3.medium)."
  }
}

variable "allow_bastion_inbound_from_anywhere" {
  type        = bool
  default     = false
  description = "Whether the bastion's security group accepts code-server traffic from 0.0.0.0/0. False, as the _monolithic template had it: the only inbound rule is the CloudFront origin-facing prefix list, so the IDE is reached through the distribution rather than directly"
}

variable "cloudfront_prefix_list_name" {
  type        = string
  default     = "com.amazonaws.global.cloudfront.origin-facing"
  description = "Managed prefix list holding the addresses CloudFront makes origin requests from, looked up by name. The _monolithic template carried a mapping of hardcoded prefix list IDs keyed by region, so a region missing from the table failed with an error about a map key"

  validation {
    condition     = length(var.cloudfront_prefix_list_name) > 0
    error_message = "cloudfront_prefix_list_name must not be empty."
  }
}

variable "cloudfront_origin_request_policy_name" {
  type        = string
  default     = "Managed-AllViewer"
  description = "Managed origin request policy, by name. The distribution needs every header forwarded, because code-server upgrades to a WebSocket"

  validation {
    condition     = length(var.cloudfront_origin_request_policy_name) > 0
    error_message = "cloudfront_origin_request_policy_name must not be empty."
  }
}

variable "cloudfront_price_class" {
  type        = string
  default     = "PriceClass_200"
  description = "CloudFront price class"

  validation {
    condition     = contains(["PriceClass_All", "PriceClass_200", "PriceClass_100"], var.cloudfront_price_class)
    error_message = "cloudfront_price_class must be one of: PriceClass_All, PriceClass_200, PriceClass_100."
  }
}

variable "kubectl_download_version" {
  type        = string
  default     = "1.34.11/2026-09-22"
  description = "kubectl build downloaded onto the bastion, as <version>/<release-date>. Kept within one minor of kubernetes_version; the _monolithic template pinned a 1.33 build"

  validation {
    condition     = can(regex("^1\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.34.11/2026-09-22."
  }
}

variable "code_server_version" {
  type        = string
  default     = "4.108.2"
  description = "code-server release installed on the bastion. The _monolithic template pinned 4.102.3"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a three-part semantic version."
  }
}

variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the bastion where each bootstrap stage drops its completion marker (rules.md D-5)"

  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/'."
  }
}

variable "readme_timeout_seconds" {
  type        = number
  default     = 1800
  description = "How long the README association waits for success. It has to cover the whole instance bootstrap, since the command blocks on the userdata marker"

  validation {
    condition     = var.readme_timeout_seconds >= 300
    error_message = "readme_timeout_seconds must be at least 300."
  }
}
