variable "name" {
  type        = string
  default     = "stablediffusion"
  description = "Name of the RayService. The operator derives the head Service name from it as <name>-head-svc, which is what the Ingress points at"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 label."
  }
}

variable "namespace" {
  type        = string
  default     = "stablediffusion"
  description = "Namespace the RayService and its Ingress live in"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 label."
  }
}

variable "create_namespace" {
  type        = bool
  default     = true
  description = "Whether this module creates the namespace. False when something else owns it (rules.md B-4)"
}

variable "image" {
  type        = string
  default     = "public.ecr.aws/data-on-eks/ray2.11.0-py310-gpu-stablediffusion:latest"
  description = "Container image for both the head and the workers. One image for both, as the _monolithic template had it: the head imports the same Serve module the workers run"

  validation {
    condition     = length(var.image) > 0
    error_message = "image must not be empty."
  }
}

variable "image_pull_policy" {
  type        = string
  default     = "IfNotPresent"
  description = "Image pull policy. IfNotPresent, so a node that already cached this several-gigabyte image does not pull it again when a pod restarts"

  validation {
    condition     = contains(["Always", "IfNotPresent", "Never"], var.image_pull_policy)
    error_message = "image_pull_policy must be one of: Always, IfNotPresent, Never."
  }
}

variable "ray_version" {
  type        = string
  default     = "2.48.0"
  description = "Ray version the cluster reports. It has to match the Ray inside the image - a mismatch is what KubeRay reports as a version check failure rather than as a wrong image"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.ray_version))
    error_message = "ray_version must be a three-part semantic version."
  }
}

variable "enable_in_tree_autoscaling" {
  type        = bool
  default     = true
  description = "Whether the Ray autoscaler runs inside the cluster and adds worker pods on demand. True: it is the inner of the two autoscalers in this project - it asks for pods, and Karpenter then provides nodes for them"
}

variable "model_id" {
  type        = string
  default     = "sd2-community/stable-diffusion-2-1"
  description = "Model the Serve application loads, passed as the MODEL_ID environment variable"

  validation {
    condition     = length(var.model_id) > 0
    error_message = "model_id must not be empty."
  }
}

variable "extra_env_vars" {
  type        = map(string)
  default     = {}
  description = "Extra environment variables merged into the Serve runtime environment alongside MODEL_ID"
}

variable "serve_application_name" {
  type        = string
  default     = "stable-diffusion-deployment"
  description = "Name of the Serve application"

  validation {
    condition     = length(var.serve_application_name) > 0
    error_message = "serve_application_name must not be empty."
  }
}

variable "serve_deployment_name" {
  type        = string
  default     = "stable-diffusion-v2"
  description = "Name of the Serve deployment inside the application. It has to match the name the module at serve_import_path declares, or the autoscaling and actor options below apply to nothing"

  validation {
    condition     = length(var.serve_deployment_name) > 0
    error_message = "serve_deployment_name must not be empty."
  }
}

variable "serve_import_path" {
  type        = string
  default     = "ray_serve_sd:entrypoint"
  description = "Python import path of the Serve entrypoint, as <module>:<attribute>. It refers to a module inside the image, so changing the image usually means changing this"

  validation {
    condition     = can(regex("^[A-Za-z_][A-Za-z0-9_.]*:[A-Za-z_][A-Za-z0-9_]*$", var.serve_import_path))
    error_message = "serve_import_path must look like module:attribute."
  }
}

variable "serve_route_prefix" {
  type        = string
  default     = "/"
  description = "HTTP prefix the Serve application answers on"

  validation {
    condition     = startswith(var.serve_route_prefix, "/")
    error_message = "serve_route_prefix must start with '/'."
  }
}

variable "serve_pip_packages" {
  type        = list(string)
  default     = ["transformers==4.25.1"]
  description = "Packages installed into the Serve runtime environment on top of the image, pinned as the _monolithic template pinned them. Every entry is installed when a replica starts, so this is a cost paid per replica rather than once per image"
}

variable "serve_min_replicas" {
  type        = number
  default     = 1
  description = "Minimum Serve replicas. One, so the model is loaded and the first request does not pay for it"

  validation {
    condition     = var.serve_min_replicas >= 0
    error_message = "serve_min_replicas must be zero or greater."
  }
}

variable "serve_max_replicas" {
  type        = number
  default     = 4
  description = "Maximum Serve replicas. Each one holds a GPU, so this is also the ceiling on how many GPU instances Karpenter is asked for"

  validation {
    condition     = var.serve_max_replicas >= 1
    error_message = "serve_max_replicas must be at least 1."
  }
}

variable "serve_target_ongoing_requests" {
  type        = number
  default     = 1
  description = "Requests per replica the autoscaler aims for. target_ongoing_requests is the current name; the _monolithic template used target_num_ongoing_requests_per_replica, which Ray removed - the default also changed from 1 to 2 in Ray 2.32, so it is stated explicitly"

  validation {
    condition     = var.serve_target_ongoing_requests > 0
    error_message = "serve_target_ongoing_requests must be greater than zero."
  }
}

variable "serve_max_ongoing_requests" {
  type        = number
  default     = 100
  description = "Requests a replica accepts without responding. max_ongoing_requests is the current name for what the _monolithic template called max_concurrent_queries; the default dropped from 100 to 5 in Ray 2.32, so the original value is stated rather than assumed"

  validation {
    condition     = var.serve_max_ongoing_requests >= 1
    error_message = "serve_max_ongoing_requests must be at least 1."
  }
}

variable "serve_metrics_interval_seconds" {
  type        = number
  default     = 0.2
  description = "How often replicas report their queue depth to the autoscaler"

  validation {
    condition     = var.serve_metrics_interval_seconds > 0
    error_message = "serve_metrics_interval_seconds must be greater than zero."
  }
}

variable "serve_look_back_period_seconds" {
  type        = number
  default     = 2
  description = "Window the autoscaler averages request metrics over"

  validation {
    condition     = var.serve_look_back_period_seconds > 0
    error_message = "serve_look_back_period_seconds must be greater than zero."
  }
}

variable "serve_upscale_delay_seconds" {
  type        = number
  default     = 30
  description = "How long sustained load must persist before a replica is added"

  validation {
    condition     = var.serve_upscale_delay_seconds >= 0
    error_message = "serve_upscale_delay_seconds must be zero or greater."
  }
}

variable "serve_downscale_delay_seconds" {
  type        = number
  default     = 600
  description = "How long the load must stay low before a replica is removed. Ten minutes, and deliberately long: removing a replica throws away several minutes of model loading"

  validation {
    condition     = var.serve_downscale_delay_seconds >= 0
    error_message = "serve_downscale_delay_seconds must be zero or greater."
  }
}

variable "serve_graceful_shutdown_timeout_seconds" {
  type        = number
  default     = 5
  description = "How long a replica is given to finish in-flight requests before it is killed"

  validation {
    condition     = var.serve_graceful_shutdown_timeout_seconds >= 0
    error_message = "serve_graceful_shutdown_timeout_seconds must be zero or greater."
  }
}

variable "serve_actor_cpus" {
  type        = number
  default     = 3
  description = "CPUs each Serve replica reserves inside Ray. Ray's own accounting, separate from the pod's Kubernetes requests - it has to fit inside the worker container's cpu request or replicas queue forever with capacity apparently available"

  validation {
    condition     = var.serve_actor_cpus > 0
    error_message = "serve_actor_cpus must be greater than zero."
  }
}

variable "serve_actor_gpus" {
  type        = number
  default     = 1
  description = "GPUs each Serve replica reserves inside Ray. One, matching the GPU the worker pod requests, so one replica occupies one worker"

  validation {
    condition     = var.serve_actor_gpus >= 0
    error_message = "serve_actor_gpus must be zero or greater."
  }
}

variable "serve_port" {
  type        = number
  default     = 8000
  description = "Port the Serve HTTP proxy listens on, which is also the port the Ingress backend names"

  validation {
    condition     = var.serve_port > 0 && var.serve_port <= 65535
    error_message = "serve_port must be a valid TCP port."
  }
}

variable "head_cpu" {
  type        = string
  default     = "2"
  description = "CPU request and limit for the head container, set to the same value so the pod is Guaranteed"

  validation {
    condition     = can(regex("^[0-9]+m?$", var.head_cpu))
    error_message = "head_cpu must be a Kubernetes CPU quantity such as 2 or 500m."
  }
}

variable "head_memory" {
  type        = string
  default     = "16Gi"
  description = "Memory request and limit for the head container"

  validation {
    condition     = can(regex("^[0-9]+(Ki|Mi|Gi)$", var.head_memory))
    error_message = "head_memory must be a Kubernetes memory quantity such as 16Gi."
  }
}

variable "head_node_selector" {
  type        = map(string)
  description = "Labels the head pod requires on its node. Taken from the CPU Karpenter pool's labels, so the head cannot land on a GPU node and occupy an instance the workers need (rules.md B-5)"

  validation {
    condition     = length(var.head_node_selector) > 0
    error_message = "head_node_selector must not be empty. With several node pools in the cluster, an unconstrained head pod lands on whichever pool fits first."
  }
}

variable "worker_group_name" {
  type        = string
  default     = "gpu"
  description = "Name of the Ray worker group"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.worker_group_name))
    error_message = "worker_group_name must be a valid lowercase RFC 1123 label."
  }
}

variable "worker_min_replicas" {
  type        = number
  default     = 1
  description = "Minimum Ray worker pods. One, so a GPU node exists and the model is loaded before the first request arrives"

  validation {
    condition     = var.worker_min_replicas >= 0
    error_message = "worker_min_replicas must be zero or greater."
  }
}

variable "worker_max_replicas" {
  type        = number
  default     = 4
  description = "Maximum Ray worker pods. Each one asks for a GPU, so this is the ceiling the Karpenter GPU pool is asked to satisfy"

  validation {
    condition     = var.worker_max_replicas >= 1
    error_message = "worker_max_replicas must be at least 1."
  }
}

variable "worker_cpu" {
  type        = string
  default     = "3"
  description = "CPU request and limit for each worker container"

  validation {
    condition     = can(regex("^[0-9]+m?$", var.worker_cpu))
    error_message = "worker_cpu must be a Kubernetes CPU quantity such as 3 or 500m."
  }
}

variable "worker_memory" {
  type        = string
  default     = "14Gi"
  description = "Memory request and limit for each worker container"

  validation {
    condition     = can(regex("^[0-9]+(Ki|Mi|Gi)$", var.worker_memory))
    error_message = "worker_memory must be a Kubernetes memory quantity such as 14Gi."
  }
}

variable "worker_gpus" {
  type        = number
  default     = 1
  description = "GPUs each worker pod requests. Requires the NVIDIA device plugin to be advertising nvidia.com/gpu, or the pods stay Pending on nodes that physically have GPUs"

  validation {
    condition     = var.worker_gpus >= 1
    error_message = "worker_gpus must be at least 1; a worker group that asks for no GPU does not need a GPU node pool."
  }
}

variable "worker_node_selector" {
  type        = map(string)
  description = "Labels the worker pods require on their node. Taken from the GPU Karpenter pool's labels (rules.md B-5)"

  validation {
    condition     = length(var.worker_node_selector) > 0
    error_message = "worker_node_selector must not be empty."
  }
}

variable "worker_node_taints" {
  type = list(object({
    key    = string
    value  = string
    effect = string
  }))
  default     = []
  description = "Taints on the GPU pool's nodes, which this module turns into the worker pods' tolerations. Taken from the pool rather than restated, so a toleration cannot drift from the taint it exists for (rules.md B-5)"

  validation {
    condition     = alltrue([for t in var.worker_node_taints : contains(["NoSchedule", "PreferNoSchedule", "NoExecute"], t.effect)])
    error_message = "worker_node_taints effects must be one of: NoSchedule, PreferNoSchedule, NoExecute."
  }
}

variable "create_ingress" {
  type        = bool
  default     = true
  description = "Whether to create the Ingress in front of the Serve HTTP port. False leaves the RayService reachable only from inside the cluster (rules.md B-4)"
}

variable "ingress_name" {
  type        = string
  default     = "serve"
  description = "Name of the Ingress, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.ingress_name))
    error_message = "ingress_name must be a valid lowercase RFC 1123 label."
  }
}

variable "ingress_class_name" {
  type        = string
  default     = "alb"
  description = "IngressClass the Ingress asks for. Without it no controller claims the Ingress, which is not an error - the Ingress simply never gets an address (rules.md G-1)"

  validation {
    condition     = length(var.ingress_class_name) > 0
    error_message = "ingress_class_name must not be empty."
  }
}

variable "ingress_annotations" {
  type        = map(string)
  description = "Annotations the AWS Load Balancer Controller reads: scheme, target type and the frontend security groups. Supplied by the caller, because the security group IDs come from other modules (rules.md B-6/G-1)"

  validation {
    condition     = alltrue([for key in keys(var.ingress_annotations) : length(key) > 0])
    error_message = "ingress_annotations keys must not be empty."
  }
}
