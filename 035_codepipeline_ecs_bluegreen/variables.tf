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
  default     = "stem"
  description = <<-DESC
    Prefix for every name in this project, replacing the _monolithic template's stack_name and the
    ResourceMap of literals it fed.

    "stem" is not arbitrary: it is the prefix those literals already shared, so the default reproduces the
    original names exactly - stem-vpc, stem-pub, stem-priv, stem-igw, stem-natgw, stem-bastion, stem-alb,
    stem-tg1, stem-tg2, stem-ecr, stem-cluster, stem-svc, stem-td, stem-ecs-sg, stem-pipeline, stem-build,
    stem-app and stem-dg. The security groups and the trail are prefixed where the template left them
    bare (alb-sg, bastion-sg, asg-sg, codepipeline-source-trail), because those namespaces are account-wide
    and the unprefixed names collided with the other projects in this repository.

    Changing it renames everything in one move, which is what makes a second copy in one account possible.
  DESC

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,19}$", var.project_name))
    error_message = "project_name must be 1-20 characters of lowercase letters, digits and hyphens, starting with a letter or digit. The cap leaves room inside the tightest derived limit - a target group name is capped at 32 characters and this prefix carries a \"-tg1\" suffix."
  }
}
# --- Network ----------------------------------------------------------------------------------------------
variable "vpc_cidr_block" {
  type        = string
  default     = "10.10.0.0/16"
  description = "CIDR block for the VPC, as the _monolithic template's ResourceMap had it"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.10.0.0/16)."
  }
}
variable "subnet_newbits" {
  type        = number
  default     = 8
  description = "Bits added to the VPC prefix length to size each subnet. Eight against a /16 gives the four /24s the _monolithic template carved with cidrsubnet, in the same order: public a, public b, private a, private b"

  validation {
    condition     = var.subnet_newbits >= 1 && var.subnet_newbits <= 16
    error_message = "subnet_newbits must be between 1 and 16. Four subnets have to fit, so the VPC prefix plus this value must leave at least two host bits."
  }
}
variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "b"]
  description = "The two AZ letters each subnet pair is placed in, as the _monolithic template used them. Two is also the floor: an internet-facing ALB is rejected with subnets in fewer than two zones"

  validation {
    condition     = length(var.availability_zone_suffixes) == 2
    error_message = "availability_zone_suffixes must contain exactly two entries. The network module declares one named subnet per zone rather than generating them, and an internet-facing ALB needs at least two zones."
  }

  validation {
    condition     = alltrue([for suffix in var.availability_zone_suffixes : can(regex("^[a-z]$", suffix))])
    error_message = "availability_zone_suffixes entries must each be a single lowercase letter (e.g. a), which is appended to the region name to form the zone."
  }

  validation {
    condition     = var.availability_zone_suffixes[0] != var.availability_zone_suffixes[1]
    error_message = "availability_zone_suffixes entries must differ, because an ALB needs subnets in two different zones."
  }
}
# --- Key pair ---------------------------------------------------------------------------------------------
variable "key_rsa_bits" {
  type        = number
  default     = 4096
  description = "Size of the generated RSA key, as the _monolithic template had it"

  validation {
    condition     = contains([2048, 3072, 4096], var.key_rsa_bits)
    error_message = "key_rsa_bits must be 2048, 3072 or 4096."
  }
}
# --- Container image --------------------------------------------------------------------------------------
variable "seed_image_tag" {
  type        = string
  default     = "prototype"
  description = "Tag the builder pushes and the first task definition pulls, as the _monolithic template had it. Every revision after this one is tagged by CodeBuild and is not a Terraform resource at all"

  validation {
    condition     = can(regex("^[A-Za-z0-9_][A-Za-z0-9._-]{0,127}$", var.seed_image_tag))
    error_message = "seed_image_tag must be a valid container image tag."
  }
}
variable "ecr_force_delete" {
  type        = bool
  default     = true
  description = "Whether terraform destroy deletes the repository with images still in it. True, and necessary rather than convenient: the images are pushed by the builder and by CodeBuild, so Terraform does not know about any of them and a destroy would otherwise stop at RepositoryNotEmptyException"
}
variable "ecr_scan_on_push" {
  type        = bool
  default     = false
  description = "Whether ECR runs a basic vulnerability scan on each push. False, which is what the _monolithic template got by not configuring it"
}
variable "go_base_image" {
  type        = string
  default     = "golang:1.16"
  description = "Base image of the generated Dockerfile, as the _monolithic template specified it. Reproduced rather than modernised, but worth knowing it is years out of support - and that both the builder and CodeBuild pull it from Docker Hub, which rate-limits anonymous pulls"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]*:[A-Za-z0-9._-]+$", var.go_base_image))
    error_message = "go_base_image must be a tagged image reference (e.g. golang:1.16)."
  }
}
# --- The application the builder writes -------------------------------------------------------------------
variable "container_port" {
  type        = number
  default     = 80
  description = "Port the container listens on. One value for the port mapping, both target groups and their health checks, the ALB's egress rule and the tasks' ingress rule - with awsvpc the load balancer reaches the task's own interface, so a separate target port cannot exist (rules.md B-5)"

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port must be a valid TCP port."
  }
}
variable "health_check_path" {
  type        = string
  default     = "/health"
  description = "Path the target groups request and the generated application answers, as the _monolithic template had it. Also handed to CodeBuild, so the revisions it registers answer the same path"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must start with '/'."
  }
}
variable "health_response_body" {
  type        = string
  default     = "OK"
  description = "Body the health route returns, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[^\"\\\\]{1,200}$", var.health_response_body))
    error_message = "health_response_body must be 1-200 characters and must not contain a double quote or a backslash - it is written straight into a Go string literal."
  }
}
variable "dummy_path" {
  type        = string
  default     = "/v1/dummy"
  description = "Path the demo route is served on, as the _monolithic template had it. This is the URL the blue/green cutover is watched on"

  validation {
    condition     = startswith(var.dummy_path, "/")
    error_message = "dummy_path must start with '/'."
  }
}
variable "dummy_response_body" {
  type        = string
  default     = "BLUE"
  description = "Body the demo route returns in the seed image, as the _monolithic template had it. Changing it in the uploaded archive and re-running the pipeline is how the deployment is observed from outside"

  validation {
    condition     = can(regex("^[^\"\\\\]{1,200}$", var.dummy_response_body))
    error_message = "dummy_response_body must be 1-200 characters and must not contain a double quote or a backslash - it is written straight into a Go string literal."
  }
}
# --- Builder instance -------------------------------------------------------------------------------------
variable "bastion_ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "SSM parameter path resolved to the builder's AMI, as the _monolithic template's AmazonLinux2023AmiId parameter had it"

  validation {
    condition     = can(regex("^/", var.bastion_ami_ssm_parameter_name))
    error_message = "bastion_ami_ssm_parameter_name must be an absolute SSM parameter path starting with '/'."
  }
}
variable "bastion_instance_type" {
  type        = string
  default     = "t3.small"
  description = "Instance type for the builder, as the _monolithic template's ResourceMap had it. It builds one small Go image once"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.bastion_instance_type))
    error_message = "bastion_instance_type must be a valid EC2 instance type (e.g. t3.small)."
  }
}
variable "bastion_root_volume_size" {
  type        = number
  default     = 30
  description = "Root volume size in GiB for the builder. Larger than the AL2023 default of 8 GiB the _monolithic template took, because the golang base image and the build layers land on this disk"

  validation {
    condition     = var.bastion_root_volume_size >= 8
    error_message = "bastion_root_volume_size must be at least 8 GiB, the size of the AL2023 root snapshot."
  }
}
variable "bastion_associate_public_ip_address" {
  type        = bool
  default     = true
  description = "Whether the builder gets a public address, as the _monolithic template had it. Load-bearing: it sits in a public subnet with no NAT gateway of its own, so this is its only route to Docker Hub, ECR, S3 and SSM"
}
variable "bastion_ssh_ingress_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "Sources allowed to reach SSH on the builder, as the _monolithic template had it. Nothing in this project needs inbound SSH - the work is done by userdata and read back through SSM - so this can be narrowed to [] without breaking the demo"

  validation {
    condition     = alltrue([for cidr in var.bastion_ssh_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "bastion_ssh_ingress_cidr_blocks must contain valid IPv4 CIDR blocks (e.g. 203.0.113.0/24)."
  }
}
# --- Load balancer ----------------------------------------------------------------------------------------
variable "load_balancer_internal" {
  type        = bool
  default     = false
  description = "Whether the ALB is internal. False as the _monolithic template had it, and it has to agree with the subnets the module is given: an internet-facing scheme needs public subnets"
}
variable "listener_port" {
  type        = number
  default     = 80
  description = "Port the production listener accepts traffic on, as the _monolithic template had it. This is the listener CodeDeploy rewrites on every deployment"

  validation {
    condition     = var.listener_port > 0 && var.listener_port <= 65535
    error_message = "listener_port must be a valid TCP port."
  }
}
variable "load_balancer_idle_timeout" {
  type        = number
  default     = 60
  description = "Seconds the ALB holds an idle connection open, as the _monolithic template had it"

  validation {
    condition     = var.load_balancer_idle_timeout >= 1 && var.load_balancer_idle_timeout <= 4000
    error_message = "load_balancer_idle_timeout must be between 1 and 4000 seconds."
  }
}
variable "load_balancer_ingress_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "Sources allowed to reach the listener, as the _monolithic template had it. This is the public entry point of the demo"

  validation {
    condition     = length(var.load_balancer_ingress_cidr_blocks) > 0
    error_message = "load_balancer_ingress_cidr_blocks must contain at least one CIDR block, otherwise the ALB answers nobody."
  }

  validation {
    condition     = alltrue([for cidr in var.load_balancer_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "load_balancer_ingress_cidr_blocks must contain valid IPv4 CIDR blocks (e.g. 203.0.113.0/24)."
  }
}
variable "target_group_health_check_interval" {
  type        = number
  default     = 10
  description = "Seconds between health checks on both target groups, as the _monolithic template had it"

  validation {
    condition     = var.target_group_health_check_interval >= 5 && var.target_group_health_check_interval <= 300
    error_message = "target_group_health_check_interval must be between 5 and 300 seconds."
  }
}
variable "target_group_health_check_timeout" {
  type        = number
  default     = 5
  description = "Seconds a health check may take before it counts as failed, as the _monolithic template had it"

  validation {
    condition     = var.target_group_health_check_timeout >= 2 && var.target_group_health_check_timeout <= 120
    error_message = "target_group_health_check_timeout must be between 2 and 120 seconds."
  }

  validation {
    # A constraint about the pair rather than either value, so it is written as a cross-variable condition
    # (Terraform 1.9, rules.md B-1). elbv2 rejects a timeout that is not shorter than the interval.
    condition     = var.target_group_health_check_timeout < var.target_group_health_check_interval
    error_message = "target_group_health_check_timeout must be shorter than target_group_health_check_interval. elbv2 rejects CreateTargetGroup otherwise, and the failure arrives at apply."
  }
}
variable "target_group_health_check_healthy_threshold" {
  type        = number
  default     = 2
  description = "Consecutive successes before a target is considered healthy, as the _monolithic template had it"

  validation {
    condition     = var.target_group_health_check_healthy_threshold >= 2 && var.target_group_health_check_healthy_threshold <= 10
    error_message = "target_group_health_check_healthy_threshold must be between 2 and 10."
  }
}
variable "target_group_health_check_unhealthy_threshold" {
  type        = number
  default     = 4
  description = "Consecutive failures before a target is considered unhealthy, as the _monolithic template had it"

  validation {
    condition     = var.target_group_health_check_unhealthy_threshold >= 2 && var.target_group_health_check_unhealthy_threshold <= 10
    error_message = "target_group_health_check_unhealthy_threshold must be between 2 and 10."
  }
}
variable "target_group_health_check_matcher" {
  type        = string
  default     = "200"
  description = "HTTP status codes counted as a passing health check, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[0-9]{3}(-[0-9]{3})?(,[0-9]{3}(-[0-9]{3})?)*$", var.target_group_health_check_matcher))
    error_message = "target_group_health_check_matcher must be a status code, a range, or a comma-separated list of either (e.g. 200, 200-299, 200,204)."
  }
}
variable "create_user_agent_rule" {
  type        = bool
  default     = true
  description = "Whether the listener carries the user-agent matching rule the _monolithic template declared alongside the default action. It forwards to the same target group the default action does, so it changes no routing - it is there to show a listener rule. CodeDeploy rewrites its target group on every deployment just as it does the default action's, which is why the module ignores changes to its action"
}
variable "user_agent_rule_priority" {
  type        = number
  default     = 1
  description = "Priority of that rule, as the _monolithic template had it"

  validation {
    condition     = var.user_agent_rule_priority >= 1 && var.user_agent_rule_priority <= 50000
    error_message = "user_agent_rule_priority must be between 1 and 50000."
  }
}
variable "user_agent_rule_values" {
  type        = list(string)
  default     = ["Mozilla"]
  description = "User-agent values the rule matches, as the _monolithic template had it"

  validation {
    condition     = length(var.user_agent_rule_values) > 0
    error_message = "user_agent_rule_values must contain at least one value, otherwise the rule matches nothing and elbv2 rejects it."
  }
}
# --- Cluster and capacity ---------------------------------------------------------------------------------
variable "container_insights" {
  type        = string
  default     = "disabled"
  description = "Container Insights setting on the cluster. The _monolithic template set this explicitly, and \"disabled\" is the value it chose - stating it means the cluster behaves the same whatever the account default is"

  validation {
    condition     = contains(["enabled", "disabled", "enhanced"], var.container_insights)
    error_message = "container_insights must be enabled, disabled or enhanced. \"enhanced\" bills per observed task rather than being free like \"enabled\"."
  }
}
variable "execute_command_logging" {
  type        = string
  default     = "DEFAULT"
  description = "Where ECS Exec sessions are logged. DEFAULT, which is what the _monolithic template got by not configuring an execute_command_configuration at all"

  validation {
    condition     = contains(["NONE", "DEFAULT", "OVERRIDE"], var.execute_command_logging)
    error_message = "execute_command_logging must be NONE, DEFAULT or OVERRIDE. OVERRIDE additionally requires a log group or an S3 bucket, which this module does not declare."
  }
}
variable "container_instance_ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
  description = "SSM parameter path resolved to the ECS-optimized AMI, as the _monolithic template's EcsAmiId parameter had it. The ECS agent is preinstalled on it, which is why the launch template's userdata only has to write /etc/ecs/ecs.config"

  validation {
    condition     = can(regex("^/", var.container_instance_ami_ssm_parameter_name))
    error_message = "container_instance_ami_ssm_parameter_name must be an absolute SSM parameter path starting with '/'."
  }
}
variable "container_instance_types" {
  type        = list(string)
  default     = ["t3.micro"]
  description = "Instance types the Auto Scaling group may launch, as the _monolithic template had it. A list because the group uses a mixed instances policy; one entry reproduces the original"

  validation {
    condition     = length(var.container_instance_types) > 0
    error_message = "container_instance_types must contain at least one instance type."
  }

  validation {
    condition     = alltrue([for t in var.container_instance_types : can(regex("^[a-z0-9]+\\.[a-z0-9]+$", t))])
    error_message = "container_instance_types must contain valid EC2 instance types (e.g. t3.micro)."
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
  default     = 8
  description = "Maximum number of container instances, as the _monolithic template had it. The headroom matters here: a blue/green deployment runs the replacement task set alongside the original, so the cluster briefly needs capacity for twice the desired count"

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
  default     = 2
  description = "Starting number of container instances, as the _monolithic template had it. A starting point only - ECS managed scaling owns the field afterwards, which is why the Auto Scaling group stops tracking it"

  validation {
    condition     = var.container_instance_desired_capacity >= var.container_instance_min_size && var.container_instance_desired_capacity <= var.container_instance_max_size
    error_message = "container_instance_desired_capacity must be between container_instance_min_size and container_instance_max_size."
  }
}
variable "container_instance_default_cooldown" {
  type        = number
  default     = 0
  description = "Seconds the Auto Scaling group waits between its own scaling activities, as the _monolithic template had it. Zero because ECS managed scaling drives this group and a cooldown would delay the capacity a pending task set is waiting for"

  validation {
    condition     = var.container_instance_default_cooldown >= 0
    error_message = "container_instance_default_cooldown must be zero or greater."
  }
}
variable "container_instance_on_demand_base_capacity" {
  type        = number
  default     = 0
  description = "Instances filled with on-demand capacity before the percentage split applies, as the _monolithic template had it. Zero means every instance follows the percentage below"

  validation {
    condition     = var.container_instance_on_demand_base_capacity >= 0
    error_message = "container_instance_on_demand_base_capacity must be zero or greater."
  }
}
variable "container_instance_on_demand_percentage" {
  type        = number
  default     = 0
  description = "Percentage of capacity above the base that is on-demand, as the _monolithic template had it. Zero means the whole group is spot - cheap, and the reason a container instance can disappear mid-demo with the task on it rescheduled elsewhere"

  validation {
    condition     = var.container_instance_on_demand_percentage >= 0 && var.container_instance_on_demand_percentage <= 100
    error_message = "container_instance_on_demand_percentage must be between 0 and 100."
  }
}
variable "managed_scaling_target_capacity" {
  type        = number
  default     = 100
  description = "Target utilisation ECS managed scaling aims the group at, as the _monolithic template had it. 100 keeps no spare instance running, so a cutover waits for a new instance rather than finding one idle"

  validation {
    condition     = var.managed_scaling_target_capacity >= 1 && var.managed_scaling_target_capacity <= 100
    error_message = "managed_scaling_target_capacity must be between 1 and 100."
  }
}
variable "managed_scaling_instance_warmup_period" {
  type        = number
  default     = 60
  description = "Seconds ECS waits before counting a new instance towards capacity, as the _monolithic template had it"

  validation {
    condition     = var.managed_scaling_instance_warmup_period >= 0 && var.managed_scaling_instance_warmup_period <= 10000
    error_message = "managed_scaling_instance_warmup_period must be between 0 and 10000 seconds."
  }
}
# --- Service and task -------------------------------------------------------------------------------------
variable "container_name" {
  type        = string
  default     = "golang-app"
  description = "Name of the container, as the _monolithic template had it. The service's load_balancer block, the appspec CodeBuild generates and the ALB's target registration all name it, so it is one value in four places (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.container_name))
    error_message = "container_name must start with a letter or digit and contain only letters, digits, underscores and hyphens."
  }
}
variable "task_cpu" {
  type        = number
  default     = 256
  description = "Task-level CPU units, as the _monolithic template had it. Also handed to CodeBuild so the revisions it registers are sized the same"

  validation {
    condition     = var.task_cpu >= 128
    error_message = "task_cpu must be at least 128 CPU units."
  }
}
variable "task_memory" {
  type        = number
  default     = 512
  description = "Task-level memory in MiB, as the _monolithic template had it. Also handed to CodeBuild, and it has to fit the instance type: two of these plus the agent is already most of a t3.micro, which is what makes a cutover wait for a second instance"

  validation {
    condition     = var.task_memory >= 128
    error_message = "task_memory must be at least 128 MiB."
  }
}
variable "service_desired_count" {
  type        = number
  default     = 2
  description = "Number of tasks the service keeps running, as the _monolithic template had it. A blue/green cutover briefly needs capacity for twice this, which is what container_instance_max_size leaves room for"

  validation {
    condition     = var.service_desired_count >= 0
    error_message = "service_desired_count must be zero or greater."
  }
}
variable "task_additional_ingress_ports" {
  type        = map(number)
  default     = { https = 443 }
  description = "Extra ports opened on the tasks' security group from the load balancer, keyed by a label that appears in each rule's description. The _monolithic template opened 443 alongside the container port; nothing in the demo serves TLS, so this reproduces the original rather than being needed"

  validation {
    condition     = alltrue([for port in values(var.task_additional_ingress_ports) : port > 0 && port <= 65535])
    error_message = "task_additional_ingress_ports values must be valid TCP ports."
  }

  validation {
    condition     = alltrue([for label in keys(var.task_additional_ingress_ports) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "task_additional_ingress_ports keys are labels used in the rule descriptions and resource addresses, so each must be letters, digits, dots, underscores or hyphens - an apostrophe is rejected by EC2 outright (rules.md F-1)."
  }
}
variable "log_retention_in_days" {
  type        = number
  default     = 14
  description = "Days CloudWatch keeps the container log events. The _monolithic template created the group with no retention, so events were kept forever; this is a change, and it is set rather than left open because the group is written to by every pipeline run"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_in_days)
    error_message = "log_retention_in_days must be a value CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, ...)."
  }
}
# --- CodeDeploy -------------------------------------------------------------------------------------------
variable "deployment_config_name" {
  type        = string
  default     = "CodeDeployDefault.ECSAllAtOnce"
  description = "How fast traffic shifts to the replacement task set, as the _monolithic template had it. All-at-once makes the cutover a single observable moment, which is what the dummy route demonstrates"

  validation {
    condition     = length(var.deployment_config_name) > 0
    error_message = "deployment_config_name must not be empty."
  }
}
variable "deployment_ready_action_on_timeout" {
  type        = string
  default     = "CONTINUE_DEPLOYMENT"
  description = "What happens once the replacement task set is healthy, as the _monolithic template had it. CONTINUE_DEPLOYMENT shifts traffic without an approval step; STOP_DEPLOYMENT parks the deployment waiting for a person, which is the production setting and the wrong one for a demo that then shows nothing"

  validation {
    condition     = contains(["CONTINUE_DEPLOYMENT", "STOP_DEPLOYMENT"], var.deployment_ready_action_on_timeout)
    error_message = "deployment_ready_action_on_timeout must be CONTINUE_DEPLOYMENT or STOP_DEPLOYMENT."
  }
}
variable "termination_wait_time_in_minutes" {
  type        = number
  default     = 0
  description = "How long the original task set keeps running after traffic has shifted, as the _monolithic template had it. Zero means there is no window in which a rollback is instant, and it is also what keeps the container instances from holding two task sets for longer than the cutover itself"

  validation {
    condition     = var.termination_wait_time_in_minutes >= 0 && var.termination_wait_time_in_minutes <= 2880
    error_message = "termination_wait_time_in_minutes must be between 0 and 2880."
  }
}
variable "auto_rollback_events" {
  type        = list(string)
  default     = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM", "DEPLOYMENT_STOP_ON_REQUEST"]
  description = "Events that roll a deployment back automatically, as the _monolithic template had them"

  validation {
    condition     = length(var.auto_rollback_events) > 0
    error_message = "auto_rollback_events must contain at least one event; the deployment group enables automatic rollback, so an empty list is rejected."
  }

  validation {
    condition     = length(setsubtract(var.auto_rollback_events, ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM", "DEPLOYMENT_STOP_ON_REQUEST"])) == 0
    error_message = "auto_rollback_events entries must be DEPLOYMENT_FAILURE, DEPLOYMENT_STOP_ON_ALARM or DEPLOYMENT_STOP_ON_REQUEST."
  }
}
# --- CodeBuild --------------------------------------------------------------------------------------------
variable "build_compute_type" {
  type        = string
  default     = "BUILD_GENERAL1_MEDIUM"
  description = "Size of the CodeBuild container, as the _monolithic template had it"

  validation {
    condition     = contains(["BUILD_GENERAL1_SMALL", "BUILD_GENERAL1_MEDIUM", "BUILD_GENERAL1_LARGE", "BUILD_GENERAL1_XLARGE", "BUILD_GENERAL1_2XLARGE"], var.build_compute_type)
    error_message = "build_compute_type must be one of the BUILD_GENERAL1_* sizes CodeBuild accepts."
  }
}
variable "build_environment_image" {
  type        = string
  default     = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
  description = "Image the build runs in, as the _monolithic template had it. A managed CodeBuild image, which is why no registry credentials are configured"

  validation {
    condition     = length(var.build_environment_image) > 0
    error_message = "build_environment_image must not be empty."
  }
}
variable "build_timeout" {
  type        = number
  default     = 15
  description = "Minutes a build may run before CodeBuild stops it, as the _monolithic template had it"

  validation {
    condition     = var.build_timeout >= 5 && var.build_timeout <= 480
    error_message = "build_timeout must be between 5 and 480 minutes."
  }
}
variable "build_timezone" {
  type        = string
  default     = "Asia/Seoul"
  description = "Timezone the build sets before tagging an image, as the _monolithic template had it. It is load-bearing rather than cosmetic: the image tag is a timestamp, so this decides what that tag reads"

  validation {
    condition     = can(regex("^[A-Za-z]+/[A-Za-z_+-]+$", var.build_timezone))
    error_message = "build_timezone must be an IANA timezone name (e.g. Asia/Seoul)."
  }
}
# --- Pipeline, buckets and the trigger --------------------------------------------------------------------
variable "pipeline_type" {
  type        = string
  default     = "V2"
  description = "Pipeline type. V2, which is the only type CodePipeline creates now - the _monolithic template did not set it and got V2 by default"

  validation {
    condition     = contains(["V1", "V2"], var.pipeline_type)
    error_message = "pipeline_type must be V1 or V2."
  }
}
variable "pipeline_allow_self_start" {
  type        = bool
  default     = false
  description = "Whether the pipeline's own role may start the pipeline. False as the _monolithic template had it: the EventBridge rule has its own role for that, and this one only needs to read the source, write artifacts, start a build and create a deployment"
}
variable "source_object_key" {
  type        = string
  default     = "src.zip"
  description = "Key the builder uploads and the pipeline's source stage reads, as the _monolithic template had it. Also the object the CloudTrail data event selector and the EventBridge pattern name, so one value reaches four places (rules.md B-5)"

  validation {
    # The length bound is a length() call rather than a {1,1024} quantifier, because Terraform's regex()
    # is Go's RE2 and RE2 refuses to compile a repeat count above 1000. Wrapped in can(), that refusal is
    # not reported as a bad pattern - regex() errors, can() returns false, and the condition then rejects
    # every value including valid ones.
    condition     = length(var.source_object_key) >= 1 && length(var.source_object_key) <= 1024
    error_message = "source_object_key must be 1-1024 characters, which is S3's limit for an object key."
  }

  validation {
    condition     = can(regex("^[A-Za-z0-9!_.*'()/-]+$", var.source_object_key))
    error_message = "source_object_key must contain only the characters S3 documents as safe in a key: letters, digits and ! _ . * ' ( ) / -."
  }
}
variable "bucket_force_destroy" {
  type        = bool
  default     = true
  description = <<-DESC
    Whether terraform destroy empties the three buckets before deleting them - the pipeline source
    bucket, the artifact store and the CloudTrail log bucket.

    The _monolithic template declared all three as bare buckets and left this at its default of false,
    which makes destroy fail on every one of them with BucketNotEmpty. None of their contents is created
    by Terraform: the builder uploads the source archive, CodePipeline writes an artifact per execution,
    and CloudTrail writes a log file every few minutes. So the default is false in the template only
    because the template never had to tear itself down.

    True here, and the cost is stated rather than hidden: destroying this project deletes the uploaded
    source, every pipeline artifact and the whole CloudTrail audit log, including the records of who
    started which deployment. All three buckets are versioned, so force_destroy removes the versions too
    and none of it is recoverable. Set it to false to keep them and empty the buckets by hand instead.
  DESC
}
variable "cloudtrail_include_management_events" {
  type        = bool
  default     = false
  description = "Whether the trail also records management events. False, which is what the _monolithic template configured - this trail exists only to turn an S3 object write into an EventBridge event, and management events would bill for volume nothing here reads"
}
variable "trigger_enabled" {
  type        = bool
  default     = true
  description = "Whether the EventBridge rule is enabled. Disabling it leaves the pipeline in place but stops an upload from starting it, which is the way to inspect the pipeline without it running"
}
variable "trigger_event_names" {
  type        = list(string)
  default     = ["CopyObject", "PutObject", "CompleteMultipartUpload"]
  description = "S3 API calls that start the pipeline, as the _monolithic template had them. All three are needed rather than just PutObject: the CLI switches to a multipart upload above a size threshold, and then the event is CompleteMultipartUpload and a PutObject-only pattern matches nothing"

  validation {
    condition     = length(var.trigger_event_names) > 0
    error_message = "trigger_event_names must contain at least one event name, otherwise the rule matches nothing and no upload ever starts the pipeline."
  }
}
# --- Ordering and waits -----------------------------------------------------------------------------------
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the builder where its userdata drops a completion marker. The association in the root waits for that marker rather than relying on depends_on or a provider timeout, because RunInstances returning says nothing about a script that has not started yet (rules.md D-5)"

  validation {
    condition     = var.marker_file_path == null || can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/', or null to create no marker."
  }
}
variable "image_wait_timeout_seconds" {
  type        = number
  default     = 2400
  description = <<-DESC
    How long the image verification association may take. It waits for the whole builder bootstrap - dnf
    update, docker, the golang base image pull, the build - and then for the push and the upload to be
    visible.

    2400 rather than the 1800 that 031_ecs_alb_integration uses: that project's script has two polling
    phases and this one has three, so with the same image_wait_attempts and image_wait_interval_seconds
    the sleeps alone add up to 60 * 10 * 3 = 1800 seconds, and 1800 leaves no room at all. The remaining
    600 seconds cover what the product does not count - up to 120 aws CLI calls in the ECR and S3 phases,
    and the time the SSM agent on a freshly launched instance takes to pick the association up. It stays
    below the 3600 second executionTimeout of AWS-RunShellScript, so the document never cuts the script off
    first either.
  DESC

  validation {
    condition     = var.image_wait_timeout_seconds > 0
    error_message = "image_wait_timeout_seconds must be positive."
  }
}
variable "image_wait_attempts" {
  type        = number
  default     = 60
  description = "How many times the verification association polls in each of its three phases: the marker, then the image in ECR, then the archive in S3"

  validation {
    condition     = var.image_wait_attempts >= 1
    error_message = "image_wait_attempts must be at least 1."
  }

  validation {
    # A constraint about the combination rather than any one value (rules.md B-1). The script has three
    # sequential polling phases, so it can run for three times this product; if SSM gives up first the
    # association reports a bare "Failed" with nothing in it, where the script's own timeout prints which
    # phase stalled and where to look.
    condition     = var.image_wait_attempts * var.image_wait_interval_seconds * 3 < var.image_wait_timeout_seconds
    error_message = "image_wait_attempts * image_wait_interval_seconds * 3 must be below image_wait_timeout_seconds, so the script reports which of its three phases timed out instead of SSM reporting an unexplained Failed."
  }
}
variable "image_wait_interval_seconds" {
  type        = number
  default     = 10
  description = "Seconds between polls in the verification association"

  validation {
    condition     = var.image_wait_interval_seconds >= 1
    error_message = "image_wait_interval_seconds must be at least 1 second."
  }
}
