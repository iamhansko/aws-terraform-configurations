data "aws_region" "current" {}
# The two AMI IDs, from the public parameters AWS maintains, as the _monolithic template's two parameters
# resolved them.
#
# insecure_value rather than value: the provider marks every parameter's value sensitive regardless of its
# type, and a sensitive value cannot be used as an instance's ami or a launch template's image_id without
# wrapping it in nonsensitive(). insecure_value is the provider's own accessor for a parameter that is not
# a secret, and a public AMI ID is not one.
#
# Both reads are declared here and the IDs passed into the modules, so each module takes an ami- ID and
# does not have to know where it came from (rules.md B-6). It also keeps them out of modules that carry
# depends_on, which would defer them to apply (rules.md D-6).
data "aws_ssm_parameter" "workbench_ami_id" {
  name = var.workbench_ami_ssm_parameter_name
}
data "aws_ssm_parameter" "container_instance_ami_id" {
  name = var.container_instance_ami_ssm_parameter_name
}
module "network" {
  source = "./modules/network"

  vpc_cidr_block             = var.vpc_cidr_block
  availability_zone_suffixes = var.availability_zone_suffixes
  vpc_name                   = "${var.project_name}-vpc"
  internet_gateway_name      = "${var.project_name}-igw"
  public_subnet_name         = "${var.project_name}-pub"
  public_route_table_name    = "${var.project_name}-pub-rt"
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name_prefix = "${var.project_name}-key-"

  # Uses nothing from network and does not need a VPC to create a key pair. It waits anyway, because the
  # rule is that a root with a network module has no module starting before that module finishes - an
  # exception here would mean the next reader has to decide per module whether an omission was reasoned
  # or forgotten (rules.md D-3).
  depends_on = [module.network]
}
# --- Where the logs go ------------------------------------------------------------------------------
#
# Declared before anything that produces logs, because everything downstream reads its name from here:
# the task definition's FireLens options, the task role's policy, and the verification commands in the
# outputs and the README (rules.md B-5). The _monolithic template declared no log groups at all and left
# the task definition naming two that nothing created.
module "firelens_log_destination" {
  source = "./modules/firelens_log_destination"

  application_log_group_name = var.application_log_group_name
  log_router_log_group_name  = var.log_router_log_group_name
  retention_in_days          = var.log_retention_in_days
  auto_create_group          = var.firelens_auto_create_group
  log_stream_prefix          = var.log_stream_prefix
  policy_name_prefix         = "${var.project_name}-log-router-"

  depends_on = [module.network]
}
# --- The two registries -----------------------------------------------------------------------------
#
# One module instantiated twice. The repositories differ only in their name, so there is nothing about
# either that belongs in a module of its own.
module "application_repository" {
  source = "./modules/ecr_repository"

  name      = "${var.project_name}-ecr"
  image_tag = var.image_tag

  depends_on = [module.network]
}
module "fluentbit_repository" {
  source = "./modules/ecr_repository"

  name      = "${var.project_name}-fluentbit"
  image_tag = var.image_tag

  depends_on = [module.network]
}
# --- The workbench, which is also the build box -----------------------------------------------------
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name                        = "${var.project_name}-bastion"
  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  ami_id                      = data.aws_ssm_parameter.workbench_ami_id.insecure_value
  key_name                    = module.key_pair.key_name
  instance_type               = var.workbench_instance_type
  root_volume_size            = var.workbench_root_volume_size
  code_server_version         = var.code_server_version
  security_group_name         = "${var.project_name}-bastion-sg"
  security_group_description  = "Security group for the ${var.project_name} code-server workbench and image builder"
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  ssh_ingress_cidr_blocks     = var.ssh_ingress_cidr_blocks
  marker_file_path            = var.marker_file_path
  # docker, installed here rather than in the module, because the module must not have to know that this
  # root also builds container images (rules.md B-4/H-1). Building an image needs a daemon on the host,
  # which is the one case where a tool on the workbench is used to create something rather than only to
  # inspect it.
  #
  # usermod rather than "chmod 666 /var/run/docker.sock", which is what the _monolithic template's build
  # script did. Mode 666 on that socket gives every process on the box - including anything reached
  # through the unauthenticated code-server - root-equivalent control of the daemon, and the group
  # membership below is the supported way to get the same convenience (rules.md H-1).
  #
  # The restart is the part that is easy to miss: code-server is already running by this point, started
  # by the module's bootstrap above, so its process has the group list it was launched with. Its
  # integrated terminals inherit that list, and without the restart docker in the IDE fails with a
  # permission error on the socket while docker over SSH works.
  additional_user_data = <<-EOT
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    systemctl restart code-server
    runuser -u ec2-user -- env HOME=/home/ec2-user aws configure set default.region ${data.aws_region.current.region}
  EOT

  depends_on = [module.network, module.key_pair]
}
# --- Building and pushing the two images ------------------------------------------------------------
#
# What the _monolithic template did in one association, split into a build and a check, and reordered so
# that each step waits for the previous one's marker file rather than trusting depends_on or the
# provider's wait to mean "the remote command finished" (rules.md D-5).
#
# The build is here rather than in a module because it reads from four of them - the marker path and the
# instance ID from the workbench, and a repository URL, login command and tag from each registry - and
# combining other modules' outputs is the root's job (rules.md C-1).
resource "aws_ssm_association" "image_build" {
  name                             = "AWS-RunShellScript"
  association_name                 = "${var.project_name}-image-build"
  wait_for_success_timeout_seconds = var.build_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # Three parsers take a turn at this script and knowing which one owns which character is the
    # difference between editing it safely and silently breaking the build.
    #
    #  1. Terraform expands ${...} and %{...} and leaves everything else alone, so every $HOME and
    #     $(...) below reaches the instance intact. There are deliberately no empty lines: <<- strips the
    #     common indentation of the whole template, and keeping every line indented keeps that amount
    #     unambiguous - a line it computed differently would move the heredoc terminators off column
    #     zero and the shell would stop recognising them.
    #  2. The instance's shell writes the files. Every nested delimiter is quoted, so the shell expands
    #     nothing inside them - which is what keeps the Python program's own syntax intact.
    #  3. docker, and then python inside the container.
    #
    # And the file has to be saved with LF endings. A CRLF .tf file puts a carriage return on every
    # literal line in here, so the terminators become TFBUILD\r and TFLOGGENERATOR\r, the shell does not
    # accept them, the heredocs run to the end of the script and not one line executes (rules.md A-4).
    commands = <<-EOT
      set -eu
      # Phase one: wait for the workbench bootstrap. This script needs the docker the userdata installs,
      # and starting before cloud-init has finished also means contending with it for the dnf lock. A
      # bounded until loop rather than a bare test, because a failing test at top level is a non-zero
      # statement and set -e would end the script on the first pass with no output - a failing until
      # condition never triggers it (rules.md D-5).
      waited=0
      until [ -f ${module.vscode_ec2.marker_file_path}/userdata ]; do
        waited=$((waited + 1))
        if [ "$waited" -gt ${var.step_wait_attempts} ]; then
          echo "the workbench bootstrap never finished: ${module.vscode_ec2.marker_file_path}/userdata is still absent. /var/log/cloud-init-output.log on this instance has the reason." >&2
          exit 1
        fi
        sleep ${var.step_wait_interval_seconds}
      done
      # Phase two: build and push, as ec2-user. HOME is set explicitly because this script runs as root
      # and sudo -E preserves the environment, so "~" would still resolve to /root and the build context
      # would land where the code-server session cannot see it.
      sudo -Eu ec2-user bash << 'TFBUILD'
      set -eu
      export HOME=/home/ec2-user
      mkdir -p $HOME/build
      cd $HOME/build
      cat > log_generator.py << 'TFLOGGENERATOR'
      #!/usr/bin/env python3
      import json
      import random
      import time
      from datetime import datetime, timezone
      LOG_LEVELS = ["INFO", "DEBUG", "WARNING", "ERROR", "CRITICAL"]
      MESSAGES = {
          "INFO": "Service started successfully.",
          "DEBUG": "Debugging variable state.",
          "WARNING": "Memory usage nearing limit.",
          "ERROR": "Unable to connect to database.",
          "CRITICAL": "System failure! Immediate action required.",
      }
      def generate_token():
          return "".join(random.choices("abcdefghijklmnopqrstuvwxyz0123456789", k=16))
      def generate_log():
          while True:
              log_level = random.choice(LOG_LEVELS)
              log_entry = {
                  "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
                  "log_level": log_level,
                  "message": MESSAGES[log_level],
              }
              if log_level == "ERROR":
                  log_entry["token"] = generate_token()
              print(json.dumps(log_entry))
              time.sleep(random.uniform(0.5, 2.0))
      if __name__ == "__main__":
          generate_log()
      TFLOGGENERATOR
      cat > Dockerfile.app << 'TFDOCKERFILEAPP'
      FROM ${var.application_base_image}
      WORKDIR /app
      COPY log_generator.py .
      CMD ["python", "-u", "log_generator.py"]
      TFDOCKERFILEAPP
      cat > Dockerfile.fluentbit << 'TFDOCKERFILEFLUENTBIT'
      FROM ${var.fluentbit_base_image}
      TFDOCKERFILEFLUENTBIT
      ${module.application_repository.docker_login_command}
      docker build -f Dockerfile.app -t ${module.application_repository.image_uri} .
      docker push ${module.application_repository.image_uri}
      docker build -f Dockerfile.fluentbit -t ${module.fluentbit_repository.image_uri} .
      docker push ${module.fluentbit_repository.image_uri}
      TFBUILD
      touch ${module.vscode_ec2.marker_file_path}/image_build
      EOT
  }
  depends_on = [module.vscode_ec2, module.application_repository, module.fluentbit_repository]
}
# The check, and it is what the service is actually ordered behind.
#
# This exists because the marker file above only means "the script reached its end", and because
# rules.md D-5 is explicit that wait_for_success_timeout_seconds is not a reliable statement that a
# remote command finished. Asking ECR is the only thing here that distinguishes "the build worked" from
# "the association resource completed".
#
# Without something in this position the service starts immediately and its tasks stop with
# CannotPullContainerError against images that do not exist yet. ECS keeps replacing them, so it does
# eventually recover once the pushes land - which is worse than failing, because the demo looks broken
# for ten minutes and then silently is not.
resource "aws_ssm_association" "images_pushed" {
  name                             = "AWS-RunShellScript"
  association_name                 = "${var.project_name}-images-pushed"
  wait_for_success_timeout_seconds = var.image_verify_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    commands = <<-EOT
      set -u
      # The build exits non-zero on a failed login, build or push, so this marker already means the
      # pushes reported success. What it does not establish is that both images are in both
      # repositories, which is what the loop below asks ECR directly.
      waited=0
      until [ -f ${module.vscode_ec2.marker_file_path}/image_build ]; do
        waited=$((waited + 1))
        if [ "$waited" -gt ${var.step_wait_attempts} ]; then
          echo "the image build never finished: ${module.vscode_ec2.marker_file_path}/image_build is still absent. Read the output of the ${var.project_name}-image-build association on this instance." >&2
          exit 1
        fi
        sleep ${var.step_wait_interval_seconds}
      done
      # Each reference is name:tag, split with cut rather than with shell parameter expansion: the brace
      # form of that expansion is what Terraform reads as an interpolation, so it cannot appear in here.
      for reference in ${module.application_repository.name}:${module.application_repository.image_tag} ${module.fluentbit_repository.name}:${module.fluentbit_repository.image_tag}; do
        repository=$(echo "$reference" | cut -d: -f1)
        tag=$(echo "$reference" | cut -d: -f2)
        found=0
        for attempt in $(seq 1 ${var.image_verify_attempts}); do
          if aws ecr describe-images --region ${data.aws_region.current.region} --repository-name "$repository" --image-ids imageTag="$tag" > /dev/null 2>&1; then
            found=1
            break
          fi
          sleep ${var.step_wait_interval_seconds}
        done
        if [ "$found" -ne 1 ]; then
          echo "$repository has no image tagged $tag although the build reported success. The build association's output on this instance has the reason." >&2
          exit 1
        fi
      done
      touch ${module.vscode_ec2.marker_file_path}/images_pushed
      EOT
  }
  depends_on = [aws_ssm_association.image_build]
}
# --- The cluster, its capacity and the workload -----------------------------------------------------
module "ecs_cluster" {
  source = "./modules/ecs_cluster"

  name               = "${var.project_name}-cluster"
  container_insights = var.container_insights

  depends_on = [module.network]
}
module "ecs_asg_capacity_provider" {
  source = "./modules/ecs_asg_capacity_provider"

  vpc_id = module.network.vpc_id
  # Both public subnets. There are no private ones and no NAT gateway in this VPC, and these instances
  # have to reach the ECS control plane, ECR and - for every record Fluent Bit delivers - CloudWatch
  # Logs. See the network module for why the VPC is shaped that way.
  subnet_ids   = module.network.public_subnet_ids
  cluster_name = module.ecs_cluster.cluster_name
  ami_id       = data.aws_ssm_parameter.container_instance_ami_id.insecure_value
  key_name     = module.key_pair.key_name

  capacity_provider_name       = "${var.project_name}-capacity-provider"
  instance_name                = "${var.project_name}-container-instance"
  instance_type                = var.container_instance_type
  instance_profile_name_prefix = "${var.project_name}-container-instance-"
  security_group_name          = "${var.project_name}-container-instance-sg"
  min_size                     = var.container_instance_min_size
  max_size                     = var.container_instance_max_size
  desired_capacity             = var.container_instance_desired_capacity
  ecs_config_options           = var.ecs_config_options
  # A literal key, so the rule's resource address is known at plan while the workbench's group ID is not
  # (rules.md B-8). This replaces the _monolithic template's rule allowing the VPC's default security
  # group, which nothing in that template was ever placed in - so it admitted nothing. The workbench is
  # a group something is actually in.
  ingress_source_security_groups = {
    workbench = module.vscode_ec2.security_group_id
  }

  # The cluster has to exist before an instance tries to join it, and before the association in this
  # module can attach a capacity provider to it. The cluster name arrives as a variable and is
  # interpolated into the launch template userdata, so that much is already ordered; module-level
  # depends_on is what covers the rest of the cluster module (rules.md D-2, D-3).
  depends_on = [module.network, module.ecs_cluster, module.key_pair]
}
module "ecs_firelens_service" {
  source = "./modules/ecs_firelens_service"

  cluster_name           = module.ecs_cluster.cluster_name
  service_name           = "${var.project_name}-svc"
  task_family            = "${var.project_name}-ecs-td"
  capacity_provider_name = module.ecs_asg_capacity_provider.capacity_provider_name
  desired_count          = var.service_desired_count
  task_cpu               = var.task_cpu
  task_memory            = var.task_memory
  # Both images read back from the repository modules, so the tag the build pushed and the tag the task
  # pulls cannot differ (rules.md B-5). A mismatch is not an error anywhere - it is a service whose tasks
  # stop with CannotPullContainerError while the images sit in the repositories under another tag.
  application_image_uri = module.application_repository.image_uri
  log_router_image_uri  = module.fluentbit_repository.image_uri
  # The whole log configuration for both containers, taken from the module that created the groups and
  # wrote the policy. That is what keeps the destination in the task definition, the destination in the
  # IAM policy and the destination in the README's verification command one value (rules.md B-5).
  application_firelens_options = module.firelens_log_destination.application_firelens_options
  log_router_awslogs_options   = module.firelens_log_destination.log_router_awslogs_options
  log_router_environment       = { FLB_LOG_LEVEL = var.fluentbit_log_level }
  # A map rather than a list, because this ARN is another module's output and so is unknown at plan time
  # (rules.md B-8). It replaces the CloudWatchFullAccessV2 the _monolithic template attached to this role
  # (rules.md A-5).
  task_role_policy_arns = {
    firelens_log_router = module.firelens_log_destination.log_router_policy_arn
  }
  wait_for_steady_state = var.wait_for_steady_state

  # Four things have to be true before this service can place a running task, and only one of them is
  # implied by a value reference (rules.md D-2):
  #
  #   - both images have to exist, which is what the verification association establishes. This is the
  #     edge the _monolithic template got from depends_on on its single build association, and that
  #     association's own completion is not a statement that the build finished (rules.md D-5).
  #   - the capacity provider has to be attached to the cluster, which is the association inside
  #     ecs_asg_capacity_provider, and a container instance has to have registered.
  #     capacity_provider_name orders this after the provider resource alone, not after either of those.
  #   - both log groups have to exist. The group names arrive inside an options map, so they are strings
  #     rather than references here: without this edge the first task can start before the groups do,
  #     and the awslogs driver's response to a missing group is to fail the log router's container start,
  #     which takes the whole task with it.
  #   - network, for the uniform reason and because the instances' route to the internet gateway is what
  #     lets them register at all (rules.md D-3).
  #
  # The order matters in reverse too. On destroy this module goes first, which is what lets ECS delete
  # the capacity provider afterwards - it refuses while a service's strategy still names it - and what
  # stops the log groups being deleted out from under a task that is still delivering to them.
  depends_on = [
    module.network,
    module.ecs_cluster,
    module.ecs_asg_capacity_provider,
    module.firelens_log_destination,
    aws_ssm_association.images_pushed,
  ]
}
# --- README on the workbench ------------------------------------------------------------------------
locals {
  # Every output this root exposes, defined once. outputs.tf projects this map and the README written
  # onto the workbench renders it, so an output cannot exist without also appearing in that README
  # (rules.md H-2). The _monolithic template had one output - the code-server URL - which meant a person
  # inside that IDE could not see the cluster name, the log group, or any command for checking whether a
  # record had arrived.
  outputs = {
    vscode_url = {
      order       = 1
      title       = "VS Code URL"
      description = "The workbench. Every numbered command below is meant to be run from its terminal, and the AWS CLI there is already pointed at this region"
      value       = module.vscode_ec2.vscode_url
    }
    ecs_cluster_name = {
      order       = 2
      title       = "ECS cluster"
      description = "Name of the cluster running the logging task"
      value       = module.ecs_cluster.cluster_name
    }
    ecs_service_name = {
      order       = 3
      title       = "ECS service"
      description = "Name of the service. It has no load balancer and publishes no port, which is correct: the application is a loop that prints a JSON line and sleeps, so there is nothing to serve and nothing to health-check"
      value       = module.ecs_firelens_service.service_name
    }
    application_log_group_name = {
      order       = 4
      title       = "Where the logs go"
      description = "The log group the application's lines end up in. The path is: the container prints JSON to stdout, the fluentd log driver hands each line to the Fluent Bit sidecar over a Unix socket in the task, and Fluent Bit's cloudwatch_logs output plugin calls PutLogEvents against this group. Terraform creates the group, so it has a retention and it goes away with terraform destroy - the _monolithic template let Fluent Bit create it at runtime instead, which left it behind after every teardown"
      value       = module.firelens_log_destination.application_log_group_name
    }
    log_router_log_group_name = {
      order       = 5
      title       = "Where the log router's own output goes"
      description = "Fluent Bit cannot report its own failures through itself, so its stdout goes to this group by the ordinary awslogs driver. When the group above is empty, this one holds the reason"
      value       = module.firelens_log_destination.log_router_log_group_name
    }
    tail_application_logs_command = {
      order       = 6
      title       = "1. Watch the records arrive"
      description = "The result of the project, live. One line per record Fluent Bit delivered, from two tasks at once. Silence here while the service reports two running tasks means the pipeline rather than the application, and the next thing to read is step 4"
      value       = module.firelens_log_destination.tail_application_logs_command
    }
    read_one_record_command = {
      order       = 7
      title       = "2. Read one record in full"
      description = "What arrives is not the application's JSON but FireLens's envelope around it: container_id, container_name, source, ecs_cluster, ecs_task_arn, ecs_task_definition and ec2_instance_id, with the application's own line as a string in the \"log\" field. Seeing that envelope is how you know the record came through the log router rather than the awslogs driver"
      value       = module.firelens_log_destination.read_one_record_command
    }
    find_error_records_command = {
      order       = 8
      title       = "3. Find the records carrying a token"
      description = "The application adds a random \"token\" field to its ERROR lines and to no others. This is the demo's argument for a log router: a field you would want redacted, or sent somewhere other than CloudWatch, is visible here - and changing where it goes is an options change in the task definition rather than an application change"
      value       = module.firelens_log_destination.find_error_records_command
    }
    tail_log_router_logs_command = {
      order       = 9
      title       = "4. The log router's own output"
      description = "Fluent Bit's version banner, the output plugin it loaded, the destination it resolved, and any delivery error. An AccessDeniedException or a missing-group error from CloudWatch Logs appears here and nowhere else - ECS reports the task as healthy throughout. This group is only useful because FLB_LOG_LEVEL is info; at the error level the _monolithic template set, a working pipeline writes nothing here and so looks exactly like a broken one"
      value       = module.firelens_log_destination.tail_log_router_logs_command
    }
    describe_task_definition_command = {
      order       = 10
      title       = "5. Where the task definition actually sends logs"
      description = "The registered log configuration for both containers, as ECS stored it. This is the authoritative answer to \"where are the logs going\": these options are exactly what the agent turns into the Fluent Bit configuration file, and a misspelled option name is accepted silently by plan, by apply and by the service"
      value       = module.ecs_firelens_service.describe_task_definition_command
    }
    service_status_command = {
      order       = 11
      title       = "6. Service status"
      description = "Desired against running counts and the rollout state"
      value       = module.ecs_firelens_service.service_status_command
    }
    service_events_command = {
      order       = 12
      title       = "7. Service events"
      description = "The service's own account of what it has been trying to do. Most failures here land in this list rather than anywhere in Terraform"
      value       = module.ecs_firelens_service.service_events_command
    }
    stopped_task_reason_command = {
      order       = 13
      title       = "8. Why a task stopped"
      description = "Per container, which matters because both are essential - either one stopping takes the task with it. CannotPullContainerError means the build never pushed; a logging driver failure on the log router means its log group or the permission for it"
      value       = module.ecs_firelens_service.stopped_task_reason_command
    }
    running_task_placement_command = {
      order       = 14
      title       = "9. Where the tasks landed"
      description = "Two task ARNs is what makes step 2 interesting: each task has its own Fluent Bit sidecar and its own log stream, so the per-task metadata in the records differs between them"
      value       = module.ecs_firelens_service.running_task_placement_command
    }
    container_instances_command = {
      order       = 15
      title       = "10. Which container instances registered"
      description = "An empty list alongside a healthy Auto Scaling group is the signature of instances with no outbound path or without the container instance role - and because an instance that never registers never becomes an ECS object, nothing reports it as an error"
      value       = module.ecs_cluster.container_instances_command
    }
    container_instance_session_command = {
      order       = 16
      title       = "11. A shell on a container instance"
      description = "Two things are worth looking at from there: /var/log/ecs/ecs-agent.log for why an instance did not register, and /var/lib/ecs/data/firelens/<task-id>/config, which is the Fluent Bit configuration file the agent generated from the task definition's log options"
      value       = module.ecs_asg_capacity_provider.session_command
    }
    application_image_uri = {
      order       = 17
      title       = "Application image"
      description = "Built on the workbench from a four-line Dockerfile around the log generator, and pushed here. The CMD runs python with -u: without it stdout is block-buffered into an 8 KB pipe, so roughly eighty lines pile up before any of them is written and the stream arrives in bursts a minute and a half apart - which for a logging demo is indistinguishable from a broken pipeline"
      value       = module.ecs_firelens_service.application_image_uri
    }
    log_router_image_uri = {
      order       = 18
      title       = "Log router image"
      description = "AWS's published aws-for-fluent-bit image, pulled and re-pushed into a private repository under this tag. The Dockerfile is a single FROM line and nothing else - no configuration is baked in, because FireLens generates the configuration file and mounts it over /fluent-bit/etc/fluent-bit.conf at task start, which is what makes a bare re-tag work"
      value       = module.ecs_firelens_service.log_router_image_uri
    }
    list_application_images_command = {
      order       = 19
      title       = "12. Images in the application repository"
      description = "An empty table means the build never got as far as pushing, and the reason is in the image-build association's output rather than anywhere in ECS"
      value       = module.application_repository.list_images_command
    }
    list_fluentbit_images_command = {
      order       = 20
      title       = "13. Images in the log router repository"
      description = "Same check for the other half. The sizes differ by roughly an order of magnitude, which is the quickest way to tell at a glance that the two Dockerfiles did not get swapped"
      value       = module.fluentbit_repository.list_images_command
    }
    private_key_command = {
      order       = 21
      title       = "Workbench SSH key"
      description = "Retrieves the generated private key from Parameter Store. SSH is open on the workbench by default, but this is mostly for the case where the SSM agent is what is broken - in which case none of the associations ran either"
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
# The last step in the marker chain, so the presence of this file means the images are in both
# repositories and the demo is ready to read (rules.md D-5/H-2).
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  association_name                 = "${var.project_name}-readme"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is what orders this after the
    # verification step (rules.md D-5). The marker path comes back out of the module it was passed into
    # (rules.md B-5). SSM runs this as root, so the chown is what lets code-server edit the file.
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/images_pushed ]; do sleep ${var.step_wait_interval_seconds}; done
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_readme
      EOT
  }
  depends_on = [aws_ssm_association.images_pushed]
}
