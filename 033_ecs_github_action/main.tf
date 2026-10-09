data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
# Both AMI IDs, resolved here rather than inside the modules that launch from them.
#
# insecure_value rather than value: the provider marks a parameter's value sensitive whatever its type, and
# a sensitive value cannot be used for an instance's ami or a launch template's image_id without wrapping
# it in nonsensitive(). insecure_value is the provider's own accessor for a parameter that is not a secret,
# and a public AMI ID is not one.
#
# Reading them at the root keeps them out of modules that carry depends_on, which would defer the read to
# apply (rules.md D-6) - harmless for an AMI ID, but there is no reason to take it on - and it means each
# module takes an ami- ID without having to know where it came from (rules.md B-6).
data "aws_ssm_parameter" "bastion_ami_id" {
  name = var.bastion_ami_ssm_parameter_name
}
data "aws_ssm_parameter" "ecs_ami_id" {
  name = var.ecs_ami_ssm_parameter_name
}
# The suffix that makes the account-unique names unique per deployment, standing in for the slice the
# _monolithic template took out of its stand-in for AWS::StackId. See providers.tf for why the random
# provider survived this conversion when it usually does not.
resource "random_id" "name_suffix" {
  byte_length = var.name_suffix_byte_length
}
locals {
  name_suffix = random_id.name_suffix.hex
  # The CodeBuild project name, which the generated workflow's runs-on label is built from. Assembled once
  # here; the label itself comes back out of the runner module so the two cannot drift (rules.md B-5).
  code_build_project_name = "${var.code_build_project_name}${local.name_suffix}"
  repository_clone_url    = "https://github.com/${var.git_hub_user}/${var.git_hub_repo}.git"
  # Where the files are assembled on the workbench, and the git working tree the seed commit is made from.
  repository_directory = "/home/ec2-user/${var.git_hub_repo}"
}
# --- Network and the things that only need an account ------------------------------------------------------
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
  private_route_table_name   = "${var.project_name}-private"
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name_prefix = "${var.project_name}-"

  # Uses nothing from network and does not need a VPC to create a key pair. It waits anyway, because the
  # rule is that a root with a network module has no module starting before that module finishes - an
  # exception here would mean the next reader deciding per module whether an omission was reasoned
  # (rules.md D-3).
  depends_on = [module.network]
}
module "ecr_repository" {
  source = "./modules/ecr_repository"

  name      = "${var.project_name}-ecr"
  image_tag = var.ecr_image_tag

  depends_on = [module.network]
}
module "github_source" {
  source = "./modules/github_source"

  connection_name      = var.code_star_connection_name
  github_user          = var.git_hub_user
  github_token         = var.git_hub_token
  token_parameter_name = "/${var.project_name}/${local.name_suffix}/github-token"
  bucket_prefix        = var.source_bucket_prefix
  force_destroy        = var.force_destroy_source_bucket

  depends_on = [module.network]
}
# --- The workbench ----------------------------------------------------------------------------------------
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name                        = var.bastion_instance_name
  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  ami_id                      = data.aws_ssm_parameter.bastion_ami_id.insecure_value
  key_name                    = module.key_pair.key_name
  instance_type               = var.bastion_instance_type
  root_volume_size            = var.bastion_root_volume_size
  code_server_version         = var.code_server_version
  code_server_port            = var.code_server_port
  ssh_port                    = var.bastion_ssh_port
  security_group_name         = var.bastion_security_group_name
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  marker_file_path            = var.marker_file_path

  # docker, because this instance builds and pushes the seed image, and zip because the second association
  # zips the assembled repository for the source bucket. git comes from the module's own bootstrap.
  #
  # The group change and the restart are the two halves of rules.md H-1's docker note, and they replace
  # what the _monolithic template did here:
  #
  #   chmod 666 /var/run/docker.sock
  #
  # That makes the daemon socket world-writable, and write access to the docker socket is root on this host
  # - any user or process can start a privileged container that mounts the root filesystem. On a box whose
  # editor is served without authentication that is the whole instance, and the IAM role on it carries
  # AdministratorAccess.
  additional_user_data = <<-EOT
    dnf install -yq docker zip
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server is already running by the time the group is added, and a running process does not pick
    # up a new supplementary group for its user. Without this restart the IDE terminal still fails with
    # "permission denied while trying to connect to the Docker daemon socket", which is exactly the
    # symptom the chmod above was reaching for.
    systemctl restart code-server
    # A region for ec2-user, so the associations below and the commands in the README work as written.
    # The CLI can fall back to the instance metadata service for a region, but every command here runs
    # under "sudo -u ec2-user" with a reset environment, and a missing region surfaces as "You must
    # specify a region" rather than as anything about the environment.
    runuser -u ec2-user -- env HOME=/home/ec2-user aws configure set default.region ${data.aws_region.current.region}
  EOT

  depends_on = [module.network, module.key_pair]
}
# --- The cluster and its capacity ------------------------------------------------------------------------
module "ecs_cluster" {
  source = "./modules/ecs_cluster"

  name               = "${var.project_name}-cluster"
  container_insights = var.container_insights

  depends_on = [module.network]
}
module "ecs_asg_capacity_provider" {
  source = "./modules/ecs_asg_capacity_provider"

  vpc_id       = module.network.vpc_id
  subnet_ids   = module.network.private_subnet_ids
  cluster_name = module.ecs_cluster.cluster_name
  ami_id       = data.aws_ssm_parameter.ecs_ami_id.insecure_value
  key_name     = module.key_pair.key_name

  # A variable of its own rather than "${var.project_name}-ecs-ec2-capacity-provider". With the default
  # project_name that string starts with "ecs", which ECS reserves for capacity provider names - the
  # _monolithic template only got away with the pattern because its stack_name was codedeploy-bluegreen.
  capacity_provider_name = var.capacity_provider_name
  instance_name          = var.container_instance_name
  security_group_name    = var.container_instance_security_group_name
  instance_type          = var.container_instance_type
  min_size               = var.container_instance_min_size
  max_size               = var.container_instance_max_size
  desired_capacity       = var.container_instance_desired_capacity
  root_volume_size       = var.container_instance_root_volume_size
  # A literal key, so the rule's resource address is known at plan while the group ID behind it is not
  # (rules.md B-8).
  ingress_source_security_groups = {
    vpc_default = module.network.default_security_group_id
  }

  # The cluster has to exist before an instance tries to join it, and before the association inside this
  # module can attach a capacity provider to it. cluster_name orders this after the cluster resource;
  # module-level depends_on covers the rest of that module (rules.md D-2/D-3).
  depends_on = [module.network, module.ecs_cluster, module.key_pair]
}
# --- The load balancer, the blue/green pair and the listener ---------------------------------------------
module "application_load_balancer" {
  source = "./modules/application_load_balancer"

  name                        = var.load_balancer_name
  vpc_id                      = module.network.vpc_id
  vpc_cidr_block              = module.network.vpc_cidr_block
  subnet_ids                  = module.network.public_subnet_ids
  listener_port               = var.listener_port
  target_port                 = var.container_port
  target_group_names          = var.target_group_names
  initial_target_group_key    = var.initial_target_group_key
  health_check_path           = var.health_check_path
  security_group_name         = var.load_balancer_security_group_name
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere

  depends_on = [module.network]
}
# --- The service ------------------------------------------------------------------------------------------
module "ecs_service" {
  source = "./modules/ecs_service"

  name         = "${var.project_name}-service"
  cluster_name = module.ecs_cluster.cluster_name
  vpc_id       = module.network.vpc_id
  subnet_ids   = module.network.private_subnet_ids
  # The group the listener forwards to at creation, handed over by the module that made that choice rather
  # than chosen again here (rules.md B-5). The service, the listener and CodeDeploy all have to agree on
  # which half of the pair is live to begin with.
  target_group_arn = module.application_load_balancer.initial_target_group_arn
  container_name   = var.container_name
  # The tagged reference, so the workbench's push and this pull are one value (rules.md B-5).
  container_image = module.ecr_repository.image_uri
  # Read back from the load balancer module, so the container port, the target groups' port and the ALB's
  # egress rule cannot end up as three different numbers (rules.md B-5).
  container_port        = module.application_load_balancer.target_port
  health_check_path     = module.application_load_balancer.health_check_path
  task_family           = var.task_family
  task_cpu              = var.task_cpu
  task_memory           = var.task_memory
  desired_count         = var.service_desired_count
  security_group_name   = var.service_security_group_name
  wait_for_steady_state = var.wait_for_steady_state
  container_port_ingress_source_security_groups = {
    alb        = module.application_load_balancer.security_group_id
    vscode_ec2 = module.vscode_ec2.security_group_id
  }
  all_traffic_ingress_source_security_groups = {
    vpc_default = module.network.default_security_group_id
  }

  # Four edges no value reference provides (rules.md D-2):
  #   - application_load_balancer as a whole, because the deployment group's prod_traffic_route names the
  #     listener and target_group_arn only orders this after one target group
  #   - ecs_asg_capacity_provider as a whole, because a service with launch_type EC2 needs a registered
  #     container instance to place its task on, and the capacity provider association is what makes the
  #     cluster able to add one
  #   - the seed image, standing where the CloudFormation CreationPolicy on the bastion used to be. This
  #     edge orders the API calls and the destroy, and it does not hold the service back until the image
  #     exists. image_seeded is created seconds after the instance launches, before its SSM agent has
  #     registered, and at that point the association reports Overview.Status "Success" with no target
  #     counted - which the provider's waiter accepts, so it returns "Creation complete after 6s" while
  #     the command is still Pending (the provider issue rules.md D-5 records; 102_windows_rdp measured
  #     the same). On this project's first apply the service was created at 23:25:32, the seed image
  #     landed at 23:26:48, and the first task's pull failed with "manifest unknown" before the agent's
  #     retry pulled it at 23:26:57. It recovers on its own because the push lands within the agent's
  #     retries or ECS replaces the task; a much slower bootstrap shows CannotPullContainerError in the
  #     service events until the push lands
  #   - ecs_cluster as a whole
  #
  # And in reverse on destroy: the service goes before the capacity provider, which is what lets ECS delete
  # the provider at all - it refuses while a service still names it.
  depends_on = [
    module.network,
    module.ecs_cluster,
    module.ecs_asg_capacity_provider,
    module.application_load_balancer,
    aws_ssm_association.image_seeded,
  ]
}
# --- CodeDeploy and the runner ---------------------------------------------------------------------------
module "code_deploy_blue_green" {
  source = "./modules/code_deploy_blue_green"

  application_name                 = var.code_deploy_application_name
  deployment_group_name            = var.code_deploy_deployment_group_name
  cluster_name                     = module.ecs_cluster.cluster_name
  service_name                     = module.ecs_service.service_name
  production_listener_arn          = module.application_load_balancer.listener_arn
  blue_target_group_name           = module.application_load_balancer.blue_target_group_name
  green_target_group_name          = module.application_load_balancer.green_target_group_name
  deployment_config_name           = var.deployment_config_name
  termination_wait_time_in_minutes = var.termination_wait_time_in_minutes

  depends_on = [module.network, module.application_load_balancer, module.ecs_service]
}
module "code_build_runner" {
  source = "./modules/code_build_runner"

  project_name         = local.code_build_project_name
  repository_clone_url = local.repository_clone_url
  default_branch       = var.git_hub_branch
  # The same value the generated workflow's name field uses. GitHub matches the webhook's WORKFLOW_NAME
  # filter against it exactly, and a mismatch leaves jobs queued with nothing logged (rules.md B-5).
  workflow_name                     = var.git_hub_action
  cluster_name                      = module.ecs_cluster.cluster_name
  service_name                      = module.ecs_service.service_name
  ecr_repository_arn                = module.ecr_repository.arn
  code_deploy_application_name      = module.code_deploy_blue_green.application_name
  code_deploy_deployment_group_name = module.code_deploy_blue_green.deployment_group_name
  deployment_config_name            = var.deployment_config_name
  # The two roles a task definition registered by this build may name, so iam:PassRole covers exactly
  # those rather than every role in the account (rules.md A-5/B-5).
  task_definition_role_arns = [
    module.ecs_service.task_role_arn,
    module.ecs_service.task_execution_role_arn,
  ]
  additional_policy_arns = var.code_build_additional_policy_arns

  # The source credential has to exist before a project whose source type is GITHUB can be created, and it
  # lives in the github_source module - no value reference says so (rules.md D-2).
  depends_on = [
    module.network,
    module.github_source,
    module.ecs_service,
    module.code_deploy_blue_green,
  ]
}
# --- What the workbench writes ---------------------------------------------------------------------------
#
# The application, the Dockerfile, the workflow and the appspec are all defined here rather than inside a
# module, because each one is assembled out of five modules' outputs and joining modules is the root's job
# (rules.md C-1). They are then interpolated into the associations below, each on a line of its own at the
# heredoc's base indentation - which is what makes the dedent land the whole value at column zero and
# leaves the nested shell heredoc terminators where the shell can see them (rules.md A-4).
locals {
  app_source = <<-EOT
    from flask import Flask

    app = Flask(__name__)

    TAG = "${var.app_initial_tag}"

    @app.route("/")
    def home():
        return "${var.app_greeting}", 200

    @app.route("${var.health_check_path}")
    def health():
        return "OK", 200

    @app.route("/tag")
    def tag():
        return TAG, 200

    if __name__ == "__main__":
        app.run(host="0.0.0.0", port=${var.container_port})
    EOT
  # curl is installed because the task definition's container health check is a curl against the health
  # path; without it every container reports unhealthy while answering requests normally.
  dockerfile = <<-EOT
    FROM ${var.python_base_image}
    WORKDIR /app
    COPY cicd-app.py .
    RUN pip install --no-cache-dir Flask
    RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
    CMD ["python", "cicd-app.py"]
    EOT
  # The workflow, built as an object and rendered with yamlencode rather than written as indented text.
  #
  # It is thirty lines of nested YAML assembled from eight interpolated values, and hand-indenting that
  # inside a Terraform heredoc that is itself inside two shell heredocs is how a workflow ends up
  # syntactically valid and semantically wrong. yamlencode cannot produce mis-indented YAML.
  #
  # "$${{" throughout: Terraform's own interpolation marker is "${", so a GitHub Actions expression has to
  # escape the dollar. An unescaped one is a Terraform error rather than a silent problem, which is the
  # good case.
  workflow = {
    name = var.git_hub_action
    on = {
      push = {
        branches = [var.git_hub_branch]
      }
    }
    jobs = {
      codebuild = {
        # The label GitHub matches a queued job against. Built from the CodeBuild project's own name so the
        # two cannot disagree (rules.md B-5).
        "runs-on" = ["${module.code_build_runner.runner_label_prefix}-$${{ github.run_id }}-$${{ github.run_attempt }}"]
        steps = [
          {
            name = "Repo Checkout"
            uses = "actions/checkout@v4"
          },
          {
            # No configure-aws-credentials step: the job runs inside CodeBuild, so it already has the
            # project's service role. That role is the scoped one the runner module writes, which is why
            # an AccessDenied here names the call it was missing rather than nothing at all.
            name = "ECR Login"
            id   = "login-ecr"
            uses = "aws-actions/amazon-ecr-login@v1"
          },
          {
            name = "Docker Build and Push"
            id   = "push-ecr"
            env = {
              ECR_REGISTRY   = "$${{ steps.login-ecr.outputs.registry }}"
              ECR_REPOSITORY = module.ecr_repository.name
              IMAGE_TAG      = "$${{ github.sha }}"
              MOVING_TAG     = module.ecr_repository.image_tag
            }
            # docker tag rather than a second docker build, which is what the _monolithic template's
            # workflow did. Building twice produces two images from the same context - identical in
            # practice, but it is a second build and nothing guarantees the layer cache is warm.
            run = join("\n", [
              "docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .",
              "docker tag $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG $ECR_REGISTRY/$ECR_REPOSITORY:$MOVING_TAG",
              "docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG",
              "docker push $ECR_REGISTRY/$ECR_REPOSITORY:$MOVING_TAG",
              "echo \"IMAGE=$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG\" >> $GITHUB_ENV",
            ])
          },
          {
            # Reads taskdef.json out of the checkout - the file the third association exported from the
            # live task definition - and writes a copy with this run's image in it.
            name = "ECS TaskDefinition"
            id   = "update-taskdef"
            uses = "aws-actions/amazon-ecs-render-task-definition@v1"
            with = {
              "task-definition" = "taskdef.json"
              "container-name"  = module.ecs_service.container_name
              image             = "$${{ env.IMAGE }}"
            }
          },
          {
            # The demo's switch: setting TAG to "fargate" in cicd-app.py and pushing makes the replacement
            # task set land on Fargate instead of the container instances. The capacity provider name comes
            # from the module that created it (rules.md B-5).
            name = "Fargate Check"
            uses = "mikefarah/yq@master"
            with = {
              cmd = join("\n", [
                "if grep -q 'TAG = \"fargate\"' cicd-app.py; then",
                "  yq -i '.Resources[0].TargetService.Properties.CapacityProviderStrategy[0].CapacityProvider = \"FARGATE\"' appspec.yaml",
                "else",
                "  yq -i '.Resources[0].TargetService.Properties.CapacityProviderStrategy[0].CapacityProvider = \"${module.ecs_asg_capacity_provider.capacity_provider_name}\"' appspec.yaml",
                "fi",
              ])
            }
          },
          {
            name = "ECS Service Deployment"
            uses = "aws-actions/amazon-ecs-deploy-task-definition@v1"
            with = {
              "task-definition"             = "$${{ steps.update-taskdef.outputs.task-definition }}"
              service                       = module.ecs_service.service_name
              cluster                       = module.ecs_cluster.cluster_name
              "codedeploy-appspec"          = "appspec.yaml"
              "codedeploy-application"      = module.code_deploy_blue_green.application_name
              "codedeploy-deployment-group" = module.code_deploy_blue_green.deployment_group_name
              "wait-for-service-stability"  = true
            }
          },
        ]
      }
    }
  }
  workflow_yaml = yamlencode(local.workflow)
  # The appspec, written as literal text rather than through yamlencode, and that is the one place in this
  # file where hand-written YAML is the safer choice. CodeDeploy requires the document's version field to
  # be the number 0.0; yamlencode has no way to emit a float, so the value would arrive as either 0 or the
  # string "0.0" and be rejected. The document is also fixed in shape - four nested keys, no lists built
  # from anything.
  #
  # <TASK_DEFINITION> is a placeholder the deploy action substitutes, not a value this configuration knows.
  appspec_yaml = <<-EOT
    version: 0.0
    Resources:
      - TargetService:
          Type: AWS::ECS::Service
          Properties:
            TaskDefinition: <TASK_DEFINITION>
            LoadBalancerInfo:
              ContainerName: ${module.ecs_service.container_name}
              ContainerPort: ${module.ecs_service.container_port}
            CapacityProviderStrategy:
              - CapacityProvider: ${module.ecs_asg_capacity_provider.capacity_provider_name}
                Weight: 1
    EOT
}
# --- The bootstrap chain ---------------------------------------------------------------------------------
#
# Four associations, in order, and the order is enforced by marker files rather than by depends_on or by
# wait_for_success_timeout_seconds (rules.md D-5). Each one waits for the previous stage's marker in an
# until loop, does its work, and leaves its own marker behind: userdata -> image_seeded -> github_workflow
# -> cicd_push -> vscode_readme. One until and one touch per association, which is what makes the chain
# checkable by counting.
#
# depends_on is still declared on each of them, because it is what orders the API calls that create the
# associations and what reverses them on destroy. It is simply not what makes the remote commands run in
# order - the provider reports an association successful on a command that was still working.
resource "aws_ssm_association" "image_seeded" {
  name                             = "AWS-RunShellScript"
  association_name                 = "${var.project_name}-${local.name_suffix}-image-seeded"
  wait_for_success_timeout_seconds = var.bootstrap_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The marker path comes back out of the module it was passed into, so the loop and the bootstrap cannot
    # disagree about where to look (rules.md B-5).
    #
    # The build runs as ec2-user through sudo, which computes the target user's group vector fresh - so it
    # has the docker group the bootstrap added, unlike the already-running code-server session. The
    # _monolithic template used "su - ec2-user", which does the same job; sudo -u is used here because it
    # does not need the account to have a usable shell and does not re-run the login scripts.
    commands = <<-EOT
      set -u
      until [ -f ${module.vscode_ec2.marker_file_path}/userdata ]; do sleep ${var.marker_wait_interval_seconds}; done

      sudo -u ec2-user bash << 'TFSTEP'
      set -x
      export HOME=/home/ec2-user
      mkdir -p ${local.repository_directory}
      cd ${local.repository_directory}

      cat > cicd-app.py << 'TFAPP'
      ${local.app_source}
      TFAPP

      cat > Dockerfile << 'TFDOCKERFILE'
      ${local.dockerfile}
      TFDOCKERFILE

      ${module.ecr_repository.docker_login_command}
      docker build -t ${module.ecr_repository.image_uri} .
      docker push ${module.ecr_repository.image_uri}
      TFSTEP

      # The step above is deliberately not fatal on its own. Asking the registry is what distinguishes "the
      # build worked" from "the script finished", and this is the message that names the repository instead
      # of leaving the ECS service to report CannotPullContainerError minutes later against an image that
      # was never pushed.
      if ! aws ecr describe-images --region ${data.aws_region.current.region} --repository-name ${module.ecr_repository.name} --image-ids imageTag=${module.ecr_repository.image_tag} > /dev/null 2>&1; then
        echo "${module.ecr_repository.image_uri} is not in the repository. The build or the push failed - /var/log/cloud-init-output.log and the output above have the reason." >&2
        exit 1
      fi

      touch ${module.vscode_ec2.marker_file_path}/image_seeded
      EOT
  }
  depends_on = [module.vscode_ec2, module.ecr_repository]
}
resource "aws_ssm_association" "github_workflow" {
  name                             = "AWS-RunShellScript"
  association_name                 = "${var.project_name}-${local.name_suffix}-github-workflow"
  wait_for_success_timeout_seconds = var.bootstrap_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    commands = <<-EOT
      set -u
      until [ -f ${module.vscode_ec2.marker_file_path}/image_seeded ]; do sleep ${var.marker_wait_interval_seconds}; done

      sudo -u ec2-user bash << 'TFSTEP'
      set -ex
      export HOME=/home/ec2-user
      cd ${local.repository_directory}
      mkdir -p .github/workflows

      cat > .github/workflows/${var.workflow_file_name} << 'TFWORKFLOW'
      ${local.workflow_yaml}
      TFWORKFLOW

      cat > appspec.yaml << 'TFAPPSPEC'
      ${local.appspec_yaml}
      TFAPPSPEC

      # The exclusions keep dotfiles out of the archive. .git does not exist yet - the next association is
      # what runs git init - but it is named anyway, because the only thing stopping this from capturing a
      # repository's history is the order of two associations.
      rm -f src.zip
      zip -rq src.zip . -x '.git/*' '*/.*'
      aws s3 cp src.zip s3://${module.github_source.bucket_name}/src.zip
      TFSTEP

      touch ${module.vscode_ec2.marker_file_path}/github_workflow
      EOT
  }
  depends_on = [
    aws_ssm_association.image_seeded,
    module.github_source,
    module.code_build_runner,
    module.code_deploy_blue_green,
    module.ecs_asg_capacity_provider,
  ]
}
resource "aws_ssm_association" "cicd_push" {
  name                             = "AWS-RunShellScript"
  association_name                 = "${var.project_name}-${local.name_suffix}-cicd-push"
  wait_for_success_timeout_seconds = var.bootstrap_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # No token in this document, which is the whole shape of this stage. The _monolithic template wrote
    #
    #   git remote add origin https://<the token>@github.com/<user>/<repo>.git
    #
    # putting a GitHub personal access token in two durable places that have nothing to do with Terraform
    # state: the SSM document, readable by anyone holding ssm:DescribeAssociation for as long as the
    # association exists, and .git/config on an instance whose editor is served without authentication.
    # Marking the variable sensitive does nothing about either of them.
    #
    # What is here instead is a git credential helper that calls Parameter Store at push time. The token
    # never lands on the instance's disk, the document carries only the parameter's name, and - unlike
    # handing the token over in a temporary file - the helper keeps working afterwards, so the "edit and
    # push" step the README describes does not need the token pasted in by hand. The instance's role can
    # read the parameter because it carries AdministratorAccess (rules.md A-5).
    commands = <<-EOT
      set -u
      until [ -f ${module.vscode_ec2.marker_file_path}/github_workflow ]; do sleep ${var.marker_wait_interval_seconds}; done

      sudo -u ec2-user bash << 'TFSTEP'
      set -e
      export HOME=/home/ec2-user
      cd ${local.repository_directory}

      # The live task definition, exported as the file the workflow's render step rewrites on every run.
      # The family comes from the service module rather than being restated, so the export and the
      # definition cannot name different families (rules.md B-5).
      aws ecs describe-task-definition --task-definition ${module.ecs_service.task_family} --query taskDefinition > taskdef.json

      git config --global user.name "${var.project_name}-bootstrap"
      git config --global user.email "${var.project_name}-bootstrap@${data.aws_caller_identity.current.account_id}.invalid"
      # Single-quoted on purpose: the shell must not expand the command substitution here, so what lands in
      # .gitconfig is the helper's source text. git runs it through a shell at push time, which is when the
      # parameter is read.
      git config --global credential.helper '!f() { echo username=x-access-token; echo "password=$(aws ssm get-parameter --name ${module.github_source.token_parameter_name} --with-decryption --query Parameter.Value --output text)"; }; f'

      git init -q
      git remote add origin ${local.repository_clone_url}
      git checkout -q -b ${var.git_hub_branch}
      git add cicd-app.py Dockerfile taskdef.json appspec.yaml .github/workflows/${var.workflow_file_name}
      git commit -q -m "init"
      git push -q --set-upstream origin ${var.git_hub_branch}
      TFSTEP
      status=$?

      if [ "$status" -ne 0 ]; then
        echo "The seed push failed. A 403 here is usually the token missing workflow scope, which GitHub requires for a commit that adds a file under .github/workflows; a 404 is usually ${local.repository_clone_url} not existing yet - nothing in this project creates it." >&2
        exit "$status"
      fi

      touch ${module.vscode_ec2.marker_file_path}/cicd_push
      EOT
  }
  depends_on = [
    aws_ssm_association.github_workflow,
    module.ecs_service,
    module.code_build_runner,
    module.code_deploy_blue_green,
  ]
}
# --- The README on the workbench -------------------------------------------------------------------------
locals {
  # Every output this root exposes, defined once. outputs.tf projects this map and the README association
  # below renders it, so an output cannot exist without also appearing in that README (rules.md H-2).
  #
  # The _monolithic template had exactly one output, the code-server URL, which left the operator inside
  # that editor with no way to find the cluster, the ALB, either target group, the CodeDeploy application,
  # the CodeBuild project or - most importantly - the fact that the CodeStar connection is sitting in
  # PENDING waiting for them.
  #
  # No secret is in here. The GitHub token and the SSH private key appear as retrieval commands, because
  # this map is written to a file served by a code-server with auth: none (rules.md H-2).
  outputs = {
    vscode_url = {
      order       = 1
      title       = "VS Code URL"
      description = "The workbench. Every command below is meant to be run from its terminal, and the repository the pipeline deploys is checked out in the directory it opens"
      value       = module.vscode_ec2.vscode_url
    }
    connection_authorization_step = {
      order       = 2
      title       = "1. Authorize the GitHub connection (required, and Terraform cannot do it)"
      description = "A CodeStar connection is created in PENDING and only becomes AVAILABLE when a person completes the GitHub handshake in the console. Nothing fails until then - the apply succeeds and the connection simply is not usable. Open this page, select the connection below, and choose Update pending connection"
      value       = module.github_source.connection_console_url
    }
    connection_status_command = {
      order       = 3
      title       = "2. Check the connection status"
      description = "AVAILABLE once the handshake above is done. PENDING is the state every new connection is created in"
      value       = module.github_source.connection_status_command
    }
    connection_name = {
      order       = 4
      title       = "CodeStar connection"
      description = "Name of the connection to select on that page. Note that nothing in this project consumes it: CodeBuild authenticates to GitHub with the personal access token credential instead, which is the resource the AWS provider documents for that job. The connection is reproduced because the _monolithic template created it"
      value       = module.github_source.connection_name
    }
    application_url = {
      order       = 5
      title       = "3. The deployed application"
      description = "Served by whichever target group the listener currently forwards to. / returns the greeting and /tag returns the TAG constant from cicd-app.py, which is how a deployment is observed from outside"
      value       = module.application_load_balancer.url
    }
    application_tag_command = {
      order       = 6
      title       = "4. Watch the cutover"
      description = "Poll the tag route while a deployment runs. With CodeDeployDefault.ECSAllAtOnce the value changes in one step, which is the moment the listener was rewritten"
      value       = "while true; do curl -s ${module.application_load_balancer.url}/tag; echo; sleep 2; done"
    }
    trigger_deployment_step = {
      order       = 7
      title       = "5. Trigger a deployment"
      description = "Edit the TAG constant in cicd-app.py, commit and push. The workflow builds a new image, renders a task definition from taskdef.json and hands it to CodeDeploy. Setting TAG to exactly \"fargate\" makes the workflow's Fargate branch deploy the replacement task set onto Fargate instead of the container instances"
      value       = "cd ${local.repository_directory} && git commit -am 'bump tag' && git push"
    }
    live_target_group_command = {
      order       = 8
      title       = "6. Which target group is live"
      description = "The field CodeDeploy rewrites on every deployment, and the one this configuration deliberately stops tracking - so the listener itself is the only honest answer"
      value       = module.application_load_balancer.live_target_group_command
    }
    target_health_command = {
      order       = 9
      title       = "7. Target health in both groups"
      description = "Exactly one group holds healthy targets between deployments, and both do briefly during a cutover. Targets stuck unhealthy with Target.Timeout is a security group path problem rather than an application one"
      value       = module.application_load_balancer.target_health_command
    }
    service_status_command = {
      order       = 10
      title       = "8. Service and task sets"
      description = "Two task sets with one PRIMARY and one ACTIVE is a cutover in progress. One left behind afterwards is a deployment that was stopped rather than completed"
      value       = module.ecs_service.service_status_command
    }
    service_events_command = {
      order       = 11
      title       = "9. Service events"
      description = "Where a pull failure or a task that could not be placed is reported first. \"unable to place a task because no container instance met all of its requirements\" during a cutover is the capacity provider's instance ceiling rather than a placement constraint"
      value       = module.ecs_service.service_events_command
    }
    latest_deployment_command = {
      order       = 12
      title       = "10. The newest CodeDeploy deployment"
      description = "errorInformation is where a replacement task set that could not be placed shows up, and rollbackInfo is where an automatic rollback says what triggered it"
      value       = module.code_deploy_blue_green.describe_latest_deployment_command
    }
    build_log_command = {
      order       = 13
      title       = "11. Runner build output"
      description = "Live output from the CodeBuild project acting as the self-hosted runner. This is where the workflow's docker build, render and deploy steps report, and where a permission the scoped build role is missing names the call it needed"
      value       = module.code_build_runner.tail_build_log_command
    }
    list_builds_command = {
      order       = 14
      title       = "12. Runner builds"
      description = "Empty while a GitHub job sits queued means the webhook never fired or its label does not match the project name. The _monolithic template lost the webhook entirely in conversion, and a project without one never starts a build"
      value       = module.code_build_runner.list_builds_command
    }
    list_images_command = {
      order       = 15
      title       = "13. Images in the repository"
      description = "One image from the workbench's seed push, and one per workflow run after that"
      value       = module.ecr_repository.list_images_command
    }
    list_task_definitions_command = {
      order       = 16
      title       = "14. Task definition revisions"
      description = "Revision 1 is Terraform's. Every later one was registered by a workflow run, which is why the service's task_definition field is not tracked"
      value       = module.ecs_service.list_task_definitions_command
    }
    container_instances_command = {
      order       = 17
      title       = "15. Registered container instances"
      description = "An empty list while the Auto Scaling group reports healthy instances means an instance that cannot reach the ECS endpoint - it never becomes an ECS object that could report a problem, and the service blames placement instead"
      value       = module.ecs_cluster.list_container_instances_command
    }
    capacity_command = {
      order       = 18
      title       = "16. Container instance capacity"
      description = "DesiredCapacity differing from what the configuration declares is expected rather than drift: ECS managed scaling owns that field. MaxSize is 2 rather than the original's 1, so a blue/green cutover has somewhere to put the replacement task set"
      value       = module.ecs_asg_capacity_provider.describe_capacity_command
    }
    cluster_name = {
      order       = 19
      title       = "ECS cluster"
      description = "Name of the ECS cluster"
      value       = module.ecs_cluster.cluster_name
    }
    service_name = {
      order       = 20
      title       = "ECS service"
      description = "Name of the ECS service, which the workflow and the CodeDeploy deployment group both name"
      value       = module.ecs_service.service_name
    }
    task_family = {
      order       = 21
      title       = "Task definition family"
      description = "The family exported to taskdef.json in the repository, and the family every revision the workflow registers belongs to"
      value       = module.ecs_service.task_family
    }
    capacity_provider_name = {
      order       = 22
      title       = "EC2 capacity provider"
      description = "Named in the appspec for the replacement task set. The workflow's Fargate branch swaps this value for FARGATE"
      value       = module.ecs_asg_capacity_provider.capacity_provider_name
    }
    blue_target_group_name = {
      order       = 23
      title       = "Blue target group"
      description = "The half of the pair the listener forwards to at creation - unless initial_target_group_key was changed, in which case the live group below says otherwise"
      value       = module.application_load_balancer.blue_target_group_name
    }
    green_target_group_name = {
      order       = 24
      title       = "Green target group"
      description = "The other half. CodeDeploy works out which is which by reading the listener"
      value       = module.application_load_balancer.green_target_group_name
    }
    initial_target_group_key = {
      order       = 25
      title       = "Live group at creation"
      description = "Which half of the pair the listener, the service and CodeDeploy all started out agreeing on"
      value       = module.application_load_balancer.initial_target_group_key
    }
    code_deploy_application_name = {
      order       = 26
      title       = "CodeDeploy application"
      description = "Name the workflow passes as codedeploy-application"
      value       = module.code_deploy_blue_green.application_name
    }
    code_deploy_deployment_group_name = {
      order       = 27
      title       = "CodeDeploy deployment group"
      description = "Name the workflow passes as codedeploy-deployment-group. The _monolithic template interpolated the resource's id here, which is \"<application>:<group>\" - a value CodeDeploy has no group under, and a failure that only arrives on the first push"
      value       = module.code_deploy_blue_green.deployment_group_name
    }
    code_build_project_name = {
      order       = 28
      title       = "CodeBuild runner project"
      description = "The self-hosted runner. The workflow's runs-on label is codebuild-<this>-<run id>-<run attempt>, built from this name so the two cannot disagree"
      value       = module.code_build_runner.project_name
    }
    runner_label_prefix = {
      order       = 29
      title       = "Runner label prefix"
      description = "What GitHub matches a queued job against, before the run id and run attempt are appended"
      value       = module.code_build_runner.runner_label_prefix
    }
    repository_clone_url = {
      order       = 30
      title       = "GitHub repository"
      description = "Where the seed commit was pushed. It has to exist before the apply: the CloudFormation resource that used to create it (AWS::CodeStar::GitHubRepository) is a legacy type with no provider equivalent, so this project only pushes to it"
      value       = local.repository_clone_url
    }
    source_bucket_name = {
      order       = 31
      title       = "Source bucket"
      description = "Holds src.zip, a copy of the seeded repository. Nothing reads it - it is where the CloudFormation GitHub repository resource used to take its initial code from. terraform destroy empties it"
      value       = module.github_source.bucket_name
    }
    github_token_command = {
      order       = 32
      title       = "GitHub token"
      description = "Retrieves the token from Parameter Store. A command rather than the value: this README is served by a code-server with no authentication, so no secret is written into it (rules.md H-2)"
      value       = module.github_source.token_retrieval_command
    }
    private_key_command = {
      order       = 33
      title       = "Workbench SSH key"
      description = "Retrieves the generated private key from Parameter Store, for the case where the SSM agent is what is broken"
      value       = module.key_pair.private_key_command
    }
    ssh_command = {
      order       = 34
      title       = "Workbench SSH"
      description = "sshd was moved off port 22 by the bootstrap, and this command carries the port it was actually moved to - the _monolithic template's comment said one port while its security group opened another"
      value       = module.vscode_ec2.ssh_command
    }
  }
  # Iterating local.outputs directly would order the sections by key. Re-keying by the order field and
  # taking values() sorts by that instead, since values() returns a map's values ordered by key - so the
  # numbered steps above read top to bottom.
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
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  association_name                 = "${var.project_name}-${local.name_suffix}-readme"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # Last in the chain, waiting on the marker the push association leaves behind. Writing it earlier would
    # describe a repository that has not been pushed yet, and step 5 would be wrong.
    #
    # SSM runs as root, hence the chown. The heredoc delimiter is quoted and deliberately unlikely to
    # appear in the body: Terraform has already substituted every value, so the shell has no reason to
    # touch a "$" or a backtick in the README - and the commands in it contain both.
    commands = <<-EOT
      set -u
      until [ -f ${module.vscode_ec2.marker_file_path}/cicd_push ]; do sleep ${var.marker_wait_interval_seconds}; done
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_readme
      EOT
  }
  depends_on = [aws_ssm_association.cicd_push]
}
# --- What Terraform cannot finish ------------------------------------------------------------------------
#
# In the root, not in the github_source module, and that placement is the whole point of rules.md D-9: a
# check block holds its module open until the checks phase, which runs after every managed resource, so a
# module carrying this check and also being named in another module's depends_on closes a cycle. The root's
# close is not something anything depends on, so the same check here creates no edge at all.
#
# The nested data source re-reads the connection at check time rather than asserting on the attribute
# Terraform recorded, which would report whatever the last refresh saw - and under -refresh=false would
# report the PENDING the connection was created with forever. A nested read that fails is a warning; a
# top-level data source that fails stops the plan.
check "github_connection_available" {
  data "aws_codestarconnections_connection" "github" {
    arn = module.github_source.connection_arn
  }
  assert {
    condition     = data.aws_codestarconnections_connection.github.connection_status == "AVAILABLE"
    error_message = "CodeStar connection ${module.github_source.connection_name} is ${data.aws_codestarconnections_connection.github.connection_status}, not AVAILABLE. A connection is created in PENDING and only a person can finish it: open ${module.github_source.connection_console_url}, select the connection and choose Update pending connection. This is a warning rather than an error on purpose - the apply is complete and correct, and nothing in this project consumes the connection today, but anything that later points CodeBuild or CodePipeline at it will fail with an unhelpful message until the handshake is done."
  }
}
