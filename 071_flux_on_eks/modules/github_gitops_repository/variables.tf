variable "name" {
  type        = string
  description = "Repository name, created under the account the github provider is authenticated as"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.name))
    error_message = "name must be a valid GitHub repository name: letters, digits, dots, underscores and hyphens."
  }
}
variable "description" {
  type        = string
  default     = "GitOps repository reconciled by Flux, created by Terraform"
  description = "Repository description shown on GitHub"
}
variable "visibility" {
  type        = string
  default     = "private"
  description = "Repository visibility. Private by default, which is the case worth wiring: a private repository is the reason Flux needs a Secret at all, and a public one would reconcile with no credentials and prove nothing about the token"

  validation {
    condition     = contains(["private", "public"], var.visibility)
    error_message = "visibility must be either private or public."
  }
}
variable "path" {
  type        = string
  default     = "clusters/flux-cluster"
  description = "Directory inside the repository the seeded manifests are written to, and the directory the caller points its Kustomization at. One cluster per path is what lets one repository serve several"

  validation {
    condition     = can(regex("^[A-Za-z0-9._/-]+$", var.path)) && !startswith(var.path, "/") && !endswith(var.path, "/")
    error_message = "path must be repository-relative, must not start with '/' and must not end with '/'."
  }
}
variable "seed_manifests" {
  type        = map(string)
  default     = {}
  description = "Files to commit under path, keyed by file name. Something has to be there: a Kustomization pointed at an empty directory fails with \"kustomization.yaml not found\", which reads like a broken path rather than an empty repository. Values are the file contents, so the caller renders them with yamlencode and keeps YAML out of this module (rules.md E-3)"

  validation {
    condition     = alltrue([for file in keys(var.seed_manifests) : can(regex("^[A-Za-z0-9._-]+$", file))])
    error_message = "seed_manifests keys are file names written into path, so each must be a bare file name without directory separators."
  }
}
variable "commit_message" {
  type        = string
  default     = "Seed GitOps manifests (terraform)"
  description = "Commit message used for the seeded files"

  validation {
    condition     = length(var.commit_message) > 0
    error_message = "commit_message must not be empty."
  }
}
variable "auto_init" {
  type        = bool
  default     = true
  description = "Whether the repository is created with an initial commit. True, and effectively mandatory: without it the repository has no default branch, so neither the seeded files below nor anything Flux fetches has a reference to resolve"

  validation {
    condition     = var.auto_init
    error_message = "auto_init must be true: a repository created without an initial commit has no branch for the seeded files to be committed to, and the file resources fail with a reference error (rules.md B-1)."
  }
}
variable "archive_on_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy archives this repository instead of deleting it. True on purpose: everything else in this configuration is AWS infrastructure that is meant to be disposable, and a repository is the one thing here that holds history. Archiving leaves it readable and recoverable; deleting it is immediate and permanent. Set it false for a demo repository you mean to be thrown away, and note that an archived repository has to be unarchived by hand before a later apply can write to it again"
}
