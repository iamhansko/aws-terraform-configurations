variable "release_name" {
  type        = string
  default     = "argocd"
  description = "Helm release name. The chart names the server Service <release>-server, and that name is the second half of the stack tag the pre-created NLB must carry to be adopted (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name))
    error_message = "release_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "argocd"
  description = "Namespace Argo CD runs in, and the first half of the adoption stack tag (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "chart_version" {
  type        = string
  default     = "10.9.2"
  description = "Pinned argo-cd chart version. The _monolithic template installed from the \"stable\" manifest URL instead, so no two applies got the same Argo CD - and the repo-server Deployment it then overwrote was written against whatever version happened to be current"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a semantic version, e.g. 10.9.2."
  }
}
variable "chart_repository" {
  type        = string
  default     = "https://argoproj.github.io/argo-helm"
  description = "Helm repository hosting the argo-cd chart"

  validation {
    condition     = can(regex("^(https://|oci://)", var.chart_repository))
    error_message = "chart_repository must be an https:// or oci:// URL."
  }
}
variable "argocd_image_tag" {
  type        = string
  default     = "v3.1.5"
  description = "Argo CD application image tag, pinned alongside the chart so the repo-server and the sidecar's copyutil cannot drift apart. The _monolithic template hardcoded this same tag inside the Deployment it pasted in"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.argocd_image_tag))
    error_message = "argocd_image_tag must look like v3.1.5."
  }
}
variable "service_annotations" {
  type        = map(string)
  default     = {}
  description = "Annotations on the argocd-server Service, passed as a map and rendered through yamlencode so the dots in the keys need no escaping. The caller supplies them because the scheme, target type and frontend security group have to agree with the pre-created NLB it also owns (rules.md B-6/G-3). The _monolithic template applied these with three separate kubectl annotate calls, which left them invisible to plan"

  validation {
    condition     = alltrue([for key in keys(var.service_annotations) : length(key) > 0])
    error_message = "service_annotations must not contain empty keys."
  }
}
variable "plugin_name" {
  type        = string
  default     = "argocd-vault-plugin"
  description = "Name of the ConfigManagementPlugin. The chart keys it in argocd-cmp-cm as <name>.yaml and the sidecar mounts that key, so the two move together. An Argo CD Application asks for the plugin by this name"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.plugin_name))
    error_message = "plugin_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "vault_secret_name" {
  type        = string
  default     = "vault"
  description = "Name of the Secret in this namespace holding VAULT_ADDR, VAULT_TOKEN, AVP_AUTH_TYPE and AVP_TYPE. Passed to the plugin's generate command with -s, and named in the Role this module creates. The Secret itself is written by the bootstrap SSM Association, because its token comes from \"vault operator init\""

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.vault_secret_name))
    error_message = "vault_secret_name must be a valid lowercase Kubernetes Secret name."
  }
}
variable "avp_version" {
  type        = string
  default     = "1.16.1"
  description = "Pinned argocd-vault-plugin version the init container downloads, the same one the _monolithic template used - where it sat inside a pasted manifest with nothing surfacing it"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.avp_version))
    error_message = "avp_version must be a semantic version, e.g. 1.16.1."
  }
}
variable "sidecar_name" {
  type        = string
  default     = "avp"
  description = "Container name for the plugin sidecar in the repo-server pod"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.sidecar_name))
    error_message = "sidecar_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "sidecar_image" {
  type        = string
  default     = "registry.access.redhat.com/ubi8:latest"
  description = "Image for the plugin sidecar. It only needs a shell and the mounted binary, so a base image is enough. Tagged explicitly rather than left bare, which would resolve to :latest implicitly and change under the deployment without anything recording it"

  validation {
    condition     = can(regex(":", var.sidecar_image))
    error_message = "sidecar_image must include an explicit tag, so an apply months from now runs what was tested."
  }
}
variable "download_tools_image" {
  type        = string
  default     = "registry.access.redhat.com/ubi8:latest"
  description = "Image for the init container that downloads the plugin binary. Needs curl and nothing else"

  validation {
    condition     = can(regex(":", var.download_tools_image))
    error_message = "download_tools_image must include an explicit tag."
  }
}
variable "timeout_seconds" {
  type        = number
  default     = 900
  description = "How long to wait for the release. Generous because the repo-server cannot become ready until its init container has pulled the plugin binary over the internet"

  validation {
    condition     = var.timeout_seconds > 0
    error_message = "timeout_seconds must be positive."
  }
}
variable "additional_set_values" {
  type = list(object({
    name  = string
    value = string
    type  = optional(string)
  }))
  default     = []
  description = "Extra chart values. type is auto when omitted and may only be auto or string (rules.md E-7)"

  validation {
    condition     = alltrue([for v in var.additional_set_values : v.type == null || contains(["auto", "string"], v.type)])
    error_message = "additional_set_values type must be omitted, \"auto\" or \"string\" - the only values helm_release accepts."
  }
}
variable "server_insecure" {
  type        = bool
  default     = true
  description = "Whether argocd-server serves plain HTTP instead of terminating TLS and redirecting to HTTPS. The caller decides this, because it has to agree with which ports the frontend security group opens - the constraint lives with the load balancer rather than here (rules.md B-1)"
}
variable "create_repository_credentials" {
  type        = bool
  default     = false
  description = "Whether to create the repository credential Secret. A separate switch rather than deriving it from repository_url being null, because this decides a count and a count has to be decidable during plan - repository_url is normally the clone URL of a repository created in the same apply, so its value is unknown until then (rules.md B-8). Off by default: a public repository needs no credential and there is no reason to put a token in the cluster for one"
}
variable "repository_url" {
  type        = string
  default     = null
  description = "HTTPS clone URL of the Git repository Argo CD syncs from, used when create_repository_credentials is on. Must match the URL the Application names, because Argo CD selects the credential by URL prefix - so pass the output of whatever created the repository rather than rebuilding the string (rules.md B-5)"

  validation {
    condition     = var.repository_url == null || can(regex("^https://", var.repository_url))
    error_message = "repository_url must be an https:// clone URL, or null. An ssh:// or git@ URL needs an sshPrivateKey credential instead of the username and password this module writes."
  }
  validation {
    # Checked against the switch rather than the other way round. When the URL is an unknown value
    # at plan time Terraform defers this to apply, which is fine - the switch above is what has to
    # be known early, and it is.
    condition     = var.create_repository_credentials == false || var.repository_url != null
    error_message = "repository_url is required when create_repository_credentials is true: the Secret's url field is what Argo CD matches against the repository an Application names."
  }
}
variable "repository_username" {
  type        = string
  default     = null
  description = "Username paired with repository_token. For a GitHub personal access token the username is not what authenticates, but the field has to be present"

  validation {
    condition     = var.create_repository_credentials == false || (var.repository_username != null && var.repository_username != "")
    error_message = "repository_username is required when create_repository_credentials is true, because Argo CD's git credential needs both fields."
  }
}
variable "repository_token" {
  type        = string
  default     = null
  sensitive   = true
  description = "Personal access token with read access to the repository. Written to the password field of the credential Secret, which is where GitHub expects a token for Git over HTTPS"

  validation {
    condition     = var.create_repository_credentials == false || (var.repository_token != null && var.repository_token != "")
    error_message = "repository_token is required when create_repository_credentials is true, because a private repository cannot be cloned anonymously - and the resulting Application error names a connection problem rather than a missing credential."
  }
}
variable "repository_secret_name" {
  type        = string
  default     = "seed-repository"
  description = "Name of the repository credential Secret. Argo CD finds it by its label rather than by name, so this only has to be unique in the namespace"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.repository_secret_name))
    error_message = "repository_secret_name must be a valid lowercase RFC 1123 subdomain."
  }
}
