variable "name" {
  type        = string
  default     = "podinfo"
  description = "Name shared by the GitRepository and the Kustomization, podinfo as the _monolithic template's flux CLI calls produced. The Kustomization's sourceRef names the GitRepository by this string, so the two cannot be named separately without the pair breaking"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  description = "Namespace both objects live in. Taken from the module that installed Flux rather than defaulted, because the controllers only watch namespaces they are configured for and flux-system is the one they always watch (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "url" {
  type        = string
  default     = "https://github.com/stefanprodan/podinfo"
  description = "Git repository Flux reconciles from, the upstream podinfo repository as the _monolithic template pointed at. Public and read-only over https, so no credentials and no Secret are involved - which is what makes this half of the demo work without a GitHub token"

  validation {
    condition     = can(regex("^(https://|ssh://|git@)", var.url))
    error_message = "url must be an https://, ssh:// or git@ Git URL."
  }
}
variable "branch" {
  type        = string
  default     = "master"
  description = "Branch to track, master as the _monolithic template specified - which is the podinfo repository's default branch name, not a typo for main. A branch that does not exist leaves the GitRepository with a Ready=False condition and the Kustomization waiting on it forever"

  validation {
    condition     = length(var.branch) > 0
    error_message = "branch must not be empty."
  }
}
variable "source_interval" {
  type        = string
  default     = "1m"
  description = "How often the source controller re-checks the repository for new commits, one minute as the _monolithic template set it. This is the number that decides how long after a push the cluster notices - the Kustomization's own interval only decides how often it re-applies what it already has"

  validation {
    condition     = can(regex("^[0-9]+(s|m|h)$", var.source_interval))
    error_message = "source_interval must be a Go duration such as 30s, 1m or 1h."
  }
}
variable "path" {
  type        = string
  default     = "./kustomize"
  description = "Directory inside the repository the Kustomization applies, ./kustomize as the _monolithic template set it - which is where podinfo keeps its Deployment, Service and HorizontalPodAutoscaler"

  validation {
    condition     = can(regex("^\\./", var.path))
    error_message = "path must be repository-relative and start with ./ - Flux rejects an absolute path."
  }
}
variable "target_namespace" {
  type        = string
  default     = null
  description = "Namespace the reconciled objects are placed into. Flux rewrites every applied object's namespace to this, so it is right for a repository of workload manifests that carry no namespace of their own - and wrong for one holding Flux's own custom resources, which have to land in the namespace the controllers watch. Null omits the field and lets each manifest keep the namespace it declares, which is what a repository of GitRepository and Kustomization objects needs (rules.md B-4)"

  validation {
    condition     = var.target_namespace == null || can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.target_namespace))
    error_message = "target_namespace must be a valid lowercase RFC 1123 DNS label, or null to let each applied manifest keep its own namespace."
  }
}
variable "kustomization_interval" {
  type        = string
  default     = "5m"
  description = "How often the Kustomization re-applies what the source controller has fetched, five minutes as the _monolithic template set it. It is also the loop that undoes a manual kubectl edit, which is the property worth demonstrating: change the Deployment by hand and it reverts within this interval"

  validation {
    condition     = can(regex("^[0-9]+(s|m|h)$", var.kustomization_interval))
    error_message = "kustomization_interval must be a Go duration such as 30s, 5m or 1h."
  }
}
variable "retry_interval" {
  type        = string
  default     = "2m"
  description = "How soon a failed reconciliation is retried, two minutes as the _monolithic template set it. Shorter than the normal interval on purpose, so a transient failure does not cost a full cycle"

  validation {
    condition     = can(regex("^[0-9]+(s|m|h)$", var.retry_interval))
    error_message = "retry_interval must be a Go duration such as 30s, 2m or 1h."
  }
}
variable "health_check_timeout" {
  type        = string
  default     = "3m"
  description = "How long the Kustomization waits for the objects it applied to become ready before calling the reconciliation failed, three minutes as the _monolithic template's --health-check-timeout set it. Only meaningful together with wait_for_health"

  validation {
    condition     = can(regex("^[0-9]+(s|m|h)$", var.health_check_timeout))
    error_message = "health_check_timeout must be a Go duration such as 30s, 3m or 1h."
  }
}
variable "prune" {
  type        = bool
  default     = true
  description = "Whether removing an object from the repository removes it from the cluster. True as the _monolithic template set it, and it is what makes this GitOps rather than a repeated apply: without it Git is the source of truth for what exists but not for what does not"
}
variable "wait_for_health" {
  type        = bool
  default     = true
  description = "Whether the Kustomization reports Ready only once the objects it applied are themselves healthy. True as the _monolithic template set it: with it off the Kustomization goes Ready as soon as the objects are accepted, so \"flux get kustomizations\" says the deployment succeeded while its pods are still crash-looping"
}
variable "git_username" {
  type        = string
  default     = null
  description = "Username for an https repository that needs credentials. Null for a public one, which is what the podinfo half of this project uses and why it needs no Secret at all. For a GitHub token the username is not checked but must not be empty - \"git\" is the conventional value (rules.md B-4)"

  validation {
    condition     = var.git_username == null || length(var.git_username) > 0
    error_message = "git_username must be a non-empty string, or null for a public repository."
  }
}
variable "git_password" {
  type        = string
  sensitive   = true
  default     = null
  description = "Password or personal access token for an https repository that needs credentials. Null for a public one. When set, a Secret holding it is created in the namespace and the GitRepository's secretRef names it - the source controller reads the Secret, so the token is in the cluster as well as in the Terraform state (rules.md B-4)"

  validation {
    condition     = var.git_password == null || length(var.git_password) > 0
    error_message = "git_password must be a non-empty string, or null for a public repository."
  }
  validation {
    condition     = var.git_password == null || !can(regex("[[:space:]]", var.git_password))
    error_message = "git_password must not contain whitespace - a newline or trailing space from a paste is stored in the Secret as part of the credential, and the source controller reports it as an authentication failure against the repository (rules.md B-1)."
  }
  validation {
    # Cross-variable, available since Terraform 1.9. The constraint is about the pair: a Secret
    # with one of the two keys missing is accepted by the API server and then fails at clone time,
    # which the GitRepository reports as an authentication error rather than as a malformed Secret
    # (rules.md B-1).
    condition     = (var.git_username == null) == (var.git_password == null)
    error_message = "git_username and git_password must be set together or left null together - the Secret needs both keys, and one on its own produces an authentication failure at clone time rather than a plan error."
  }
}
variable "secret_name" {
  type        = string
  default     = null
  description = "Name of the Secret the credentials are stored in. When null it is derived from name, which keeps two sources in one namespace from sharing a Secret"

  validation {
    condition     = var.secret_name == null || can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.secret_name))
    error_message = "secret_name must be a valid lowercase RFC 1123 subdomain, or null to derive it from name."
  }
}
