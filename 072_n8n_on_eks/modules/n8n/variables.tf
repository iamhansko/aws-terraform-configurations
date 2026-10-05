variable "namespace" {
  type        = string
  default     = "n8n"
  description = "Namespace everything here lives in, n8n as the upstream n8n-hosting manifests name it. Created by this module, unlike the default namespace other projects here reuse - the original ran a separate \"kubectl create namespace n8n\" before applying, which is a step that had to succeed and was not recorded anywhere"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "name" {
  type        = string
  default     = "n8n"
  description = "Name of the n8n Deployment and Service, and the value of the service label both select on. Also the second half of the stack tag a pre-created load balancer must carry (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "image" {
  type        = string
  default     = "n8nio/n8n:2.40.5"
  description = "n8n image, the version the upstream n8n-hosting manifests pin. The _monolithic template applied those manifests and then ran \"kubectl -n n8n set image deployment n8n n8n=n8nio/n8n:1.119.2\" to override it - a change that lived only in a shell script, so the Deployment in the cluster and the Deployment in the repository disagreed with nothing recording why. Declared here instead (rules.md E-5). Docker Hub, because n8n publishes nowhere else"

  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$|@sha256:[0-9a-f]{64}$", var.image))
    error_message = "image must carry an explicit tag or a digest."
  }
}
variable "container_port" {
  type        = number
  default     = 5678
  description = "Port n8n listens on. With nlb-target-type ip the load balancer sends traffic straight to the pod, so this - not the Service port - is what the pod-side security group rule has to open (rules.md G-1/G-2)"

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port must be a valid TCP port."
  }
}
variable "service_port" {
  type        = number
  default     = 5678
  description = "Port the Service publishes, which the Ingress names as its backend port. Not the load balancer's listener port: an ALB listens on whatever the Ingress's listen-ports annotation says, and forwards to the pods on the container port behind this one (rules.md G-1)"

  validation {
    condition     = var.service_port > 0 && var.service_port <= 65535
    error_message = "service_port must be a valid TCP port."
  }
}
variable "service_type" {
  type        = string
  default     = "ClusterIP"
  description = "Type of the n8n Service. ClusterIP is right for an ALB with target-type ip, where the load balancer registers pod addresses and the Service is only a name for the Ingress to resolve. NodePort is only needed for target-type instance, where traffic arrives at a port on the node instead (rules.md G-1)"

  validation {
    # LoadBalancer is excluded on purpose rather than left to work by accident: it would build a
    # second load balancer alongside the one the Ingress fronts, and with no
    # aws-load-balancer-type annotation that second one would be a Classic Load Balancer created
    # by the in-tree cloud provider (rules.md G-1).
    condition     = contains(["ClusterIP", "NodePort"], var.service_type)
    error_message = "service_type must be ClusterIP or NodePort. LoadBalancer would create a second load balancer next to the one the Ingress already fronts - to expose n8n that way instead, drop the Ingress and set the aws-load-balancer-type annotation on the Service (rules.md G-1)."
  }
}
variable "ingress_name" {
  type        = string
  default     = null
  description = "Name of the Ingress. Null uses the workload's name, which keeps it equal to the second half of the <namespace>/<name> stack tag a pre-created load balancer has to carry to be adopted (rules.md G-3/B-5)"

  validation {
    condition     = var.ingress_name == null || can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.ingress_name))
    error_message = "ingress_name must be a valid lowercase RFC 1123 DNS label, or null to use the workload name."
  }
}
variable "ingress_class_name" {
  type        = string
  default     = "alb"
  description = "IngressClass this Ingress asks for. The single most important value here: the AWS Load Balancer Controller only reconciles an Ingress that names its class, and an Ingress it is not reconciling does not fail - it sits with an empty ADDRESS and no events. The chart creates this IngressClass itself, so nothing else has to declare it (rules.md G-1)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.ingress_class_name))
    error_message = "ingress_class_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "ingress_annotations" {
  type        = map(string)
  default     = {}
  description = "Annotations on the n8n Ingress, which is how the AWS Load Balancer Controller is told the scheme, the target type, the listener ports and which security group to keep on the load balancer. Passed in by the caller because the values reference resources this module does not own (rules.md B-6). Note the prefix: these are alb.ingress.kubernetes.io/*, and the Service spellings of the same ideas are service.beta.kubernetes.io/* - the wrong one is ignored rather than rejected (rules.md G-1)"

  validation {
    condition     = alltrue([for key in keys(var.ingress_annotations) : length(key) > 0])
    error_message = "ingress_annotations must not contain empty annotation keys."
  }
}
variable "ingress_host" {
  type        = string
  default     = null
  description = "Host header the rule matches. Null matches any host, which is what makes the load balancer's own DNS name a working address - and that address is also what n8n is told to build webhook URLs from, so a host here without a matching DNS record would make the editor unreachable at the only name it knows (rules.md B-4)"

  validation {
    condition     = var.ingress_host == null || can(regex("^[a-z0-9*]([-a-z0-9.]*[a-z0-9])?$", var.ingress_host))
    error_message = "ingress_host must be a DNS name, optionally starting with a wildcard label, or null to match any host."
  }
}
variable "ingress_path" {
  type        = string
  default     = "/"
  description = "Path the rule matches. The whole editor is served under one path, so there is one rule"

  validation {
    condition     = startswith(var.ingress_path, "/")
    error_message = "ingress_path must start with '/'."
  }
}
variable "ingress_path_type" {
  type        = string
  default     = "Prefix"
  description = "How ingress_path is matched. Prefix, because n8n serves the editor, its REST API and every webhook under the same root - Exact would match only the root document and nothing it loads"

  validation {
    condition     = contains(["Prefix", "Exact", "ImplementationSpecific"], var.ingress_path_type)
    error_message = "ingress_path_type must be Prefix, Exact or ImplementationSpecific."
  }
}
variable "external_url" {
  type        = string
  default     = null
  description = "The address users reach n8n on, written into N8N_HOST and WEBHOOK_URL. Null leaves both unset, which is what the _monolithic template did - and n8n then builds webhook URLs from the pod's own hostname, so every webhook it hands out is unreachable. This is worth setting precisely because the load balancer is created by Terraform and its DNS name is therefore known at apply time (rules.md G-3)"

  validation {
    condition     = var.external_url == null || can(regex("^https?://", var.external_url))
    error_message = "external_url must be an http:// or https:// URL, or null."
  }
}
variable "secure_cookie" {
  type        = bool
  default     = false
  description = "Whether n8n requires its session cookie to be marked secure. False, which the _monolithic template arranged with \"kubectl set env deployment n8n N8N_SECURE_COOKIE=false\" after applying. It has to be false here for a concrete reason: this deployment is fronted by a plain http listener, and with the default of true n8n sets a Secure cookie that the browser then refuses to send back - so the login page accepts the password and returns to the login page (rules.md E-5)"
}
variable "postgres_image" {
  type        = string
  default     = "public.ecr.aws/docker/library/postgres:18"
  description = "Postgres image. The ECR Public mirror of the tag the upstream manifests use, rather than Docker Hub, which rate-limits anonymous pulls per source address - and every node here shares one NAT gateway address per zone"

  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$|@sha256:[0-9a-f]{64}$", var.postgres_image))
    error_message = "postgres_image must carry an explicit tag or a digest."
  }
}
variable "init_container_image" {
  type        = string
  default     = "public.ecr.aws/docker/library/busybox:1.36"
  description = "Image for the init container that chowns n8n's data directory to uid 1000 before the app starts. Same ECR Public reasoning as postgres_image"

  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$|@sha256:[0-9a-f]{64}$", var.init_container_image))
    error_message = "init_container_image must carry an explicit tag or a digest."
  }
}
variable "postgres_database" {
  type        = string
  default     = "n8n"
  description = "Database n8n stores its workflows in"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.postgres_database))
    error_message = "postgres_database must contain only letters, digits and underscores."
  }
}
variable "postgres_admin_user" {
  type        = string
  default     = "n8nadmin"
  description = "Postgres superuser the container initialises with. The upstream manifests ship \"changeUser\" here alongside the password \"changePassword\", as literals in a Secret committed to a public repository - the names are changed and the passwords generated below rather than carried over"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]*$", var.postgres_admin_user))
    error_message = "postgres_admin_user must start with a lowercase letter and contain only lowercase letters, digits and underscores."
  }
}
variable "postgres_app_user" {
  type        = string
  default     = "n8napp"
  description = "Non-superuser role the init script creates and n8n connects as. Upstream ships \"changeNonRootUser\""

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]*$", var.postgres_app_user))
    error_message = "postgres_app_user must start with a lowercase letter and contain only lowercase letters, digits and underscores."
  }
}
variable "postgres_password_length" {
  type        = number
  default     = 32
  description = "Length of the two generated Postgres passwords. Generated rather than configurable as literals so there is no default password to forget to change - they end up in Terraform state and in a Kubernetes Secret, and neither is exposed as an output (rules.md H-2)"

  validation {
    condition     = var.postgres_password_length >= 16
    error_message = "postgres_password_length must be at least 16."
  }
}
variable "postgres_storage_size" {
  type        = string
  default     = "10Gi"
  description = "Size of the volume Postgres stores its data on. The upstream manifest asks for 300Gi, which on gp3 is a real monthly bill for a demo that writes a handful of workflow rows - and because the claim is ReadWriteOnce with a Delete reclaim policy, nobody notices the size until the invoice"

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi|Ti)$", var.postgres_storage_size))
    error_message = "postgres_storage_size must be a Kubernetes storage quantity such as 10Gi."
  }
}
variable "n8n_storage_size" {
  type        = string
  default     = "2Gi"
  description = "Size of the volume n8n keeps its own state on (/home/node/.n8n), as the upstream manifest asks for"

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi|Ti)$", var.n8n_storage_size))
    error_message = "n8n_storage_size must be a Kubernetes storage quantity such as 2Gi."
  }
}
variable "storage_class_name" {
  type        = string
  description = "StorageClass both claims ask for. Taken from the module that created the class rather than restated, because a claim naming a class that does not exist stays Pending and the pods never start (rules.md B-5). The upstream manifests name no class at all and rely on the cluster's default, which is the kind of dependency that works until somebody changes the default"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.storage_class_name))
    error_message = "storage_class_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "postgres_cpu_request" {
  type        = string
  default     = "500m"
  description = "CPU request for Postgres. Upstream asks for a whole core, which on the two-vCPU node this project runs leaves almost nothing for n8n itself"

  validation {
    condition     = can(regex("^[0-9]+m?$", var.postgres_cpu_request))
    error_message = "postgres_cpu_request must be a Kubernetes CPU quantity such as 500m or 1."
  }
}
variable "postgres_memory_request" {
  type        = string
  default     = "1Gi"
  description = "Memory request for Postgres. Upstream asks for 2Gi"

  validation {
    condition     = can(regex("^[0-9]+(Ki|Mi|Gi)$", var.postgres_memory_request))
    error_message = "postgres_memory_request must be a Kubernetes memory quantity such as 1Gi."
  }
}
variable "postgres_cpu_limit" {
  type        = string
  default     = "2"
  description = "CPU limit for Postgres. Upstream sets 4, which is more than the node has - a limit above the node's capacity is accepted and simply never reached, so it reads like a guarantee and is not one"

  validation {
    condition     = can(regex("^[0-9]+m?$", var.postgres_cpu_limit))
    error_message = "postgres_cpu_limit must be a Kubernetes CPU quantity such as 2 or 2000m."
  }
}
variable "postgres_memory_limit" {
  type        = string
  default     = "2Gi"
  description = "Memory limit for Postgres. Upstream sets 4Gi"

  validation {
    condition     = can(regex("^[0-9]+(Ki|Mi|Gi)$", var.postgres_memory_limit))
    error_message = "postgres_memory_limit must be a Kubernetes memory quantity such as 2Gi."
  }
}
variable "n8n_memory_request" {
  type        = string
  default     = "512Mi"
  description = "Memory request for n8n, as the upstream manifest sets it"

  validation {
    condition     = can(regex("^[0-9]+(Ki|Mi|Gi)$", var.n8n_memory_request))
    error_message = "n8n_memory_request must be a Kubernetes memory quantity such as 512Mi."
  }
}
variable "n8n_memory_limit" {
  type        = string
  default     = "1Gi"
  description = "Memory limit for n8n, as the upstream manifest sets it"

  validation {
    condition     = can(regex("^[0-9]+(Ki|Mi|Gi)$", var.n8n_memory_limit))
    error_message = "n8n_memory_limit must be a Kubernetes memory quantity such as 1Gi."
  }
}
variable "db_init_run_id" {
  type        = string
  default     = null
  description = "Folded into the init Job's name, which is what decides when it runs again. Null is the normal case: the Job re-runs when the script, the role name or its password change, and not otherwise. Pass a value that changes - a build number, or timestamp() - to force a run on an apply that changed none of those, at the cost of a plan that always proposes replacing the Job"

  validation {
    condition     = var.db_init_run_id == null || can(regex("^[A-Za-z0-9._-]+$", var.db_init_run_id))
    error_message = "db_init_run_id goes into a Kubernetes object name, so it must be letters, digits, dots, underscores or hyphens, or null."
  }
}
variable "db_init_backoff_limit" {
  type        = number
  default     = 6
  description = "How many times the init Job is retried before it is marked failed. The retries matter: the Job is scheduled as soon as it is created, and on a first apply Postgres may still be initialising its data directory - the pod's own wait loop covers most of that, and this covers the rest"

  validation {
    condition     = var.db_init_backoff_limit >= 0
    error_message = "db_init_backoff_limit must not be negative."
  }
}
variable "db_init_ttl_seconds" {
  type        = number
  default     = 600
  description = "How long a finished init Job is kept before the API server deletes it and its pod. Long enough to read the log after an apply, short enough that a namespace does not collect one Job per credential change forever"

  validation {
    condition     = var.db_init_ttl_seconds >= 0
    error_message = "db_init_ttl_seconds must not be negative."
  }
}
variable "db_init_timeout" {
  type        = string
  default     = "10m"
  description = "How long the apply waits for the init Job to report Complete. It covers Postgres's own first start, since the Job is created alongside it and waits for it to answer - so this is larger than the work the Job itself does"

  validation {
    condition     = can(regex("^[0-9]+(s|m|h)$", var.db_init_timeout))
    error_message = "db_init_timeout must be a Go duration such as 30s, 10m or 1h."
  }
}
