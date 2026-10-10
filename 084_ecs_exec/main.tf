# ECS Exec: an ECS service of one AWS CLI task on EC2 container instances, with execute-command enabled, and a
# VS Code workbench to open a shell in it from.
#
# What the _monolithic template got wrong is mostly invisible at apply, which is why it is listed here. Every
# security group lacked egress - Terraform drops the allow-all rule CloudFormation leaves - so the container
# instances could not register, the task could not reach ssmmessages and the workbench could not download
# code-server. The task definition took role names where it needed ARNs, which re-registers it on every plan.
# The service named the capacity provider by ARN and did not wait for the provider to join the cluster. And the
# exec command it printed was a multi-line string that no shell runs, on a workbench without the Session Manager
# plugin that execute-command hands the session to. Each fix is described where it is made.
data "aws_region" "current" {}
# The container instances' AMI, from the public parameter AWS maintains. Read here rather than in the module,
# whose depends_on would defer the read to apply (rules.md D-6), and passed in as an id (rules.md B-6).
#
# insecure_value rather than value: the provider marks value sensitive for every parameter, and a public AMI
# id is not a secret.
data "aws_ssm_parameter" "container_instance_ami_id" {
  name = var.container_instance_ami_ssm_parameter_name
}
locals {
  region = data.aws_region.current.region
  # Read back out of the module it was passed into, so the README step waits on the directory the bootstrap
  # actually writes to (rules.md B-5).
  marker = module.vscode_ec2.marker_file_path
}
module "network" {
  source = "./modules/network"
}
module "key_pair" {
  source = "./modules/key_pair"

  # Uses nothing from network and waits anyway, so the root has no exception to reason about (rules.md D-3).
  depends_on = [module.network]
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name                        = "vscode"
  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  code_server_version         = var.code_server_version
  security_group_name         = "bastion-sg"
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  marker_file_path            = var.marker_file_path
  # What the _monolithic template installed after code-server - Python, docker and bash-completion; git and the
  # Development Tools group come with the module - plus the two things the exec commands need on this machine.
  #
  # docker with the group membership and a code-server restart rather than the template's chmod 666 on
  # /var/run/docker.sock, which handed the root-equivalent socket to every local user and was lost again on the
  # next docker restart. code-server is restarted because it was started before ec2-user joined the group.
  #
  # The Session Manager plugin is the addition this project cannot work without: aws ecs execute-command hands
  # the session to it, and Amazon Linux 2023 does not ship it. The default region is the other: the README's
  # commands carry no --region, and the workbench has no region configured otherwise.
  additional_user_data = <<-EOT
    dnf install -yq python${var.workbench_python_version} docker bash-completion
    ln -sf /usr/bin/python${var.workbench_python_version} /usr/bin/python
    python -m ensurepip --upgrade
    systemctl enable --now docker
    usermod -aG docker ec2-user
    systemctl restart code-server
    dnf install -yq https://s3.amazonaws.com/session-manager-downloads/plugin/${var.session_manager_plugin_version}/linux_64bit/session-manager-plugin.rpm
    runuser -u ec2-user -- env HOME=/home/ec2-user aws configure set default.region ${local.region}
  EOT

  depends_on = [module.network, module.key_pair]
}
module "ecs_cluster" {
  source = "./modules/ecs_cluster"

  name               = "${var.project_name}-ecs-cluster"
  container_insights = var.container_insights

  depends_on = [module.network]
}
module "ecs_asg_capacity_provider" {
  source = "./modules/ecs_asg_capacity_provider"

  vpc_id = module.network.vpc_id
  # Private subnets, so outbound goes through the zonal NAT gateways. The ECS agent cannot register an instance
  # it cannot reach the ECS endpoint from, and an instance that never registers is absent rather than broken.
  subnet_ids   = module.network.private_subnet_ids
  cluster_name = module.ecs_cluster.cluster_name
  ami_id       = data.aws_ssm_parameter.container_instance_ami_id.insecure_value
  key_name     = module.key_pair.key_name

  capacity_provider_name                = "${var.project_name}-ecs-ec2-capacity-provider"
  instance_type                         = var.container_instance_type
  min_size                              = var.container_instance_min_size
  max_size                              = var.container_instance_max_size
  desired_capacity                      = var.container_instance_desired_capacity
  additional_cluster_capacity_providers = var.additional_cluster_capacity_providers

  # The cluster has to exist before an instance tries to join it and before the association in this module
  # attaches the provider to it. The cluster name is interpolated into the launch template userdata, so that
  # part is ordered by value; module-level depends_on covers the rest of the cluster module (rules.md D-2, D-3).
  depends_on = [module.network, module.ecs_cluster, module.key_pair]
}
module "task_security_group" {
  source = "./modules/task_security_group"

  vpc_id = module.network.vpc_id
  # No self_ingress_ports: nothing connects to this task. An exec session is a connection the SSM agent inside
  # the task makes outward, which is why the group's egress rule is the one that matters here.

  depends_on = [module.network]
}
module "ecs_service" {
  source = "./modules/ecs_service"

  cluster_name = module.ecs_cluster.cluster_name
  service_name = "${var.project_name}-ecs-service"
  # Read in the root, where nothing defers it (rules.md D-6).
  region                 = local.region
  subnet_ids             = module.network.private_subnet_ids
  security_group_ids     = [module.task_security_group.security_group_id]
  capacity_provider_name = module.ecs_asg_capacity_provider.capacity_provider_name
  desired_count          = var.service_desired_count

  task_family    = "aws-cli-td"
  task_cpu       = var.task_cpu
  task_memory    = var.task_memory
  container_name = "aws-cli"
  image          = var.aws_cli_image
  # The image's own entrypoint is the aws command, which prints its usage and exits - the service would replace
  # the task forever. The template's sleep loop keeps a process alive to exec into.
  entry_point = ["sh", "-c", "while true; do sleep 3600; done"]

  # The _monolithic template's log group was "/aws/ecs/<uuid slice>"; named after the project instead, now that
  # there is no uuid.
  log_group_name        = "/ecs/${var.project_name}"
  log_retention_in_days = var.log_retention_in_days
  log_stream_prefix     = "ecs-task-"

  enable_execute_command = true
  task_role_policy_arns  = var.task_role_policy_arns

  # The capacity provider has to be associated with the cluster before CreateService names it in a strategy,
  # and that association is inside the capacity module - capacity_provider_name orders this after the provider
  # resource only, not after the association (rules.md D-2). The _monolithic template had exactly that race.
  # The order also matters in reverse: on destroy this module goes first, which is what lets ECS delete the
  # capacity provider afterwards - it refuses while a service's strategy still names it.
  depends_on = [module.network, module.ecs_asg_capacity_provider]
}
# --- README on the workbench ------------------------------------------------------------------------------
locals {
  # One running task, for the exec commands below. --task takes the ARN as it is, so the template's
  # cut -d"/" -f3 to extract the ID was not needed.
  exec_task = "$(${module.ecs_service.first_task_arn_command})"
  exec_base = "aws ecs execute-command --cluster ${module.ecs_cluster.cluster_name} --task ${local.exec_task} --container ${module.ecs_service.container_name} --interactive"
  # Every output this root exposes, defined once. outputs.tf projects this map and the README on the workbench
  # renders it, so an output cannot exist without also appearing in that README (rules.md H-2).
  outputs = {
    vscode_url = {
      order       = 1
      title       = "VS Code URL"
      description = "The workbench, as the _monolithic template output VsCode. Every command below runs from its terminal, where the AWS CLI is set to this region and has the Session Manager plugin that execute-command needs"
      value       = module.vscode_ec2.vscode_url
    }
    cluster_name = {
      order       = 2
      title       = "ECS cluster"
      description = "The cluster the aws-cli service runs in"
      value       = module.ecs_cluster.cluster_name
    }
    execute_command_agent_command = {
      order       = 3
      title       = "1. Whether the task can take a session"
      description = "enableExecuteCommand True and the ExecuteCommandAgent RUNNING. An empty table means no task is running yet - the service events below say why"
      value       = module.ecs_service.execute_command_agent_command
    }
    ecs_exec_command = {
      order       = 4
      title       = "2. Open a shell in the aws-cli container"
      description = "The _monolithic template output EcsExecCommand, as one line. The template printed it with a newline before every option and no line continuation, so a pasted copy ran a bare aws ecs execute-command and then tried each option as a command of its own"
      value       = "${local.exec_base} --command /bin/sh"
    }
    ecs_exec_identity_command = {
      order       = 5
      title       = "3. Run one command as the task role"
      description = "execute-command runs a single command too. This one shows that a session runs as the task role - an assumed-role ARN, with no credentials configured in the container - which is also what decides what the session can do in the account"
      value       = "${local.exec_base} --command 'aws sts get-caller-identity --region ${local.region}'"
    }
    container_log_command = {
      order       = 6
      title       = "4. The session log"
      description = "The container output, and the ECS Exec sessions: under the default session logging ECS writes each session to the task log group, provided the image carries the script and cat utilities the upload uses. A session that works but never appears here is an image without them"
      value       = module.ecs_service.container_log_command
    }
    service_events_command = {
      order       = 7
      title       = "When no task is running: the service events"
      description = "Nearly every failure is reported here first, not in Terraform"
      value       = module.ecs_service.service_events_command
    }
    container_instance_status_command = {
      order       = 8
      title       = "When no task is running: the container instances"
      description = "Which instances registered with the cluster. Instances launched but missing here cannot reach the ECS endpoint or lack the container instance role policy"
      value       = module.ecs_asg_capacity_provider.container_instance_status_command
    }
    scaling_activities_command = {
      order       = 9
      title       = "When instances are missing: the Auto Scaling activity"
      description = "Launch failures are recorded here rather than in ECS"
      value       = module.ecs_asg_capacity_provider.scaling_activities_command
    }
    private_key_command = {
      order       = 10
      title       = "SSH key"
      description = "Retrieves the generated private key from Parameter Store. No security group opens port 22; this is for the case where the SSM agent is what is broken"
      value       = module.key_pair.private_key_command
    }
  }
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  readme_body = join("\n", concat(
    ["# ECS Exec", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  association_name                 = "${var.project_name}-vscode-readme"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # Waits for the workbench bootstrap, whose marker is written after the Session Manager plugin is installed
    # (rules.md B-4/D-5).
    commands = <<-EOT
      until [ -f ${local.marker}/userdata ]; do sleep 10; done
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${local.marker}/vscode_readme
      EOT
  }
}
