variable "project_name" {
  type        = string
  description = "Name of the CodeBuild project. The workflow's runs-on label is codebuild-<project_name>-<run id>-<run attempt>, so the label and this name have to agree exactly - a mismatch leaves jobs queued with nothing logged on either side. The caller derives it, which is why the runner label is an output of this module (rules.md B-5)"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{1,254}$", var.project_name))
    error_message = "project_name must be 2-255 characters of letters, digits, underscores or hyphens, starting with a letter or digit."
  }
}
variable "description" {
  type        = string
  default     = "GitHub Actions self-hosted runner backed by CodeBuild"
  description = "Project description"

  validation {
    condition     = length(var.description) <= 255
    error_message = "description must be 255 characters or fewer."
  }
}
variable "repository_clone_url" {
  type        = string
  description = "https clone URL of the repository the build checks out. Assembled by the caller from the GitHub account and repository name so the credential, the clone URL and the seed push all name one repository (rules.md B-5)"

  validation {
    condition     = can(regex("^https://github\\.com/[^/]+/[^/]+\\.git$", var.repository_clone_url))
    error_message = "repository_clone_url must be an https://github.com/<owner>/<repo>.git URL - CodeBuild's GITHUB source type expects one."
  }
}
variable "default_branch" {
  type        = string
  description = "Source version the project starts from. A self-hosted runner project needs one even though the job's own checkout step decides what is built; the _monolithic template omitted it"

  validation {
    condition     = length(var.default_branch) > 0
    error_message = "default_branch must not be empty."
  }
}
variable "workflow_name" {
  type        = string
  description = "Workflow the webhook filters on. Taken from the same variable the generated workflow's name field uses, because the filter and the workflow name have to match exactly or no build ever starts (rules.md B-5)"

  validation {
    condition     = length(var.workflow_name) > 0
    error_message = "workflow_name must not be empty."
  }
}
variable "cluster_name" {
  type        = string
  description = "Name of the ECS cluster, used to scope ecs:DescribeServices to the one service this build deploys"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "service_name" {
  type        = string
  description = "Name of the ECS service, used to scope ecs:DescribeServices. wait-for-service-stability in the workflow is what calls it"

  validation {
    condition     = length(var.service_name) > 0
    error_message = "service_name must not be empty."
  }
}
variable "ecr_repository_arn" {
  type        = string
  description = "ARN of the repository the build pushes to, used to scope the push permission to it. The _monolithic template attached AdministratorAccess instead (rules.md A-5)"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:ecr:", var.ecr_repository_arn))
    error_message = "ecr_repository_arn must be an ECR repository ARN (arn:aws:ecr:...)."
  }
}
variable "code_deploy_application_name" {
  type        = string
  description = "Name of the CodeDeploy application, used to scope the deployment permissions. Taken from the deployment group module's output (rules.md B-5)"

  validation {
    condition     = length(var.code_deploy_application_name) > 0
    error_message = "code_deploy_application_name must not be empty."
  }
}
variable "code_deploy_deployment_group_name" {
  type        = string
  description = "Name of the CodeDeploy deployment group, used to scope the deployment permissions"

  validation {
    condition     = length(var.code_deploy_deployment_group_name) > 0
    error_message = "code_deploy_deployment_group_name must not be empty."
  }
}
variable "deployment_config_name" {
  type        = string
  description = "Name of the deployment configuration, which needs its own statement: a CodeDeployDefault.* configuration is an AWS-owned resource in this account's namespace and is not covered by the application ARN"

  validation {
    condition     = length(var.deployment_config_name) > 0
    error_message = "deployment_config_name must not be empty."
  }
}
variable "task_definition_role_arns" {
  type        = list(string)
  description = "The roles a task definition registered by this build may name, which is what iam:PassRole is scoped to. Both come from the service module, so the permission covers exactly the roles that exist rather than every role in the account (rules.md B-5)"

  validation {
    condition     = length(var.task_definition_role_arns) > 0 && alltrue([for arn in var.task_definition_role_arns : can(regex("^arn:aws[a-z-]*:iam::[0-9]+:role/", arn))])
    error_message = "task_definition_role_arns must contain at least one IAM role ARN. An empty list produces a PassRole statement with no resources, which IAM rejects, and the registered task definition then cannot name its execution role."
  }
}
variable "create_runner_policy" {
  type        = bool
  default     = true
  description = "Whether this module writes the scoped inline policy the generated workflow needs. False leaves the role with only additional_policy_arns, which is the shape to use when a caller wants to supply the whole policy itself"
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
variable "additional_policy_arns" {
  type        = list(string)
  default     = []
  description = "Extra IAM managed policy ARNs attached on top of the inline policy. Empty by default: a variable whose default is AdministratorAccess is never narrowed, however the description is worded (rules.md A-5). Put the _monolithic template's behaviour back by listing it here"

  validation {
    condition     = alltrue([for arn in var.additional_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "additional_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "environment_type" {
  type        = string
  default     = "LINUX_CONTAINER"
  description = "CodeBuild environment type, as the _monolithic template had it"

  validation {
    condition     = contains(["LINUX_CONTAINER", "LINUX_GPU_CONTAINER", "ARM_CONTAINER"], var.environment_type)
    error_message = "environment_type must be one of: LINUX_CONTAINER, LINUX_GPU_CONTAINER, ARM_CONTAINER."
  }
}
variable "compute_type" {
  type        = string
  default     = "BUILD_GENERAL1_SMALL"
  description = "Compute size for the runner container, as the _monolithic template had it"

  validation {
    condition     = contains(["BUILD_GENERAL1_SMALL", "BUILD_GENERAL1_MEDIUM", "BUILD_GENERAL1_LARGE", "BUILD_GENERAL1_2XLARGE"], var.compute_type)
    error_message = "compute_type must be one of: BUILD_GENERAL1_SMALL, BUILD_GENERAL1_MEDIUM, BUILD_GENERAL1_LARGE, BUILD_GENERAL1_2XLARGE."
  }
}
variable "build_image" {
  type        = string
  default     = "aws/codebuild/standard:7.0"
  description = "Build image. 7.0 rather than the _monolithic template's 5.0, which is out of support and ships a Docker old enough that buildx defaults have moved on since"

  validation {
    condition     = length(var.build_image) > 0
    error_message = "build_image must not be empty."
  }
}
variable "privileged_mode" {
  type        = bool
  default     = true
  description = "Whether the build container gets a Docker daemon. Required here: the generated workflow runs docker build, which cannot work without it. The _monolithic template omitted this, so its workflow would have failed at that step"

  validation {
    condition     = var.privileged_mode
    error_message = "privileged_mode must be true in this configuration. The generated workflow's docker build step needs a Docker daemon inside the build container, and without privileged mode it fails with \"Cannot connect to the Docker daemon\" - on the GitHub side, long after the apply succeeded."
  }
}
