variable "release_name" {
  type        = string
  default     = "argocd"
  description = "Helm release name"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name))
    error_message = "release_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "argocd"
  description = "Namespace Argo CD runs in, as the _monolithic template's 'kubectl create namespace argocd' had it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "chart_repository" {
  type        = string
  default     = "https://argoproj.github.io/argo-helm"
  description = "Helm repository holding the argo-cd chart"

  validation {
    condition     = can(regex("^(https://|oci://)", var.chart_repository))
    error_message = "chart_repository must be an https:// or oci:// URL."
  }
}
variable "chart_name" {
  type        = string
  default     = "argo-cd"
  description = "Chart name"

  validation {
    condition     = length(var.chart_name) > 0
    error_message = "chart_name must not be empty."
  }
}
variable "chart_version" {
  type        = string
  default     = "9.1.6"
  description = "Chart version, pinned rather than the _monolithic template's 'kubectl apply -f .../stable/manifests/install.yaml' - which installed whatever stable pointed at on the day the demo ran"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a semantic version (e.g. 9.1.6)."
  }
}
variable "server_service_type" {
  type        = string
  default     = "LoadBalancer"
  description = "Service type for argocd-server. LoadBalancer reproduces the kubectl patch the _monolithic template applied, and the AWS Load Balancer Controller turns it into an NLB"

  validation {
    condition     = contains(["ClusterIP", "NodePort", "LoadBalancer"], var.server_service_type)
    error_message = "server_service_type must be one of: ClusterIP, NodePort, LoadBalancer."
  }
}
variable "server_service_scheme" {
  type        = string
  default     = "internet-facing"
  description = <<-DESC
    Scheme for the load balancer in front of argocd-server: internet-facing or internal.

    Stated rather than left to the controller, whose default for a Service is internal. The default
    here is the opposite because the point of this Service is a dashboard opened from a browser, and
    an internal load balancer is not a broken one - it is a working one with a hostname that resolves
    only inside the VPC, which is why leaving it unset produces no error anywhere.

    internal is still a valid choice for this project, reached from the code-server workbench instead
    of from a browser. internet-facing needs the kubernetes.io/role/elb tag on the public subnets and
    internal needs kubernetes.io/role/internal-elb on the private ones; the root passes both
    (rules.md G-1).
  DESC

  validation {
    condition     = contains(["internet-facing", "internal"], var.server_service_scheme)
    error_message = "server_service_scheme must be internet-facing or internal - the two values the AWS Load Balancer Controller accepts. Any other string is not rejected by the controller, it is simply ignored, leaving the scheme at its internal default."
  }
}
variable "repository_url" {
  type        = string
  description = "Git repository Argo CD watches. Pass the repository module's clone URL rather than restating it, so the Application cannot point at a repository that does not exist (rules.md B-5)"

  validation {
    condition     = can(regex("^https://", var.repository_url))
    error_message = "repository_url must be an https:// Git URL. Argo CD can use SSH, but that needs a deploy key this project does not create."
  }
}
variable "application_name" {
  type        = string
  default     = "argo-app"
  description = "Name of the Argo CD Application, as the _monolithic template's 'argocd app create argo-app' had it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.application_name))
    error_message = "application_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "manifest_path" {
  type        = string
  default     = "manifest"
  description = "Path inside the repository Argo CD syncs. The GitHub Actions workflow rewrites the image in this directory's deployment.yaml, which is what closes the loop"

  validation {
    condition     = length(var.manifest_path) > 0
    error_message = "manifest_path must not be empty."
  }
}
variable "target_revision" {
  type        = string
  default     = "HEAD"
  description = "Branch or revision Argo CD tracks"

  validation {
    condition     = length(var.target_revision) > 0
    error_message = "target_revision must not be empty."
  }
}
variable "destination_namespace" {
  type        = string
  default     = "default"
  description = "Namespace the synced manifests are applied into, as the _monolithic template's --dest-namespace default had it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.destination_namespace))
    error_message = "destination_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "sync_prune" {
  type        = bool
  default     = true
  description = "Whether Argo CD deletes resources removed from the repository. True, matching the _monolithic template's --sync-policy automated"
}
variable "sync_self_heal" {
  type        = bool
  default     = true
  description = "Whether Argo CD reverts changes made directly against the cluster. True, matching the _monolithic template's --self-heal. This is what makes a kubectl edit against the synced Deployment snap back"
}
variable "timeout_seconds" {
  type        = number
  default     = 900
  description = "How long to wait for the release to become ready. Generous because the chart brings up several Deployments and a StatefulSet, and the load balancer for argocd-server is provisioned within that window"

  validation {
    condition     = var.timeout_seconds > 0
    error_message = "timeout_seconds must be greater than zero."
  }
}
variable "additional_set_values" {
  type = list(object({
    name  = string
    value = string
    type  = optional(string)
  }))
  default     = []
  description = "Extra Helm values appended to the release's set list"

  validation {
    condition     = alltrue([for entry in var.additional_set_values : length(entry.name) > 0])
    error_message = "additional_set_values entries must each have a non-empty name."
  }
  validation {
    condition     = alltrue([for entry in var.additional_set_values : entry.type == null || contains(["auto", "string"], entry.type)])
    error_message = "additional_set_values[*].type must be auto or string (rules.md E-7)."
  }
}
