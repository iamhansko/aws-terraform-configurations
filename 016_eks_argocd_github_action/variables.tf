variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.)"
}
variable "prefix" {
  type        = string
  default     = "eks"
  description = "Prefix for the network resources' Name tags (\"eks\" produces eks-vpc, eks-igw, eks-public-a, ...)"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.prefix))
    error_message = "prefix must be lowercase alphanumeric, optionally with hyphens."
  }
}
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
}
variable "public_subnet_tags" {
  type = map(string)
  default = {
    "kubernetes.io/role/elb" = "1"
  }
  description = <<-DESC
    Tags merged into every public subnet. The kubernetes.io/role/elb tag is how the AWS Load Balancer
    Controller auto-discovers subnets for an internet-facing load balancer; without it the controller
    fails with "couldn't auto-discover subnets" (rules.md G-1).

    Two load balancers in this project depend on it: the NLB for the Argo CD UI, and the ALB the
    controller builds from the Ingress Argo CD syncs. Neither is a Terraform resource, so with the tag
    missing nothing fails - the Service and the Ingress are created, every resource reports success, and
    their address fields simply stay empty forever. That is the state this project was applied in.
  DESC

  validation {
    condition = alltrue([
      for key, value in var.public_subnet_tags :
      length(key) > 0 && length(key) <= 128 && length(value) <= 256 && !startswith(lower(key), "aws:")
    ])
    error_message = "public_subnet_tags keys must be 1-128 characters and must not use the reserved \"aws:\" prefix, and values must be 256 characters or fewer. A misspelled key is not rejected by AWS, so the failure surfaces much later as a controller that cannot auto-discover subnets (rules.md G-1)."
  }
}
variable "private_subnet_tags" {
  type = map(string)
  default = {
    "kubernetes.io/role/internal-elb" = "1"
  }
  description = "Tags merged into every private subnet, used the same way for internal load balancers (rules.md G-1)"

  validation {
    condition = alltrue([
      for key, value in var.private_subnet_tags :
      length(key) > 0 && length(key) <= 128 && length(value) <= 256 && !startswith(lower(key), "aws:")
    ])
    error_message = "private_subnet_tags keys must be 1-128 characters and must not use the reserved \"aws:\" prefix, and values must be 256 characters or fewer. A misspelled key is not rejected by AWS, so the failure surfaces much later as a controller that cannot auto-discover subnets (rules.md G-1)."
  }
}
variable "cluster_name" {
  type        = string
  default     = "eks-cluster"
  description = "Name of the EKS cluster"

  validation {
    condition     = can(regex("^[0-9A-Za-z][A-Za-z0-9\\-_]{0,99}$", var.cluster_name))
    error_message = "cluster_name must start with a letter or digit and contain only letters, digits, hyphens and underscores (100 characters or fewer)."
  }
}
variable "kubernetes_version" {
  type        = string
  default     = "1.33"
  description = "EKS cluster Kubernetes version (1.XX)"

  validation {
    condition     = contains(["1.31", "1.32", "1.33"], var.kubernetes_version)
    error_message = "kubernetes_version must be one of: 1.31, 1.32, 1.33."
  }
}
variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the EKS cluster API server endpoint is reachable from the public internet. Needed because the helm and kubectl providers run from the machine executing terraform apply rather than from inside the VPC (rules.md E-1/E-2). Restrict access with public_access_cidrs rather than leaving it open to 0.0.0.0/0"
}
variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDR blocks allowed to reach the EKS API server's public endpoint when endpoint_public_access is true. Set this to your own address in CIDR form (e.g. [\"203.0.113.4/32\"]) instead of leaving the default: bootstrap_cluster_creator_admin_permissions grants anyone who can reach this endpoint with the creating AWS identity full cluster admin"

  validation {
    condition     = alltrue([for cidr in var.public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "public_access_cidrs must contain valid IPv4 CIDR blocks."
  }
}
variable "key_name" {
  type        = string
  default     = "eks-key"
  description = "Name of the EC2 key pair created for the VS Code instance and the managed node group"

  validation {
    condition     = can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be a non-empty string of printable ASCII characters, 255 characters or fewer."
  }
}
variable "node_group_name" {
  type        = string
  default     = "nodegroup"
  description = "Name of the managed node group that hosts the Karpenter controller itself. Karpenter cannot provision the nodes its own controller runs on, so this group is a prerequisite rather than a duplicate of it"

  validation {
    condition     = length(var.node_group_name) > 0
    error_message = "node_group_name must not be empty."
  }
}
variable "node_group_instance_types" {
  type        = list(string)
  default     = ["t3.medium"]
  description = "EC2 instance types for the managed node group hosting the Karpenter controller"

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "node_group_instance_types must contain at least one instance type."
  }
}
variable "node_group_desired_size" {
  type        = number
  default     = 2
  description = "Desired node count for the managed node group. Two nodes let the Karpenter controller's leader-elected replica pair spread across availability zones"

  validation {
    condition     = var.node_group_desired_size >= 0
    error_message = "node_group_desired_size must be zero or greater."
  }
}
variable "node_group_min_size" {
  type        = number
  default     = 2
  description = "Minimum node count for the managed node group"

  validation {
    condition     = var.node_group_min_size >= 0
    error_message = "node_group_min_size must be zero or greater."
  }
}
variable "node_group_max_size" {
  type        = number
  default     = 4
  description = "Maximum node count for the managed node group. Kept small on purpose: application scale-out is Karpenter's job, not this group's"

  validation {
    condition     = var.node_group_max_size >= 0
    error_message = "node_group_max_size must be zero or greater."
  }
}
variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "EC2 instance type for the VS Code EC2 instance"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must be a valid EC2 instance type (e.g. t3.medium)."
  }
}
variable "enable_cloudfront" {
  type        = bool
  default     = true
  description = "Whether to front the VS Code instance with a CloudFront distribution, so the editor is reached over HTTPS and the instance's own port stays closed to the internet. When false, reach code-server directly (see allow_inbound_from_anywhere) or through SSM Session Manager port forwarding"
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether to allow inbound access to the code-server port (8000) on the instance from 0.0.0.0/0. Unnecessary when enable_cloudfront is true, because the instance's security group then admits only the CloudFront origin-facing prefix list"
}
variable "cloudfront_origin_facing_prefix_list_name" {
  type        = string
  default     = "com.amazonaws.global.cloudfront.origin-facing"
  description = "Name of the AWS managed prefix list covering CloudFront's origin-facing address ranges. Looked up per region with a data source rather than carried in a hardcoded region-to-prefix-list map like the _monolithic template's AWSRegions2PrefixListId mapping, which went stale as AWS added regions"

  validation {
    condition     = length(var.cloudfront_origin_facing_prefix_list_name) > 0
    error_message = "cloudfront_origin_facing_prefix_list_name must not be empty."
  }
}
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory holding the bootstrap marker files, shared between the vscode_ec2 module (which touches <path>/userdata as the last step of its user data) and the SSM association that polls for it before writing the README (rules.md D-5/H-2). Under /run so the markers vanish on reboot rather than making a stale file look like a completed bootstrap"

  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/'."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the SSM association waits for the README command to report success. It has to cover the whole instance bootstrap, since the command's first act is to wait for the user data marker file"

  validation {
    condition     = var.readme_timeout_seconds > 0
    error_message = "readme_timeout_seconds must be greater than zero."
  }
}
variable "kubectl_download_version" {
  type        = string
  default     = "1.33.3/2025-08-03"
  description = "Version and release-date path segment of the kubectl binary downloaded onto the VS Code EC2 instance, from the amazon-eks S3 bucket layout (<version>/<date>)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.33.3/2025-08-03."
  }
}
variable "load_balancer_controller_chart_version" {
  type        = string
  default     = "1.14.1"
  description = "Version of the aws-load-balancer-controller Helm chart. Pinned rather than whatever the _monolithic template's cloned install script happened to fetch"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.load_balancer_controller_chart_version))
    error_message = "load_balancer_controller_chart_version must be a semantic version (e.g. 1.14.1)."
  }
}
variable "enable_backend_security_group" {
  type        = bool
  default     = false
  description = "Whether the AWS Load Balancer Controller uses a shared backend security group. False, as in every project in this repository: no workload here sets the manage-backend-security-group-rules annotation, so the controller writes no node-side rules and needs no shared group as their source. The load balancer carries the EKS cluster security group, which already reaches pod IPs (rules.md G-2)"
}
variable "github_owner" {
  type        = string
  description = "GitHub user or organisation the repository is created under. No default: this has to be an account the token below can write to"

  validation {
    condition     = can(regex("^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$", var.github_owner))
    error_message = "github_owner must be a valid GitHub login."
  }
}
variable "github_token" {
  type        = string
  sensitive   = true
  description = "GitHub personal access token, used by both the github provider and CodeBuild. Needs repo and workflow scope - without workflow, GitHub rejects the commit that creates .github/workflows/codebuild.yaml and the apply fails after the repository already exists. Pass it with TF_VAR_github_token rather than a tfvars file that could be committed"

  validation {
    condition     = length(var.github_token) > 0
    error_message = "github_token must not be empty."
  }
}
variable "github_repository_name" {
  type        = string
  default     = "argocd-repo"
  description = "Name of the GitHub repository Terraform creates and Argo CD watches"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{1,100}$", var.github_repository_name))
    error_message = "github_repository_name must be 1-100 characters of letters, digits, dots, underscores or hyphens."
  }
}
variable "github_default_branch" {
  type        = string
  default     = "main"
  description = "Branch the workflow triggers on and Argo CD tracks. The _monolithic template's workflow watched master, which is not what GitHub initialises a repository with any more - so it would never have fired"

  validation {
    condition     = length(var.github_default_branch) > 0
    error_message = "github_default_branch must not be empty."
  }
}
variable "github_workflow_name" {
  type        = string
  default     = "argocd"
  description = "Workflow name. The CodeBuild webhook filters on it, so both sides receive this one value"

  validation {
    condition     = length(var.github_workflow_name) > 0
    error_message = "github_workflow_name must not be empty."
  }
}
variable "codebuild_project_name" {
  type        = string
  default     = "github-actions-runner"
  description = "Name of the CodeBuild project backing the self-hosted runner. The _monolithic template derived it from the CloudFormation stack ID; it is a plain variable here (rules.md B-3)"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{1,254}$", var.codebuild_project_name))
    error_message = "codebuild_project_name must be 2-255 characters of letters, digits, underscores or hyphens."
  }
}
variable "ecr_repository_name" {
  type        = string
  default     = "app-repo"
  description = "Name of the ECR repository the pipeline pushes to"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]{1,255}$", var.ecr_repository_name))
    error_message = "ecr_repository_name must start with a lowercase letter or digit."
  }
}
variable "app_name" {
  type        = string
  default     = "nginx-deploy"
  description = "Name of the Deployment in the synced manifests, and the base for its Service and Ingress"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.app_name))
    error_message = "app_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "app_replica_count" {
  type        = number
  default     = 3
  description = "Replicas in the synced Deployment"

  validation {
    condition     = var.app_replica_count > 0
    error_message = "app_replica_count must be greater than zero."
  }
}
variable "argocd_chart_version" {
  type        = string
  default     = "9.1.6"
  description = "Version of the argo-cd Helm chart. Pinned rather than the _monolithic template's kubectl apply of stable/manifests/install.yaml, which installed whatever stable pointed at that day"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.argocd_chart_version))
    error_message = "argocd_chart_version must be a semantic version (e.g. 9.1.6)."
  }
}
variable "argocd_namespace" {
  type        = string
  default     = "argocd"
  description = "Namespace Argo CD runs in"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.argocd_namespace))
    error_message = "argocd_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "argocd_application_name" {
  type        = string
  default     = "argo-app"
  description = "Name of the Argo CD Application watching the repository"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.argocd_application_name))
    error_message = "argocd_application_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "manifest_path" {
  type        = string
  default     = "manifest"
  description = "Directory in the repository the workflow rewrites and Argo CD syncs. One variable feeds both sides so they cannot disagree (rules.md B-5)"

  validation {
    condition     = can(regex("^[A-Za-z0-9._/-]+$", var.manifest_path))
    error_message = "manifest_path must be a relative path."
  }
}
