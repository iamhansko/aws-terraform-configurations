variable "tenants" {
  type        = map(string)
  description = <<-DESC
    Tenants, as a map of a caller-chosen label to the namespace to create for it. The same map the tenant role
    module is given, so the namespaces the roles are scoped to and the namespaces that exist are the same set
    (rules.md B-5).

    tenant-a and tenant-b as the _monolithic template had them, but as a map rather than two copies of every
    resource: that template declared the namespaces in one YAML document, the quotas in another, and then used
    a shell "for TENANT in tenant-a tenant-b" loop to render the workloads - three different mechanisms for the
    same list.
  DESC

  validation {
    condition     = length(var.tenants) >= 2
    error_message = "tenants must name at least two tenants. The demonstration is that one tenant cannot reach the other's namespace, which needs two."
  }
  validation {
    condition     = alltrue([for label in keys(var.tenants) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "tenants keys are labels used in resource addresses, so each must be letters, digits, dots, underscores or hyphens."
  }
  validation {
    condition     = alltrue([for namespace in values(var.tenants) : can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", namespace))])
    error_message = "tenants values must be valid lowercase RFC 1123 DNS labels."
  }
}
variable "management_ui_namespace" {
  type        = string
  default     = "management-ui"
  description = "Namespace the management UI runs in, as the _monolithic template had it. Separate from the tenants because the UI has to reach both - and the NetworkPolicies below allow it in by namespace label, which is how that exception is expressed"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.management_ui_namespace))
    error_message = "management_ui_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "management_ui_name" {
  type        = string
  default     = "management-ui"
  description = "Name of the management UI Deployment and Service. Also the second half of the stack tag a pre-created load balancer must carry to be adopted rather than duplicated, which is why the caller reads it back from this module (rules.md B-5/G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.management_ui_name))
    error_message = "management_ui_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "management_ui_role_label" {
  type        = string
  default     = "management-ui"
  description = "Value of the role label on the management UI's namespace, which the allow-ui NetworkPolicy selects on. One value feeds the namespace label and the policy's namespaceSelector, because a policy selecting a label the namespace does not carry silently allows nothing (rules.md B-5)"

  validation {
    condition     = length(var.management_ui_role_label) > 0
    error_message = "management_ui_role_label must not be empty."
  }
}
variable "probe_image" {
  type        = string
  default     = "calico/star-probe:v0.1.0"
  description = "Image the frontend and backend pods run, as the _monolithic template had it. It answers /status and reports which of the URLs it was given it could reach, which is what makes the policy effect visible rather than inferred"

  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$", var.probe_image))
    error_message = "probe_image must carry an explicit tag."
  }
}
variable "collect_image" {
  type        = string
  default     = "calico/star-collect:v0.1.0"
  description = "Image the management UI runs, as the _monolithic template had it. It polls each probe and draws the result as a graph"

  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$", var.collect_image))
    error_message = "collect_image must carry an explicit tag."
  }
}
variable "frontend_port" {
  type        = number
  default     = 80
  description = "Port the frontend probe listens on, as the _monolithic template had it"

  validation {
    condition     = var.frontend_port > 0 && var.frontend_port <= 65535
    error_message = "frontend_port must be a valid TCP port."
  }
}
variable "backend_port" {
  type        = number
  default     = 6379
  description = "Port the backend probe listens on, as the _monolithic template had it. The backend NetworkPolicy names this port explicitly, so one value feeds both (rules.md B-5)"

  validation {
    condition     = var.backend_port > 0 && var.backend_port <= 65535
    error_message = "backend_port must be a valid TCP port."
  }
}
variable "management_ui_container_port" {
  type        = number
  default     = 9001
  description = "Port the collector listens on, as the _monolithic template had it"

  validation {
    condition     = var.management_ui_container_port > 0 && var.management_ui_container_port <= 65535
    error_message = "management_ui_container_port must be a valid TCP port."
  }
}
variable "management_ui_service_port" {
  type        = number
  default     = 80
  description = "Port the management UI Service publishes, and therefore the load balancer's listener port - the one the frontend security group has to open"

  validation {
    condition     = var.management_ui_service_port > 0 && var.management_ui_service_port <= 65535
    error_message = "management_ui_service_port must be a valid TCP port."
  }
}
variable "replicas" {
  type        = number
  default     = 1
  description = "Replicas for each Deployment, one as the _monolithic template had it. One is enough: the demonstration is which pods can reach which, not how many there are"

  validation {
    condition     = var.replicas >= 1
    error_message = "replicas must be at least 1."
  }
}
variable "service_annotations" {
  type        = map(string)
  default     = {}
  description = "Annotations on the management UI Service, which is how the AWS Load Balancer Controller is told what to build. Supplied by the caller because the values name security groups this module does not own (rules.md B-6)"

  validation {
    condition     = alltrue([for key in keys(var.service_annotations) : length(key) > 0])
    error_message = "service_annotations must not contain empty annotation keys."
  }
}
variable "apply_network_policies" {
  type        = bool
  default     = true
  description = <<-DESC
    Whether to apply the NetworkPolicies that isolate the tenants.

    True, which is the finished state. Set false to see what the cluster does without them: every probe reaches
    every other, and the management UI graph is fully connected - which is also exactly what it looks like when
    the policies are applied to a CNI that does not enforce them, so the two cases are worth being able to
    compare (rules.md B-4).
  DESC
}
variable "resource_quota" {
  type = object({
    pods            = number
    requests_cpu    = string
    requests_memory = string
    limits_cpu      = string
    limits_memory   = string
  })
  default = {
    pods            = 20
    requests_cpu    = "4"
    requests_memory = "4Gi"
    limits_cpu      = "8"
    limits_memory   = "8Gi"
  }
  description = <<-DESC
    The ResourceQuota applied to every tenant namespace, as the _monolithic template set it.

    It is the other half of soft multi-tenancy, and the half that is easy to overlook: namespace isolation stops
    one tenant reading another's data, and a quota stops one tenant consuming the whole cluster's capacity. The
    IAM access scope does nothing about the second.

    CPU and memory are strings because Kubernetes quantities are - "4" and "4Gi" are not numbers, and a number
    here would serialise as 4 rather than "4" and be rejected.
  DESC

  validation {
    condition     = var.resource_quota.pods >= 1
    error_message = "resource_quota.pods must be at least 1."
  }
  validation {
    condition = alltrue([
      for quantity in [var.resource_quota.requests_cpu, var.resource_quota.requests_memory, var.resource_quota.limits_cpu, var.resource_quota.limits_memory] :
      can(regex("^[0-9]+(\\.[0-9]+)?(m|Ki|Mi|Gi|Ti|k|M|G|T)?$", quantity))
    ])
    error_message = "resource_quota quantities must be Kubernetes quantities such as \"4\", \"500m\" or \"4Gi\"."
  }
}
variable "limit_range" {
  type = object({
    default_cpu            = string
    default_memory         = string
    default_request_cpu    = string
    default_request_memory = string
  })
  default = {
    default_cpu            = "200m"
    default_memory         = "256Mi"
    default_request_cpu    = "100m"
    default_request_memory = "128Mi"
  }
  description = "The LimitRange applied to every tenant namespace, as the _monolithic template set it. It is what makes the quota effective: a container with no requests counts as zero against a requests quota, so without defaults a tenant could run far more pods than the quota appears to allow"

  validation {
    condition = alltrue([
      for quantity in [var.limit_range.default_cpu, var.limit_range.default_memory, var.limit_range.default_request_cpu, var.limit_range.default_request_memory] :
      can(regex("^[0-9]+(\\.[0-9]+)?(m|Ki|Mi|Gi|Ti|k|M|G|T)?$", quantity))
    ])
    error_message = "limit_range quantities must be Kubernetes quantities such as \"200m\" or \"256Mi\"."
  }
}
