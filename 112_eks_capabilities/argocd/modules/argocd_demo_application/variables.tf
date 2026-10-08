variable "name" {
  type        = string
  default     = "guestbook"
  description = "Name of the Application object"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 label."
  }
}

variable "argocd_namespace" {
  type        = string
  description = "Namespace Argo CD runs in, taken from the capability's configuration rather than restated. An Application outside it is never read (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.argocd_namespace))
    error_message = "argocd_namespace must be a valid lowercase RFC 1123 label."
  }
}

variable "project" {
  type        = string
  default     = "default"
  description = "Argo CD project the Application belongs to. default is the one Argo CD creates for itself"

  validation {
    condition     = length(var.project) > 0
    error_message = "project must not be empty."
  }
}

variable "repo_url" {
  type        = string
  default     = "https://github.com/argoproj/argocd-example-apps.git"
  description = "Git repository the Application syncs from. The upstream Argo CD example repository, which needs no credentials"

  validation {
    condition     = can(regex("^(https://|git@)", var.repo_url))
    error_message = "repo_url must be an https or ssh git URL."
  }
}

variable "path" {
  type        = string
  default     = "guestbook"
  description = "Directory inside the repository to sync. guestbook is two plain manifests, a Deployment and a Service, with no Helm or Kustomize in the way"

  validation {
    condition     = length(var.path) > 0
    error_message = "path must not be empty; use \".\" for the repository root."
  }
}

variable "target_revision" {
  type        = string
  default     = "HEAD"
  description = "Revision to sync. HEAD because the example repository publishes no releases; name a commit for anything longer lived, since automated sync means an upstream push changes this cluster"

  validation {
    condition     = length(var.target_revision) > 0
    error_message = "target_revision must not be empty."
  }
}

variable "destination_namespace" {
  type        = string
  default     = "guestbook"
  description = "Namespace the synced objects land in. Created by Argo CD through the CreateNamespace sync option, so it is deliberately not declared as a Terraform resource - Argo CD owns what it creates"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.destination_namespace))
    error_message = "destination_namespace must be a valid lowercase RFC 1123 label."
  }
}

variable "prune" {
  type        = bool
  default     = true
  description = "Whether automated sync deletes objects that disappear from the repository"
}

variable "self_heal" {
  type        = bool
  default     = true
  description = "Whether automated sync reverts changes made directly against the cluster. True makes the demo self-evident: edit the Deployment with kubectl and watch it come back"
}

variable "capability_dependency" {
  type        = any
  default     = null
  description = "Value the caller passes purely to order this module after the Argo CD capability. The Application CRD does not exist until the capability has installed Argo CD (rules.md D-4)"
}
