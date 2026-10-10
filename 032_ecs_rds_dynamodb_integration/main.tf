data "aws_region" "current" {}
# The two AMI ids, from the public parameters AWS maintains.
#
# insecure_value rather than value: the provider marks value sensitive for every parameter whatever its
# type, and a sensitive value cannot be used as an instance's ami or a launch template's image_id without
# nonsensitive(). insecure_value is the provider's own accessor for a parameter that is not a secret, and a
# public AMI id is not one.
#
# Read here and passed in as ids, so each module takes an ami- id and does not have to know where it came
# from (rules.md B-6). It also keeps these reads out of modules that carry depends_on, which would defer
# them to apply (rules.md D-6) - harmless for an AMI id, but there is no reason to take it on.
data "aws_ssm_parameter" "workbench_ami_id" {
  name = var.workbench_ami_ssm_parameter_name
}
data "aws_ssm_parameter" "container_instance_ami_id" {
  name = var.container_instance_ami_ssm_parameter_name
}
locals {
  # The three applications, read from the one copy in the project rather than restated in a shell script.
  #
  # This is the decision the conversion left open. The _monolithic template carried all nine files inline in
  # its AWS::CloudFormation::Init metadata, and src/ on disk is the extracted form of exactly that metadata.
  # Writing them inline again here would mean two copies of three Go programs with nothing keeping them in
  # step - and because the template's copies were never executed, a divergence would have been invisible.
  # So src/ is the source of truth, read with file() at plan time, and the build steps receive strings.
  #
  # file() rather than a data source on purpose: a function is evaluated during plan regardless of what
  # depends_on the consuming module carries, which is what keeps these values out of rules.md D-6's trap.
  #
  # The Dockerfile is read from whatever the application calls it on disk and written into the build context
  # as "Dockerfile", which is the one name docker build looks for. src/user/ calls its file Dockerfile.user,
  # and that asymmetry is resolved here rather than by renaming a file in src/.
  application_source_files = {
    for name, app in var.applications : name => {
      "go.mod"     = file("${path.root}/src/${name}/go.mod")
      "main.go"    = file("${path.root}/src/${name}/main.go")
      "Dockerfile" = file("${path.root}/src/${name}/${app.dockerfile}")
    }
  }
  # Each image's tag is a digest of the three files it is built from, where it used to be one moving
  # "latest" for every build.
  #
  # The moving tag is why fixing a bug in src/ did not fix the running service. A changed file changes the
  # build association's parameters, so SSM rebuilds and pushes over :latest - but the task definition still
  # names :latest, so it is not replaced, the service is not redeployed, and the task already running keeps
  # the image it pulled at start. apply reports success and the old code goes on answering. With the tag
  # derived from the source, a source change is a new image reference, which is a new task definition
  # revision, which is a rolling deployment of exactly that service - and plan shows it.
  #
  # Known at plan, because file() is. That matters twice: the tag becomes part of the build association's
  # for_each key in modules/container_image_builder (rules.md B-8), and the ECR module hands it back out so
  # the push, the pull and that key are one value (rules.md B-5). jsonencode sorts map keys, so the digest
  # does not depend on the order the files were listed in.
  application_image_tags = {
    for name, files in local.application_source_files : name => substr(sha256(jsonencode(files)), 0, 12)
  }
}
module "network" {
  source = "./modules/network"

  vpc_cidr_block             = var.vpc_cidr_block
  availability_zone_suffixes = var.availability_zone_suffixes
}
module "key_pair" {
  source = "./modules/key_pair"

  # Uses nothing from network and does not need a VPC to create a key pair. It waits anyway, because the
  # rule is that a root with a network module has no module starting before that module finishes - an
  # exception here would mean the next reader has to decide per module whether an omission was reasoned or
  # forgotten (rules.md D-3).
  depends_on = [module.network]
}
# --- The workbench, which is where everything this project does actually happens -------------------------
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  vpc_id = module.network.vpc_id
  # The public subnet: the bootstrap downloads code-server, the builds pull base images from public
  # registries and push to ECR, and a browser reaches code-server over the instance's public address.
  subnet_id                   = module.network.public_subnet_a_id
  ami_id                      = data.aws_ssm_parameter.workbench_ami_id.insecure_value
  key_name                    = module.key_pair.key_name
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  # The marker the whole SSM chain hangs off (rules.md B-4, D-5).
  marker_file_path = var.marker_file_path

  # The dockerInstallandLogin config set, minus the login.
  #
  # Here rather than in the module because the module must not need to know that its root builds container
  # images (rules.md H-1): code-server is the module's job, and the tools a particular project needs are the
  # caller's. The ECR login the template put in this config set has moved into the build steps instead,
  # where it is re-run each time rather than captured once at boot - a token lasts twelve hours.
  #
  # The docker group, not chmod 666 on the socket. The template's metadata had both, with the usermod
  # commented out and the chmod live:
  #
  #   # usermod -aG docker ec2-user
  #   # newgrp docker
  #   chmod 666 /var/run/docker.sock
  #
  # 666 on the socket is root on the host for every local user and every process they start, which is a
  # larger grant than the group it was standing in for. The group is what is used here (rules.md H-1).
  #
  # The restart matters and is the reason the commented-out line would not have worked on its own.
  # code-server is already running by this point - the module starts it just above - so it holds the
  # process group list it was given at exec time and will not see docker in it. Without the restart, the
  # terminal inside the IDE gets "permission denied while trying to connect to the Docker daemon socket",
  # which is exactly the symptom the chmod was reached for.
  #
  # newgrp is dropped rather than translated: it execs a new shell as a child of this script, reading its
  # commands from stdin, which cloud-init supplies as /dev/null. It returns immediately having changed
  # nothing about the process that goes on to run the rest of the script.
  additional_user_data = <<-EOT
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    systemctl restart code-server

    # The mysql client, for the schema step below and for the README's interactive session. There is no
    # package called mysql on Amazon Linux 2023.
    dnf install -yq ${var.mysql_client_package}

    # The Session Manager plugin, because the README's ECS Exec command hands the session to it - without it
    # that command fails with "SessionManagerPlugin is not found" on the instance the README is read from.
    dnf install -yq https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm

    # So the README's commands run as written, without --region on every one of them.
    runuser -u ec2-user -- env HOME=/home/ec2-user aws configure set default.region ${data.aws_region.current.region}
  EOT

  depends_on = [module.network, module.key_pair]
}
# --- What the applications talk to -----------------------------------------------------------------------
module "ecr_repository" {
  source   = "./modules/ecr_repository"
  for_each = var.applications

  # The keys are literal strings in configuration, so for_each over this map is fine - it is the values
  # arriving from other modules that would not be (rules.md B-8).
  name = "${var.ecr_repository_name_prefix}${each.key}"
  # Derived from the source rather than the module's "latest" default - see local.application_image_tags.
  # Every source change leaves the previous image in the repository under its own tag; that is one image
  # per change to src/, not one per apply.
  image_tag = local.application_image_tags[each.key]

  # Uses nothing from network and waits anyway, for the reason given on key_pair (rules.md D-3).
  depends_on = [module.network]
}
module "dynamodb_table" {
  source = "./modules/dynamodb_table"

  # The module's defaults key the table on id alone, which is a departure from the _monolithic template's
  # id + price composite key - the product application reads by id only, and that call was a guaranteed
  # ValidationException against the template's table. See the module for the reasoning; applying this to a
  # table created in the template's shape replaces it, items included.

  depends_on = [module.network]
}
# Declared before the database, because the database's ingress rule names this group as a source. That edge
# is the one the _monolithic template was missing: its rule admitted the VPC's default security group, which
# nothing in the project joins, so the tasks could not reach MySQL at all.
module "ecs_service_security_group" {
  source = "./modules/ecs_service_security_group"

  vpc_id = module.network.vpc_id
  # The template's first ingress block. The VPC CIDR is read back off the network module rather than from
  # var.vpc_cidr_block, so the rule describes the VPC that exists rather than the one that was asked for
  # (rules.md B-5).
  all_traffic_cidr_blocks = var.restrict_task_ingress_to_vpc ? [module.network.vpc_cidr_block] : []
  # A literal key, so the rule's resource address is known at plan while the workbench's group ID is not
  # (rules.md B-8).
  port_source_security_groups = {
    workbench = module.vscode_ec2.security_group_id
  }

  depends_on = [module.network, module.vscode_ec2]
}
module "rds_mysql" {
  source = "./modules/rds_mysql"

  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.private_subnet_ids

  db_name             = var.rds_database
  username            = var.rds_username
  master_password     = var.rds_password
  create_read_replica = var.create_read_replica

  # Both sources the database needs, keyed by literal labels (rules.md B-8). The task group is what the
  # template got wrong; the workbench is what the schema step and the README's mysql session connect from,
  # and is the only route to an instance with no public address.
  ingress_source_security_groups = {
    ecs_tasks = module.ecs_service_security_group.security_group_id
    workbench = module.vscode_ec2.security_group_id
  }

  depends_on = [module.network, module.ecs_service_security_group, module.vscode_ec2]
}
# --- The cluster and its capacity ------------------------------------------------------------------------
module "ecs_cluster" {
  source = "./modules/ecs_cluster"

  depends_on = [module.network]
}
module "ecs_asg_capacity_provider" {
  source = "./modules/ecs_asg_capacity_provider"

  vpc_id = module.network.vpc_id
  # Private subnets, so outbound goes through the per-zone NAT gateways. The ECS agent cannot register an
  # instance that cannot reach the ECS endpoint, and an instance that never registers is absent rather than
  # broken - see the module for what that looks like.
  subnet_ids   = module.network.private_subnet_ids
  cluster_name = module.ecs_cluster.cluster_name
  ami_id       = data.aws_ssm_parameter.container_instance_ami_id.insecure_value
  key_name     = module.key_pair.key_name
  # CloudFormation generated this name automatically and Terraform requires one, so it comes from the
  # project name as the template derived it from the stack name.
  capacity_provider_name = "${var.project_name}-ecs-ec2-capacity-provider"

  # The cluster has to exist before an instance tries to join it, and before the association inside this
  # module can attach a capacity provider to it. The cluster name arrives as a variable and is interpolated
  # into the launch template userdata, so that part is already ordered; module-level depends_on covers the
  # rest of the cluster module (rules.md D-2, D-3).
  depends_on = [module.network, module.ecs_cluster, module.key_pair]
}
module "ecs_task_iam_roles" {
  source = "./modules/ecs_task_iam_roles"

  # What replaces AdministratorAccess on the task role: the one table the product application writes to,
  # and its index ARN pattern (rules.md A-5).
  dynamodb_table_arns = [module.dynamodb_table.arn, module.dynamodb_table.index_arn_pattern]
  # What replaces CloudWatchFullAccessV2 on the execution role: read on the one secret it injects.
  secret_arns = [module.rds_mysql.credentials_secret_arn]

  depends_on = [module.dynamodb_table, module.rds_mysql]
}
# --- Building the three images, which the template never did ---------------------------------------------
module "container_image_builder" {
  source = "./modules/container_image_builder"

  instance_id = module.vscode_ec2.instance_id
  # The path comes back out of the module it was passed into, so the bootstrap's marker and the chain that
  # waits for it are one value (rules.md B-5).
  marker_file_path        = module.vscode_ec2.marker_file_path
  association_name_prefix = var.project_name

  # Static keys, apply-time values: exactly the shape rules.md B-8 asks for. The repository URLs do not
  # exist at plan time, and a set built from them could not provide resource addresses.
  applications = {
    for name, app in var.applications : name => {
      order           = app.order
      repository_name = module.ecr_repository[name].name
      image_uri       = module.ecr_repository[name].image_uri
      image_tag       = module.ecr_repository[name].image_tag
      files           = local.application_source_files[name]
    }
  }

  depends_on = [module.network, module.vscode_ec2, module.ecr_repository]
}
# The MySQL schema, which the template created nowhere.
#
# An addition rather than a reproduction, and the smallest one that makes the user service work: its POST
# handler inserts into a table called user, and nothing in the template ever created it. The result would
# have been a 500 from the endpoint the service exists for, with "Table 'dev.user' doesn't exist" visible
# only in a container log the template also did not configure.
#
# Here rather than in a module because it joins three of them - the workbench's instance, the database's
# endpoint and its credential secret - and combining modules is the root's job (rules.md C-1).
#
# The password is fetched on the instance rather than interpolated into this script. That is the point of
# the extra three lines: parameters on an SSM association are stored by AWS and readable with
# describe-association, and they are in Terraform state as plain strings, so an interpolated password would
# be written to two more places than it already is. MYSQL_PWD rather than -p"..." for the same reason at a
# smaller scale - a password on the command line is visible in ps to every user on the box.
resource "aws_ssm_association" "rds_schema" {
  name                             = "AWS-RunShellScript"
  association_name                 = "${var.project_name}-rds-schema"
  wait_for_success_timeout_seconds = var.schema_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    executionTimeout = tostring(var.schema_timeout_seconds)
    # The until loop, not depends_on and not wait_for_success_timeout_seconds, is what orders this after the
    # image builds (rules.md D-5). The marker name is derived by the builder module from its own build
    # order, so adding an application with a higher order moves it and this still waits for the last one
    # (rules.md B-5).
    commands = <<-EOT
      set -u

      waited=0
      until [ -f ${module.container_image_builder.completion_marker_file} ]; do
        waited=$((waited + 1))
        if [ "$waited" -gt ${var.marker_wait_attempts} ]; then
          echo "timed out waiting for ${module.container_image_builder.completion_marker_file}. The image builds have not all finished; read their association output." >&2
          exit 1
        fi
        sleep 10
      done

      PASSWORD=$(aws secretsmanager get-secret-value --secret-id ${module.rds_mysql.credentials_secret_arn} --query SecretString --output text | python -c 'import json,sys; print(json.load(sys.stdin)["password"])')
      if [ -z "$PASSWORD" ]; then
        echo "could not read the password out of ${module.rds_mysql.credentials_secret_arn}. The instance role needs secretsmanager:GetSecretValue, and python is installed by the bootstrap." >&2
        exit 1
      fi

      MYSQL_PWD="$PASSWORD" mysql \
        --host ${module.rds_mysql.address} \
        --port ${module.rds_mysql.port} \
        --user ${module.rds_mysql.username} \
        --database ${module.rds_mysql.db_name} << 'TFSCHEMA'
      ${var.rds_schema_sql}
      TFSCHEMA
      schema_status=$?
      if [ "$schema_status" -ne 0 ]; then
        echo "the schema statements failed against ${module.rds_mysql.address}. A connection timeout here means the database security group does not admit this instance; an access denied means the credential." >&2
        exit "$schema_status"
      fi

      mkdir -p ${module.vscode_ec2.marker_file_path}
      touch ${module.vscode_ec2.marker_file_path}/rds_schema
      EOT
  }
  depends_on = [module.vscode_ec2, module.rds_mysql, module.container_image_builder]
}
# --- The three services ----------------------------------------------------------------------------------
module "ecs_service" {
  source   = "./modules/ecs_service"
  for_each = var.applications

  service_name = "${each.key}-service"
  # One family per application, where the template gave all three "user-taskdef" - see the module.
  task_family  = "${each.key}-taskdef"
  cluster_name = module.ecs_cluster.cluster_name
  subnet_ids   = module.network.private_subnet_ids
  # A list rather than a map: this value is an argument and never a for_each key (rules.md B-8).
  security_group_ids = [module.ecs_service_security_group.security_group_id]
  # The port the security group opened, read back from that module so the container, the health check and
  # the rule cannot disagree (rules.md B-5).
  container_port = module.ecs_service_security_group.port

  image_uri = module.ecr_repository[each.key].image_uri
  # CloudFormation generated no log group at all here; this one is an addition, named per application so the
  # three services do not interleave into one stream prefix.
  log_group_name = "/ecs/${var.project_name}/${each.key}"

  # Each application's environment, wired by name: these values come from the database and table modules, so
  # they cannot live in var.applications, and that is what its key-set validation exists to protect.
  #
  # Conditionals inside merge() rather than a lookup table keyed by application name, and the difference is
  # types rather than taste. A map literal whose values are objects with different attributes - four
  # MYSQL_* entries, two TABLE_* entries, and nothing for stress - is an object type with three dissimilar
  # attributes, and what happens when such a thing is indexed by a variable key depends on whether Terraform
  # can unify those attribute types. Each conditional here is instead unified on its own, against an empty
  # object, which converts cleanly to the map(string) this argument takes.
  #
  # Nothing secret is in this list. The _monolithic template put MYSQL_PASSWORD here, which writes the
  # password in plaintext into every task definition revision; the ecs_service module now rejects a
  # credential-looking key in this argument and takes it through secrets instead.
  environment = merge(
    each.key == "user" ? {
      MYSQL_USER   = module.rds_mysql.username
      MYSQL_HOST   = module.rds_mysql.address
      MYSQL_PORT   = tostring(module.rds_mysql.port)
      MYSQL_DBNAME = module.rds_mysql.db_name
    } : {},
    each.key == "product" ? {
      TABLE_NAME       = module.dynamodb_table.name
      TABLE_INDEX_NAME = var.dynamo_table_index_name
    } : {},
    # src/stress/main.go reads no environment at all, which is why there is no third branch.
  )
  # Only the user application needs one. The reference selects a single key out of the credential document,
  # so the container receives the password and not the host, user and database name alongside it - assembled
  # by the database module so the ARN and the key name travel together (rules.md B-5).
  secrets = each.key == "user" ? {
    MYSQL_PASSWORD = module.rds_mysql.password_secret_reference
  } : {}

  task_role_arn      = module.ecs_task_iam_roles.task_role_arn
  execution_role_arn = module.ecs_task_iam_roles.execution_role_arn

  capacity_provider_name = module.ecs_asg_capacity_provider.capacity_provider_name
  desired_count          = var.service_desired_count
  wait_for_steady_state  = var.wait_for_steady_state

  # Four things have to be true before a task can start, and only two are implied by a value reference.
  #
  #   - the image has to exist, which is what the build associations establish. This is the edge the
  #     CloudFormation CreationPolicy used to provide: the template's task definitions carried
  #     depends_on = [aws_instance.bastion_ec2], and in CloudFormation that meant "after cfn-signal", which
  #     meant "after the images were pushed". In Terraform an aws_instance is complete when it is running,
  #     minutes before docker is even installed, so that ordering is gone (rules.md D-5)
  #   - the capacity provider has to be attached to the cluster and instances have to have registered.
  #     capacity_provider_name orders this after the provider resource alone, not after either of those
  #     (rules.md D-2)
  #   - the task role and execution role need their policies attached before a task is placed, or the pull
  #     is denied and the secret injection fails (rules.md D-1)
  #   - network, for the uniform reason and because the container instances' route to a NAT gateway is what
  #     lets them register at all (rules.md D-3)
  #
  # The order also matters in reverse. On destroy these go first, which is what lets ECS delete the capacity
  # provider afterwards - it refuses while a service's strategy still names it.
  depends_on = [
    module.network,
    module.ecs_asg_capacity_provider,
    module.ecs_task_iam_roles,
    module.container_image_builder,
  ]
}
# --- Outputs, and the README that mirrors them -----------------------------------------------------------
locals {
  # Every output this root exposes, defined once. outputs.tf projects this map and the README association
  # below renders it, so an output cannot exist without also appearing in that README (rules.md H-2).
  #
  # The _monolithic template had no outputs at all - not one - on a project whose whole surface is a browser
  # URL and a set of private IP addresses that only answer from inside the VPC. There was no supported way
  # to find out what it had built.
  #
  # Commands rather than values wherever Terraform cannot know the answer: which tasks are running, what
  # address each got, whether an image was pushed. And a retrieval command rather than the value for the
  # database password, because this map is written to a file on a disk that an unauthenticated code-server
  # serves (rules.md H-2).
  #
  # The per-application entries are joined across the three service modules rather than declared one each,
  # which keeps the number of entries here fixed and equal to the number of output blocks in outputs.tf.
  # The keys come from var.applications rather than from keys(module.ecs_service): the two sets are the
  # same, and a plain map is a safer thing to call keys() on than a map of module instances.
  outputs = {
    vscode_url = {
      order       = 1
      title       = "VS Code URL"
      description = "The workbench. Every command below is meant to be run from its terminal, and the three services have no other way in - their tasks have private addresses only"
      value       = module.vscode_ec2.vscode_url
    }
    image_build_order = {
      order       = 2
      title       = "Image build order"
      description = "The order the three images are built in, one after another on this instance. Serial on purpose: two Go builds at once, one of them linking the AWS SDK, is what gets the linker killed"
      value       = join(" -> ", module.container_image_builder.build_order)
    }
    image_build_status_command = {
      order       = 3
      title       = "1. Did the three images get built"
      description = "The status of each build step. This is the work the _monolithic template never did - its two cfn-init calls had no CloudFormation stack to read metadata from, so nothing was ever built and the three services referenced images that did not exist"
      value       = module.container_image_builder.build_status_command
    }
    image_build_output_command = {
      order       = 4
      title       = "2. Read a build step's output"
      description = "The first step's actual stdout and stderr. An ExecutionElapsedTime of a fraction of a second means the script failed to parse rather than failed to run. Change the association id in the command to read another step"
      value       = module.container_image_builder.build_output_command
    }
    ecr_list_images_command = {
      order       = 5
      title       = "3. The images in ECR"
      description = "One listing per repository. An empty table is the first thing to check when a service reports CannotPullContainerError - it means the answer is in the build step's output rather than anywhere in ECS"
      value       = join("\n", [for name in sort(keys(var.applications)) : module.ecr_repository[name].list_images_command])
    }
    service_status_command = {
      order       = 6
      title       = "4. Service status"
      description = "Desired against running counts for each service. apply does not wait for a steady state, so these are still settling when it returns"
      value       = join("\n", [for name in sort(keys(var.applications)) : module.ecs_service[name].service_status_command])
    }
    service_events_command = {
      order       = 7
      title       = "5. Service events"
      description = "Each service's own account of what it has been trying to do. Nearly every failure in this project appears here first"
      value       = join("\n", [for name in sort(keys(var.applications)) : module.ecs_service[name].service_events_command])
    }
    stopped_task_reason_command = {
      order       = 8
      title       = "6. Why stopped tasks stopped"
      description = "CannotPullContainerError means the image; a ResourceInitializationError naming the secret means the task ENI's route out or the execution role"
      value       = join("\n", [for name in sort(keys(var.applications)) : module.ecs_service[name].stopped_task_reason_command])
    }
    service_health_command = {
      order       = 9
      title       = "7. Reach each service"
      description = "Resolves each service's first running task and requests its health endpoint. Three replies of {\"status\":\"ok\"} means every image was built, pushed, pulled and started, and that the task security group admits this instance - the whole chain in three lines"
      value       = join("\n", [for name in sort(keys(var.applications)) : module.ecs_service[name].curl_health_command])
    }
    user_write_command = {
      order       = 10
      title       = "8. Write a row through the user service"
      description = "The MySQL half. This is the request that would have failed on the _monolithic template with \"Table 'dev.user' doesn't exist\": nothing in it created a schema, and nothing configured a log driver to say so"
      value = join("\n", [
        "IP=$(${module.ecs_service["user"].task_private_ips_command} | head -1)",
        "curl -s -X POST \"http://$IP:${module.ecs_service_security_group.port}/v1/user\" -H 'Content-Type: application/json' -d '{\"requestid\":\"r1\",\"uuid\":\"u1\",\"username\":\"alice\",\"email\":\"alice@example.com\",\"status_message\":\"hello\"}'",
      ])
    }
    user_read_command = {
      order       = 11
      title       = "9. Read it back"
      description = "The application requires all three query parameters before it looks anything up, and then selects on email alone"
      value = join("\n", [
        "IP=$(${module.ecs_service["user"].task_private_ips_command} | head -1)",
        "curl -s \"http://$IP:${module.ecs_service_security_group.port}/v1/user?email=alice@example.com&requestid=r1&uuid=u1\"",
      ])
    }
    product_write_command = {
      order       = 12
      title       = "10. Write an item through the product service"
      description = "The DynamoDB half. Expect {\"status\":\"created\"}. As converted, this returned \"Internal Server Error\" before a request ever left the container: the three aws-sdk-go-v2 modules in src/product/go.mod were from three different releases, and the DynamoDB client could not find the endpoint middleware it is built around - \"not found, ResolveEndpointV2\" in the container log. They are pinned to one release now. Writing the same id again replaces the item"
      value = join("\n", [
        "IP=$(${module.ecs_service["product"].task_private_ips_command} | head -1)",
        "curl -s -X POST \"http://$IP:${module.ecs_service_security_group.port}/v1/product\" -H 'Content-Type: application/json' -d '{\"requestid\":\"r1\",\"uuid\":\"u1\",\"id\":\"p1\",\"name\":\"widget\",\"price\":9.99}'",
      ])
    }
    product_read_command = {
      order       = 13
      title       = "11. Read it back"
      description = "Expect {\"id\":\"p1\",\"name\":\"widget\",\"price\":9.99}, and 404 for an id never written. Behind the SDK fault above was a second one: the _monolithic table had price as a sort key beside id, and this GetItem names id alone, which DynamoDB rejects with ValidationException. The table is keyed on id alone now, and the read is strongly consistent so it finds a write made a moment earlier. A 500 here means the container log has the reason"
      value = join("\n", [
        "IP=$(${module.ecs_service["product"].task_private_ips_command} | head -1)",
        "curl -s \"http://$IP:${module.ecs_service_security_group.port}/v1/product?id=p1&requestid=r1&uuid=u1\"",
        "# a 500 from either call: the handler's DynamoDB error is in",
        module.ecs_service["product"].container_log_command,
      ])
    }
    dynamodb_scan_command = {
      order       = 14
      title       = "12. The item as DynamoDB holds it"
      description = "The stored form rather than the rendered one: price is the number string the handler formatted, and a second POST of the same id shows as one item, not two"
      value       = module.dynamodb_table.scan_command
    }
    stress_command = {
      order       = 15
      title       = "13. The stress service"
      description = "Returns a hex string of the requested length. It touches no AWS service and no database, which is why its task role needs nothing"
      value = join("\n", [
        "IP=$(${module.ecs_service["stress"].task_private_ips_command} | head -1)",
        "curl -s -X POST \"http://$IP:${module.ecs_service_security_group.port}/v1/stress\" -H 'Content-Type: application/json' -d '{\"requestid\":\"r1\",\"uuid\":\"u1\",\"length\":64}'",
      ])
    }
    container_log_command = {
      order       = 16
      title       = "14. Container output"
      description = "One log group per service. These are an addition: the template configured no log driver, so the containers logged to the instance's local json-file driver and the real reason behind every \"Internal Server Error\" was unreachable"
      value       = join("\n", [for name in sort(keys(var.applications)) : module.ecs_service[name].container_log_command])
    }
    mysql_session_command = {
      order       = 17
      title       = "15. A MySQL session"
      description = "Only this instance can reach the database - it is in private subnets and its security group names this one group and the task group as sources. The password is fetched inline, so it is never typed or left in shell history"
      value       = module.rds_mysql.mysql_connect_command
    }
    rds_credentials_command = {
      order       = 18
      title       = "16. The database credential"
      description = "A retrieval command, not the password. The template had it as a variable with default \"dbpassword\" and passed it to three containers as a plaintext environment variable; it is generated now and injected through the task definition's secrets list instead. This file is served by an unauthenticated code-server, which is the other reason the value is not in it"
      value       = module.rds_mysql.get_credentials_command
    }
    rds_storage_command = {
      order       = 19
      title       = "17. The storage figures"
      description = "gp3 at 400 GiB with 12000 IOPS and 500 MiB/s, on a db.t3.micro. Reproduced from the template and valid - 400 GiB is exactly the threshold at which MySQL's gp3 volume stripes and those two become settable at all - but the instance class cannot drive that bandwidth, so it is paid for and not delivered. Lowering the storage is the change that breaks it"
      value       = module.rds_mysql.describe_command
    }
    rds_replica_status_command = {
      order       = 20
      title       = "18. Is the replica a replica"
      description = "ReadReplicaSourceDBInstanceIdentifier being populated is the difference between a read replica and the standalone second instance the conversion left behind - it dropped SourceDBInstanceIdentifier into a TODO comment, leaving an aws_db_instance with no engine, which the provider rejects at plan"
      value       = var.create_read_replica ? module.rds_mysql.replica_status_command : "create_read_replica is false, so there is no replica"
    }
    cluster_status_command = {
      order       = 21
      title       = "19. Cluster and capacity"
      description = "Registered instances and running against pending task counts. Three instances and three tasks is the whole cluster"
      value       = module.ecs_cluster.cluster_status_command
    }
    container_instance_status_command = {
      order       = 22
      title       = "20. Container instances"
      description = "Which instances registered and how much memory each has left. Instances that launched but are missing here is the signature of the revoked egress rule this conversion had on all four security groups"
      value       = module.ecs_asg_capacity_provider.container_instance_status_command
    }
    task_role_policy_command = {
      order       = 23
      title       = "21. What the task role can do"
      description = "The point is what is not there. The template gave this role AdministratorAccess; what replaced it is one statement naming one DynamoDB table, because that table is the only AWS resource any of the three applications touches"
      value       = module.ecs_task_iam_roles.task_role_policy_command
    }
    ecs_exec_command = {
      order       = 24
      title       = "22. A shell inside a task"
      description = "ECS Exec, enabled on all three services. The Session Manager plugin it needs is installed by this instance's bootstrap"
      value       = join("\n", [for name in sort(keys(var.applications)) : module.ecs_service[name].execute_command])
    }
    rds_endpoint = {
      order       = 25
      title       = "Database endpoint"
      description = "Host and port of the primary. Reachable from this instance and from the task ENIs, and from nowhere else"
      value       = module.rds_mysql.endpoint
    }
    rds_replica_address = {
      order       = 26
      title       = "Read replica endpoint"
      description = "Nothing in this project connects to it - the user task definition only receives the primary - so this is the only way to reach it. That is reproduced from the template, which created a replica and used it for nothing"
      value       = var.create_read_replica ? module.rds_mysql.replica_address : "create_read_replica is false, so there is no replica"
    }
    dynamodb_table_name = {
      order       = 27
      title       = "DynamoDB table"
      description = "Name of the table the product service writes to"
      value       = module.dynamodb_table.name
    }
    ecs_cluster_name = {
      order       = 28
      title       = "ECS cluster"
      description = "Name of the cluster"
      value       = module.ecs_cluster.cluster_name
    }
    capacity_provider_name = {
      order       = 29
      title       = "Capacity provider"
      description = "The provider the three services place tasks through. The template's services used launch_type EC2 instead, which works and bypasses the provider entirely - so its managed scaling had nothing to scale for"
      value       = module.ecs_asg_capacity_provider.capacity_provider_name
    }
    ecr_repository_urls = {
      order       = 30
      title       = "ECR repositories"
      description = "The image references the builds push and the task definitions pull. One value behind both, so the tag cannot differ between them"
      value       = join("\n", [for name in sort(keys(var.applications)) : module.ecr_repository[name].image_uri])
    }
    docker_login_command = {
      order       = 31
      title       = "ECR login"
      description = "The login the build steps run. Worth having by hand: an authorization token lasts twelve hours, so a docker push attempted a day later fails with \"no basic auth credentials\", which reads like a permissions problem"
      value       = module.ecr_repository[sort(keys(var.applications))[0]].docker_login_command
    }
    vpc_id = {
      order       = 32
      title       = "VPC"
      description = "ID of the VPC"
      value       = module.network.vpc_id
    }
    nat_gateway_public_ips = {
      order       = 33
      title       = "NAT gateway addresses"
      description = "What the container instances and the task ENIs appear as from outside. Public registries rate-limit anonymous pulls by source address, and these are the addresses counted"
      value       = join(" ", module.network.nat_gateway_public_ips)
    }
    cloud_init_log_command = {
      order       = 34
      title       = "This instance's bootstrap log"
      description = "Where to look when code-server did not come up, or when every build step is still waiting for the userdata marker"
      value       = module.vscode_ec2.cloud_init_log_command
    }
    private_key_command = {
      order       = 35
      title       = "Workbench SSH key"
      description = "Retrieves the generated private key from Parameter Store. A command rather than the key, for the same reason as the database credential"
      value       = module.key_pair.private_key_command
    }
  }
  # Re-keyed by order so values() returns the sections in reading order rather than alphabetically - the
  # numbered steps above only mean anything in sequence.
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
# The README on the workbench, last in the chain.
#
# Everything above is reachable only from this instance - the services have private addresses, the database
# is in private subnets - and there is no terraform output inside a code-server session. So every output
# this root exposes is also written to /home/ec2-user/README.md, which is the directory code-server opens
# (rules.md H-2).
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  association_name                 = "${var.project_name}-vscode-readme"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    executionTimeout = tostring(var.readme_timeout_seconds)
    # Waits for the schema step, which waits for the last image build, which waits for the bootstrap. The
    # until loop is what orders it, not depends_on and not the timeout above (rules.md D-5) - and the point
    # of waiting at all is that the README should describe a project that is actually finished.
    #
    # The heredoc delimiter is quoted, so the shell expands nothing in the body. Terraform has already
    # substituted every value, and the README contains shell snippets full of $ and backticks that must
    # arrive intact. The delimiter is long for the same reason: EOF or MD could plausibly appear at the
    # start of a line in a document made of commands.
    commands = <<-EOT
      set -u

      waited=0
      until [ -f ${module.vscode_ec2.marker_file_path}/rds_schema ]; do
        waited=$((waited + 1))
        if [ "$waited" -gt ${var.marker_wait_attempts} ]; then
          echo "timed out waiting for ${module.vscode_ec2.marker_file_path}/rds_schema. The schema step has not finished; read its association output." >&2
          exit 1
        fi
        sleep 10
      done

      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      # SSM commands run as root, so without this the file is not editable in the code-server session.
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_readme
      EOT
  }
  depends_on = [module.vscode_ec2, aws_ssm_association.rds_schema]
}
