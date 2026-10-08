data "aws_region" "current" {}
module "network" {
  source = "./modules/network"

  vpc_cidr_block             = var.vpc_cidr_block
  availability_zone_suffixes = var.availability_zone_suffixes
}
module "key_pair" {
  source = "./modules/key_pair"

  # Uses nothing from network and waits anyway: a root with a network module has no module that starts
  # before it finishes, so nobody has to decide per module whether an omission was reasoned (rules.md D-3).
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
  security_group_name         = "vscode-sg"
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  marker_file_path            = var.marker_file_path
  # The Session Manager plugin, because the one command in the README that touches a running task is ECS
  # Exec, and the AWS CLI hands an execute-command session to that plugin - without it the command fails with
  # "SessionManagerPlugin is not found" on the instance the README is read from. The region is set for
  # ec2-user so the README's commands run as written.
  additional_user_data = <<-EOT
    dnf install -yq https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm
    runuser -u ec2-user -- env HOME=/home/ec2-user aws configure set default.region ${data.aws_region.current.region}
  EOT

  depends_on = [module.network, module.key_pair]
}
# --- Where the logs go ------------------------------------------------------------------------------------
module "log_delivery_stream" {
  source = "./modules/firehose_s3_delivery_stream"

  # CloudFormation generated this name; Terraform requires one, so it comes from the project name as the
  # _monolithic template derived it from the stack name.
  name                       = "${var.project_name}-delivery-stream"
  buffering_interval_seconds = var.firehose_buffering_interval_seconds
  force_destroy              = var.force_destroy_destination_bucket

  depends_on = [module.network]
}
module "container_logs" {
  source = "./modules/firehose_log_subscription"

  log_group_name    = var.log_group_name
  retention_in_days = var.log_retention_in_days
  # Both from the stream's own module, so the filter's destination, the role's permission and the key grant
  # name the same stream (rules.md B-5).
  delivery_stream_arn         = module.log_delivery_stream.delivery_stream_arn
  delivery_stream_kms_key_arn = module.log_delivery_stream.kms_key_arn

  depends_on = [module.network]
}
# --- What produces them -----------------------------------------------------------------------------------
module "application_load_balancer" {
  source = "./modules/application_load_balancer"

  name                        = var.load_balancer_name
  vpc_id                      = module.network.vpc_id
  vpc_cidr_block              = module.network.vpc_cidr_block
  subnet_ids                  = module.network.public_subnet_ids
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  target_port                 = var.container_port
  target_group_names          = var.target_group_names

  depends_on = [module.network]
}
module "ecs_cluster" {
  source = "./modules/ecs_cluster"

  name = "${var.project_name}-ecs-cluster"

  depends_on = [module.network]
}
module "ecs_service" {
  source = "./modules/ecs_service"

  name         = "${var.project_name}-ecs-service"
  cluster_name = module.ecs_cluster.cluster_name
  region       = data.aws_region.current.region
  vpc_id       = module.network.vpc_id
  subnet_ids   = module.network.private_subnet_ids
  # A literal key, so the rule's address is known at plan while the ALB's group ID is not (rules.md B-8).
  ingress_source_security_groups = {
    alb = module.application_load_balancer.security_group_id
  }
  container_image = var.container_image
  # The same port the target groups were built for, read back from the ALB module (rules.md B-5).
  container_port               = module.application_load_balancer.target_port
  desired_count                = var.service_desired_count
  target_group_arn             = module.application_load_balancer.primary_target_group_arn
  alternate_target_group_arn   = module.application_load_balancer.alternate_target_group_arn
  production_listener_rule_arn = module.application_load_balancer.production_listener_rule_arn
  # The subscribed group, so the container writes to exactly what Firehose is reading (rules.md B-5).
  log_group_name        = module.container_logs.log_group_name
  log_group_arn         = module.container_logs.log_group_arn
  wait_for_steady_state = var.wait_for_steady_state

  # The value references above order the service after the specific resources they name. These cover what
  # they do not (rules.md D-2):
  #   - container_logs as a whole, so the subscription filter exists before the first task writes - otherwise
  #     the first events reach CloudWatch and never reach S3, which looks like a broken subscription
  #   - application_load_balancer as a whole, so the listener the rule hangs off is in place before ECS
  #     registers a task into the primary group
  #   - ecs_cluster as a whole, for the capacity provider association
  # and on destroy the reverse: the service is removed while the ALB, the cluster and the log pipeline it
  # depends on are all still there.
  depends_on = [
    module.network,
    module.ecs_cluster,
    module.application_load_balancer,
    module.container_logs,
  ]
}
# --- README on the workbench ------------------------------------------------------------------------------
locals {
  # Every output this root exposes, defined once. outputs.tf projects this map and the README on the
  # workbench renders it, so an output cannot exist without also appearing in that README (rules.md H-2).
  outputs = {
    vscode_url = {
      order       = 1
      title       = "VS Code URL"
      description = "The workbench. Every command below is meant to be run from its terminal"
      value       = module.vscode_ec2.vscode_url
    }
    alb_url = {
      order       = 2
      title       = "nginx behind the ALB"
      description = "Each request is one access log line from the container, which is the record this project streams"
      value       = module.application_load_balancer.url
    }
    generate_traffic_command = {
      order       = 3
      title       = "1. Produce some log lines"
      description = "Fifty requests, one status code per line. 200s mean the ALB, the target group and the tasks are all reachable"
      value       = "for i in $(seq 1 50); do curl -s -o /dev/null -w '%%{http_code}\\n' ${module.application_load_balancer.url}/; done"
    }
    tail_logs_command = {
      order       = 4
      title       = "2. Watch them arrive in CloudWatch"
      description = "The stream half: CloudWatch receives each line as nginx writes it, and the subscription hands it to Firehose the moment it arrives"
      value       = module.container_logs.tail_command
    }
    list_delivered_command = {
      order       = 5
      title       = "3. Watch them arrive in S3"
      description = "The batch half: Firehose holds what it receives and writes one object per buffering interval (firehose_buffering_interval_seconds, 300 by default) or 5 MB, whichever comes first. Empty until the first interval has passed"
      value       = module.log_delivery_stream.list_delivered_command
    }
    read_delivered_command = {
      order       = 6
      title       = "4. Read the newest object"
      description = "Gunzipped twice, because CloudWatch Logs already gzips what it sends to a subscription and the stream's GZIP compresses it again. What comes out is CloudWatch's JSON envelope with the nginx lines inside logEvents"
      value       = "aws s3 cp s3://${module.log_delivery_stream.bucket_name}/$(aws s3api list-objects-v2 --bucket ${module.log_delivery_stream.bucket_name} --prefix ${module.log_delivery_stream.prefix} --query 'sort_by(Contents,&LastModified)[-1].Key' --output text) - | gunzip | gunzip"
    }
    list_errors_command = {
      order       = 7
      title       = "5. Records Firehose could not deliver"
      description = "Should stay empty. Anything here is the reason a gap appears under the delivered prefix"
      value       = module.log_delivery_stream.list_errors_command
    }
    describe_delivery_stream_command = {
      order       = 8
      title       = "6. Delivery stream status and encryption"
      description = "ENABLED with CUSTOMER_MANAGED_CMK is the encryption the _monolithic template declared a key for and then lost in conversion"
      value       = module.log_delivery_stream.describe_command
    }
    service_status_command = {
      order       = 9
      title       = "7. Service status"
      description = "Desired against running tasks and the rollout state"
      value       = module.ecs_service.service_status_command
    }
    service_events_command = {
      order       = 10
      title       = "8. Service events"
      description = "Where a pull failure, an unhealthy target or a circuit-breaker rollback is reported first"
      value       = module.ecs_service.service_events_command
    }
    target_health_command = {
      order       = 11
      title       = "9. Target health"
      description = "Whether the ALB can reach the tasks. Target.Timeout is a security group path problem rather than an application one"
      value       = module.application_load_balancer.target_health_command
    }
    execute_command = {
      order       = 12
      title       = "10. A shell inside a running task"
      description = "ECS Exec. The session itself is logged to the same group, so it streams to S3 along with the access log"
      value       = module.ecs_service.execute_command
    }
    ecs_cluster_name = {
      order       = 13
      title       = "ECS cluster"
      description = "Name of the ECS cluster"
      value       = module.ecs_cluster.cluster_name
    }
    ecs_service_name = {
      order       = 14
      title       = "ECS service"
      description = "Name of the ECS service"
      value       = module.ecs_service.service_name
    }
    log_group_name = {
      order       = 15
      title       = "Log group"
      description = "The group the containers write to and Firehose is subscribed to"
      value       = module.container_logs.log_group_name
    }
    delivery_stream_name = {
      order       = 16
      title       = "Delivery stream"
      description = "Name of the Firehose delivery stream"
      value       = module.log_delivery_stream.delivery_stream_name
    }
    destination_bucket_name = {
      order       = 17
      title       = "Destination bucket"
      description = "Where Firehose writes. terraform destroy empties it first, so the delivered logs go with it"
      value       = module.log_delivery_stream.bucket_name
    }
    private_key_command = {
      order       = 18
      title       = "Workbench SSH key"
      description = "Retrieves the generated private key from Parameter Store. No security group opens port 22; this is for the case where the SSM agent is what is broken"
      value       = module.key_pair.private_key_command
    }
  }
  # Re-keyed by order so values() returns the sections in reading order rather than alphabetically.
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  readme_body = join("\n", concat(
    ["# ${var.project_name}", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}
# The _monolithic template's README was the single line "# ECS Cluster", written by userdata. This writes
# every output instead, after the bootstrap has finished (rules.md H-2).
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is what orders this after the
    # bootstrap (rules.md D-5). The marker path comes back out of the module it was passed into (rules.md B-5).
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/userdata ]; do sleep 10; done
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_readme
      EOT
  }
  depends_on = [module.vscode_ec2]
}
