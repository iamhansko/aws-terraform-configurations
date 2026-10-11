variable "hostname" {
  type        = string
  description = "Fully qualified host the Ingress matches on, e.g. keycloak.example.com. Must be the name the ACM certificate was issued for and the name the Route 53 record points at the load balancer - three places that have to agree, which is why all of them read one value in the root (rules.md B-5)"

  validation {
    condition     = can(regex("^([a-z0-9]([-a-z0-9]*[a-z0-9])?\\.)+[a-z]{2,}$", var.hostname))
    error_message = "hostname must be a fully qualified lowercase domain name such as keycloak.example.com."
  }
}
variable "namespace" {
  type        = string
  default     = "keycloak"
  description = "Namespace everything here goes into, and the first half of the Ingress adoption stack tag (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "service_name" {
  type        = string
  default     = "keycloak"
  description = "Name of the Keycloak Service and StatefulSet. The headless discovery Service is named after it with a -discovery suffix, and the StatefulSet's serviceName points at that - so renaming this moves all three together"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.service_name))
    error_message = "service_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "ingress_name" {
  type        = string
  default     = "keycloak"
  description = "Name of the Ingress, and the second half of the adoption stack tag. A pre-created load balancer must be tagged <namespace>/<this> to be adopted rather than duplicated (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.ingress_name))
    error_message = "ingress_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "ingress_class_name" {
  type        = string
  default     = "alb"
  description = "IngressClass the Ingress asks for. alb, the class the AWS Load Balancer Controller owns (rules.md G-1)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.ingress_class_name))
    error_message = "ingress_class_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "ingress_annotations" {
  type        = map(string)
  default     = {}
  description = "Annotations on the Ingress. The caller supplies them because the scheme, target type, frontend security group and certificate ARN all have to agree with resources it owns (rules.md B-6/G-3)"

  validation {
    condition     = alltrue([for key in keys(var.ingress_annotations) : length(key) > 0])
    error_message = "ingress_annotations must not contain empty keys."
  }
}
variable "admin_username" {
  type        = string
  default     = "admin"
  description = "Bootstrap admin username, created on first start only. Upstream's quickstart hardcodes admin"

  validation {
    condition     = length(var.admin_username) > 0
    error_message = "admin_username must not be empty."
  }
}
variable "admin_password" {
  type        = string
  sensitive   = true
  description = "Bootstrap admin password. sensitive, and no default on purpose: the upstream quickstart hardcodes \"admin\", and this deployment publishes the console on an internet-facing load balancer - so the upstream value would be a working administrator login on a public address"

  validation {
    condition     = length(var.admin_password) >= 12
    error_message = "admin_password must be at least 12 characters. Keycloak itself accepts anything, including upstream's \"admin\", and the console it protects is reachable from the internet."
  }
}
variable "database_name" {
  type        = string
  default     = "keycloak"
  description = "PostgreSQL database name, matching upstream's quickstart. Read by both the database and Keycloak, so one value feeds both (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-zA-Z_][a-zA-Z0-9_]*$", var.database_name))
    error_message = "database_name must be a valid PostgreSQL identifier."
  }
}
variable "database_user" {
  type        = string
  default     = "keycloak"
  description = "PostgreSQL user, matching upstream's quickstart"

  validation {
    condition     = can(regex("^[a-zA-Z_][a-zA-Z0-9_]*$", var.database_user))
    error_message = "database_user must be a valid PostgreSQL identifier."
  }
}
variable "database_password" {
  type        = string
  sensitive   = true
  description = "PostgreSQL password. sensitive and without a default, because upstream hardcodes \"keycloak\" and notes in the manifest itself that a production setup should use a secret. It reaches both pods through the Secret this module creates rather than as an inline env value"

  validation {
    condition     = length(var.database_password) >= 12
    error_message = "database_password must be at least 12 characters."
  }
}
variable "credentials_secret_name" {
  type        = string
  default     = "keycloak-credentials"
  description = "Name of the Secret holding the admin and database passwords. Both pods reference it with secretKeyRef rather than carrying the values inline - which is what upstream's own comment recommends, and also what keeps the passwords out of terraform plan output, since kubectl_manifest's yaml_body_parsed attribute is computed and not sensitive"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.credentials_secret_name))
    error_message = "credentials_secret_name must be a valid lowercase Kubernetes Secret name."
  }
}
variable "keycloak_image" {
  type        = string
  default     = "quay.io/keycloak/keycloak:26.7.4"
  description = "Keycloak image. Pinned here rather than taken from the branch manifest the _monolithic template curled, which changes this tag without notice"

  validation {
    condition     = can(regex(":", var.keycloak_image))
    error_message = "keycloak_image must include an explicit tag."
  }
}
variable "postgres_image" {
  type        = string
  default     = "mirror.gcr.io/postgres:17"
  description = "PostgreSQL image, matching upstream's quickstart. The gcr mirror avoids Docker Hub's anonymous pull limits, which is why upstream uses it"

  validation {
    condition     = can(regex(":", var.postgres_image))
    error_message = "postgres_image must include an explicit tag."
  }
}
variable "replicas" {
  type        = number
  default     = 2
  description = "Keycloak replicas, two as upstream recommends: it is what allows a rolling update for a configuration change without losing the in-memory session cache, which is only held in two copies. One replica works and saves about 1.7Gi of requested memory"

  validation {
    condition     = var.replicas >= 1
    error_message = "replicas must be at least 1."
  }
}
variable "container_port" {
  type        = number
  default     = 8080
  description = "Port Keycloak serves http on. With target-type ip the load balancer sends traffic straight here, so this is the port the pod-side security group rule has to open - not the Service port (rules.md G-1/G-2)"

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port must be between 1 and 65535."
  }
}
variable "service_port" {
  type        = number
  default     = 8080
  description = "Port the Keycloak Service publishes, which the Ingress backend names"

  validation {
    condition     = var.service_port > 0 && var.service_port <= 65535
    error_message = "service_port must be between 1 and 65535."
  }
}
variable "hostname_strict" {
  type        = bool
  default     = false
  description = "Whether Keycloak rejects requests whose Host header does not match its configured hostname. False as upstream's exploratory setup has it. Turning it on is the production move but also requires KC_HOSTNAME to be set to exactly the Ingress host, so it is not a one-line change"
}
variable "cpu_request" {
  type        = string
  default     = "500m"
  description = "CPU request per Keycloak pod, matching upstream. With two replicas this is what decides whether the StatefulSet fits on the node group"

  validation {
    condition     = can(regex("^[0-9]+m?$", var.cpu_request))
    error_message = "cpu_request must be a Kubernetes CPU quantity such as 500m."
  }
}
variable "cpu_limit" {
  type        = string
  default     = "2000m"
  description = "CPU limit per Keycloak pod, matching upstream"

  validation {
    condition     = can(regex("^[0-9]+m?$", var.cpu_limit))
    error_message = "cpu_limit must be a Kubernetes CPU quantity such as 2000m."
  }
}
variable "memory_request" {
  type        = string
  default     = "1700Mi"
  description = "Memory request per Keycloak pod, matching upstream. Two replicas ask for 3400Mi between them, which does not fit alongside the cluster addons on two t3.medium nodes - the reason this project's node group is larger than most"

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi)$", var.memory_request))
    error_message = "memory_request must be a Kubernetes memory quantity such as 1700Mi."
  }
}
variable "memory_limit" {
  type        = string
  default     = "2000Mi"
  description = "Memory limit per Keycloak pod, matching upstream"

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi)$", var.memory_limit))
    error_message = "memory_limit must be a Kubernetes memory quantity such as 2000Mi."
  }
}
