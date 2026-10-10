variable "name" {
  type        = string
  description = "Name of the build project. CodeBuild names its log group after it, which is what the policy's log statement is scoped to"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{1,254}$", var.name))
    error_message = "name must be 2-255 characters of letters, digits, underscores and hyphens, starting with a letter or digit."
  }
}
variable "region" {
  type        = string
  description = "Region the buildspec passes as AWS_DEFAULT_REGION and the log group ARNs are built from. Passed in rather than read from a data source, so this module has no data source to be deferred to apply (rules.md D-6)"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must be an AWS region code such as ap-northeast-2."
  }
}
variable "account_id" {
  type        = string
  description = "Account the buildspec passes as AWS_ACCOUNT_ID and the log group ARNs are built from"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}
variable "partition" {
  type        = string
  default     = "aws"
  description = "ARN partition, used to build the log group ARNs the policy is scoped to"

  validation {
    condition     = can(regex("^aws[a-zA-Z-]*$", var.partition))
    error_message = "partition must be an AWS partition such as aws, aws-cn or aws-us-gov."
  }
}
variable "role_name_prefix" {
  type        = string
  description = "Prefix the CodeBuild service role name is generated from, replacing the _monolithic template's CodeBuildRole plus a uuid-derived suffix"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,38}$", var.role_name_prefix))
    error_message = "role_name_prefix must be 1-38 characters from the IAM role name character set, leaving room for the generated suffix inside IAM's 64 character limit."
  }
}
variable "create_build_policy" {
  type        = bool
  default     = true
  description = "Whether to create the inline policy scoped to what the buildspec actually does. True, and turning it off means supplying an equivalent some other way - the build makes six distinct kinds of call and fails on the first one it is not allowed (rules.md A-5)"
}
variable "ecr_repository_name" {
  type        = string
  description = "Repository the build pushes to, passed as IMAGE_REPO_NAME. Taken from the repository module so the build, the bastion and the task definition all name one repository (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]{1,255}$", var.ecr_repository_name))
    error_message = "ecr_repository_name must be a valid ECR repository name."
  }
}
variable "ecr_repository_arn" {
  type        = string
  description = "ARN of that repository, which the policy's push statement is scoped to. Both the name and the ARN are taken because reassembling one from the other is how a policy comes to point at the wrong repository (rules.md A-5)"

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:ecr:", var.ecr_repository_arn))
    error_message = "ecr_repository_arn must be an ECR repository ARN."
  }
}
variable "artifact_bucket_arn" {
  type        = string
  description = "ARN of the pipeline's artifact store, which the policy's S3 statement is scoped to. This is where the build reads its input artefact from and writes the appspec back to - the source bucket is not in the build's path at all"

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:s3:::", var.artifact_bucket_arn))
    error_message = "artifact_bucket_arn must be an S3 bucket ARN (e.g. arn:aws:s3:::my-bucket)."
  }
}
variable "capacity_provider_name" {
  type        = string
  description = "Capacity provider the appspec's strategy names, by name rather than ARN. The _monolithic template passed the capacity provider resource's id, which is its ARN, and CreateTaskSet rejects that - the rejection then arrives inside a CodeDeploy deployment rather than in the build"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.capacity_provider_name))
    error_message = "capacity_provider_name must be a capacity provider name, not an ARN: 1-255 characters of letters, digits, underscores and hyphens. An ARN here is accepted by every Terraform check and fails inside the deployment."
  }
}
variable "task_execution_role_arn" {
  type        = string
  description = "Execution role the registered task definition names, and the only role the policy allows this build to pass. The _monolithic template rebuilt this ARN inside the buildspec from the account id and the role name; taking the ARN directly means the two cannot diverge (rules.md B-5)"

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:iam::[0-9]{12}:role/", var.task_execution_role_arn))
    error_message = "task_execution_role_arn must be an IAM role ARN."
  }
}
variable "task_family" {
  type        = string
  description = "Task definition family the build registers revisions into. The same family the service's first revision is in, so a deployment moves the service forward within one family (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.task_family))
    error_message = "task_family must be 1-255 characters of letters, digits, underscores and hyphens."
  }
}
variable "container_name" {
  type        = string
  description = "Container name in the registered revision and in the appspec's LoadBalancerInfo. A value here that differs from the service's container name stops the deployment rather than the build"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.container_name))
    error_message = "container_name must be 1-255 characters of letters, digits, underscores and hyphens, starting with a letter or digit."
  }
}
variable "container_port" {
  type        = number
  default     = 80
  description = "Port in the registered revision and in the appspec. Emitted as a JSON number rather than a string - see the --argjson note in the buildspec"

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "container_port must be between 1 and 65535."
  }
}
variable "health_check_path" {
  type        = string
  default     = "/health"
  description = "Path the registered revision's container health check requests, taken from the load balancer module so every copy of this path is one value (rules.md B-5)"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must start with a slash."
  }
}
variable "log_group_name" {
  type        = string
  description = "Log group the registered revision writes to, taken from the service module. The _monolithic template wrote this as a literal in the buildspec while Terraform created the group elsewhere, so renaming the group would have left the pipeline writing to one that does not exist (rules.md B-5)"

  validation {
    condition     = startswith(var.log_group_name, "/")
    error_message = "log_group_name must start with a slash."
  }
}
variable "log_stream_prefix" {
  type        = string
  default     = "ecs"
  description = "awslogs stream prefix in the registered revision, matching the one the service module uses"

  validation {
    condition     = length(var.log_stream_prefix) > 0
    error_message = "log_stream_prefix must not be empty."
  }
}
variable "task_cpu" {
  type        = number
  default     = 256
  description = "CPU units in the registered revision, matching the revision this apply registers"

  validation {
    condition     = var.task_cpu >= 128 && var.task_cpu <= 10240
    error_message = "task_cpu must be between 128 and 10240 CPU units."
  }
}
variable "task_memory" {
  type        = number
  default     = 512
  description = "Memory in MiB in the registered revision, matching the revision this apply registers"

  validation {
    condition     = var.task_memory >= 128
    error_message = "task_memory must be at least 128 MiB."
  }
}
variable "container_health_check_interval" {
  type        = number
  default     = 10
  description = "Health check interval in the registered revision. The _monolithic template's buildspec set this and the three below while its Terraform task definition set none of them, so the first revision and every later one behaved differently"

  validation {
    condition     = var.container_health_check_interval >= 5 && var.container_health_check_interval <= 300
    error_message = "container_health_check_interval must be between 5 and 300 seconds."
  }
}
variable "container_health_check_timeout" {
  type        = number
  default     = 5
  description = "Health check timeout in the registered revision"

  validation {
    condition     = var.container_health_check_timeout >= 2 && var.container_health_check_timeout <= 60
    error_message = "container_health_check_timeout must be between 2 and 60 seconds."
  }
  validation {
    condition     = var.container_health_check_timeout < var.container_health_check_interval
    error_message = "container_health_check_timeout must be less than container_health_check_interval."
  }
}
variable "container_health_check_retries" {
  type        = number
  default     = 3
  description = "Health check retries in the registered revision"

  validation {
    condition     = var.container_health_check_retries >= 1 && var.container_health_check_retries <= 10
    error_message = "container_health_check_retries must be between 1 and 10."
  }
}
variable "container_health_check_start_period" {
  type        = number
  default     = 0
  description = "Health check start period in the registered revision"

  validation {
    condition     = var.container_health_check_start_period >= 0 && var.container_health_check_start_period <= 300
    error_message = "container_health_check_start_period must be between 0 and 300 seconds."
  }
}
variable "go_base_image" {
  type        = string
  default     = "golang:1.16"
  description = "Base image of the Dockerfile the build writes. golang:1.16 as the _monolithic template specified in both of its Dockerfiles. It is a 2021 release, long out of support, and the Dockerfile is single stage so the resulting image carries the whole toolchain - both reproduced rather than modernised, because the image the project deploys is the thing being demonstrated"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]*:[a-zA-Z0-9._-]+$", var.go_base_image))
    error_message = "go_base_image must be an image reference including a tag."
  }
}
variable "timezone" {
  type        = string
  default     = "Asia/Seoul"
  description = "Zone the build container's clock is set to, as the _monolithic template set it. This is what the image tag timestamps are in"

  validation {
    condition     = can(regex("^[A-Za-z]+/[A-Za-z_+-]+$", var.timezone))
    error_message = "timezone must be a zoneinfo name such as Asia/Seoul, which has to exist under /usr/share/zoneinfo in the build image."
  }
}
variable "compute_type" {
  type        = string
  default     = "BUILD_GENERAL1_MEDIUM"
  description = "Build container size, as the _monolithic template had it"

  validation {
    condition     = contains(["BUILD_GENERAL1_SMALL", "BUILD_GENERAL1_MEDIUM", "BUILD_GENERAL1_LARGE", "BUILD_GENERAL1_XLARGE", "BUILD_GENERAL1_2XLARGE"], var.compute_type)
    error_message = "compute_type must be one of the BUILD_GENERAL1 sizes."
  }
}
variable "environment_type" {
  type        = string
  default     = "LINUX_CONTAINER"
  description = "Build environment type, as the _monolithic template had it"

  validation {
    condition     = contains(["LINUX_CONTAINER", "LINUX_GPU_CONTAINER", "ARM_CONTAINER", "LINUX_LAMBDA_CONTAINER", "ARM_LAMBDA_CONTAINER", "WINDOWS_SERVER_2019_CONTAINER", "WINDOWS_SERVER_2022_CONTAINER"], var.environment_type)
    error_message = "environment_type must be a CodeBuild environment type. The LAMBDA variants cannot run a Docker daemon at all, so they would break this build rather than slow it."
  }
}
variable "environment_image" {
  type        = string
  default     = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
  description = "Build image, as the _monolithic template had it. It carries the AWS CLI, docker and jq, which is what the buildspec relies on - a slimmer image would need those installed in pre_build"

  validation {
    condition     = length(var.environment_image) > 0
    error_message = "environment_image must not be empty."
  }
}
variable "privileged_mode" {
  type        = bool
  default     = true
  description = "Whether a Docker daemon runs inside the build container. True, which the _monolithic template did not set - the default is false, and with it false the three docker commands in the build phase have no daemon to reach and the build fails with \"Cannot connect to the Docker daemon\""
}
variable "build_timeout" {
  type        = number
  default     = 15
  description = "Minutes a build may run, as the _monolithic template had it. The golang base image pull is most of it, so a cold build on a rate-limited pull can reach this"

  validation {
    condition     = var.build_timeout >= 5 && var.build_timeout <= 480
    error_message = "build_timeout must be between 5 and 480 minutes."
  }
}
