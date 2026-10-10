# ECS service discovery with Cloud Map: three nginx tasks registered as A records in a private DNS namespace, a
# dnsutils task that finds them through the VPC resolver, EC2 container instances for both, and a VS Code
# workbench to exec into the client from.
#
# The base is 084_ecs_exec's, and so were its faults: no security group had egress, so the instances could not
# register and an ECS Exec session could not reach ssmmessages; the task definitions took role names where they
# needed ARNs; the services named the capacity provider by ARN and did not wait for it to join the cluster; and
# the test command it printed was a multi-line string no shell runs, on a workbench without the Session Manager
# plugin. Particular to this project, the Cloud Map service set a health check argument the provider deprecates
# and could not be destroyed while ECS still had a task registered in it. Each fix is described where it is made.
data "aws_region" "current" {}
# The container instances' AMI, read here rather than in the module, whose depends_on would defer the read to
# apply (rules.md D-6), and passed in as an id (rules.md B-6).
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
  # Development Tools group come with the module - plus the two things the test commands need on this machine.
  #
  # docker with the group membership and a code-server restart rather than the template's chmod 666 on
  # /var/run/docker.sock, which handed the root-equivalent socket to every local user. code-server is restarted
  # because it was started before ec2-user joined the group.
  #
  # Every test runs in the dnsutils task through aws ecs execute-command, which hands the session to the Session
  # Manager plugin; Amazon Linux 2023 does not ship it. The default region is the other addition: the README's
  # commands carry no --region.
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
module "service_discovery" {
  source = "./modules/service_discovery"

  # The namespace's hosted zone is associated with this VPC, so only resolvers inside it answer for the names.
  vpc_id         = module.network.vpc_id
  namespace_name = var.service_discovery_namespace_name
  service_name   = var.app_discovery_service_name
  dns_ttl        = var.app_dns_ttl

  depends_on = [module.network]
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
  # attaches the provider to it (rules.md D-2, D-3).
  depends_on = [module.network, module.ecs_cluster, module.key_pair]
}
module "task_security_group" {
  source = "./modules/task_security_group"

  vpc_id = module.network.vpc_id
  # Both services' tasks carry this group, so a rule from the group to itself is a rule from the client to the
  # servers. A records point at the nginx task ENIs, so the client connects straight to the container port -
  # the same value the task definition publishes (rules.md B-5). The lookup itself needs no rule: security
  # groups do not filter traffic to the VPC resolver.
  self_ingress_ports = [var.app_container_port]

  depends_on = [module.network]
}
module "app_service" {
  source = "./modules/ecs_service"

  cluster_name           = module.ecs_cluster.cluster_name
  service_name           = var.app_service_name
  region                 = local.region
  subnet_ids             = module.network.private_subnet_ids
  security_group_ids     = [module.task_security_group.security_group_id]
  capacity_provider_name = module.ecs_asg_capacity_provider.capacity_provider_name
  desired_count          = var.app_desired_count

  task_family       = "nginx-td"
  task_cpu          = var.task_cpu
  task_memory       = var.task_memory
  container_name    = "nginx"
  image             = var.app_image
  container_port    = var.app_container_port
  port_mapping_name = var.app_port_name

  log_group_name        = "/ecs/${var.project_name}/nginx"
  log_retention_in_days = var.log_retention_in_days
  log_stream_prefix     = "ecs-app-"

  task_role_policy_arns = var.task_role_policy_arns
  # Each task registers its ENI address in the Cloud Map service as it starts and is deregistered as it stops.
  service_registry = {
    registry_arn = module.service_discovery.service_arn
  }

  # The capacity provider has to be associated with the cluster before CreateService names it in a strategy,
  # and that association is inside the capacity module - capacity_provider_name orders this after the provider
  # resource only (rules.md D-2). On destroy this module goes first, which lets ECS delete the provider after,
  # and stops the tasks before the Cloud Map service they are registered in is deleted.
  depends_on = [module.network, module.ecs_asg_capacity_provider]
}
module "dnsutils_service" {
  source = "./modules/ecs_service"

  cluster_name           = module.ecs_cluster.cluster_name
  service_name           = var.client_service_name
  region                 = local.region
  subnet_ids             = module.network.private_subnet_ids
  security_group_ids     = [module.task_security_group.security_group_id]
  capacity_provider_name = module.ecs_asg_capacity_provider.capacity_provider_name
  desired_count          = var.client_desired_count

  task_family    = "dnsutils-td"
  task_cpu       = var.task_cpu
  task_memory    = var.task_memory
  container_name = "dnsutils"
  image          = var.client_image

  log_group_name        = "/ecs/${var.project_name}/dnsutils"
  log_retention_in_days = var.log_retention_in_days
  log_stream_prefix     = "ecs-dnsutils-"

  enable_execute_command = true
  task_role_policy_arns  = var.task_role_policy_arns

  # Not ordered after app_service, unlike its counterpart in 085_ecs_service_connect. A DNS client resolves at
  # query time, so a dnsutils task that starts before the nginx tasks register simply gets no answer until they
  # do - there is nothing fixed at task start to get wrong.
  depends_on = [module.network, module.ecs_asg_capacity_provider]
}
# --- README on the workbench ------------------------------------------------------------------------------
locals {
  # One running dnsutils task, for the exec commands below. --task takes the ARN as it is, so the template's
  # cut -d"/" -f3 to extract the ID was not needed.
  exec_task = "$(${module.dnsutils_service.first_task_arn_command})"
  exec_base = "aws ecs execute-command --cluster ${module.ecs_cluster.cluster_name} --task ${local.exec_task} --container ${module.dnsutils_service.container_name} --interactive"
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
      description = "The cluster both services run in"
      value       = module.ecs_cluster.cluster_name
    }
    service_discovery_fqdn = {
      order       = 3
      title       = "The nginx name"
      description = "Name the nginx tasks resolve at. Any resolver in the VPC answers for it - it is a record in a private hosted zone - and nothing outside the VPC does"
      value       = module.service_discovery.fqdn
    }
    service_discovery_instances_command = {
      order       = 4
      title       = "1. What ECS registered in Cloud Map"
      description = "One instance per running nginx task, with the task ENI address"
      value       = module.service_discovery.list_instances_command
    }
    service_discovery_records_command = {
      order       = 5
      title       = "2. The records Cloud Map wrote"
      description = "The A records in the namespace hosted zone, one per task - what a lookup from inside the VPC answers with"
      value       = module.service_discovery.hosted_zone_records_command
    }
    service_discovery_test_commands = {
      order       = 6
      title       = "3. Open a shell in the dnsutils container"
      description = "The _monolithic template output ServiceDiscoveryTestCommands, as one line. The template printed it with a newline before every option and no line continuation, so a pasted copy ran a bare aws ecs execute-command and then tried each option as a command of its own. In the shell, dig and curl the name above"
      value       = "${local.exec_base} --command /bin/sh"
    }
    service_discovery_dig_command = {
      order       = 7
      title       = "4. Resolve the name"
      description = "The lookup in one command: one address per nginx task, from the VPC resolver, under the MULTIVALUE routing policy"
      value       = "${local.exec_base} --command 'dig +short ${module.service_discovery.fqdn}'"
    }
    service_discovery_curl_command = {
      order       = 8
      title       = "5. Call nginx by name"
      description = "The nginx welcome page, fetched by name from inside the client task. The port comes from the client, not from DNS - an A record carries an address only"
      value       = "${local.exec_base} --command 'curl -sS http://${module.service_discovery.fqdn}:${module.app_service.container_port}'"
    }
    app_service_events_command = {
      order       = 9
      title       = "When records are missing: the nginx service events"
      description = "Nearly every failure is reported here first, not in Terraform"
      value       = module.app_service.service_events_command
    }
    dnsutils_execute_command_agent_command = {
      order       = 10
      title       = "When exec fails: whether the dnsutils task can take a session"
      description = "enableExecuteCommand True and the ExecuteCommandAgent RUNNING. An empty table means no dnsutils task is running"
      value       = module.dnsutils_service.execute_command_agent_command
    }
    container_instance_status_command = {
      order       = 11
      title       = "When no task is running: the container instances"
      description = "Which instances registered with the cluster. Instances launched but missing here cannot reach the ECS endpoint or lack the container instance role policy"
      value       = module.ecs_asg_capacity_provider.container_instance_status_command
    }
    private_key_command = {
      order       = 12
      title       = "SSH key"
      description = "Retrieves the generated private key from Parameter Store. No security group opens port 22; this is for the case where the SSM agent is what is broken"
      value       = module.key_pair.private_key_command
    }
  }
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  readme_body = join("\n", concat(
    ["# ECS Service Discovery", ""],
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
