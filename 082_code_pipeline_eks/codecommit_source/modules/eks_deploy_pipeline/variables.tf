variable "name" {
  type        = string
  description = "Base name for the pipeline, the build project and the roles. No default: the caller derives it from the project name, and the names appear in the ARNs the IAM policies below are scoped to"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{1,80}$", var.name))
    error_message = "name must be 2-81 characters of letters, digits, dots, underscores and hyphens - CodePipeline's own limit."
  }
}
variable "cluster_name" {
  type        = string
  description = "EKS cluster the deploy stage applies the manifest to. The stage runs inside the VPC and talks to the cluster's API server, so the cluster's access entry has to name this pipeline's role - which the caller creates (rules.md C-1)"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "cluster_arn" {
  type        = string
  description = "ARN of that cluster, so the pipeline role's eks:DescribeCluster is scoped to it rather than to every cluster in the account (rules.md A-5)"

  validation {
    condition     = can(regex("^arn:aws:eks:", var.cluster_arn))
    error_message = "cluster_arn must be an EKS cluster ARN."
  }
}
variable "deploy_security_group_ids" {
  type        = list(string)
  description = "Security groups the deploy stage's network interface is given. It has to be able to reach the cluster's API server, so in practice this is the cluster security group - passed in as an ID list so this module never learns what it belongs to (rules.md B-6)"

  validation {
    condition     = length(var.deploy_security_group_ids) > 0 && alltrue([for id in var.deploy_security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "deploy_security_group_ids must be a non-empty list of valid security group IDs."
  }
}
variable "deploy_subnet_ids" {
  type        = list(string)
  description = "Subnets the deploy stage's network interface is placed in. Private subnets, because the stage needs to reach the API server and an egress route, not an inbound one"

  validation {
    condition     = length(var.deploy_subnet_ids) > 0 && alltrue([for id in var.deploy_subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "deploy_subnet_ids must be a non-empty list of valid subnet IDs."
  }
}
variable "source_action" {
  type = object({
    name          = string
    provider      = string
    configuration = map(string)
    namespace     = optional(string)
  })
  description = <<-DESC
    The pipeline's source stage, which is the only thing that differs between this project's variants: an
    ECR image push, a CodeCommit repository, or an object in S3.

    provider is CodePipeline's action provider name - ECR, CodeCommit or S3 - and configuration is that
    provider's own settings. namespace is needed only when a later stage reads a variable the source
    produced: the ECR source exports ImageURI that way, and the others do not.
  DESC

  validation {
    condition     = contains(["ECR", "S3", "CodeCommit"], var.source_action.provider)
    error_message = "source_action.provider must be ECR, S3 or CodeCommit - the three this project demonstrates."
  }
  validation {
    condition     = length(var.source_action.configuration) > 0
    error_message = "source_action.configuration must not be empty - every source provider needs at least a repository or a bucket."
  }
  validation {
    # The ECR source is the only one that hands a later stage a variable, and a stage referencing
    # #{SourceVariables.ImageURI} without the namespace fails at execution rather than at apply
    # (rules.md B-1).
    condition     = var.source_action.provider != "ECR" || var.source_action.namespace != null
    error_message = "source_action.namespace is required for the ECR provider: the build stage reads #{SourceVariables.ImageURI} from it, and without a namespace that reference resolves to nothing at execution time while the pipeline applies cleanly."
  }
}
variable "source_role_policy_statements" {
  type        = list(any)
  default     = []
  description = "Statements appended to the pipeline role's policy for whatever the source stage needs - ecr:DescribeImages for the ECR source, s3:GetObject on one key for the S3 source, codecommit:UploadArchive and friends for the CodeCommit source. Empty by default and supplied by the caller, because only the caller knows which source it configured (rules.md B-6)"
}
variable "include_image_build_stage" {
  type        = bool
  default     = false
  description = "Whether the pipeline builds a container image from the source artifact before the build stage. False for the ECR source, where the image already exists and pushing it is what started the pipeline; true for the CodeCommit and S3 sources, where the source is a source tree and something has to turn it into an image. That difference is the whole reason those two variants have four stages and this one has three"
}
variable "ecr_repository_name" {
  type        = string
  description = "Repository the image is in, or is built into. Named in the build project's environment and, when include_image_build_stage is on, in the image build stage's configuration"

  validation {
    condition     = length(var.ecr_repository_name) > 0
    error_message = "ecr_repository_name must not be empty."
  }
}
variable "ecr_repository_arn" {
  type        = string
  description = "ARN of that repository, so the image build stage's permissions can be scoped to it (rules.md A-5)"

  validation {
    condition     = can(regex("^arn:aws:ecr:", var.ecr_repository_arn))
    error_message = "ecr_repository_arn must be an ECR repository ARN."
  }
}
variable "image_tags" {
  type        = string
  default     = "latest"
  description = "Tag the image build stage pushes, and the tag the ECR source watches. One value, because a pipeline that pushes one tag and triggers on another never runs twice (rules.md B-5)"

  validation {
    condition     = length(var.image_tags) > 0
    error_message = "image_tags must not be empty."
  }
}
variable "workload_name" {
  type        = string
  default     = "fastapi"
  description = "Name of the Deployment and Service the build stage renders and the deploy stage applies. Also the second half of the stack tag a pre-created load balancer must carry to be adopted, which is why the caller passes the same value to both (rules.md B-5/G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.workload_name))
    error_message = "workload_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "workload_namespace" {
  type        = string
  default     = "default"
  description = "Namespace the deploy stage applies into, as the _monolithic template had it. Also the first half of the load balancer's stack tag"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.workload_namespace))
    error_message = "workload_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "workload_replicas" {
  type        = number
  default     = 2
  description = "Replicas in the rendered Deployment, two as the _monolithic template had it"

  validation {
    condition     = var.workload_replicas >= 1
    error_message = "workload_replicas must be at least 1."
  }
}
variable "workload_container_port" {
  type        = number
  default     = 8000
  description = "Port the application listens on, which uvicorn binds and which the Service targets. With nlb-target-type ip this is also the port the pod-side security group rule has to open - not the Service port (rules.md G-1/G-2)"

  validation {
    condition     = var.workload_container_port > 0 && var.workload_container_port <= 65535
    error_message = "workload_container_port must be a valid TCP port."
  }
}
variable "workload_service_port" {
  type        = number
  default     = 80
  description = "Port the Service publishes, and therefore the load balancer's listener port"

  validation {
    condition     = var.workload_service_port > 0 && var.workload_service_port <= 65535
    error_message = "workload_service_port must be a valid TCP port."
  }
}
variable "service_annotations" {
  type        = map(string)
  default     = {}
  description = "Annotations on the rendered Service, which is how the AWS Load Balancer Controller is told what to build. Supplied by the caller because the values name security groups this module does not own (rules.md B-6)"

  validation {
    condition     = alltrue([for key in keys(var.service_annotations) : length(key) > 0])
    error_message = "service_annotations must not contain empty annotation keys."
  }
}
variable "codebuild_image" {
  type        = string
  default     = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
  description = "CodeBuild environment image, as the _monolithic template had it. The build step only renders a YAML file, so the image's contents hardly matter - what matters is that it is pinned rather than :latest, because a managed image moving under a pipeline changes the build without any change to this configuration"

  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$", var.codebuild_image))
    error_message = "codebuild_image must carry an explicit tag."
  }
}
variable "codebuild_compute_type" {
  type        = string
  default     = "BUILD_GENERAL1_SMALL"
  description = "CodeBuild compute size. Small, where the _monolithic template used MEDIUM: the build writes one YAML file with a shell heredoc, and CodeBuild is billed per build minute by size"

  validation {
    condition     = contains(["BUILD_GENERAL1_SMALL", "BUILD_GENERAL1_MEDIUM", "BUILD_GENERAL1_LARGE", "BUILD_GENERAL1_2XLARGE"], var.codebuild_compute_type)
    error_message = "codebuild_compute_type must be one of the BUILD_GENERAL1 sizes."
  }
}
variable "build_timeout_minutes" {
  type        = number
  default     = 15
  description = "How long the build stage may take, fifteen minutes as the _monolithic template had it"

  validation {
    condition     = var.build_timeout_minutes >= 5 && var.build_timeout_minutes <= 480
    error_message = "build_timeout_minutes must be between 5 and 480 - CodeBuild's own range."
  }
}
variable "log_retention_days" {
  type        = number
  default     = 14
  description = "How long the build project's logs are kept. The _monolithic template created no log group at all, so CodeBuild made one with retention set to never expire - logs kept forever for a demo, billed forever"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of the retention periods CloudWatch Logs accepts."
  }
}
variable "artifact_bucket_name" {
  type        = string
  default     = null
  description = "Fixed name for the artifact bucket. Null generates one, which is what lets this project be deployed twice in one account - bucket names are globally unique. The _monolithic template declared a bare aws_s3_bucket with no arguments, which also generates a name and leaves everything else at the provider's defaults"

  validation {
    condition     = var.artifact_bucket_name == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.artifact_bucket_name))
    error_message = "artifact_bucket_name must be a valid S3 bucket name, or null to generate one."
  }
}
variable "execution_mode" {
  type        = string
  default     = "QUEUED"
  description = "What happens when a new execution starts while one is running. QUEUED as the _monolithic template had it: the second waits rather than superseding the first, which for a pipeline that deploys to a cluster means two deploys do not race"

  validation {
    condition     = contains(["QUEUED", "SUPERSEDED", "PARALLEL"], var.execution_mode)
    error_message = "execution_mode must be QUEUED, SUPERSEDED or PARALLEL."
  }
}
