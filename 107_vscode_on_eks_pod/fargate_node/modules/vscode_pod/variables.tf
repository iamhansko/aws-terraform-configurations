variable "name" {
  type        = string
  default     = "vscode"
  description = "Name shared by the StatefulSet, Service, ServiceAccount, ConfigMaps and Ingress, as the _monolithic template named them"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 label."
  }
}

variable "namespace" {
  type        = string
  default     = "default"
  description = "Namespace every object is created in, as the _monolithic template placed them. The first half of the load balancer's adoption stack tag (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 label."
  }
}

variable "image" {
  type        = string
  default     = "codercom/code-server:4.108.2-fedora"
  description = <<-DESC
    Image the code-server container runs.

    The tag suffix is the base distribution, not a build number: 4.108.2-fedora and 4.108.2-39 are the same
    digest (Fedora 39), while a bare 4.108.2 is Debian bookworm. That matters because the tooling installed
    into this pod has to match - the _monolithic template's in-pod script ran dnf and yum, which only exist
    on the Fedora variant. Switching to the bare tag silently breaks it.
  DESC

  validation {
    condition     = can(regex("^[^\\s]+:[^\\s:]+$", var.image))
    error_message = "image must include an explicit tag; a floating :latest makes a restart a different pod."
  }
}

variable "container_port" {
  type        = number
  default     = 8080
  description = "Port code-server listens on inside the pod, and the Service and Ingress backend port. One value reaching all three (rules.md B-5)"

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port must be a valid TCP port."
  }
}

variable "replicas" {
  type        = number
  default     = 1
  description = "Replica count. One, and deliberately not more: code-server keeps editor state in the container, so a second replica behind one load balancer serves a different workspace on alternate requests"

  validation {
    condition     = var.replicas >= 1
    error_message = "replicas must be at least 1."
  }
}

variable "cpu_request" {
  type        = string
  default     = "3"
  description = "CPU request, as the _monolithic template set it. Sized so one pod fits a single node of the group and no second pod lands beside it"

  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?m?$", var.cpu_request))
    error_message = "cpu_request must be a Kubernetes CPU quantity (e.g. 3, 500m)."
  }
}

variable "memory_request" {
  type        = string
  default     = "12Gi"
  description = "Memory request, as the _monolithic template set it"

  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?(Ki|Mi|Gi|Ti|K|M|G|T)?$", var.memory_request))
    error_message = "memory_request must be a Kubernetes memory quantity (e.g. 12Gi)."
  }
}

variable "service_account_annotations" {
  type        = map(string)
  default     = {}
  description = "Annotations on the ServiceAccount. Empty for a cluster using EKS Pod Identity, which needs none; the IRSA role annotation goes here for a Fargate-only cluster, where Pod Identity is not supported"
}

# --- Cluster credentials baked into a kubeconfig ---

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster, written into the kubeconfig the pod mounts"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}

variable "cluster_endpoint" {
  type        = string
  description = "API server endpoint, written into the kubeconfig the pod mounts"

  validation {
    condition     = can(regex("^https://", var.cluster_endpoint))
    error_message = "cluster_endpoint must be an https URL."
  }
}

variable "certificate_authority_data" {
  type        = string
  description = "Base64 cluster CA, written into the kubeconfig the pod mounts. Passed already encoded because that is the form a kubeconfig wants"

  validation {
    condition     = can(base64decode(var.certificate_authority_data))
    error_message = "certificate_authority_data must be base64 encoded."
  }
}

variable "aws_region" {
  type        = string
  description = "Region the kubeconfig's token command is run against, and the AWS_REGION the container gets"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region name."
  }
}

# --- Tools installed into the pod ---

variable "install_tools" {
  type        = bool
  default     = true
  description = <<-DESC
    Whether an init container installs kubectl, helm, eksctl, terraform and the AWS CLI into the pod.

    An init container rather than the kubectl exec the _monolithic template used, for two reasons. The exec
    was not declarative - nothing recorded that it had run, and a second apply re-ran it - and more
    importantly its results did not survive: the tools went into the container's own filesystem, so every
    restart of the StatefulSet pod came back without them. Here they land in a volume the init container
    fills on every start (rules.md E-1).
  DESC
}

variable "tools_init_image" {
  type        = string
  default     = "public.ecr.aws/docker/library/alpine:3.22"
  description = "Image the init container runs. Only needs wget, tar and unzip; from the ECR public mirror of the official image rather than Docker Hub, whose anonymous pull limit is shared by every node in the region"

  validation {
    condition     = can(regex("^[^\\s]+:[^\\s:]+$", var.tools_init_image))
    error_message = "tools_init_image must include an explicit tag."
  }
}

variable "tools_path" {
  type        = string
  default     = "/home/coder/tools"
  description = "Directory the init container fills and the container prepends to PATH. Inside the home directory so it is visible from the IDE's file tree"

  validation {
    condition     = can(regex("^/", var.tools_path))
    error_message = "tools_path must be an absolute path."
  }
}

variable "kubectl_download_version" {
  type        = string
  default     = "1.34.11/2026-09-22"
  description = "kubectl build installed into the pod, as <version>/<release-date>. Keep within one minor of the cluster version"

  validation {
    condition     = can(regex("^1\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.34.11/2026-09-22."
  }
}

variable "helm_version" {
  type        = string
  default     = "3.19.1"
  description = "helm release installed into the pod. Pinned rather than fetched through get-helm-4, which resolves the latest release at pod start - so two restarts of the same pod could get different versions"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.helm_version))
    error_message = "helm_version must be a three-part semantic version."
  }
}

variable "eksctl_version" {
  type        = string
  default     = "0.220.0"
  description = "eksctl release installed into the pod. Pinned, and from eksctl-io rather than the weaveworks path the _monolithic template used - that one still redirects, but it is not the project's name any more"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.eksctl_version))
    error_message = "eksctl_version must be a three-part semantic version."
  }
}

variable "terraform_version" {
  type        = string
  default     = "1.14.5"
  description = "Terraform release installed into the pod. Downloaded as a release zip rather than through the HashiCorp yum repository the _monolithic template added, which needs root inside the container"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.terraform_version))
    error_message = "terraform_version must be a three-part semantic version."
  }
}

variable "install_aws_cli" {
  type        = bool
  default     = true
  description = "Whether the init container also unpacks AWS CLI v2. Its bundle is glibc-only, so it is extracted rather than installed - the installer wants to run on the target system, and the init container is a different one"
}

# --- Storage ---

variable "volume_claim_templates" {
  type = list(object({
    name               = string
    mount_path         = string
    storage_class_name = string
    size               = string
    access_modes       = optional(list(string), ["ReadWriteOnce"])
  }))
  default     = []
  description = "Volumes the StatefulSet provisions per replica, each mounted at its own path. Used for block storage, where one volume belongs to one pod - dynamic provisioning through a CSI driver, so the driver's addon has to exist first"

  validation {
    condition     = alltrue([for v in var.volume_claim_templates : can(regex("^/", v.mount_path))])
    error_message = "each volume_claim_templates mount_path must be an absolute path."
  }

  validation {
    condition     = length(distinct([for v in var.volume_claim_templates : v.name])) == length(var.volume_claim_templates)
    error_message = "volume_claim_templates names must be unique."
  }
}

variable "persistent_volume_claims" {
  type = list(object({
    name       = string
    claim_name = string
    mount_path = string
    read_only  = optional(bool, false)
  }))
  default     = []
  description = "Claims that already exist, mounted into the container. Used for shared storage the caller created outside this module - a statically provisioned EFS volume, or a bucket surfaced by the Mountpoint for S3 driver (rules.md B-6)"

  validation {
    condition     = alltrue([for v in var.persistent_volume_claims : can(regex("^/", v.mount_path))])
    error_message = "each persistent_volume_claims mount_path must be an absolute path."
  }

  validation {
    condition     = length(distinct([for v in var.persistent_volume_claims : v.name])) == length(var.persistent_volume_claims)
    error_message = "persistent_volume_claims names must be unique."
  }
}

variable "fs_group" {
  type        = number
  default     = null
  description = "fsGroup applied to the pod, or null for none. Needed whenever a volume is mounted: the image runs as uid 1000, and a freshly provisioned volume is owned by root, so without this the container cannot write to it and the failure looks like a permissions bug in code-server"

  validation {
    condition     = var.fs_group == null || var.fs_group > 0
    error_message = "fs_group must be a positive uid, or null."
  }
}

# --- Ingress ---

variable "ingress_name" {
  type        = string
  default     = "vscode"
  description = "Name of the Ingress. The second half of the load balancer's adoption stack tag, which the caller builds from the same values (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.ingress_name))
    error_message = "ingress_name must be a valid lowercase RFC 1123 label."
  }
}

variable "ingress_class_name" {
  type        = string
  default     = "alb"
  description = "ingressClassName handed to the controller. Without it nothing claims the Ingress and no load balancer is ever created - and that is not an error anywhere (rules.md G-1)"

  validation {
    condition     = length(var.ingress_class_name) > 0
    error_message = "ingress_class_name must not be empty."
  }
}

variable "ingress_annotations" {
  type        = map(string)
  default     = {}
  description = "Annotations on the Ingress. The scheme, target type and frontend security group come from the caller, which is what decides the shape of the load balancer"
}

variable "capability_dependency" {
  type        = any
  default     = null
  description = "Value the caller passes purely to order this module after the things these manifests need at runtime - the controller that reconciles the Ingress and the node capacity the pod lands on (rules.md D-4)"
}
