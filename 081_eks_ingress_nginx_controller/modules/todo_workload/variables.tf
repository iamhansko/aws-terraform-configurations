variable "name" {
  type        = string
  default     = "todo"
  description = "Name of the Deployment and the value of the app label its Service and its PodDisruptionBudget-free selector match on"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "default"
  description = "Namespace everything here lives in, as the _monolithic template had it. Not created here - default already exists, and a module that created it would delete it on destroy"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "replicas" {
  type        = number
  default     = 1
  description = "How many pods to run, one as the _monolithic template had it. One is not an arbitrary choice here: the MySQL sidecar writes to a ReadWriteOnce volume, so a second replica would be scheduled onto a node that cannot attach it and would stay Pending"

  validation {
    condition     = var.replicas == 1
    error_message = "replicas must be 1. The pod carries its own MySQL container backed by a ReadWriteOnce claim, so a second replica cannot attach the volume and stays Pending - to run more than one, split MySQL out into its own workload first."
  }
}
variable "app_image" {
  type        = string
  default     = "sce06147/fastapi-todo-app:latest"
  description = "Container image for the FastAPI app, as the _monolithic template had it. Worth knowing what it is: an image on Docker Hub whose only published tag is latest, so the tag is mutable and the registry rate-limits anonymous pulls per source address - every node here shares one NAT gateway address per zone. Nothing else in this project pulls from Docker Hub"

  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$|@sha256:[0-9a-f]{64}$", var.app_image))
    error_message = "app_image must carry an explicit tag or a digest."
  }
}
variable "app_container_port" {
  type        = number
  default     = 8000
  description = "Port uvicorn listens on inside the pod, and the Service's target port"

  validation {
    condition     = var.app_container_port > 0 && var.app_container_port <= 65535
    error_message = "app_container_port must be a valid TCP port."
  }
}
variable "path_prefix" {
  type        = string
  default     = "/v1"
  description = "The one prefix the app is served under, and the point where this module earns its keep. It reaches three places that have to agree: uvicorn's --root-path, the Ingress rule's path regex (<prefix>/(.*)), and the rewrite-target annotation that strips it again. The _monolithic template wrote /v1 into all three by hand, so changing it meant changing three strings and getting a 404 from the app if any one was missed (rules.md B-1)"

  validation {
    condition     = can(regex("^/[a-z0-9][a-z0-9-]*$", var.path_prefix))
    error_message = "path_prefix must be a single absolute path segment such as /v1 - it is interpolated into a regex and into uvicorn's --root-path, neither of which accepts a trailing slash."
  }
}
variable "mysql_image" {
  type        = string
  default     = "public.ecr.aws/docker/library/mysql:8.0.44"
  description = "Container image for the MySQL sidecar. Pinned to a patch version and taken from the ECR Public mirror, where the _monolithic template used mysql:8.0 from Docker Hub - a tag that moves, on a registry that rate-limits anonymous pulls per source address"

  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$|@sha256:[0-9a-f]{64}$", var.mysql_image))
    error_message = "mysql_image must carry an explicit tag or a digest."
  }
}
variable "mysql_port" {
  type        = number
  default     = 3306
  description = "Port MySQL listens on inside the pod. The app reaches it over localhost because both containers share the pod's network namespace, which is also why no Service publishes it"

  validation {
    condition     = var.mysql_port > 0 && var.mysql_port <= 65535
    error_message = "mysql_port must be a valid TCP port."
  }
}
variable "mysql_database" {
  type        = string
  default     = "demo"
  description = "Database the MySQL image creates on first start, which the app's migration step then populates"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.mysql_database))
    error_message = "mysql_database must contain only letters, digits and underscores."
  }
}
variable "mysql_timezone" {
  type        = string
  default     = "Asia/Seoul"
  description = "TZ for the MySQL container, as the _monolithic template had it"

  validation {
    condition     = length(var.mysql_timezone) > 0
    error_message = "mysql_timezone must not be empty."
  }
}
variable "create_dnsutils_container" {
  type        = bool
  default     = true
  description = "Whether to keep the third container, an agnhost image the _monolithic template called dnsutils and used as a shell for DNS and connectivity checks from inside the pod. It runs agnhost pause - the image's own default command - so it costs nothing but a container slot. Set false to drop it (rules.md B-4)"
}
variable "dnsutils_image" {
  type        = string
  default     = "registry.k8s.io/e2e-test-images/agnhost:2.39"
  description = "Image for that debugging container, as the _monolithic template had it. Its ENTRYPOINT is /agnhost and its CMD is pause, so the manifest deliberately sets no command - which is what keeps it sleeping rather than exiting and restarting"

  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$|@sha256:[0-9a-f]{64}$", var.dnsutils_image))
    error_message = "dnsutils_image must carry an explicit tag or a digest."
  }
}
variable "storage_class_name" {
  type        = string
  description = "Name of the StorageClass the claim asks for. Taken from the module that created the class rather than restated, because a claim naming a class that does not exist stays Pending and the pod never starts - with nothing on the Deployment to say why (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.storage_class_name))
    error_message = "storage_class_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "volume_size" {
  type        = string
  default     = "3Gi"
  description = "Size of the claim MySQL's data directory sits on, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi|Ti)$", var.volume_size))
    error_message = "volume_size must be a Kubernetes storage quantity such as 3Gi."
  }
}
variable "service_port" {
  type        = number
  default     = 8000
  description = "Port the Service publishes. The Ingress backend names this port, and the ingress controller reaches the pod through it"

  validation {
    condition     = var.service_port > 0 && var.service_port <= 65535
    error_message = "service_port must be a valid TCP port."
  }
}
variable "ingress_class_name" {
  type        = string
  description = "IngressClass this Ingress names in spec.ingressClassName, which is what decides which of the cluster's ingress controllers reconciles it. No default: naming a class no controller owns leaves the Ingress with no address and no error, and that is precisely the mistake this project's two classes make easy"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.ingress_class_name))
    error_message = "ingress_class_name must be a valid lowercase RFC 1123 DNS label."
  }
}
