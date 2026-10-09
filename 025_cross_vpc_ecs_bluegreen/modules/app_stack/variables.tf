variable "stack_key" {
  type        = string
  description = "Short name of this stack - green or red. Every derived name, the container name, the log stream prefix and the two path patterns are built from it, so one key is what distinguishes the two instances of this module rather than a dozen separate name variables"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{0,15}$", var.stack_key))
    error_message = "stack_key must start with a lowercase letter and contain only lowercase letters and digits, 16 characters or fewer: it becomes part of a path pattern, a container name and a log stream prefix."
  }
}
variable "region" {
  type        = string
  description = "Region, used in the FireLens and awslogs options and in the CodeDeploy ARNs the pipeline policy is scoped to. Passed in rather than read with a data source, which a module carrying depends_on would defer to apply (rules.md B-6, D-6)"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must be an AWS region code (e.g. ap-northeast-2)."
  }
}
variable "account_id" {
  type        = string
  description = "Account ID, used to build the CodeDeploy ARNs the pipeline policy names"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}
variable "partition" {
  type        = string
  description = "ARN partition. Passed in rather than hardcoded aws, which the _monolithic template did in half its ARNs and read from data.aws_partition in the other half"

  validation {
    condition     = can(regex("^aws[a-z-]*$", var.partition))
    error_message = "partition must be an AWS partition name (e.g. aws, aws-cn, aws-us-gov)."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC both target groups belong to. The target type is ip and the tasks use awsvpc, so a target group in the wrong VPC accepts no registration"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Private subnets the service places tasks in"

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "subnet_ids must contain at least one subnet."
  }
  validation {
    condition     = alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "subnet_ids must contain valid subnet IDs (e.g. subnet-0123456789abcdef0)."
  }
}
variable "security_group_ids" {
  type        = list(string)
  description = "Security groups attached to each task's elastic network interface. The shared ECS service group, injected rather than looked up (rules.md B-6)"

  validation {
    condition     = length(var.security_group_ids) >= 1
    error_message = "security_group_ids must contain at least one group."
  }
  validation {
    condition     = alltrue([for id in var.security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "security_group_ids must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "cluster_name" {
  type        = string
  description = "ECS cluster the service runs in and the CodeDeploy deployment group targets"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "listener_arn" {
  type        = string
  description = "The application load balancer's HTTP listener. Both of this stack's rules attach to it and the deployment group names it as the production traffic route - so CodeDeploy rewrites rules on the same listener Terraform created them on, which is why the rules ignore changes to their action (rules.md E-8)"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:elasticloadbalancing:", var.listener_arn))
    error_message = "listener_arn must be an elbv2 listener ARN."
  }
}
variable "task_definition_family" {
  type        = string
  description = "Task definition family. Also the family field of the taskdef.json template every pipeline artefact carries, which is what keeps the revisions CodeDeploy registers in the same family as the one Terraform registered"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.task_definition_family))
    error_message = "task_definition_family must be 1-255 characters of letters, digits, underscores and hyphens."
  }
}
variable "service_name" {
  type        = string
  description = "ECS service name. Unique within the cluster, and named by the CodeDeploy deployment group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.service_name))
    error_message = "service_name must be 1-255 characters of letters, digits, underscores and hyphens."
  }
}
variable "container_name" {
  type        = string
  description = "Name of the application container. Named in three places that have to agree: the task definition, the service's load balancer block, and the LoadBalancerInfo section of the appspec.yaml the second SSM association writes. A mismatch is rejected by CodeDeploy at deployment time, not at apply"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.container_name))
    error_message = "container_name must be 1-255 characters of letters, digits, underscores and hyphens."
  }
}
variable "image_uri" {
  type        = string
  description = "Repository URL without a tag, from the ECR module. Injected rather than assembled here, so the build step, the task definition and the pipeline's imageDetail.json all name one repository (rules.md B-5)"

  validation {
    condition     = can(regex("^[0-9]{12}\\.dkr\\.ecr\\.", var.image_uri))
    error_message = "image_uri must be an ECR repository URL (e.g. 123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/green)."
  }
}
variable "image_tag" {
  type        = string
  description = "Tag the task definition starts on. The _monolithic template used v1.0.0 and had the build step push v1.0.1 as well, which is the tag the pipeline deploys - so the blue/green switch is visible as a version change"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{1,128}$", var.image_tag))
    error_message = "image_tag must be 1-128 characters of letters, digits, underscores, dots and hyphens."
  }
}
variable "container_port" {
  type        = number
  description = "Port the application listens on. Both stacks use the same one, which the duplicated _monolithic code made look like it might differ"

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port must be a valid TCP port."
  }
}
variable "task_cpu" {
  type        = string
  description = "Task-level CPU units. One of the genuine differences between the two stacks: 1024 for green, 512 for red. Required for Fargate, and a Fargate task whose CPU and memory are not one of the documented pairs is rejected at RegisterTaskDefinition"

  validation {
    condition     = contains(["256", "512", "1024", "2048", "4096", "8192", "16384"], var.task_cpu)
    error_message = "task_cpu must be one of the Fargate CPU values: 256, 512, 1024, 2048, 4096, 8192 or 16384."
  }
}
variable "task_memory" {
  type        = string
  description = "Task-level memory in MiB. The same for both stacks"

  validation {
    condition     = can(regex("^[0-9]+$", var.task_memory))
    error_message = "task_memory must be a whole number of MiB as a string."
  }
}
variable "cpu_architecture" {
  type        = string
  description = "CPU architecture of the runtime platform. X86_64 in the _monolithic template, which has to match the images the build step produces - an arm64 image on an X86_64 platform fails at task start with an exec format error"

  validation {
    condition     = contains(["X86_64", "ARM64"], var.cpu_architecture)
    error_message = "cpu_architecture must be X86_64 or ARM64."
  }
}
variable "launch_type" {
  type        = string
  description = "EC2 or FARGATE. The other genuine difference between the two stacks, and the one that requires_compatibilities and platform_version are derived from"

  validation {
    condition     = contains(["EC2", "FARGATE"], var.launch_type)
    error_message = "launch_type must be EC2 or FARGATE. EXTERNAL is not valid here: an ECS Anywhere service cannot use a load balancer or Availability Zone rebalancing."
  }
}
variable "platform_version" {
  type        = string
  default     = "LATEST"
  description = "Fargate platform version, ignored when launch_type is EC2 - ECS rejects it for an EC2 service, so the resource passes null in that case"

  validation {
    condition     = var.platform_version == "LATEST" || can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.platform_version))
    error_message = "platform_version must be LATEST or a three-part version (e.g. 1.4.0)."
  }
}
variable "availability_zone_rebalancing" {
  type        = string
  description = "Whether ECS redistributes tasks across zones as capacity changes. ENABLED in the _monolithic template for both stacks. Supported for Fargate and for EC2 capacity providers; the EC2 case rebalances only across instances that already exist, because ECS will not launch one to do it"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.availability_zone_rebalancing)
    error_message = "availability_zone_rebalancing must be ENABLED or DISABLED."
  }
}
variable "desired_count" {
  type        = number
  description = "Tasks the service runs. The same for both stacks. Each task takes an elastic network interface on a container instance for the EC2 stack, so this is bounded by the Auto Scaling group's size and by the instance type's interface limit"

  validation {
    condition     = var.desired_count >= 1
    error_message = "desired_count must be at least 1: a CodeDeploy blue/green deployment has nothing to replace at zero."
  }
}
variable "task_role_arn" {
  type        = string
  description = "Task role, shared between stacks. Used at runtime by the FireLens sidecar (rules.md B-6)"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/", var.task_role_arn))
    error_message = "task_role_arn must be an IAM role ARN."
  }
}
variable "execution_role_arn" {
  type        = string
  description = "Task execution role, shared between stacks. Used by the agent for the ECR pull, the secret injection and the log group creation"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/", var.execution_role_arn))
    error_message = "execution_role_arn must be an IAM role ARN."
  }
}
variable "task_definition_role_arns" {
  type        = list(string)
  description = "Roles a task definition registered by this pipeline may name, which is what the pipeline policy's iam:PassRole statement is scoped to. Both the task and the execution role. Unscoped, that statement is the ability to pass any role in the account (rules.md A-5)"

  validation {
    condition     = length(var.task_definition_role_arns) > 0
    error_message = "task_definition_role_arns must contain at least one ARN: an empty resource list makes IAM reject the policy with MalformedPolicyDocument."
  }
  validation {
    condition     = alltrue([for arn in var.task_definition_role_arns : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/", arn))])
    error_message = "task_definition_role_arns must contain IAM role ARNs."
  }
}
variable "secret_arn" {
  type        = string
  description = "The credential secret all three of this task definition's secret references select a key from"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:secretsmanager:", var.secret_arn))
    error_message = "secret_arn must be a Secrets Manager secret ARN."
  }
}
variable "log_group_name" {
  type        = string
  description = "CloudWatch Logs group the FireLens sidecar writes this stack's application output to. Also queried by name in the dashboard, so it is one value (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_./#-]{1,512}$", var.log_group_name))
    error_message = "log_group_name must be 1-512 characters of letters, digits and the set _./#- that CloudWatch Logs accepts."
  }
}
variable "log_retention_in_days" {
  type        = number
  description = "Retention on the application log group. The _monolithic template created no group, so there was none"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_in_days)
    error_message = "log_retention_in_days must be one of the retention periods CloudWatch Logs accepts."
  }
}
variable "log_exclude_pattern" {
  type        = string
  description = "Regular expression FireLens drops matching lines on. The _monolithic template used \"health\", which removes the container health check request that fires on every task every interval and would otherwise be most of the log"

  validation {
    condition     = length(var.log_exclude_pattern) > 0
    error_message = "log_exclude_pattern must not be empty: an empty pattern is not \"match nothing\", it matches every line, so the log group stays empty with nothing reporting why."
  }
}
variable "fluent_bit_image" {
  type        = string
  description = "Image for the FireLens sidecar. The AWS-maintained distribution, pinned by the caller"

  validation {
    condition     = length(var.fluent_bit_image) > 0
    error_message = "fluent_bit_image must not be empty."
  }
}
variable "fluent_bit_log_group_name" {
  type        = string
  description = "Log group the sidecar's own awslogs driver writes to. Shared between both stacks and deliberately not a Terraform resource - two instances of this module declaring the same group would fail the second apply with ResourceAlreadyExistsException, so awslogs-create-group makes the agent create it instead"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_./#-]{1,512}$", var.fluent_bit_log_group_name))
    error_message = "fluent_bit_log_group_name must be 1-512 characters of letters, digits and the set _./#- that CloudWatch Logs accepts."
  }
}
variable "target_group_blue_name" {
  type        = string
  description = "Name of the target group that is live first. CodeDeploy names both target groups by name rather than ARN, and a target group name is region-wide, so a second copy of this project collides here"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,32}$", var.target_group_blue_name))
    error_message = "target_group_blue_name must be 32 characters or fewer of letters, digits and hyphens."
  }
}
variable "target_group_green_name" {
  type        = string
  description = "Name of the replacement target group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,32}$", var.target_group_green_name))
    error_message = "target_group_green_name must be 32 characters or fewer of letters, digits and hyphens."
  }
  validation {
    condition     = var.target_group_green_name != var.target_group_blue_name
    error_message = "target_group_green_name must differ from target_group_blue_name: CodeDeploy needs two distinct target groups to shift traffic between, and elbv2 would reject the duplicate name anyway."
  }
}
variable "health_check_path" {
  type        = string
  description = "Path the target group health check and the container health check both request, and the path the health check listener rule matches"

  validation {
    condition     = can(regex("^/", var.health_check_path))
    error_message = "health_check_path must start with '/'."
  }
}
variable "health_check_interval" {
  type        = number
  description = "Seconds between target group health checks"

  validation {
    condition     = var.health_check_interval >= 5 && var.health_check_interval <= 300
    error_message = "health_check_interval must be between 5 and 300 seconds."
  }
}
variable "health_check_timeout" {
  type        = number
  description = "Seconds a target group health check may take before it counts as a failure"

  validation {
    condition     = var.health_check_timeout >= 2 && var.health_check_timeout <= 120
    error_message = "health_check_timeout must be between 2 and 120 seconds."
  }
  validation {
    condition     = var.health_check_timeout < var.health_check_interval
    error_message = "health_check_timeout must be smaller than health_check_interval: elbv2 rejects a timeout that is not shorter than the interval."
  }
}
variable "health_check_healthy_threshold" {
  type        = number
  description = "Consecutive successes before a target is in service"

  validation {
    condition     = var.health_check_healthy_threshold >= 2 && var.health_check_healthy_threshold <= 10
    error_message = "health_check_healthy_threshold must be between 2 and 10."
  }
}
variable "health_check_unhealthy_threshold" {
  type        = number
  description = "Consecutive failures before a target is out of service"

  validation {
    condition     = var.health_check_unhealthy_threshold >= 2 && var.health_check_unhealthy_threshold <= 10
    error_message = "health_check_unhealthy_threshold must be between 2 and 10."
  }
}
variable "health_check_matcher" {
  type        = string
  description = "HTTP status codes counted as healthy"

  validation {
    condition     = can(regex("^[0-9]{3}(-[0-9]{3})?(,[0-9]{3}(-[0-9]{3})?)*$", var.health_check_matcher))
    error_message = "health_check_matcher must be a status code, a range, or a comma separated list of either (e.g. 200 or 200-299)."
  }
}
variable "container_health_check_interval" {
  type        = number
  description = "Seconds between the container's own health check command"

  validation {
    condition     = var.container_health_check_interval >= 5 && var.container_health_check_interval <= 300
    error_message = "container_health_check_interval must be between 5 and 300 seconds."
  }
}
variable "container_health_check_timeout" {
  type        = number
  description = "Seconds the container health check command may take"

  validation {
    condition     = var.container_health_check_timeout >= 2 && var.container_health_check_timeout <= 60
    error_message = "container_health_check_timeout must be between 2 and 60 seconds."
  }
}
variable "container_health_check_retries" {
  type        = number
  description = "Consecutive failures before the container is unhealthy and ECS replaces the task"

  validation {
    condition     = var.container_health_check_retries >= 1 && var.container_health_check_retries <= 10
    error_message = "container_health_check_retries must be between 1 and 10."
  }
}
variable "container_health_check_start_period" {
  type        = number
  description = "Grace seconds before a failed container health check counts. The _monolithic template used 5, which is short - a container still starting is replaced rather than waited for, and the replacement starts the same clock"

  validation {
    condition     = var.container_health_check_start_period >= 0 && var.container_health_check_start_period <= 300
    error_message = "container_health_check_start_period must be between 0 and 300 seconds."
  }
}
variable "deregistration_delay" {
  type        = number
  description = "Seconds each target group waits before completing a deregistration. Paid twice on every blue/green switch - once for the task set being drained and once again on a rollback"

  validation {
    condition     = var.deregistration_delay >= 0 && var.deregistration_delay <= 3600
    error_message = "deregistration_delay must be between 0 and 3600 seconds."
  }
}
variable "listener_rule_priority" {
  type        = number
  description = "Priority of the path rule. One of the genuine differences between the two stacks: 1 for green, 2 for red. A duplicate priority on one listener is rejected at apply, with the message naming only the rule that arrived second"

  validation {
    condition     = var.listener_rule_priority >= 1 && var.listener_rule_priority <= 50000
    error_message = "listener_rule_priority must be between 1 and 50000."
  }
}
variable "health_check_rule_priority" {
  type        = number
  description = "Priority of the health check rule - 3 for green, 4 for red in the _monolithic template. Both rules match the same path, so only the lower priority one is ever reached; see the resource in main.tf"

  validation {
    condition     = var.health_check_rule_priority >= 1 && var.health_check_rule_priority <= 50000
    error_message = "health_check_rule_priority must be between 1 and 50000."
  }
  validation {
    condition     = var.health_check_rule_priority != var.listener_rule_priority
    error_message = "health_check_rule_priority must differ from listener_rule_priority: elbv2 rejects two rules with the same priority on one listener."
  }
}
variable "code_deploy_application_name" {
  type        = string
  description = "CodeDeploy application name, account and region wide"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._+=,@-]{1,100}$", var.code_deploy_application_name))
    error_message = "code_deploy_application_name must be 1-100 characters from the set CodeDeploy accepts."
  }
}
variable "code_deploy_deployment_group_name" {
  type        = string
  description = "CodeDeploy deployment group name. Also assembled into the deployment group ARN the pipeline policy is scoped to, so it is read twice from this one variable rather than restated (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._+=,@-]{1,100}$", var.code_deploy_deployment_group_name))
    error_message = "code_deploy_deployment_group_name must be 1-100 characters from the set CodeDeploy accepts."
  }
}
variable "deployment_config_name" {
  type        = string
  description = "Deployment configuration. The _monolithic template used CodeDeployDefault.ECSAllAtOnce, which shifts all traffic in one step once the replacement task set is healthy - a canary or linear configuration would shift it in stages and make the demo longer and more interesting"

  validation {
    condition     = can(regex("^(CodeDeployDefault\\.ECS(AllAtOnce|Canary10Percent(5|15)Minutes|Linear10PercentEvery(1|3)Minutes)|[a-zA-Z0-9._+=,@-]{1,100})$", var.deployment_config_name))
    error_message = "deployment_config_name must be an ECS deployment configuration name. The AWS-provided ones are CodeDeployDefault.ECSAllAtOnce, ECSCanary10Percent5Minutes, ECSCanary10Percent15Minutes, ECSLinear10PercentEvery1Minutes and ECSLinear10PercentEvery3Minutes."
  }
}
variable "deployment_ready_action_on_timeout" {
  type        = string
  description = "What CodeDeploy does when the replacement task set is ready. CONTINUE_DEPLOYMENT shifts traffic straight away, as the _monolithic template had it; STOP_DEPLOYMENT waits for a manual approval"

  validation {
    condition     = contains(["CONTINUE_DEPLOYMENT", "STOP_DEPLOYMENT"], var.deployment_ready_action_on_timeout)
    error_message = "deployment_ready_action_on_timeout must be CONTINUE_DEPLOYMENT or STOP_DEPLOYMENT."
  }
}
variable "termination_wait_time_in_minutes" {
  type        = number
  description = "Minutes the original task set is kept after traffic has shifted. Zero in the _monolithic template, which removes the window in which a rollback is instant"

  validation {
    condition     = var.termination_wait_time_in_minutes >= 0 && var.termination_wait_time_in_minutes <= 2880
    error_message = "termination_wait_time_in_minutes must be between 0 and 2880 (48 hours)."
  }
}
variable "auto_rollback_events" {
  type        = list(string)
  description = "Events that trigger an automatic rollback"

  validation {
    condition     = length(var.auto_rollback_events) > 0
    error_message = "auto_rollback_events must contain at least one event: an enabled rollback configuration with no events is rejected by CodeDeploy."
  }
  validation {
    condition     = alltrue([for event in var.auto_rollback_events : contains(["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM", "DEPLOYMENT_STOP_ON_REQUEST"], event)])
    error_message = "auto_rollback_events must contain only DEPLOYMENT_FAILURE, DEPLOYMENT_STOP_ON_ALARM or DEPLOYMENT_STOP_ON_REQUEST."
  }
}
variable "code_deploy_role_name_prefix" {
  type        = string
  description = "Prefix for this stack's generated CodeDeploy service role name. Per stack rather than shared, which is what lets the other delivery policies name single resources - see main.tf (rules.md A-5)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,38}$", var.code_deploy_role_name_prefix))
    error_message = "code_deploy_role_name_prefix must be 1-38 characters from the set IAM accepts in a role name, leaving room for the generated suffix inside the 64 character limit."
  }
}
variable "code_deploy_policy_arns" {
  type        = list(string)
  description = "Managed policy ARNs on the CodeDeploy role. AWSCodeDeployRoleForECS, kept as the _monolithic template attached it: it is the AWS service-role policy for ECS blue/green and is already scoped (rules.md A-5)"

  validation {
    condition     = length(var.code_deploy_policy_arns) > 0
    error_message = "code_deploy_policy_arns must contain at least one policy: CodeDeploy validates the role at CreateDeploymentGroup and rejects one that cannot act on an ECS service."
  }
  validation {
    condition     = alltrue([for arn in var.code_deploy_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "code_deploy_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "code_pipeline_role_name_prefix" {
  type        = string
  description = "Prefix for this stack's generated CodePipeline role name"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,38}$", var.code_pipeline_role_name_prefix))
    error_message = "code_pipeline_role_name_prefix must be 1-38 characters from the set IAM accepts in a role name, leaving room for the generated suffix inside the 64 character limit."
  }
}
variable "event_rule_role_name_prefix" {
  type        = string
  description = "Prefix for this stack's generated EventBridge role name"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,38}$", var.event_rule_role_name_prefix))
    error_message = "event_rule_role_name_prefix must be 1-38 characters from the set IAM accepts in a role name, leaving room for the generated suffix inside the 64 character limit."
  }
}
variable "pipeline_name" {
  type        = string
  description = "CodePipeline name, account and region wide"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]{1,100}$", var.pipeline_name))
    error_message = "pipeline_name must be 1-100 characters of letters, digits, dots, underscores and hyphens."
  }
}
variable "execution_mode" {
  type        = string
  description = "How CodePipeline handles a second execution while one is running. QUEUED in the _monolithic template, which waits rather than cancelling the blue/green switch in flight"

  validation {
    condition     = contains(["QUEUED", "SUPERSEDED", "PARALLEL"], var.execution_mode)
    error_message = "execution_mode must be QUEUED, SUPERSEDED or PARALLEL."
  }
}
variable "source_object_key" {
  type        = string
  description = "Object key the pipeline's source action reads and the EventBridge rule matches on. Also the name the helper script uploads, and the key the CloudTrail data event selector names - four places from one value (rules.md B-5)"

  validation {
    condition     = can(regex("^[^/][^\\s]*$", var.source_object_key))
    error_message = "source_object_key must be an object key without a leading slash (e.g. artifact.zip)."
  }
}
variable "task_definition_template_path" {
  type        = string
  description = "Path inside the artefact to the task definition template. Both artefacts carry a file with this name: the seed this module uploads, and the one the second SSM association assembles from the task_definition_template output"

  validation {
    condition     = can(regex("^[^/][^\\s]*$", var.task_definition_template_path))
    error_message = "task_definition_template_path must be a path inside the artefact without a leading slash (e.g. taskdef.json)."
  }
}
variable "app_spec_template_path" {
  type        = string
  description = "Path inside the artefact to the CodeDeploy appspec. Both artefacts carry a file with this name, built from the app_spec_template output"

  validation {
    condition     = can(regex("^[^/][^\\s]*$", var.app_spec_template_path))
    error_message = "app_spec_template_path must be a path inside the artefact without a leading slash (e.g. appspec.yaml)."
  }
}
variable "image_detail_file_name" {
  type        = string
  description = "Name of the image detail file inside the artefact. CodeDeployToECS takes the image URI from it and substitutes it for the placeholder in the task definition template. Taken here because the seed artefact this module uploads carries one"

  validation {
    condition     = can(regex("^[^/][^\\s]*$", var.image_detail_file_name))
    error_message = "image_detail_file_name must be a path inside the artefact without a leading slash (e.g. imageDetail.json)."
  }
}
variable "image_placeholder_name" {
  type        = string
  description = "Name of the image placeholder CodePipeline substitutes in the task definition template. The template file contains it wrapped in angle brackets - <IMAGE1_NAME> - and this value is the name without them"

  validation {
    condition     = can(regex("^[A-Z0-9_]+$", var.image_placeholder_name))
    error_message = "image_placeholder_name must be uppercase letters, digits and underscores (e.g. IMAGE1_NAME)."
  }
}
variable "source_bucket_prefix" {
  type        = string
  description = "Prefix for this stack's generated source bucket name. A prefix rather than the template's name built from a RandomNumber parameter, which made a variable with no default mandatory just to get a globally unique bucket name"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,40}$", var.source_bucket_prefix))
    error_message = "source_bucket_prefix must be 2-41 characters of lowercase letters, digits, dots and hyphens, leaving room for the generated suffix inside the 63 character bucket name limit."
  }
}
variable "artifact_store_bucket_prefix" {
  type        = string
  description = "Prefix for this stack's generated pipeline artifact store bucket name. The _monolithic template declared this bucket with no arguments at all, so the provider generated the whole name"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,40}$", var.artifact_store_bucket_prefix))
    error_message = "artifact_store_bucket_prefix must be 2-41 characters of lowercase letters, digits, dots and hyphens, leaving room for the generated suffix inside the 63 character bucket name limit."
  }
}
variable "force_destroy" {
  type        = bool
  description = "Whether terraform destroy empties both buckets before deleting them. True here: pipeline runs leave objects and object versions behind, and S3 refuses to delete a non-empty bucket - so a destroy otherwise stops with BucketNotEmpty. This deletes every version, so it is irreversible"
}
variable "event_rule_name" {
  type        = string
  description = "EventBridge rule name, region wide within the event bus"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]{1,64}$", var.event_rule_name))
    error_message = "event_rule_name must be 1-64 characters of letters, digits, dots, underscores and hyphens."
  }
}
variable "event_rule_description" {
  type        = string
  description = "Description of the EventBridge rule. The _monolithic template carried the Korean text the CodePipeline console writes when it creates this rule itself, which is a useful hint that the rule is managed here instead"

  validation {
    condition     = length(var.event_rule_description) > 0 && length(var.event_rule_description) <= 512
    error_message = "event_rule_description must be between 1 and 512 characters."
  }
}
