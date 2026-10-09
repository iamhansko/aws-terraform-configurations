variable "aws_region" {
  type        = string
  default     = null
  description = "Region to deploy into. Null follows the provider chain (AWS_REGION / AWS_DEFAULT_REGION), which is how the _monolithic template was run"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a region code such as ap-northeast-2, or null to follow the provider chain."
  }
}
variable "project_name" {
  type        = string
  default     = "ecs-cicd"
  description = "Prefix for the names CloudFormation generated - the VPC, subnets, gateways, route tables, the repository, the cluster, the service and the ALB. Replaces the _monolithic template's stack_name and keeps the names it produced"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,24}$", var.project_name))
    error_message = "project_name must be 2-25 characters of lowercase letters, digits and hyphens, so every name derived from it stays inside its own service's limit - the ALB name is capped at 32 characters."
  }
}
# --- Network ----------------------------------------------------------------------------------------------
variable "vpc_cidr_block" {
  type        = string
  default     = "10.100.0.0/16"
  description = "CIDR block for the VPC, as the _monolithic template had it"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.100.0.0/16)."
  }
}
variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "b"]
  description = "The two AZ letters the subnet pairs are placed in, as the _monolithic template used them"

  validation {
    condition     = length(var.availability_zone_suffixes) == 2 && alltrue([for suffix in var.availability_zone_suffixes : can(regex("^[a-z]$", suffix))])
    error_message = "availability_zone_suffixes must contain exactly two single lowercase letters (e.g. [\"a\", \"b\"])."
  }
}
# --- Workbench --------------------------------------------------------------------------------------------
variable "bastion_ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "SSM parameter path resolved to the workbench's AMI ID, as the _monolithic template had it"

  validation {
    condition     = can(regex("^/", var.bastion_ami_ssm_parameter_name))
    error_message = "bastion_ami_ssm_parameter_name must be an absolute SSM parameter path starting with '/'."
  }
}
variable "bastion_instance_name" {
  type        = string
  default     = "ecs-cicd-bastion"
  description = "Name tag for the workbench instance, as the _monolithic template named it"

  validation {
    condition     = length(var.bastion_instance_name) > 0
    error_message = "bastion_instance_name must not be empty."
  }
}
variable "bastion_instance_type" {
  type        = string
  default     = "t3.small"
  description = "Instance type for the workbench, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.bastion_instance_type))
    error_message = "bastion_instance_type must be a valid EC2 instance type (e.g. t3.small)."
  }
}
variable "bastion_root_volume_size" {
  type        = number
  default     = 30
  description = "Root volume size in GiB for the workbench. It builds and pushes a container image, so the Docker Hub base image, the build layers and the result all land here"

  validation {
    condition     = var.bastion_root_volume_size >= 20
    error_message = "bastion_root_volume_size must be at least 20 GiB - the seed image build needs room for the python:3.13-slim base image and the built layers on top of the AL2023 root filesystem."
  }
}
variable "bastion_security_group_name" {
  type        = string
  default     = "bastion-ec2-sg"
  description = "Name of the workbench's security group, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.bastion_security_group_name)) && !startswith(var.bastion_security_group_name, "sg-")
    error_message = "bastion_security_group_name must be 1-255 characters from the set AWS accepts for a security group name (no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "code_server_version" {
  type        = string
  default     = "4.102.3"
  description = "code-server release installed on the workbench. The _monolithic template pinned 4.100.3"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a semantic version (e.g. 4.102.3)."
  }
}
variable "code_server_port" {
  type        = number
  default     = 8000
  description = "Port code-server binds to on the workbench, as the _monolithic template had it"

  validation {
    condition     = var.code_server_port > 0 && var.code_server_port <= 65535
    error_message = "code_server_port must be a valid TCP port."
  }
}
variable "bastion_ssh_port" {
  type        = number
  default     = 2222
  description = "Port sshd is moved to on the workbench, as the _monolithic template moved it"

  validation {
    condition     = var.bastion_ssh_port > 0 && var.bastion_ssh_port <= 65535
    error_message = "bastion_ssh_port must be a valid TCP port."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether code-server, the workbench's ssh port and the ALB listener accept traffic from 0.0.0.0/0. True as the _monolithic template had it. code-server runs with auth: none, so this is an unauthenticated editor on a public address - which is also why no secret is written into the README it serves (rules.md H-2)"
}
# --- Container instances ----------------------------------------------------------------------------------
variable "ecs_ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
  description = "SSM parameter path resolved to the ECS-optimized AMI ID, as the _monolithic template had it"

  validation {
    condition     = can(regex("^/", var.ecs_ami_ssm_parameter_name))
    error_message = "ecs_ami_ssm_parameter_name must be an absolute SSM parameter path starting with '/'."
  }
}
variable "container_instance_name" {
  type        = string
  default     = "ecs-container-instance"
  description = "Name tag for the container instances, as the _monolithic template named it"

  validation {
    condition     = length(var.container_instance_name) > 0
    error_message = "container_instance_name must not be empty."
  }
}
variable "container_instance_security_group_name" {
  type        = string
  default     = "ecs-container-instance-sg"
  description = "Name of the container instances' security group, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.container_instance_security_group_name)) && !startswith(var.container_instance_security_group_name, "sg-")
    error_message = "container_instance_security_group_name must be 1-255 characters from the set AWS accepts for a security group name (no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "container_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type for the container instances, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.container_instance_type))
    error_message = "container_instance_type must be a valid EC2 instance type (e.g. t3.medium)."
  }
}
variable "container_instance_min_size" {
  type        = number
  default     = 1
  description = "Minimum number of container instances, as the _monolithic template had it"

  validation {
    condition     = var.container_instance_min_size >= 0
    error_message = "container_instance_min_size must be zero or greater."
  }
}
variable "container_instance_max_size" {
  type        = number
  default     = 2
  description = "Maximum number of container instances. Two rather than the _monolithic template's one: a blue/green deployment runs the replacement task set alongside the original, and a ceiling of one leaves managed scaling nowhere to put it when it does not fit on the existing instance"

  validation {
    condition     = var.container_instance_max_size >= 1
    error_message = "container_instance_max_size must be at least 1."
  }
  validation {
    condition     = var.container_instance_max_size >= var.container_instance_min_size
    error_message = "container_instance_max_size must be greater than or equal to container_instance_min_size."
  }
}
variable "container_instance_desired_capacity" {
  type        = number
  default     = 1
  description = "Starting number of container instances, as the _monolithic template had it. A starting point only - ECS managed scaling owns the field afterwards"

  validation {
    condition     = var.container_instance_desired_capacity >= var.container_instance_min_size && var.container_instance_desired_capacity <= var.container_instance_max_size
    error_message = "container_instance_desired_capacity must be between container_instance_min_size and container_instance_max_size."
  }
}
variable "capacity_provider_name" {
  type        = string
  default     = "codedeploy-bluegreen-ecs-ec2-capacity-provider"
  description = "Name of the EC2 capacity provider, which the generated appspec names for the replacement task set. The name the _monolithic template produced from its default stack_name. Not derived from project_name: the default project_name starts with \"ecs\", a prefix ECS reserves for capacity provider names, so \"<project_name>-...\" is rejected for every project_name this root would most naturally be given"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.capacity_provider_name))
    error_message = "capacity_provider_name must be 1-255 characters of letters, digits, underscores or hyphens, starting with a letter or digit."
  }
  validation {
    condition     = !startswith(lower(var.capacity_provider_name), "aws") && !startswith(lower(var.capacity_provider_name), "ecs") && !startswith(lower(var.capacity_provider_name), "fargate")
    error_message = "capacity_provider_name must not start with aws, ecs or fargate - ECS reserves those prefixes and rejects CreateCapacityProvider with a ClientException. codedeploy-bluegreen-ecs-ec2-capacity-provider is the name the _monolithic template used."
  }
}
variable "container_instance_root_volume_size" {
  type        = number
  default     = 30
  description = "Root volume size in GiB for each container instance, which is also where pulled image layers land"

  validation {
    condition     = var.container_instance_root_volume_size >= 30
    error_message = "container_instance_root_volume_size must be at least 30 GiB, which is the ECS-optimized AMI's own root volume size."
  }
}
variable "container_insights" {
  type        = string
  default     = "enhanced"
  description = "Container Insights level on the cluster, as the _monolithic template had it. \"enhanced\" bills per observed task rather than being free like \"enabled\""

  validation {
    condition     = contains(["enhanced", "enabled", "disabled"], var.container_insights)
    error_message = "container_insights must be enhanced, enabled or disabled."
  }
}
# --- Load balancer and target groups ----------------------------------------------------------------------
variable "load_balancer_name" {
  type        = string
  default     = "ecs-cicd-alb"
  description = "Name of the ALB, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,32}$", var.load_balancer_name))
    error_message = "load_balancer_name must be 32 characters or fewer of letters, digits and hyphens."
  }
}
variable "load_balancer_security_group_name" {
  type        = string
  default     = "alb-sg"
  description = "Name of the ALB's security group, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.load_balancer_security_group_name)) && !startswith(var.load_balancer_security_group_name, "sg-")
    error_message = "load_balancer_security_group_name must be 1-255 characters from the set AWS accepts for a security group name (no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "listener_port" {
  type        = number
  default     = 80
  description = "Port the production listener accepts traffic on, as the _monolithic template had it"

  validation {
    condition     = var.listener_port > 0 && var.listener_port <= 65535
    error_message = "listener_port must be a valid TCP port."
  }
}
variable "target_group_names" {
  type = map(string)
  default = {
    blue  = "cicd-tg"
    green = "green-tg"
  }
  description = "The blue/green target group pair, keyed by role. The names are what the _monolithic template used"

  validation {
    condition     = length(setsubtract(keys(var.target_group_names), ["blue", "green"])) == 0 && length(var.target_group_names) == 2
    error_message = "target_group_names must contain exactly the keys blue and green."
  }
}
variable "initial_target_group_key" {
  type        = string
  default     = "blue"
  description = "Which half of the pair the listener forwards to at creation, and therefore which group the service registers into. The _monolithic template pointed both the listener and the service at the blue group"

  validation {
    condition     = contains(["blue", "green"], var.initial_target_group_key)
    error_message = "initial_target_group_key must be blue or green."
  }
}
variable "health_check_path" {
  type        = string
  default     = "/health"
  description = "Path the target groups and the container health check both request, as the _monolithic template had it. The seeded Flask application answers it"

  validation {
    condition     = can(regex("^/", var.health_check_path))
    error_message = "health_check_path must start with '/'."
  }
}
# --- Service and task -------------------------------------------------------------------------------------
variable "service_security_group_name" {
  type        = string
  default     = "ecs-service-sg"
  description = "Name of the tasks' security group, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.service_security_group_name)) && !startswith(var.service_security_group_name, "sg-")
    error_message = "service_security_group_name must be 1-255 characters from the set AWS accepts for a security group name (no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "task_family" {
  type        = string
  default     = "ecs-task-def"
  description = "Task definition family, as the _monolithic template named it. The seed association exports this family into taskdef.json and the workflow renders new revisions from that file"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.task_family))
    error_message = "task_family must be 1-255 characters of letters, digits, underscores or hyphens."
  }
}
variable "container_name" {
  type        = string
  default     = "python"
  description = "Name of the container, as the _monolithic template named it. The service's load_balancer block, the appspec's LoadBalancerInfo and the workflow's render step all have to use it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.container_name))
    error_message = "container_name must be 1-255 characters of letters, digits, underscores or hyphens, starting with a letter or digit."
  }
}
variable "container_port" {
  type        = number
  default     = 80
  description = "Port the container listens on, as the _monolithic template had it. With awsvpc this is also the host port and the target group port"

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port must be a valid TCP port."
  }
}
variable "task_cpu" {
  type        = string
  default     = "512"
  description = "Task-level CPU units, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[0-9]+$", var.task_cpu))
    error_message = "task_cpu must be a whole number of CPU units expressed as a string (e.g. \"512\")."
  }
}
variable "task_memory" {
  type        = string
  default     = "1024"
  description = "Task-level memory in MiB, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[0-9]+$", var.task_memory))
    error_message = "task_memory must be a whole number of MiB expressed as a string (e.g. \"1024\")."
  }
}
variable "service_desired_count" {
  type        = number
  default     = 1
  description = "Number of tasks the service keeps running, as the _monolithic template had it"

  validation {
    condition     = var.service_desired_count >= 0
    error_message = "service_desired_count must be zero or greater."
  }
}
variable "ecr_image_tag" {
  type        = string
  default     = "latest"
  description = "Moving tag the workbench pushes and the task definition pulls. The workflow pushes it alongside the commit sha on every run"

  validation {
    condition     = can(regex("^[A-Za-z0-9_][A-Za-z0-9._-]{0,127}$", var.ecr_image_tag))
    error_message = "ecr_image_tag must be 1-128 characters of letters, digits, dots, underscores or hyphens, starting with a letter, digit or underscore."
  }
}
variable "app_initial_tag" {
  type        = string
  default     = "ec2-v1.0.0"
  description = "Value of the TAG constant in the seeded cicd-app.py, which its /tag route returns. The workflow's Fargate branch keys off this constant being exactly \"fargate\", so this is also what makes the first deployment an EC2 one"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{1,64}$", var.app_initial_tag))
    error_message = "app_initial_tag must be 1-64 characters of letters, digits, dots, underscores or hyphens - it is written into a Python string literal and returned verbatim by the /tag route."
  }
}
variable "app_greeting" {
  type        = string
  default     = "Hello Korea!"
  description = "Body the seeded application's root route returns, as the _monolithic template had it. Changing it and pushing is the shortest way to watch a blue/green deployment happen"

  validation {
    condition     = can(regex("^[^\"\\\\]{1,200}$", var.app_greeting))
    error_message = "app_greeting must be 1-200 characters and must not contain a double quote or a backslash - it is written straight into a Python string literal."
  }
}
variable "python_base_image" {
  type        = string
  default     = "python:3.13-slim"
  description = "Base image of the seeded Dockerfile, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]*:[A-Za-z0-9._-]+$", var.python_base_image))
    error_message = "python_base_image must be a tagged image reference (e.g. python:3.13-slim)."
  }
}
variable "wait_for_steady_state" {
  type        = bool
  default     = false
  description = "Whether apply blocks until the ECS service reaches a steady state. False because the workbench's own image-verification association already reports the failure that would otherwise hold this open for the full timeout"
}
# --- CodeDeploy -------------------------------------------------------------------------------------------
variable "code_deploy_application_name" {
  type        = string
  default     = "ecs-codedeploy-app"
  description = "Name of the CodeDeploy application, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._+=,@-]{1,100}$", var.code_deploy_application_name))
    error_message = "code_deploy_application_name must be 1-100 characters from the set CodeDeploy accepts."
  }
}
variable "code_deploy_deployment_group_name" {
  type        = string
  default     = "ecs-codedeploy-dg"
  description = "Name of the CodeDeploy deployment group, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._+=,@-]{1,100}$", var.code_deploy_deployment_group_name))
    error_message = "code_deploy_deployment_group_name must be 1-100 characters from the set CodeDeploy accepts."
  }
}
variable "deployment_config_name" {
  type        = string
  default     = "CodeDeployDefault.ECSAllAtOnce"
  description = "Deployment configuration controlling how fast traffic shifts, as the _monolithic template had it"

  validation {
    condition     = length(var.deployment_config_name) > 0
    error_message = "deployment_config_name must not be empty."
  }
}
variable "termination_wait_time_in_minutes" {
  type        = number
  default     = 0
  description = "How long the original task set keeps running after traffic has shifted, as the _monolithic template had it"

  validation {
    condition     = var.termination_wait_time_in_minutes >= 0 && var.termination_wait_time_in_minutes <= 2880
    error_message = "termination_wait_time_in_minutes must be between 0 and 2880."
  }
}
# --- GitHub and CodeBuild ---------------------------------------------------------------------------------
variable "git_hub_user" {
  type        = string
  description = "GitHub account that owns the repository the seed commit is pushed to. No default: it is the one value that cannot be guessed"

  validation {
    # No lookahead. Terraform's regex() is Go's RE2, which has no lookahead at all - and because the
    # expression is wrapped in can(), an unsupported construct is not reported as a bad pattern. regex()
    # errors, can() swallows the error and returns false, and the condition then rejects every value
    # including valid ones. This form expresses the same rule (no leading or trailing hyphen) with a
    # trailing character class instead.
    condition     = can(regex("^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?$", var.git_hub_user))
    error_message = "git_hub_user must be a GitHub account name: 1-39 characters of letters, digits and single hyphens, not starting or ending with a hyphen."
  }
}
variable "git_hub_token" {
  type        = string
  sensitive   = true
  description = "GitHub personal access token with repo and workflow scope. sensitive so plan, apply and terraform console do not print it - the _monolithic template declared this variable with no type constraint and no sensitive marker, so the token appeared in plan output and in any log that captured it. Pass it with TF_VAR_git_hub_token, and note that it still lands in state: treat this project's state file as a secret. The repository must already exist on GitHub - nothing here creates it, because the CloudFormation resource that did (AWS::CodeStar::GitHubRepository) has no provider equivalent"

  validation {
    condition     = can(regex("^(gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{22,})$", var.git_hub_token))
    error_message = "git_hub_token must look like a GitHub personal access token: ghp_/gho_/ghu_/ghs_/ghr_ followed by at least 36 characters, or github_pat_ followed by at least 22."
  }
}
variable "git_hub_repo" {
  type        = string
  default     = "ecs-repo"
  description = "Repository the seed commit is pushed to, as the _monolithic template had it. Also the directory on the workbench the files are assembled in"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{1,100}$", var.git_hub_repo))
    error_message = "git_hub_repo must be 1-100 characters of letters, digits, dots, underscores or hyphens."
  }
}
variable "git_hub_branch" {
  type        = string
  default     = "ecs-app"
  description = "Branch the seed commit is pushed to and the workflow triggers on, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[A-Za-z0-9._/-]{1,255}$", var.git_hub_branch))
    error_message = "git_hub_branch must be 1-255 characters of letters, digits, dots, underscores, slashes or hyphens."
  }
}
variable "git_hub_action" {
  type        = string
  default     = "ecs-cicd-action"
  description = "Name of the generated workflow, as the _monolithic template had it. The CodeBuild webhook filters on it with a WORKFLOW_NAME pattern, so one value reaches both the workflow file and the filter (rules.md B-5)"

  validation {
    condition     = can(regex("^[A-Za-z0-9 ._-]{1,100}$", var.git_hub_action))
    error_message = "git_hub_action must be 1-100 characters of letters, digits, spaces, dots, underscores or hyphens."
  }
}
variable "workflow_file_name" {
  type        = string
  default     = "codebuild.yaml"
  description = "File name the workflow is written to under .github/workflows, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+\\.ya?ml$", var.workflow_file_name))
    error_message = "workflow_file_name must end in .yml or .yaml - GitHub ignores any other file under .github/workflows."
  }
}
variable "code_build_project_name" {
  type        = string
  default     = "GitHubRunner"
  description = "Base name of the CodeBuild project, as the _monolithic template had it. A generated suffix is appended, because a CodeBuild project name is account-and-region unique and has no name_prefix equivalent"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,200}$", var.code_build_project_name))
    error_message = "code_build_project_name must be 1-201 characters of letters, digits, underscores or hyphens starting with a letter or digit, leaving room for the generated suffix inside CodeBuild's 255-character limit."
  }
}
variable "code_build_additional_policy_arns" {
  type        = list(string)
  default     = []
  description = "Extra managed policies on the CodeBuild role, on top of the scoped inline policy the runner needs. Empty by default: the _monolithic template attached AdministratorAccess to a role assumed by a build that runs whatever is on a GitHub branch, and that is not a workbench (rules.md A-5). Set it to [\"arn:aws:iam::aws:policy/AdministratorAccess\"] to get the original behaviour back"

  validation {
    condition     = alltrue([for arn in var.code_build_additional_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "code_build_additional_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "code_star_connection_name" {
  type        = string
  default     = "github-connection"
  description = "Name of the CodeStar connection, as the _monolithic template named it. Account-and-region unique and not suffixed, so a second copy of this project in one account collides here - which the original also did"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{1,32}$", var.code_star_connection_name))
    error_message = "code_star_connection_name must be 1-32 characters of letters, digits, underscores, dots or hyphens."
  }
}
variable "source_bucket_prefix" {
  type        = string
  default     = "github-runner-bucket-"
  description = "Prefix for the generated source bucket name, matching what the _monolithic template built from the stack uuid"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,37}$", var.source_bucket_prefix))
    error_message = "source_bucket_prefix must be 2-38 characters of lowercase letters, digits, dots and hyphens starting with a letter or digit."
  }
}
variable "force_destroy_source_bucket" {
  type        = bool
  default     = true
  description = "Whether terraform destroy may delete the source bucket with the uploaded zip still in it"
}
variable "name_suffix_byte_length" {
  type        = number
  default     = 4
  description = "Bytes of randomness behind the generated name suffix, rendered as twice that many hex characters. Four gives eight characters, against the four the _monolithic template sliced out of its stack uuid"

  validation {
    condition     = var.name_suffix_byte_length >= 2 && var.name_suffix_byte_length <= 16
    error_message = "name_suffix_byte_length must be between 2 and 16."
  }
}
# --- Bootstrap sequencing ---------------------------------------------------------------------------------
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the workbench where each stage drops its completion marker. Every association waits for the previous stage's marker with an until loop rather than trusting depends_on or a provider timeout (rules.md D-5)"

  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/'."
  }
}
variable "bootstrap_timeout_seconds" {
  type        = number
  default     = 1800
  description = "How long each bootstrap association may take. The first one waits for the workbench bootstrap - dnf update, the code-server download, docker - and then builds and pushes a container image, so it is the long one"

  validation {
    condition     = var.bootstrap_timeout_seconds >= 300
    error_message = "bootstrap_timeout_seconds must be at least 300. The first association waits for a bootstrap that runs dnf update and downloads code-server before it starts its own work, and a shorter timeout fails the apply on a stage that was still progressing."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 1800
  description = "How long the README association may take. It is last in the chain, so it waits for every stage before it"

  validation {
    condition     = var.readme_timeout_seconds >= 300
    error_message = "readme_timeout_seconds must be at least 300."
  }
}
variable "marker_wait_interval_seconds" {
  type        = number
  default     = 10
  description = "Seconds each until loop sleeps between checks for the previous stage's marker"

  validation {
    condition     = var.marker_wait_interval_seconds >= 1 && var.marker_wait_interval_seconds <= 60
    error_message = "marker_wait_interval_seconds must be between 1 and 60."
  }
}
