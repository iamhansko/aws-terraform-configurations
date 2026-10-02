variable "repository_name" {
  type        = string
  description = "Name of the repository to create under the owner the github provider is configured with. Argo CD is pointed at this repository, so the name is part of the demo rather than incidental"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{1,100}$", var.repository_name))
    error_message = "repository_name must be 1-100 characters of letters, digits, dots, underscores or hyphens, which is what GitHub accepts for a repository name."
  }
}
variable "repository_description" {
  type        = string
  default     = "Seed manifests for the Argo CD and Vault demo, created by Terraform"
  description = "Repository description shown on GitHub"

  validation {
    condition     = length(var.repository_description) <= 350
    error_message = "repository_description must be 350 characters or fewer."
  }
}
variable "visibility" {
  type        = string
  default     = "private"
  description = "Repository visibility. Private by default: the manifests carry <path:...> placeholders rather than secrets, but the repository is created under a real account and a demo is a poor reason to publish anything"

  validation {
    condition     = contains(["public", "private"], var.visibility)
    error_message = "visibility must be either public or private. GitHub's internal visibility needs an organisation, which this module does not assume."
  }
}
variable "files" {
  type        = map(string)
  description = "Manifests to commit, keyed by their path in the repository (for example \"manifest/deployment.yaml\"). Rendered by the caller so the same definitions also reach the working copy on the instance, rather than existing twice (rules.md B-5)"

  validation {
    condition     = length(var.files) > 0
    error_message = "files must contain at least one manifest: an empty repository gives Argo CD nothing to sync, which is the failure this module was added to fix."
  }
  validation {
    condition     = alltrue([for path in keys(var.files) : can(regex("^[A-Za-z0-9._/-]+$", path)) && !startswith(path, "/")])
    error_message = "files keys are repository-relative paths, so each must be a non-empty relative path of letters, digits, dots, slashes, underscores or hyphens."
  }
}
variable "commit_message_prefix" {
  type        = string
  default     = "Add"
  description = "Prefix for each file's commit message, which the file path is appended to"

  validation {
    condition     = length(var.commit_message_prefix) > 0
    error_message = "commit_message_prefix must not be empty."
  }
}
variable "commit_author" {
  type        = string
  default     = "Terraform"
  description = "Author name recorded on the manifest commits"

  validation {
    condition     = length(var.commit_author) > 0
    error_message = "commit_author must not be empty."
  }
}
variable "commit_email" {
  type        = string
  default     = "terraform@example.com"
  description = "Author email recorded on the manifest commits. An example.com address on purpose: it is written into public commit metadata, and GitHub does not require it to be a real or verified address"

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+$", var.commit_email))
    error_message = "commit_email must look like an email address."
  }
}
