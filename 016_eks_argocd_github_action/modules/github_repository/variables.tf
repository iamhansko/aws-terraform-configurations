variable "repository_name" {
  type        = string
  default     = "argocd-repo"
  description = "Name of the GitHub repository, as the _monolithic template's GitHubRepo parameter had it"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{1,100}$", var.repository_name))
    error_message = "repository_name must be 1-100 characters of letters, digits, dots, underscores or hyphens."
  }
}
variable "description" {
  type        = string
  default     = "GitOps repository synced by Argo CD, built by CodeBuild through GitHub Actions"
  description = "Repository description"
}
variable "visibility" {
  type        = string
  default     = "public"
  description = "Repository visibility. Public, as the _monolithic template's IsPrivate: false had it - and because Argo CD pulls this repository without credentials, so a private one would need a deploy key or token this project does not create"

  validation {
    condition     = contains(["public", "private"], var.visibility)
    error_message = "visibility must be either public or private."
  }
  validation {
    condition     = var.visibility == "public"
    error_message = "visibility must be public in this configuration. Argo CD is given an https clone URL and no credentials, so a private repository leaves the Application permanently Unknown with an authentication error. Add a repository secret to Argo CD first if a private repository is wanted."
  }
}
variable "default_branch" {
  type        = string
  default     = "main"
  description = "Branch the workflow triggers on and Argo CD tracks. The _monolithic template's workflow watched \"master\", which is not what GitHub initialises a new repository with any more - the workflow would never have fired"

  validation {
    condition     = length(var.default_branch) > 0
    error_message = "default_branch must not be empty."
  }
}
variable "workflow_name" {
  type        = string
  default     = "argocd"
  description = "Name of the GitHub Actions workflow. The CodeBuild webhook filters on it, so it has to match the runner's WORKFLOW_NAME filter"

  validation {
    condition     = length(var.workflow_name) > 0
    error_message = "workflow_name must not be empty."
  }
}
variable "workflow_file_name" {
  type        = string
  default     = "codebuild.yaml"
  description = "File name of the workflow inside .github/workflows"

  validation {
    condition     = can(regex("\\.ya?ml$", var.workflow_file_name))
    error_message = "workflow_file_name must end in .yml or .yaml."
  }
}
variable "codebuild_project_name" {
  type        = string
  description = "Name of the CodeBuild project backing the self-hosted runner. Goes into the workflow's runs-on label, which is how GitHub routes the job - pass the runner module's output rather than restating it, because a mismatch leaves the job queued forever with no error (rules.md B-5)"

  validation {
    condition     = length(var.codebuild_project_name) > 0
    error_message = "codebuild_project_name must not be empty."
  }
}
variable "ecr_repository_name" {
  type        = string
  description = "ECR repository the workflow pushes to. Pass the registry module's name output (rules.md B-5)"

  validation {
    condition     = length(var.ecr_repository_name) > 0
    error_message = "ecr_repository_name must not be empty."
  }
}
variable "app_name" {
  type        = string
  default     = "nginx-deploy"
  description = "Name used for the Deployment, and the base for the Service and Ingress names"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.app_name))
    error_message = "app_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "yq_version" {
  type        = string
  default     = "v4.54.1"
  description = <<-DESC
    Release tag of the yq binary the workflow downloads to rewrite the image in deployment.yaml.

    A pinned binary fetched in a run step, rather than the mikefarah/yq action this workflow used to
    use. That action is a Docker container action, and a container action cannot read the workspace on
    a runner that is itself a container - see the comment on local.workflow in main.tf for the failure
    it produced. Pinning rather than tracking latest for the same reason the charts here are pinned;
    the action was referenced as @master, which is a floating ref.
  DESC

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.yq_version))
    error_message = "yq_version must be a yq release tag of the form vX.Y.Z (e.g. v4.54.1). The value goes straight into a release download URL, so a tag that does not exist fails the workflow step with a 404 from curl rather than anything about yq."
  }
}
variable "manifest_path" {
  type        = string
  default     = "manifest"
  description = "Directory holding the manifests Argo CD syncs. Both the workflow (which rewrites deployment.yaml) and the Argo CD Application (which watches the path) depend on this, so it is one variable passed to both"

  validation {
    condition     = can(regex("^[A-Za-z0-9._/-]+$", var.manifest_path))
    error_message = "manifest_path must be a relative path of letters, digits, dots, underscores, hyphens or slashes."
  }
}
variable "initial_image" {
  type        = string
  default     = "public.ecr.aws/nginx/nginx:latest"
  description = "Image in the first commit's deployment.yaml. An upstream image rather than one from ECR, because nothing has been pushed there when Argo CD first syncs - the workflow replaces it on the first commit to index.html"

  validation {
    condition     = length(var.initial_image) > 0
    error_message = "initial_image must not be empty."
  }
}
variable "initial_version" {
  type        = string
  default     = "v1.0.0"
  description = "Contents of the version file, which the workflow reads as the image tag. Bumping it and editing index.html is what triggers a new build"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.initial_version))
    error_message = "initial_version must be usable as a container image tag: letters, digits, dots, underscores or hyphens."
  }
}
variable "replica_count" {
  type        = number
  default     = 3
  description = "Replicas in the synced Deployment"

  validation {
    condition     = var.replica_count > 0
    error_message = "replica_count must be greater than zero."
  }
}
variable "container_port" {
  type        = number
  default     = 80
  description = "Port the container listens on, and the Service's targetPort"

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port must be a valid TCP port."
  }
}
variable "service_port" {
  type        = number
  default     = 80
  description = "Port the Service exposes, and the port the Ingress routes to"

  validation {
    condition     = var.service_port > 0 && var.service_port <= 65535
    error_message = "service_port must be a valid TCP port."
  }
}
variable "ingress_load_balancer_name" {
  type        = string
  default     = "cicd-alb"
  description = "Name the AWS Load Balancer Controller gives the ALB it provisions from the Ingress, as the _monolithic template's annotation had it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,32}$", var.ingress_load_balancer_name))
    error_message = "ingress_load_balancer_name must be 32 characters or fewer of letters, digits and hyphens."
  }
}
variable "commit_author_name" {
  type        = string
  default     = "GitHubAction"
  description = "Author name on the commits Terraform makes and the workflow pushes back"

  validation {
    condition     = length(var.commit_author_name) > 0
    error_message = "commit_author_name must not be empty."
  }
}
variable "commit_author_email" {
  type        = string
  default     = "github-action@example.com"
  description = "Author email on those commits. The _monolithic template used abc@abc.com"

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+$", var.commit_author_email))
    error_message = "commit_author_email must look like an email address."
  }
}
variable "commit_message_prefix" {
  type        = string
  default     = "Add"
  description = "Prefix for the commit message on each file Terraform creates"

  validation {
    condition     = length(var.commit_message_prefix) > 0
    error_message = "commit_message_prefix must not be empty."
  }
}
