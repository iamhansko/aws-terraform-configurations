variable "namespace" {
  type        = string
  default     = "default"
  description = "Namespace both pods run in, as the _monolithic template had it. Not created here - default already exists, and a module that created it would delete it on destroy"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "smi_pod_name" {
  type        = string
  default     = "nvidia-smi"
  description = "Name of the pod that just runs nvidia-smi. It is the cheapest possible check that a GPU was actually attached to a container rather than merely advertised by the node"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.smi_pod_name))
    error_message = "smi_pod_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "smi_image" {
  type        = string
  default     = "public.ecr.aws/amazonlinux/amazonlinux:2023-minimal"
  description = "Image for that pod, as the _monolithic template had it. It contains no NVIDIA tooling of its own: nvidia-smi works inside it because the container runtime injects the driver from the host, which is the thing being demonstrated"

  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$|@sha256:[0-9a-f]{64}$", var.smi_image))
    error_message = "smi_image must carry an explicit tag or a digest."
  }
}
variable "app_pod_name" {
  type        = string
  default     = "musicgpt"
  description = "Name of the application pod"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.app_pod_name))
    error_message = "app_pod_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "app_image" {
  type        = string
  default     = "gabotechs/musicgpt:0.3.28"
  description = "Image for the application pod. Pinned to a version tag, where the _monolithic template used the bare name gabotechs/musicgpt - docker.io's floating latest, from a registry that rate-limits anonymous pulls per source address. 0.3.28 is the newest tag the image is published under; a tag that does not exist is not caught by plan and only shows up as a Deployment that never finishes rolling out. The image is large - about 2.1 GB compressed, nearly all of it the CUDA 12.6 and cuDNN 9 runtime the binary links against - but it holds no model weights: the application downloads those into app_data_path when it first starts"

  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$|@sha256:[0-9a-f]{64}$", var.app_image))
    error_message = "app_image must carry an explicit tag or a digest."
  }
}
variable "app_port" {
  type        = number
  default     = 8642
  description = "Port the application's web interface listens on, as the _monolithic template had it. Nothing publishes it: there is no Service and no load balancer here, so the interface is reached with kubectl port-forward - which is also the only way the original could have reached it, though it never said so"

  validation {
    condition     = var.app_port > 0 && var.app_port <= 65535
    error_message = "app_port must be a valid TCP port."
  }
}
variable "app_args" {
  type        = list(string)
  default     = ["--ui-expose", "--gpu"]
  description = "Arguments to the application, as the _monolithic template had them. --gpu is the half that matters here: without it the container runs on the CPU and the whole GPU arrangement around it proves nothing"

  validation {
    condition     = length(var.app_args) > 0
    error_message = "app_args must contain at least one argument."
  }
}
variable "app_replicas" {
  type        = number
  default     = 1
  description = "How many application pods to run. One without time slicing, because one GPU is one nvidia.com/gpu and a second pod would stay Pending - which is exactly what the time-slicing cluster is for, and there this can be raised to watch several pods share a card"

  validation {
    condition     = var.app_replicas >= 1
    error_message = "app_replicas must be at least 1."
  }
}
variable "app_data_path" {
  type        = string
  default     = "/root/.local/share/musicgpt"
  description = "Where the application keeps its downloaded models inside the container, as the _monolithic template had it. Backed by a host path so a restarted pod on the same node does not download them again"

  validation {
    condition     = can(regex("^/", var.app_data_path))
    error_message = "app_data_path must be an absolute path."
  }
}
variable "app_host_path" {
  type        = string
  default     = "/var/lib/musicgpt"
  description = "Directory on the node the model cache is kept in. Changed from the _monolithic template's /home/user/.musicgpt, which names a home directory that does not exist on an EKS AL2023 node - hostPath with DirectoryOrCreate creates it anyway, as a root-owned directory under a path nothing else uses, so the original worked by accident. /var/lib is where a node is expected to hold state of this kind. A hostPath at all is the compromise: the cache is tied to one node, so a pod rescheduled elsewhere downloads the models again"

  validation {
    condition     = can(regex("^/", var.app_host_path))
    error_message = "app_host_path must be an absolute path."
  }
}
variable "gpu_request" {
  type        = number
  default     = 1
  description = "How many nvidia.com/gpu each pod asks for. One, and it has to be a whole number - the resource is countable rather than divisible, which is why sharing a GPU needs the device plugin to advertise several of them rather than a pod asking for a fraction"

  validation {
    condition     = var.gpu_request >= 1 && floor(var.gpu_request) == var.gpu_request
    error_message = "gpu_request must be a whole number of GPUs. Kubernetes extended resources cannot be requested fractionally - to share one GPU, have the device plugin advertise it as several (time slicing) instead."
  }
}
variable "gpu_toleration_key" {
  type        = string
  default     = "nvidia.com/gpu"
  description = "Taint key the pods tolerate, as the _monolithic template's nvidia-smi pod did. The AL2023 NVIDIA AMI does not taint its nodes, so nothing here needs the toleration today - it is kept because a GPU node group is usually tainted to keep ordinary workloads off it, and a pod without the toleration then stays Pending on a cluster with idle GPUs"

  validation {
    condition     = length(var.gpu_toleration_key) > 0
    error_message = "gpu_toleration_key must not be empty."
  }
}
