variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.)"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region such as ap-northeast-2, or null to fall back to the provider default chain."
  }
}
variable "project_name" {
  type        = string
  default     = "codecommit-source"
  description = "Base name for everything in this variant: the cluster, the registry, the pipeline, the build project and the roles. One value rather than a name per resource, so the three variants of this project can coexist in one account without colliding - which they otherwise would, since the _monolithic templates all derived their names from the same CloudFormation stack name"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,40}$", var.project_name))
    error_message = "project_name must be 2-41 characters of lowercase letters, digits and hyphens, short enough to leave room for the per-resource suffixes."
  }
}
variable "kubernetes_version" {
  type        = string
  default     = "1.34"
  description = "Kubernetes version for the EKS cluster"

  validation {
    condition     = can(regex("^1\\.(3[0-9]|[4-9][0-9])$", var.kubernetes_version))
    error_message = "kubernetes_version must be a supported 1.XX version, e.g. 1.34."
  }
}
variable "kubectl_download_version" {
  type        = string
  default     = "1.34.11/2026-09-22"
  description = "Version path used to download kubectl onto the VS Code instance, in <version>/<release-date> form. Raised together with kubernetes_version: kubectl more than one minor version from the API server is outside the supported skew (rules.md H-1)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.34.11/2026-09-22."
  }
}
variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the EKS API server endpoint is reachable from the internet. True as the _monolithic template had it. Unlike most roots here it is not needed for a kubectl provider - there is none - but the helm provider that installs the load balancer controller runs on the machine executing terraform apply, and the workbench reaches the cluster through it as well. Narrow public_access_cidrs rather than leaving the default open"

  validation {
    # Pinned in the direction this variant depends on, with the alternative named (rules.md B-1/E-9).
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because the AWS Load Balancer Controller is installed by the helm provider from the machine running terraform. Note that the pipeline's own deploy stage does not need it - that stage runs inside the VPC. To run with a private endpoint, install the controller from the bastion through an SSM Association instead, as 041_eks_private_cluster does (rules.md E-9)."
  }
}
variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDR blocks allowed to reach the public API server endpoint. Set this to your own address in CIDR form: bootstrap_cluster_creator_admin_permissions means anyone who can reach this endpoint with a valid AWS credential for the creating principal has cluster-admin"

  validation {
    condition     = alltrue([for cidr in var.public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "public_access_cidrs must contain valid IPv4 CIDR blocks."
  }
}
variable "public_subnet_tags" {
  type = map(string)
  default = {
    "kubernetes.io/role/elb" = "1"
  }
  description = "Tags merged into every public subnet. The kubernetes.io/role/elb tag is how the AWS Load Balancer Controller auto-discovers subnets for an internet-facing load balancer; without it the controller fails with 'couldn't auto-discover subnets' (rules.md G-1)"

  validation {
    condition = alltrue([
      for key, value in var.public_subnet_tags :
      length(key) > 0 && length(key) <= 128 && length(value) <= 256 && !startswith(lower(key), "aws:")
    ])
    error_message = "public_subnet_tags keys must be 1-128 characters and must not use the reserved \"aws:\" prefix, and values must be 256 characters or fewer (rules.md G-1)."
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
    error_message = "private_subnet_tags keys must be 1-128 characters and must not use the reserved \"aws:\" prefix, and values must be 256 characters or fewer."
  }
}
variable "key_name" {
  type        = string
  default     = null
  description = "Name of the EC2 key pair created for the demo instance. Null derives it from project_name, which keeps the three variants from colliding on one key pair name"

  validation {
    condition     = var.key_name == null || length(var.key_name) > 0
    error_message = "key_name must be a non-empty string, or null to derive it from project_name."
  }
}
variable "node_group_instance_types" {
  type        = list(string)
  default     = ["t3.medium"]
  description = "Instance types for the managed node group, t3.medium as the _monolithic template had it"

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "node_group_instance_types must contain at least one instance type."
  }
}
variable "node_group_desired_size" {
  type        = number
  default     = 2
  description = "Desired node count, two as the _monolithic template had it. Two matters here: the rendered Deployment asks for two replicas, and with one node a rolling update has nowhere to put the new pod until the old one goes"

  validation {
    condition     = var.node_group_desired_size >= 1
    error_message = "node_group_desired_size must be at least 1."
  }
}
variable "node_group_min_size" {
  type        = number
  default     = 2
  description = "Minimum node count"

  validation {
    condition     = var.node_group_min_size >= 1
    error_message = "node_group_min_size must be at least 1."
  }
}
variable "node_group_max_size" {
  type        = number
  default     = 4
  description = "Maximum node count, four as the _monolithic template had it. Nothing scales this node group"

  validation {
    condition     = var.node_group_max_size >= 1
    error_message = "node_group_max_size must be at least 1."
  }
  validation {
    condition     = var.node_group_max_size >= var.node_group_min_size
    error_message = "node_group_max_size must be greater than or equal to node_group_min_size."
  }
}
variable "aws_load_balancer_controller_chart_version" {
  type        = string
  default     = "1.14.1"
  description = "Pinned aws-load-balancer-controller chart version. It is what turns the Service the pipeline applies into an NLB; the _monolithic template installed it with a helm command in user data, after an \"exec bash\" line that discarded every remaining line - so on a real boot it was never installed and the pipeline's Service never got an address (rules.md E-1/H-1)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.aws_load_balancer_controller_chart_version))
    error_message = "aws_load_balancer_controller_chart_version must be a semantic version."
  }
}
variable "enable_service_mutator_webhook" {
  type        = bool
  default     = false
  description = "Whether the controller installs the mservice.elbv2.k8s.aws mutating webhook. False: the one Service of type LoadBalancer here sets aws-load-balancer-type: external and is claimed without it (rules.md G-1), while the webhook's failurePolicy: Fail and missing namespaceSelector make every Service creation in the cluster wait on a controller pod being Ready - and here that Service is created by a pipeline stage whose failure is several screens away (rules.md G-4)"

  validation {
    condition     = var.enable_service_mutator_webhook == false
    error_message = "enable_service_mutator_webhook must stay false in this variant. The Service the pipeline applies sets aws-load-balancer-type: external, so the controller claims it without the webhook, while the webhook's failurePolicy: Fail applies to every Service created in the cluster (rules.md G-4)."
  }
}
variable "workload_name" {
  type        = string
  default     = "fastapi"
  description = "Name of the Deployment and Service the pipeline renders and applies. Also the second half of the stack tag the pre-created NLB must carry to be adopted rather than duplicated - one value feeds both, so the tag cannot drift from the Service the pipeline creates (rules.md B-5/G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.workload_name))
    error_message = "workload_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "workload_namespace" {
  type        = string
  default     = "default"
  description = "Namespace the pipeline's deploy stage applies into, as the _monolithic template had it. Also the first half of the load balancer's stack tag"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.workload_namespace))
    error_message = "workload_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "workload_container_port" {
  type        = number
  default     = 8000
  description = "Port the application listens on, 8000 as the _monolithic template's Dockerfile and manifest had it. With nlb-target-type ip the load balancer sends traffic straight to the pod, so this - not the Service port - is what the pod-side security group rule has to open (rules.md G-1/G-2)"

  validation {
    condition     = var.workload_container_port > 0 && var.workload_container_port <= 65535
    error_message = "workload_container_port must be between 1 and 65535."
  }
}
variable "workload_service_port" {
  type        = number
  default     = 80
  description = "Port the Service publishes, and therefore the NLB's listener port - the one the frontend security group opens"

  validation {
    condition     = var.workload_service_port > 0 && var.workload_service_port <= 65535
    error_message = "workload_service_port must be between 1 and 65535."
  }
}
variable "workload_replicas" {
  type        = number
  default     = 2
  description = "Replicas in the Deployment the pipeline renders, two as the _monolithic template had it"

  validation {
    condition     = var.workload_replicas >= 1
    error_message = "workload_replicas must be at least 1."
  }
}
variable "image_tag" {
  type        = string
  default     = "latest"
  description = "Tag the pipeline's image build stage publishes. Nothing watches it in this variant - the source event is a push to CodeCommit - so it exists only so a reader can find the image the run produced by tag as well as by digest"

  validation {
    condition     = length(var.image_tag) > 0
    error_message = "image_tag must not be empty."
  }
}
variable "load_balancer_security_group_name" {
  type        = string
  default     = null
  description = "Name of the frontend security group attached to the pre-created NLB. Null derives it from project_name, which keeps the three variants from colliding. An NLB can only be given security groups at creation, so this group and the load balancer are created together (rules.md G-3)"

  validation {
    condition     = var.load_balancer_security_group_name == null || (can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.load_balancer_security_group_name)) && !startswith(var.load_balancer_security_group_name, "sg-"))
    error_message = "load_balancer_security_group_name must use the character set EC2 accepts for a security group name (no apostrophe) and must not start with \"sg-\" (rules.md F-1), or be null to derive it."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the NLB frontend security group and the VS Code security group accept traffic from 0.0.0.0/0. True as the _monolithic template had it, because the application and code-server are both reached from a browser - but code-server has no authentication in front of it, so narrow this with ingress_cidr_blocks where possible"
}
variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "EC2 instance type for the VS Code EC2 instance. Unlike the ECR-source variant it does not build the image - the pipeline's image build stage does - so this only has to run code-server and hold the git repository it pushes to CodeCommit"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must be a valid EC2 instance type, e.g. t3.medium."
  }
}
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the VS Code instance where each step drops its completion marker. Two SSM associations run here in order - build and push the image, then write the README - and they are sequenced by these markers rather than by depends_on (rules.md D-5/H-2)"

  validation {
    condition     = var.marker_file_path == null || can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/', or null."
  }
}
variable "git_prepare_timeout_seconds" {
  type        = number
  default     = 1200
  description = "How long the association that prepares the git repository may take. The work itself is writing four files and one commit, so nearly all of this budget is spent waiting for the instance bootstrap to finish installing kubectl, eksctl and helm - which is what the association waits on before it starts (rules.md D-5)"

  validation {
    condition     = var.git_prepare_timeout_seconds > 0
    error_message = "git_prepare_timeout_seconds must be positive."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 1800
  description = "How long the README association may take. It waits for the git preparation association to finish first, so its budget has to cover that as well"

  validation {
    condition     = var.readme_timeout_seconds > 0
    error_message = "readme_timeout_seconds must be positive."
  }
  validation {
    # The README waits on the git preparation marker, so its own budget has to be the larger of the two or it gives up
    # while the step it is waiting for is still running - and SSM reports that as a bare Failed
    # (rules.md B-1/D-5).
    condition     = var.readme_timeout_seconds > var.git_prepare_timeout_seconds
    error_message = "readme_timeout_seconds must be greater than git_prepare_timeout_seconds: the README association waits for the git preparation to finish, so a smaller budget makes it give up on a step that is still running, and SSM reports that only as \"unexpected state 'Failed'\"."
  }
}
variable "repository_name" {
  type        = string
  default     = null
  description = "Name of the CodeCommit repository the pipeline reads. Null derives it from project_name, which is what keeps two copies of this project in one account from colliding - a repository name is unique per account and region"

  validation {
    condition     = var.repository_name == null || can(regex("^[A-Za-z0-9._-]{1,100}$", var.repository_name))
    error_message = "repository_name must be 1-100 characters of letters, digits, dots, underscores and hyphens, or null to derive it from project_name."
  }
}
variable "repository_description" {
  type        = string
  default     = "Sample FastAPI application deployed to EKS by CodePipeline"
  description = "Description set on the CodeCommit repository"
}
variable "branch_name" {
  type        = string
  default     = "main"
  description = "Branch the pipeline reads. Chosen here rather than read back, because CodeCommit adopts the first branch pushed as the repository default and this project makes that push - so one value feeds the local branch the workbench creates, the source stage and the EventBridge rule (rules.md B-5). Main rather than the _monolithic template's master, because that is what git now creates by default"

  validation {
    condition     = can(regex("^[A-Za-z0-9._/-]{1,255}$", var.branch_name))
    error_message = "branch_name must be a plain git branch name."
  }
}
variable "enable_pipeline_trigger" {
  type        = bool
  default     = true
  description = <<-DESC
    Whether a push to the branch starts the pipeline automatically.

    True, which is the finished state and the thing this variant exists to show: the source stage sets
    PollForSourceChanges to false, so the EventBridge rule is the only thing that starts a run. It is also
    what makes the apply self-completing - the workbench's first push is matched by the rule, so the
    application is built and deployed before the apply returns.

    Set false to see exactly that: the pipeline is created, the push lands, and nothing happens until
    start-pipeline-execution is run by hand (rules.md B-4).
  DESC
}
