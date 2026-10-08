data "aws_region" "current" {}
# The two AMI ids, from the public parameters AWS maintains.
#
# insecure_value rather than value: the provider marks value sensitive for every parameter regardless of
# its type, and a sensitive value cannot be used for an instance's ami or a launch template's image_id
# without wrapping it in nonsensitive(). insecure_value is the provider's own accessor for a parameter
# that is not a secret, and a public AMI id is not one.
#
# Both are declared here and the ids passed into the modules, so that each module takes an ami- id and
# does not have to know where it came from (rules.md B-6). It also keeps these reads out of modules that
# carry depends_on, which would defer them to apply (rules.md D-6) - harmless for an AMI id, but there is
# no reason to take it on.
data "aws_ssm_parameter" "builder_ami_id" {
  name = var.builder_ami_ssm_parameter_name
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
  nat_gateway_name           = "${var.project_name}-natgw"
  public_subnet_name         = "${var.project_name}-public"
  private_subnet_name        = "${var.project_name}-private"
  public_route_table_name    = "${var.project_name}-public-rt"
  private_route_table_name   = "${var.project_name}-private-rt"
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name_prefix = "${var.project_name}-"

  # This module uses nothing from network and does not need a VPC to create a key pair. It waits anyway,
  # because the rule is that a root with a network module has no module starting before that module
  # finishes - an exception here would mean the next reader has to decide per module whether the omission
  # was reasoned or forgotten (rules.md D-3).
  depends_on = [module.network]
}
module "ecr_repository" {
  source = "./modules/ecr_repository"

  # CloudFormation generated this name; Terraform requires one, so it comes from the project name. The
  # _monolithic template built "${stack_name}-ecr-repository" the same way.
  name      = "${var.project_name}-ecr-repository"
  image_tag = var.image_tag

  # Also uses nothing from network, and also waits, for the reason above (rules.md D-3).
  depends_on = [module.network]
}
module "ecs_cluster" {
  source = "./modules/ecs_cluster"

  name               = "${var.project_name}-ecs-cluster"
  container_insights = var.container_insights

  depends_on = [module.network]
}
# The builder, which is the only thing in this root that produces the image everything else consumes.
module "image_builder_ec2" {
  source = "./modules/image_builder_ec2"

  vpc_id = module.network.vpc_id
  # The public subnet: the build pulls the docker package, the JDK base image from Docker Hub and an ECR
  # token, and pushes the result - all from userdata, all outbound.
  subnet_id = module.network.public_subnet_a_id
  ami_id    = data.aws_ssm_parameter.builder_ami_id.insecure_value
  key_name  = module.key_pair.key_name

  instance_name              = var.project_name
  instance_type              = var.builder_instance_type
  root_volume_size           = var.builder_root_volume_size
  security_group_name        = "${var.project_name}-builder-sg"
  security_group_description = "Security group for the arm64 image builder instance"
  ssh_ingress_cidr_blocks    = var.builder_ssh_ingress_cidr_blocks

  # Both taken from the repository module rather than restated, so the push, the verification step below
  # and the task definition's pull are one value (rules.md B-5).
  ecr_image_uri    = module.ecr_repository.image_uri
  ecr_registry_url = module.ecr_repository.registry_url

  java_base_image      = var.java_base_image
  container_mount_path = var.container_mount_path
  write_size_mb        = var.write_size_mb
  retained_file_count  = var.retained_file_count
  # The completion marker the association below polls for (rules.md B-4).
  marker_file_path = var.marker_file_path

  # network for the usual reason (rules.md D-3), and here it is also load-bearing rather than only
  # uniform: vpc_id and subnet_id order this after the VPC and that one subnet, and the route to the
  # internet gateway is exactly the sort of resource that ordering misses. cloud-init runs dnf within
  # seconds of the launch, so losing that race means no docker, no image and an ECS service with nothing
  # to pull - and the userdata does not stop on error, so it proceeds to write its marker anyway.
  depends_on = [module.network, module.key_pair, module.ecr_repository]
}
# What the CloudFormation CreationPolicy used to do.
#
# The template held the stack at the builder instance until cfn-signal reported from inside its userdata,
# which is how the task definition and the service came to be created only after an image existed. The
# conversion dropped it - its own comment says the CreationPolicy is not reproduced - and left the task
# definition with depends_on = [aws_instance.ec2], which in Terraform is satisfied as soon as the instance
# is running. That is minutes before docker is even installed.
#
# Without something here, the service starts immediately and its tasks stop with CannotPullContainerError
# against an image that does not exist yet. ECS keeps replacing them, so it does eventually recover on its
# own once the push lands - which is worse than failing, because the demo looks broken for ten minutes and
# then silently is not.
#
# So: wait for the marker, then ask the repository. Two phases rather than one because they fail for
# different reasons and the message should say which (rules.md D-5 for the marker-and-loop shape, which
# this repository uses instead of trusting depends_on or a provider timeout to mean "the remote command
# finished").
#
# The ECR check is the part that matters. The marker only says the script reached its end - it does not
# stop on error - so a failed docker login or a build that ran the disk out of space still writes it.
# Asking ECR is the only thing here that distinguishes "the build worked" from "the script finished".
#
# The wait only happens on create. The provider honours wait_for_success_timeout_seconds in
# CreateAssociation and not in UpdateAssociation, so when the builder is replaced - which any change to
# its userdata now does - an association that merely had its target updated would return at once,
# re-run on its own in the background, and let the service below go ahead against an image the new
# builder has not pushed yet. This resource carries the builder's instance id so that a new builder
# replaces the association instead of updating it, which puts it back on the path that waits.
resource "terraform_data" "image_builder_instance" {
  triggers_replace = module.image_builder_ec2.instance_id
}
resource "aws_ssm_association" "image_pushed" {
  name                             = "AWS-RunShellScript"
  association_name                 = "${var.project_name}-image-pushed"
  wait_for_success_timeout_seconds = var.image_wait_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.image_builder_ec2.instance_id]
  }
  parameters = {
    commands = <<-EOT
      set -u

      MARKER=${module.image_builder_ec2.marker_file}

      # Phase one: the marker. An until loop rather than "[ -f ... ] && break" inside a for, because a
      # bare test that fails is a non-zero statement at top level - and if the shell SSM runs this with
      # has -e set, that ends the script on the first pass with no output. A failing until condition never
      # triggers -e, which is why rules.md D-5's shape is an until loop and not a test.
      waited=0
      until [ -f "$MARKER" ]; do
        waited=$((waited + 1))
        if [ "$waited" -gt ${var.image_wait_attempts} ]; then
          echo "builder userdata never finished: $MARKER is still absent. Read /var/log/cloud-init-output.log on this instance." >&2
          exit 1
        fi
        sleep ${var.image_wait_interval_seconds}
      done

      # Phase two: the repository. A command that fails as an if condition is also exempt from -e.
      for attempt in $(seq 1 ${var.image_wait_attempts}); do
        if aws ecr describe-images --region ${data.aws_region.current.region} --repository-name ${module.ecr_repository.name} --image-ids imageTag=${module.ecr_repository.image_tag} > /dev/null 2>&1; then
          touch ${var.marker_file_path}/image_pushed
          exit 0
        fi
        sleep ${var.image_wait_interval_seconds}
      done

      echo "${module.ecr_repository.image_uri} is not in the repository although the builder script finished. The build or the push failed; /var/log/cloud-init-output.log on this instance has the reason." >&2
      exit 1
      EOT
  }

  lifecycle {
    replace_triggered_by = [terraform_data.image_builder_instance]
  }
}
module "ecs_asg_capacity_provider" {
  source = "./modules/ecs_asg_capacity_provider"

  vpc_id = module.network.vpc_id
  # Private subnets, so outbound goes through the regional NAT gateway. The ECS agent cannot register an
  # instance it cannot reach the ECS endpoint from, and an instance that never registers is absent rather
  # than broken - see the module for what that looks like.
  subnet_ids   = module.network.private_subnet_ids
  cluster_name = module.ecs_cluster.cluster_name
  ami_id       = data.aws_ssm_parameter.container_instance_ami_id.insecure_value
  key_name     = module.key_pair.key_name

  capacity_provider_name = "${var.project_name}-capacity-provider"
  instance_name          = "${var.project_name}-container-instance"
  security_group_name    = "${var.project_name}-container-instance-sg"
  instance_types         = var.container_instance_types
  min_size               = var.container_instance_min_size
  max_size               = var.container_instance_max_size
  desired_capacity       = var.container_instance_desired_capacity
  root_volume_size       = var.container_instance_root_volume_size
  ecs_config_options     = var.ecs_config_options
  # The launch template creates this directory and the task definition mounts it - one value to both
  # (rules.md B-5).
  host_volume_path = var.host_volume_path

  # The cluster has to exist before an instance tries to join it, and before the association in this
  # module can attach a capacity provider to it. The cluster name arrives as a variable and is
  # interpolated into the launch template userdata, so that part is already ordered; module-level
  # depends_on is what covers the rest of the cluster module (rules.md D-2, D-3).
  depends_on = [module.network, module.ecs_cluster, module.key_pair]
}
module "ecs_service" {
  source = "./modules/ecs_service"

  cluster_name = module.ecs_cluster.cluster_name
  service_name = "${var.project_name}-ecs-service"
  # Read in the root, where nothing defers it. Inside the module, its depends_on below would push the read
  # to apply and turn container_definitions unknown, replacing the task definition on every such apply
  # (rules.md D-6).
  region         = data.aws_region.current.region
  log_group_name = "/ecs/${var.project_name}"
  # The _monolithic template used the literal "/ecs/task" here, which collides between two copies of this
  # project in one account - and the collision is at apply, with ResourceAlreadyExistsException.
  log_retention_in_days = var.log_retention_in_days

  image_uri              = module.ecr_repository.image_uri
  capacity_provider_name = module.ecs_asg_capacity_provider.capacity_provider_name

  desired_count = var.service_desired_count
  task_cpu      = var.task_cpu
  task_memory   = var.task_memory
  # The same two paths the builder baked into the image and the launch template created on the host
  # (rules.md B-5). Nothing checks that they agree: a container writing to a path the task definition does
  # not mount writes into its own layer and the host directory stays empty, with the task reporting
  # healthy throughout.
  host_volume_path     = var.host_volume_path
  container_mount_path = var.container_mount_path

  wait_for_steady_state = var.wait_for_steady_state

  # Three things have to be true before this service can place a task, and only one of them is implied by
  # a value reference.
  #
  #   - the capacity provider has to be attached to the cluster, which is the association inside
  #     ecs_asg_capacity_provider, and container instances have to have registered. capacity_provider_name
  #     orders this after the provider resource alone, not after either of those (rules.md D-2)
  #   - the image has to exist, which is what the verification association above establishes - this is
  #     the edge the CloudFormation CreationPolicy used to provide
  #   - network, for the uniform reason and because the instances' route to the NAT gateway is what lets
  #     them register at all (rules.md D-3)
  #
  # The order also matters in reverse. On destroy this module goes first, which is what lets ECS delete
  # the capacity provider afterwards - it refuses while a service's strategy still names it.
  depends_on = [
    module.network,
    module.ecs_asg_capacity_provider,
    aws_ssm_association.image_pushed,
  ]
}
