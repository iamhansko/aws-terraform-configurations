variable "name" {
  type        = string
  description = "Name of the function, and the basis for its log group's name"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,64}$", var.name))
    error_message = "name must be 1-64 characters of letters, digits, hyphens and underscores."
  }
}
variable "source_dir" {
  type        = string
  description = "Directory holding the function's source, zipped at plan time"

  validation {
    condition     = length(var.source_dir) > 0
    error_message = "source_dir must not be empty."
  }
}
variable "project_name" {
  type        = string
  description = "CodeBuild project the function starts. Passed in from the module that created it, so the invocation's input and the role's permission cannot name different projects (rules.md B-5)"

  validation {
    condition     = length(var.project_name) > 0
    error_message = "project_name must not be empty."
  }
}
variable "project_arn" {
  type        = string
  description = "ARN of that project, so codebuild:StartBuild is scoped to it rather than to every project in the account"

  validation {
    condition     = can(regex("^arn:aws:codebuild:", var.project_arn))
    error_message = "project_arn must be a CodeBuild project ARN."
  }
}
variable "runtime" {
  type        = string
  default     = "nodejs22.x"
  description = "Lambda runtime. The _monolithic template used nodejs20.x while its own buildspec installed nodejs 22 - and nodejs20.x is now in the deprecation window. The function is ES module JavaScript using the v3 SDK, which every current Node runtime provides"

  validation {
    condition     = can(regex("^nodejs(2[2-9]|[3-9][0-9])\\.x$", var.runtime))
    error_message = "runtime must be nodejs22.x or newer. Older Node runtimes have reached or are approaching end of support."
  }
}
variable "handler" {
  type        = string
  default     = "index.handler"
  description = "Entry point. The source is an .mjs file, which is what makes the ES module export syntax work without a package.json declaring the type"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_./-]+\\.[a-zA-Z0-9_]+$", var.handler))
    error_message = "handler must be in <module>.<function> form."
  }
}
variable "timeout" {
  type        = number
  default     = 30
  description = "How long the function may run, thirty seconds as the _monolithic template had it. It makes one StartBuild call and returns - it does not wait for the build, which takes up to two hours"

  validation {
    condition     = var.timeout >= 1 && var.timeout <= 900
    error_message = "timeout must be between 1 and 900 seconds."
  }
}
variable "log_retention_days" {
  type        = number
  default     = 14
  description = "How long the function's logs are kept. The _monolithic template declared no group, so Lambda created one with retention set to never expire"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of the retention periods CloudWatch Logs accepts."
  }
}
variable "start_build_on_apply" {
  type        = bool
  default     = true
  description = "Whether applying this configuration starts a build. True, which is what the _monolithic template did through its custom resource - the point of the project is that one apply deploys the whole thing. Set false to create the pipeline and start it by hand, which is the safer way to try it: the build deploys a CDK stack that Terraform does not track and cannot remove (rules.md B-4)"
}
variable "build_revision" {
  type        = string
  default     = null
  description = "Opaque revision of the build definition - in this project the hash of the buildspec, which carries the Dockerfile inside it. Changing it re-invokes the trigger and therefore starts a new build. Null omits the triggers map, so the invocation stays a one-shot that fires only on first create (see main.tf for what that meant in practice)"

  validation {
    condition     = var.build_revision == null || length(var.build_revision) > 0
    error_message = "build_revision must be a non-empty string, or null to leave the trigger firing only on create."
  }
}
