variable "storage_class_name" {
  type        = string
  description = "StorageClass the volumeClaimTemplate names. Taken from the storage module's output rather than restated, because a claim naming a class that does not exist stays Pending and the StatefulSet says nothing about why (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.storage_class_name))
    error_message = "storage_class_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "name" {
  type        = string
  default     = "web"
  description = "Name of the StatefulSet and the label its pods carry, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "service_name" {
  type        = string
  default     = "nginx"
  description = "Name of the Service, as the _monolithic template named it. Also what the StatefulSet's serviceName field points at - which is not strictly correct for a type LoadBalancer Service, since per-pod DNS needs a headless one, but it is what the original had and this demo does not use per-pod DNS"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.service_name))
    error_message = "service_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "default"
  description = "Namespace both objects go in, as the _monolithic template had it - and the namespace the demo backup includes. Not created here: default already exists, and a module that created it would delete it on destroy"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "replicas" {
  type        = number
  default     = 2
  description = "Pods in the StatefulSet, two as the _monolithic template had it. Each gets its own volume from the claim template, so two is also two volumes to snapshot - which is what makes the backup take visibly longer than a stateless one"

  validation {
    condition     = var.replicas >= 1
    error_message = "replicas must be at least 1."
  }
}
variable "image" {
  type        = string
  default     = "public.ecr.aws/nginx/nginx:1.29.5-alpine"
  description = "Container image. The _monolithic template used registry.k8s.io/nginx-slim:0.8, the image from the upstream StatefulSet tutorial - a build from 2016 that is amd64-only and has had no security updates in the better part of a decade. Pinned and from ECR Public here, which also avoids a rate-limited anonymous pull on a cluster whose nodes share one NAT gateway address per zone"

  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$", var.image))
    error_message = "image must carry an explicit tag."
  }
}
variable "container_port" {
  type        = number
  default     = 80
  description = "Port the container listens on, and the Service's targetPort. With nlb_target_type ip the load balancer sends traffic here directly rather than to a node port (rules.md G-1)"

  validation {
    condition     = var.container_port > 0 && var.container_port < 65536
    error_message = "container_port must be a valid TCP port."
  }
}
variable "service_port" {
  type        = number
  default     = 80
  description = "Port the Service publishes, which becomes the load balancer's listener port"

  validation {
    condition     = var.service_port > 0 && var.service_port < 65536
    error_message = "service_port must be a valid TCP port."
  }
}
variable "volume_name" {
  type        = string
  default     = "www"
  description = "Name of the volumeClaimTemplate, as the _monolithic template named it. It becomes part of each claim's name (<volume>-<statefulset>-<ordinal>), which is what a restore recreates"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.volume_name))
    error_message = "volume_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "mount_path" {
  type        = string
  default     = "/usr/share/nginx/html"
  description = "Where the volume is mounted, as the _monolithic template had it. nginx serves this directory, so writing a file into it and reading it back through the load balancer is how a restore is proved to have moved the data rather than only the objects"

  validation {
    condition     = can(regex("^/", var.mount_path))
    error_message = "mount_path must be an absolute path."
  }
}
variable "volume_size" {
  type        = string
  default     = "1Gi"
  description = "Size of each pod's volume, as the _monolithic template had it. Small on purpose: the backup moves this data through the node agent into S3, and a large volume makes the demo slow without making it clearer"

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi|Ti)$", var.volume_size))
    error_message = "volume_size must be a binary quantity such as 1Gi."
  }
}
variable "cpu_request" {
  type        = string
  default     = "100m"
  description = "CPU request per pod. The _monolithic template set no requests at all, which lets the scheduler put both replicas on one node - and with WaitForFirstConsumer binding, both volumes then land in one availability zone, so a zone failure takes the whole demo rather than half of it"

  validation {
    condition     = can(regex("^[0-9]+m?$", var.cpu_request))
    error_message = "cpu_request must be a Kubernetes CPU quantity such as 100m or 1."
  }
}
variable "memory_request" {
  type        = string
  default     = "64Mi"
  description = "Memory request per pod"

  validation {
    condition     = can(regex("^[0-9]+(Ki|Mi|Gi)?$", var.memory_request))
    error_message = "memory_request must be a Kubernetes memory quantity such as 64Mi."
  }
}
variable "load_balancer_scheme" {
  type        = string
  default     = "internet-facing"
  description = "Whether the NLB is reachable from the internet. internet-facing needs public subnets carrying the kubernetes.io/role/elb tag, which the network module writes (rules.md G-1)"

  validation {
    condition     = contains(["internet-facing", "internal"], var.load_balancer_scheme)
    error_message = "load_balancer_scheme must be either internet-facing or internal."
  }
}
variable "nlb_target_type" {
  type        = string
  default     = "ip"
  description = "Whether the load balancer targets pod IPs or node ports. ip, so traffic reaches the container port directly - which works because the VPC CNI makes pod addresses routable in the VPC. Note the annotation key carries an nlb- prefix that the ALB equivalent does not, and the wrong one is ignored rather than rejected (rules.md G-1)"

  validation {
    condition     = contains(["ip", "instance"], var.nlb_target_type)
    error_message = "nlb_target_type must be either ip or instance."
  }
}
variable "service_annotations" {
  type        = map(string)
  default     = {}
  description = "Extra annotations merged onto the Service, for anything this module does not expose as a named variable. Merged over the three it always sets, so a caller can override them - including aws-load-balancer-type, which would hand the Service back to the in-tree provider"

  validation {
    condition     = alltrue([for key in keys(var.service_annotations) : length(key) > 0])
    error_message = "service_annotations must not contain empty annotation keys."
  }
}
