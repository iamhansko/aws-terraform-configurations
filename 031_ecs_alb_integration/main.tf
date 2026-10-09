data "aws_region" "current" {}
# The workbench AMI, read here rather than inside the module that uses it.
#
# insecure_value rather than value: the provider marks every parameter's value sensitive whatever its type,
# and a sensitive value cannot be used for an instance's ami without nonsensitive(). insecure_value is the
# provider's own accessor for a parameter that is not a secret, and a public AMI id is not one.
#
# Reading it in the root also keeps it out of a module that carries depends_on, which would defer it to
# apply (rules.md D-6). Nothing derives a resource address from it, so deferring would be harmless here -
# but the root is the answer that does not have to be re-examined when a module grows a for_each.
data "aws_ssm_parameter" "bastion_ami_id" {
  name = var.bastion_ami_ssm_parameter_name
}
module "network" {
  source = "./modules/network"

  vpc_cidr_block             = var.vpc_cidr_block
  public_subnet_a_cidr_block = var.public_subnet_a_cidr_block
  public_subnet_c_cidr_block = var.public_subnet_c_cidr_block
  availability_zone_suffixes = var.availability_zone_suffixes
  vpc_name                   = var.vpc_name
  internet_gateway_name      = var.internet_gateway_name
  public_subnet_name         = var.public_subnet_name
  public_route_table_name    = var.public_route_table_name
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name_prefix = var.key_name_prefix
  rsa_bits        = var.key_rsa_bits

  # Uses nothing from network and does not need a VPC to create a key pair. It waits anyway: a root with a
  # network module has no module that starts before that module finishes, so nobody has to decide per module
  # whether an omission was reasoned or forgotten (rules.md D-3).
  depends_on = [module.network]
}
module "ecr_repository" {
  source = "./modules/ecr_repository"

  name         = var.ecr_repository_name
  image_tag    = var.image_tag
  force_delete = var.ecr_force_delete
  scan_on_push = var.ecr_scan_on_push

  # Also uses nothing from network, and also waits, for the reason above (rules.md D-3).
  depends_on = [module.network]
}
module "ecs_cluster" {
  source = "./modules/ecs_cluster"

  name               = var.ecs_cluster_name
  container_insights = var.container_insights

  depends_on = [module.network]
}
module "application_load_balancer" {
  source = "./modules/application_load_balancer"

  name                = var.load_balancer_name
  vpc_id              = module.network.vpc_id
  vpc_cidr_block      = module.network.vpc_cidr_block
  subnet_ids          = module.network.public_subnet_ids
  security_group_name = var.alb_security_group_name
  ingress_cidr_blocks = var.alb_ingress_cidr_blocks
  listener_port       = var.listener_port
  target_group_name   = var.target_group_name
  target_port         = var.container_port
  health_check_path   = var.health_check_path

  # The subnet and VPC references order this after those specific resources, not after the route to the
  # internet gateway - which an internet-facing load balancer needs before it can answer anything
  # (rules.md D-3).
  depends_on = [module.network]
}
locals {
  # Everything the workbench does beyond running code-server, injected through additional_user_data so the
  # vscode_ec2 module does not have to know what this project builds on it (rules.md B-4).
  #
  # Flat indentation on purpose, and it is load-bearing. Terraform's <<- strips the smallest indentation of
  # any literal line in the heredoc, so with nothing indented further every line - the quoted heredoc
  # terminators included - lands at column 0. A shell heredoc terminator with leading whitespace is not
  # recognised, the heredoc then swallows the rest of the script, and the whole thing fails to parse with a
  # syntax error at the last line (rules.md A-4 describes the same failure arriving from a CRLF line
  # ending). The two ${file(...)} interpolations below make this a nested heredoc, which is exactly the
  # shape that breaks.
  #
  # No set -e, matching the module's base script. With it, a failed docker login would stop before the
  # completion marker and the associations below would then sit until their timeouts with nothing to say
  # beyond "it never finished". Without it the script always reaches the marker, and the ECR check in
  # aws_ssm_association.image_pushed is what decides whether the build actually produced anything - a check
  # whose failure message names the repository.
  bastion_user_data = <<-EOT
    dnf install -yq docker
    systemctl enable --now docker
    # Adds ec2-user to the docker group rather than the _monolithic template's
    # "chmod 666 /var/run/docker.sock", which makes the daemon socket world-writable and hands every local
    # account root-equivalent control of the host (rules.md H-1). The build below runs as root and needs
    # neither.
    usermod -aG docker ec2-user
    # code-server is already running by this point, so its process predates the docker group and its
    # terminals inherit the groups it started with. Restarting is what makes docker usable from the IDE,
    # which is where a person rebuilding the image by hand will be.
    systemctl restart code-server

    # The application and its Dockerfile, shipped from src/ rather than echoed inline.
    #
    # The _monolithic template wrote both with shell echo statements inside this script, while src/
    # already held a monitoring.py that nothing read. There were two copies of the application and the one
    # under version control was the one not running. src/ is the source of truth now and this is the only
    # place it is read.
    #
    # src/index.html is not used and is not referenced from anywhere in this project or in the
    # _monolithic template either. Its title is "WS CloudFront Test", so it arrived from a different
    # project; it is left in place rather than deleted, and this is the note saying why nothing reads it.
    mkdir -p /home/ec2-user/image
    cat > /home/ec2-user/image/monitoring.py << 'TFMONITORINGAPP'
    ${file("${path.root}/src/monitoring.py")}
    TFMONITORINGAPP
    cat > /home/ec2-user/image/Dockerfile << 'TFDOCKERFILE'
    ${file("${path.root}/src/Dockerfile")}
    TFDOCKERFILE
    chown -R ec2-user:ec2-user /home/ec2-user/image

    # Login against the registry host with no repository path. docker accepts a login that carries a path
    # and then fails to match it when pushing, which surfaces as "no basic auth credentials" on the push
    # and reads like a permissions problem.
    ${module.ecr_repository.docker_login_command}
    # A dedicated build context directory rather than the original's /home/ec2-user, which hands the whole
    # home directory to the daemon as the context.
    docker build -t ${module.ecr_repository.image_uri} /home/ec2-user/image
    docker push ${module.ecr_repository.image_uri}
    EOT
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  instance_name = var.bastion_instance_name
  vpc_id        = module.network.vpc_id
  # The first public subnet. This box is the public side of the project: it serves code-server to a browser
  # and reaches ECR and the ALB outbound, and there is no NAT gateway for it to use instead.
  subnet_id                   = module.network.public_subnet_a_id
  ami_id                      = data.aws_ssm_parameter.bastion_ami_id.insecure_value
  instance_type               = var.bastion_instance_type
  key_name                    = module.key_pair.key_name
  root_volume_size            = var.bastion_root_volume_size
  associate_public_ip_address = var.bastion_associate_public_ip_address
  security_group_name         = var.bastion_security_group_name
  ingress_cidr_blocks         = var.bastion_ingress_cidr_blocks
  code_server_version         = var.code_server_version
  code_server_port            = var.code_server_port
  ssh_port                    = var.ssh_port
  python_version              = var.python_version
  iam_name_prefix             = var.bastion_iam_name_prefix
  iam_policy_arns             = var.bastion_iam_policy_arns
  # What the two associations below poll for (rules.md B-4/H-2). The module touches <path>/userdata as its
  # very last step, after the script above has run.
  marker_file_path     = var.marker_file_path
  additional_user_data = local.bastion_user_data

  # network for the uniform reason, and here it is load-bearing too: cloud-init starts dnf within seconds of
  # the launch, and the route to the internet gateway is exactly the sort of resource a value reference
  # misses (rules.md D-3). ecr_repository because the script above pushes into it - the value references
  # order this after the repository resource, and the module-level edge covers the rest of that module.
  depends_on = [module.network, module.key_pair, module.ecr_repository]
}
# What the CloudFormation CreationPolicy used to do.
#
# The original held the stack at the bastion until cfn-signal reported from inside its userdata, which is
# how an image came to exist before anything pulled it. The conversion dropped it - its own comment says the
# CreationPolicy is not reproduced - and the ECS service was left pointing at
# "${aws_ecr_repository.ecr.repository_url}:latest" with nothing ordering it after the push.
#
# What actually happens without this: the service is created in parallel with the instance, its first tasks
# stop with CannotPullContainerError against a tag that does not exist, and ECS keeps replacing them. It
# does eventually recover on its own once the push lands, which is worse than failing - the demo looks
# broken for several minutes and then silently is not. With wait_for_steady_state on the service it is worse
# still: the apply blocks on a steady state that cannot arrive until the race resolves, and may give up
# first.
#
# So: wait for the marker, then ask the repository. Two phases, because they fail for different reasons and
# the message should say which (rules.md D-5 for the marker-and-loop shape, which this repository uses
# instead of trusting depends_on or a provider timeout to mean "the remote command finished").
#
# The ECR check is the part that matters. The marker only says the script reached its end - it does not stop
# on error - so a failed docker login, a DNS problem or a disk that ran out still writes it. Asking ECR is
# the only thing here that distinguishes "the build worked" from "the script finished".
resource "aws_ssm_association" "image_pushed" {
  name                             = "AWS-RunShellScript"
  association_name                 = "${var.project_name}-image-pushed"
  wait_for_success_timeout_seconds = var.image_wait_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    commands = <<-EOT
      set -u

      MARKER=${module.vscode_ec2.marker_file_path}/userdata

      # An until loop rather than "[ -f ... ] && break" inside a for: a bare test that fails is a non-zero
      # statement at top level, and if the shell SSM runs this with has -e set that ends the script on the
      # first pass with no output. A failing until condition never triggers -e, which is why rules.md D-5's
      # shape is an until loop and not a test.
      waited=0
      until [ -f "$MARKER" ]; do
        waited=$((waited + 1))
        if [ "$waited" -gt ${var.image_wait_attempts} ]; then
          echo "the workbench bootstrap never finished: $MARKER is still absent. Read /var/log/cloud-init-output.log on this instance." >&2
          exit 1
        fi
        sleep ${var.image_wait_interval_seconds}
      done

      # A command that fails as an if condition is also exempt from -e.
      for attempt in $(seq 1 ${var.image_wait_attempts}); do
        if aws ecr describe-images --region ${data.aws_region.current.region} --repository-name ${module.ecr_repository.name} --image-ids imageTag=${module.ecr_repository.image_tag} > /dev/null 2>&1; then
          exit 0
        fi
        sleep ${var.image_wait_interval_seconds}
      done

      echo "${module.ecr_repository.image_uri} is not in the repository although the bootstrap finished. The build or the push failed; /var/log/cloud-init-output.log on this instance has the reason." >&2
      exit 1
      EOT
  }

  # The repository has to exist before a push and the instance before anything runs on it. Nothing in the
  # command above references the instance except through the targets block, which does not create an
  # ordering edge (rules.md D-1).
  depends_on = [module.ecr_repository, module.vscode_ec2]
}
module "ecs_service" {
  source = "./modules/ecs_service"

  service_name   = var.service_name
  cluster_name   = module.ecs_cluster.cluster_name
  task_family    = var.task_family
  container_name = var.container_name
  # From the repository module rather than reassembled, so the tag the workbench pushed and the tag this
  # pulls are one value (rules.md B-5).
  image_uri = module.ecr_repository.image_uri
  # The same port the target group was built for, read back from the load balancer module (rules.md B-5).
  container_port   = module.application_load_balancer.target_port
  task_cpu         = var.task_cpu
  task_memory      = var.task_memory
  desired_count    = var.service_desired_count
  vpc_id           = module.network.vpc_id
  subnet_ids       = module.network.public_subnet_ids
  assign_public_ip = var.assign_public_ip
  target_group_arn = module.application_load_balancer.target_group_arn
  # A literal key, so the rule's resource address is known at plan while the ALB's group ID is not
  # (rules.md B-8).
  ingress_source_security_groups = {
    alb = module.application_load_balancer.security_group_id
  }
  security_group_name   = var.ecs_service_security_group_name
  log_group_name        = var.log_group_name
  log_retention_in_days = var.log_retention_in_days
  wait_for_steady_state = var.wait_for_steady_state

  # Three edges. The value references above order this after the individual resources they name, and none
  # of the three is covered by that (rules.md D-2).
  #
  #   network                    vpc_id and subnet_ids order this after the VPC and the two subnets, not
  #                              after the route to the internet gateway - and that route is the tasks'
  #                              only path to ECR and CloudWatch Logs, so a task placed before it exists
  #                              stops with ResourceInitializationError (rules.md D-3)
  #   application_load_balancer  the target group ARN orders this after the group, not after the listener
  #                              in front of it or after the group's egress rule. It matters most in
  #                              reverse: on destroy the service goes first, which deregisters the targets
  #                              before elbv2 is asked to delete a group that still has some
  #   image_pushed               the image has to be in the repository before the service starts pulling
  #                              it, and nothing above refers to that association at all. This is the edge
  #                              the CloudFormation CreationPolicy used to provide
  depends_on = [
    module.network,
    module.application_load_balancer,
    aws_ssm_association.image_pushed,
  ]
}
module "observability" {
  source = "./modules/observability"

  region         = data.aws_region.current.region
  dashboard_name = var.dashboard_name
  # Both dimensions of the ECS widget come from the modules that created the things they name, so renaming
  # the cluster or the service cannot leave the widget pointing at nothing (rules.md B-5). A widget whose
  # dimensions match no published metric renders as an empty chart rather than as an error.
  cluster_name             = module.ecs_cluster.cluster_name
  service_name             = module.ecs_service.service_name
  load_balancer_name       = var.load_balancer_name
  load_balancer_arn_suffix = module.application_load_balancer.arn_suffix
  metric_period            = var.metric_period
  alarm_name               = var.alarm_name
  alarm_threshold          = var.alarm_threshold
  alarm_period             = var.alarm_period
  alarm_evaluation_periods = var.alarm_evaluation_periods
  alarm_actions            = var.alarm_actions

  depends_on = [module.network, module.application_load_balancer, module.ecs_service]
}
# --- README on the workbench ------------------------------------------------------------------------------
locals {
  # Every output this root exposes, defined once. outputs.tf projects this map and the README written onto
  # the workbench renders it, so an output cannot exist without also appearing in that README
  # (rules.md B-5/H-2).
  #
  # The _monolithic template had no outputs at all. Everything a person needed - the code-server URL, the
  # ALB URL, the name of the cluster to query - had to be found in the console, from inside a browser IDE
  # that has no terraform state to ask.
  #
  # Add an entry here first: an output in outputs.tf has nothing to reference without one, so the README
  # cannot fall behind.
  outputs = {
    vscode_url = {
      order       = 1
      title       = "VS Code URL"
      description = "The workbench. Every command below is meant to be run from its terminal, and code-server runs without authentication - so this URL is the credential"
      value       = module.vscode_ec2.vscode_url
    }
    alb_url = {
      order       = 2
      title       = "The application behind the ALB"
      description = "The Flask app from src/monitoring.py, answering on / with Hello ECS"
      value       = module.application_load_balancer.url
    }
    hello_command = {
      order       = 3
      title       = "1. Check the path end to end"
      description = "Ten requests, one status code per line. 200s mean the ALB, the target group, the task and the image are all in place"
      value       = "for i in $(seq 1 10); do curl -s -o /dev/null -w '%%{http_code}\\n' ${module.application_load_balancer.url}/; done"
    }
    error_command = {
      order       = 4
      title       = "2. Produce some 5xx"
      description = "The /error route returns 500 on purpose. alarm_threshold is 2 within one alarm_period of 300 seconds, so five is comfortably over it"
      value       = "for i in $(seq 1 5); do curl -s -o /dev/null -w '%%{http_code}\\n' ${module.application_load_balancer.url}/error; done"
    }
    alarm_state_command = {
      order       = 5
      title       = "3. Watch the alarm turn"
      description = "OK before the step above and ALARM a few minutes after it. The _monolithic template's alarm had an empty dimension map, so it stayed in INSUFFICIENT_DATA whatever the load balancer returned - this is the command that shows the difference"
      value       = module.observability.alarm_state_command
    }
    dashboard_url = {
      order       = 6
      title       = "4. The dashboard"
      description = "ECS CPU and memory on the left, ALB request count and 5xx on the right. The 5xx series fills in from the step above"
      value       = module.observability.dashboard_url
    }
    service_status_command = {
      order       = 7
      title       = "5. Service status"
      description = "Desired against running task counts and the rollout state"
      value       = module.ecs_service.service_status_command
    }
    service_events_command = {
      order       = 8
      title       = "6. Service events"
      description = "The service's own account of what it has been doing. A pull failure or an unhealthy target is reported here before anywhere else"
      value       = module.ecs_service.service_events_command
    }
    target_health_command = {
      order       = 9
      title       = "7. Target health"
      description = "Whether the load balancer can reach the task. Target.Timeout here is a security group path problem rather than an application one, and it is what the _monolithic template's missing egress rules produced"
      value       = module.application_load_balancer.target_health_command
    }
    tail_logs_command = {
      order       = 10
      title       = "8. The container's own output"
      description = "Flask logs one line per request. An addition to the original, whose container definition had no log configuration at all - so on Fargate, with no instance to run docker logs on, a task that failed to start said nothing anywhere"
      value       = module.ecs_service.tail_logs_command
    }
    list_images_command = {
      order       = 11
      title       = "9. What is in the repository"
      description = "One image, pushed by this instance during its bootstrap. An empty table means the build never got as far as pushing, and the reason is in /var/log/cloud-init-output.log on this box"
      value       = module.ecr_repository.list_images_command
    }
    rebuild_command = {
      order       = 12
      title       = "10. Rebuild the image by hand"
      description = "Edit /home/ec2-user/image/monitoring.py, then run this. The task definition names a moving tag, so the push alone changes nothing until the tasks are replaced - which is what the second command does. Keep src/monitoring.py in this repository in step, because the next apply ships that file and not the edited one"
      value       = "cd /home/ec2-user/image && ${module.ecr_repository.docker_login_command} && docker build -t ${module.ecr_repository.image_uri} . && docker push ${module.ecr_repository.image_uri} && ${module.ecs_service.force_redeploy_command}"
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
    ecr_repository_url = {
      order       = 15
      title       = "ECR repository"
      description = "Host and path the workbench pushes to and the task definition pulls from"
      value       = module.ecr_repository.repository_url
    }
    log_group_name = {
      order       = 16
      title       = "Log group"
      description = "Where the container's stdout goes"
      value       = module.ecs_service.log_group_name
    }
    dashboard_name = {
      order       = 17
      title       = "Dashboard name"
      description = "Name of the CloudWatch dashboard"
      value       = module.observability.dashboard_name
    }
    alarm_name = {
      order       = 18
      title       = "Alarm name"
      description = "Name of the 5xx alarm"
      value       = module.observability.alarm_name
    }
    alarm_actions_enabled = {
      order       = 19
      title       = "Alarm notification"
      description = "Whether the alarm has anywhere to notify. False unless the alarm_actions variable was given a topic ARN - the _monolithic template set actions_enabled = true with no actions, which reads as configured notification and delivers nothing"
      value       = tostring(module.observability.actions_enabled)
    }
    private_key_command = {
      order       = 20
      title       = "Workbench SSH key"
      description = "Retrieves the generated private key from Parameter Store into key.pem. CloudFormation puts a key pair it generates there, and this reproduces that"
      value       = module.key_pair.private_key_command
    }
    ssh_command = {
      order       = 21
      title       = "SSH to the workbench"
      description = "For the case where code-server is what is broken. Run the command above first to get key.pem"
      value       = module.vscode_ec2.ssh_command
    }
  }
  # Re-keyed by order so values() returns the sections in reading order rather than alphabetically - which
  # would otherwise put "10. Rebuild the image" above "2. Produce some 5xx".
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
# The README, written onto the workbench because that is where the work happens and there is no terraform
# output inside a browser IDE (rules.md H-2). code-server opens /home/ec2-user, so this file is the first
# thing in the explorer.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  association_name                 = "${var.project_name}-vscode-readme"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on and not wait_for_success_timeout_seconds, is what orders this after the
    # bootstrap (rules.md D-5). The marker path comes back out of the module it was passed into
    # (rules.md B-5).
    #
    # The heredoc terminator is quoted, and chosen as a string that cannot appear in the body: the README
    # contains shell commands, backticks and dollar signs, and Terraform has already substituted every value
    # that needed substituting - so there is nothing left for the shell to expand.
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
