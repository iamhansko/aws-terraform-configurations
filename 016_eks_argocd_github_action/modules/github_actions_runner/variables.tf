variable "project_name" {
  type        = string
  description = "Name of the CodeBuild project. The workflow's runs-on label is built from it, so the repository module receives this same value - a mismatch leaves jobs queued with nothing logged"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{1,254}$", var.project_name))
    error_message = "project_name must be 2-255 characters of letters, digits, underscores or hyphens, starting with a letter or digit."
  }
}
variable "description" {
  type        = string
  default     = "GitHub Actions self-hosted runner backed by CodeBuild"
  description = "Project description"
}
variable "github_token" {
  type        = string
  sensitive   = true
  description = "GitHub personal access token CodeBuild authenticates with. Marked sensitive so it stays out of plan output; it still lands in state, which is why the state file for this project should be treated as a secret"

  validation {
    condition     = length(var.github_token) > 0
    error_message = "github_token must not be empty."
  }
}
variable "repository_clone_url" {
  type        = string
  description = "https clone URL of the repository the build checks out. Pass the repository module's output (rules.md B-5)"

  validation {
    condition     = can(regex("^https://github\\.com/", var.repository_clone_url))
    error_message = "repository_clone_url must be an https://github.com/ URL - CodeBuild's GITHUB source type expects one."
  }
}
variable "default_branch" {
  type        = string
  default     = "main"
  description = "Source version the project starts from. A self-hosted runner project needs one even though the job's checkout step decides what is actually built"

  validation {
    condition     = length(var.default_branch) > 0
    error_message = "default_branch must not be empty."
  }
}
variable "workflow_name" {
  type        = string
  description = "Workflow the webhook filters on. Pass the repository module's output, because the filter and the workflow's name have to agree exactly (rules.md B-5)"

  validation {
    condition     = length(var.workflow_name) > 0
    error_message = "workflow_name must not be empty."
  }
}
variable "ecr_repository_arn" {
  type        = string
  description = "ARN of the repository the build pushes to, used to scope the push permission. The _monolithic template attached AdministratorAccess instead"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:ecr:", var.ecr_repository_arn))
    error_message = "ecr_repository_arn must be an ECR repository ARN (arn:aws:ecr:...)."
  }
}
variable "policy_name" {
  type        = string
  default     = "CodeBuildRunnerPolicy"
  description = "Name of the inline policy on the build's role"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,128}$", var.policy_name))
    error_message = "policy_name must be 1-128 characters from the set IAM accepts for a policy name."
  }
}
variable "environment_type" {
  type        = string
  default     = "LINUX_CONTAINER"
  description = "CodeBuild environment type"

  validation {
    condition     = contains(["LINUX_CONTAINER", "LINUX_GPU_CONTAINER", "ARM_CONTAINER"], var.environment_type)
    error_message = "environment_type must be one of: LINUX_CONTAINER, LINUX_GPU_CONTAINER, ARM_CONTAINER."
  }
}
variable "compute_type" {
  type        = string
  default     = "BUILD_GENERAL1_SMALL"
  description = "Compute size for the runner container"

  validation {
    condition     = contains(["BUILD_GENERAL1_SMALL", "BUILD_GENERAL1_MEDIUM", "BUILD_GENERAL1_LARGE"], var.compute_type)
    error_message = "compute_type must be one of: BUILD_GENERAL1_SMALL, BUILD_GENERAL1_MEDIUM, BUILD_GENERAL1_LARGE."
  }
}
variable "build_image" {
  type        = string
  default     = "aws/codebuild/standard:7.0"
  description = "Build image. 7.0 rather than the _monolithic template's 5.0, which is out of support and ships a Docker version old enough that buildx defaults have moved on"

  validation {
    condition     = length(var.build_image) > 0
    error_message = "build_image must not be empty."
  }
}
variable "privileged_mode" {
  type        = bool
  default     = true
  description = "Whether the build container gets a Docker daemon. Required: the workflow runs docker build, which cannot work without it. The _monolithic template omitted this, so its build would have failed at the docker build step"

  validation {
    condition     = var.privileged_mode
    error_message = "privileged_mode must be true in this configuration. The workflow's docker build step needs a Docker daemon inside the build container, and without privileged mode it fails with \"Cannot connect to the Docker daemon\"."
  }
}
