data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
# The workbench AMI, resolved here rather than inside the module that launches it, so no module that carries
# depends_on declares a data source (rules.md D-6). insecure_value because the provider marks every parameter
# value sensitive, and a public AMI id is not a secret.
data "aws_ssm_parameter" "vscode_ami_id" {
  name = var.ami_ssm_parameter_name
}
locals {
  region     = data.aws_region.current.region
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  # Where the build context is assembled on the workbench, as the _monolithic template placed it.
  build_directory = "/home/ec2-user/lambda"
}
module "network" {
  source = "./modules/network"

  region                   = local.region
  vpc_cidr_block           = var.vpc_cidr_block
  public_subnet_cidr_block = var.public_subnet_cidr_block
  availability_zone_suffix = var.availability_zone_suffix
  vpc_name                 = "vpc"
  internet_gateway_name    = "igw"
  public_subnet_name       = "public-subnet"
  public_route_table_name  = "public-rt"
}
# Every module below waits for the whole network module, directly or through one that does, including the ones
# that need no VPC - so the root has no exceptions and destroy runs uniformly in reverse (rules.md D-3).
module "key_pair" {
  source = "./modules/key_pair"

  key_name_prefix = "${var.project_name}-"
  rsa_bits        = var.key_rsa_bits

  depends_on = [module.network]
}
module "ecr_repository" {
  source = "./modules/ecr_repository"

  name         = var.ecr_repository_name
  image_tag    = var.image_tag
  force_delete = var.ecr_force_delete
  scan_on_push = var.ecr_scan_on_push

  depends_on = [module.network]
}
module "result_bucket" {
  source = "./modules/result_bucket"

  bucket_prefix = "${var.project_name}-result-"
  force_destroy = var.bucket_force_destroy

  depends_on = [module.network]
}
locals {
  # Everything the workbench does beyond running code-server, handed to the module through additional_user_data
  # so the module does not have to know what is built on it (rules.md B-4).
  #
  # Every literal line sits at the same four-space indent, and that is load-bearing. <<- strips the smallest
  # indentation of the template's own lines, so each one - the quoted heredoc terminators included - lands at
  # column 0, where the shell recognises it. The three file() values are interpolated content, not template
  # lines, so they are not stripped: their own indentation (index.py's function body) survives intact
  # (rules.md E-9 on nested heredocs; A-4 on what a terminator that is not at column 0 does to a script).
  #
  # The sources come from src/ rather than from echo statements in this script, which is how the _monolithic
  # template wrote them - with the bucket name interpolated into the Python source, so the image itself had to
  # change when the bucket did. The handler reads the bucket and key from its environment now.
  #
  # The README.md, Dockerfile and index.py at the root of this project are not read by anything, and were not
  # read by the _monolithic template either. They are a different, smaller demo - a hello-world handler - and
  # that Dockerfile copies an app.py that does not exist, so it cannot build. They are left in place, and this
  # is the note saying why nothing uses them.
  build_user_data = <<-EOT
    dnf install -yq docker
    systemctl enable --now docker
    # The group rather than the template's "chmod 666 /var/run/docker.sock", which makes the socket
    # world-writable - root on this host for every local account (rules.md H-1). The build below runs as root
    # and needs neither.
    usermod -aG docker ec2-user
    # code-server started before the group existed, so its terminals still lack it. Restarting is what makes
    # build.sh runnable from the IDE, which is where a rebuild happens.
    systemctl restart code-server

    mkdir -p ${local.build_directory}
    cat > ${local.build_directory}/index.py << 'TFINDEX'
    ${file("${path.root}/src/index.py")}
    TFINDEX
    cat > ${local.build_directory}/requirements.txt << 'TFREQUIREMENTS'
    ${file("${path.root}/src/requirements.txt")}
    TFREQUIREMENTS
    cat > ${local.build_directory}/Dockerfile << 'TFDOCKERFILE'
    ${file("${path.root}/src/Dockerfile")}
    TFDOCKERFILE

    # docker build and docker push, not the template's
    #
    #   docker buildx build --push --platform linux/amd64 --provenance=false
    #
    # The two flags existed for real reasons, and neither needs buildx. --provenance=false kept BuildKit from
    # attaching an attestation, which turns the pushed manifest into an index that Lambda rejects; an image built
    # into the local store and pushed with docker push carries no attestation, because the classic store cannot
    # hold one. --platform linux/amd64 matched the function's architecture; this instance is x86_64, so a native
    # build already is. What buildx added was a dependency - Amazon Linux 2023's package list has docker but no
    # buildx plugin, and "buildx is not a docker command" would have left the repository empty.
    cat > ${local.build_directory}/build.sh << 'TFBUILD'
    #!/bin/bash
    set -euo pipefail
    ${module.ecr_repository.docker_login_command}
    docker build -t ${module.ecr_repository.image_uri} ${local.build_directory}
    docker push ${module.ecr_repository.image_uri}
    TFBUILD
    chmod +x ${local.build_directory}/build.sh
    chown -R ec2-user:ec2-user ${local.build_directory}
    ${local.build_directory}/build.sh
    EOT
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  instance_name    = var.vscode_instance_name
  vpc_id           = module.network.vpc_id
  subnet_id        = module.network.public_subnet_a_id
  ami_id           = data.aws_ssm_parameter.vscode_ami_id.insecure_value
  instance_type    = var.vscode_instance_type
  key_name         = module.key_pair.key_name
  root_volume_size = var.vscode_root_volume_size

  security_group_name     = var.vscode_security_group_name
  ingress_cidr_blocks     = var.inbound_from_anywhere ? ["0.0.0.0/0"] : []
  ssh_ingress_cidr_blocks = var.ssh_ingress_cidr_blocks
  code_server_port        = var.code_server_port
  code_server_version     = var.code_server_version

  iam_name_prefix = "${var.project_name}-vscode-"
  iam_policy_arns = var.vscode_iam_policy_arns

  # The module touches <path>/userdata as its last step, after the script above (rules.md B-4/H-2).
  marker_file_path     = var.marker_file_path
  additional_user_data = local.build_user_data

  # network for the uniform reason and because cloud-init runs dnf within seconds of launch - the route to the
  # internet gateway is exactly what the subnet reference does not order this after (rules.md D-3).
  # ecr_repository because the script pushes into it.
  depends_on = [module.network, module.key_pair, module.ecr_repository]
}
# What the CloudFormation CreationPolicy used to do.
#
# The template held the stack at the instance until cfn-signal reported from the end of its userdata, and that
# is how the image came to exist before the function was created. The conversion dropped the CreationPolicy -
# its own comment says so - and gave the function depends_on = [aws_instance.vs_code_ec2], which is satisfied
# when RunInstances returns: minutes before docker is even installed.
#
# Lambda is less forgiving than ECS here. An ECS service with a missing image keeps retrying and recovers once
# the push lands; CreateFunction resolves the image on the spot and fails the apply. So the converted template
# could not apply at all on a first run.
#
# This association is the half on the workbench: wait for the bootstrap marker, then ask ECR for the tag. Two
# phases, because they fail for different reasons and the message should say which (rules.md D-5). The second
# is the one that matters - the bootstrap does not stop on error, so the marker means the script reached its
# end, not that the push worked. It also leaves the image_pushed marker the README association starts from.
#
# It is not the half that holds Terraform - module.image_waiter below is. The function used to wait on this
# association through depends_on, trusting wait_for_success_timeout_seconds to hold its create until the
# script had finished. It did not. From CloudTrail and the association's history, 2026-10-11 (KST):
#
#   05:12:13  RunInstances             the workbench launches
#   05:12:27  RegisterManagedInstance  its SSM agent registers
#   05:12:27  CreateAssociation        image_pushed; the provider's waiter reads Overview Success and returns
#   05:12:31  CreateFunction x4        "cannot be assumed by Lambda" - the new role, retried by the provider
#   - 05:12:35
#   05:12:38  SendCommand              the association's script reaches the workbench, 11 seconds after
#                                      Terraform was told it had succeeded
#   05:12:40  CreateFunction           "Source image ...:latest does not exist" - not retried, the apply fails
#   05:15:39  the image is pushed
#   05:15:49  the association's execution ends Success
#
# An association no target has picked up yet reports Success, and every first apply creates this one seconds
# after its instance. That is the provider issue rules.md D-5 warns about (hashicorp/terraform-provider-aws
# #31175), and 063_gamelift_flexmatch and 073_cognito_identity_pool met it the same way.
resource "aws_ssm_association" "image_pushed" {
  name                             = "AWS-RunShellScript"
  association_name                 = "${var.project_name}-image-pushed"
  wait_for_success_timeout_seconds = var.image_wait_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # until rather than a bare test, because a failing test at top level ends the script under -e with no
    # output, and a failing until condition never does. The marker path comes back out of the module it was
    # handed to, so this and the bootstrap cannot disagree about it (rules.md B-5).
    commands = <<-EOT
      set -u
      MARKER=${module.vscode_ec2.marker_file_path}/userdata
      waited=0
      until [ -f "$MARKER" ]; do
        waited=$((waited + 1))
        if [ "$waited" -gt ${var.image_wait_attempts} ]; then
          echo "The workbench bootstrap never finished: $MARKER is still absent. /var/log/cloud-init-output.log on this instance shows where it stopped." >&2
          exit 1
        fi
        sleep ${var.image_wait_interval_seconds}
      done

      pushed=0
      for attempt in $(seq 1 ${var.image_wait_attempts}); do
        if aws ecr describe-images --region ${local.region} --repository-name ${module.ecr_repository.name} --image-ids imageTag=${module.ecr_repository.image_tag} > /dev/null 2>&1; then
          pushed=1
          break
        fi
        sleep ${var.image_wait_interval_seconds}
      done
      if [ "$pushed" -ne 1 ]; then
        echo "${module.ecr_repository.image_uri} is not in the repository although the bootstrap finished. CreateFunction would fail on it; the build or the push failed, and /var/log/cloud-init-output.log on this instance says which." >&2
        exit 1
      fi

      touch ${module.vscode_ec2.marker_file_path}/image_pushed
      EOT
  }

  # The instance id orders this after the instance; the module edge also covers its egress rule and its role's
  # policy, without which SSM Agent cannot register and the association never runs.
  depends_on = [module.vscode_ec2, module.ecr_repository]
}
# The half that holds Terraform: a function that asks ECR for the tag until it is there, invoked synchronously.
# It stops early only when the association above has failed - never on its Success, for the reason in the
# timeline.
#
# The function below takes its image_uri from this module's result rather than from module.ecr_repository, and
# that is the whole ordering: the result is unknown until the invocation has returned, so CreateFunction cannot
# be sent before. No depends_on on module.lambda_function, which would also hold its role and policies - the
# role is better created during the wait, so it has propagated by the time CreateFunction needs it.
module "image_waiter" {
  source = "./modules/ecr_image_waiter"

  function_name   = "${var.project_name}-image-waiter"
  repository_name = module.ecr_repository.name
  repository_arn  = module.ecr_repository.arn
  image_tag       = module.ecr_repository.image_tag
  image_uri       = module.ecr_repository.image_uri
  association_id  = aws_ssm_association.image_pushed.association_id
  association_arn = aws_ssm_association.image_pushed.arn
  partition       = local.partition
  # The same number as the association's own wait, so "how long the bootstrap may take" stays one value, capped
  # at the 900 seconds a Lambda function can run. Capped here rather than by lowering the variable: the
  # association's wait_for_success_timeout_seconds reads it too, and the provider sends any change to that as
  # an UpdateAssociation, which re-runs the check on the workbench. A timeout is not recorded in state, so the
  # next apply simply waits again.
  timeout_seconds = min(var.image_wait_timeout_seconds, 900)

  depends_on = [module.network]
}
module "lambda_function" {
  source = "./modules/container_lambda_function"

  function_name = var.function_name
  # From the waiter, not from module.ecr_repository: this reference is what holds CreateFunction until the
  # image is in the repository (see module.image_waiter).
  image_uri           = module.image_waiter.image_uri
  ecr_repository_name = module.ecr_repository.name
  timeout             = var.lambda_timeout
  memory_size         = var.lambda_memory_size

  # One key, in two places that have to agree: the handler writes it and the role's grant names it
  # (rules.md B-5).
  result_bucket_arn = module.result_bucket.bucket_arn
  result_object_key = var.result_object_key
  environment_variables = {
    BUCKET_NAME             = module.result_bucket.bucket_name
    OBJECT_KEY              = var.result_object_key
    SOURCE_URL              = var.source_url
    REQUEST_TIMEOUT_SECONDS = tostring(var.source_request_timeout_seconds)
  }

  role_name_prefix       = "${var.project_name}-function-"
  additional_policy_arns = var.lambda_additional_policy_arns
  log_retention_in_days  = var.lambda_log_retention_in_days

  region     = local.region
  account_id = local.account_id
  partition  = local.partition

  # The image edge is not here: it is the image_uri reference above. aws_ssm_association.image_pushed used to be
  # in this list, and its create returned before the push - the timeline above (rules.md D-5).
  depends_on = [
    module.network,
    module.result_bucket,
    module.ecr_repository,
  ]
}
# --- README on the workbench ------------------------------------------------------------------------------
locals {
  # Every output this root exposes, defined once. outputs.tf projects this map and the README written onto the
  # workbench renders it, so an output cannot exist without also appearing there (rules.md B-5/H-2).
  #
  # The _monolithic template had one output, the code-server URL. Everything else - how to invoke the function,
  # where its result goes, how to rebuild - had to be found in the console from inside a browser IDE that has
  # no terraform output to ask.
  outputs = {
    vscode_url = {
      order       = 1
      title       = "VS Code URL"
      description = "The workbench, and the _monolithic template's one output. Every command below is meant for its terminal. code-server runs without authentication, so this URL is the credential"
      value       = module.vscode_ec2.vscode_url
    }
    invoke_command = {
      order       = 2
      title       = "1. Invoke the function"
      description = "Runs it once and prints what it returned. statusCode 200 means the page was fetched and written; 500 carries the exception text in its body"
      value       = module.lambda_function.invoke_command
    }
    read_result_command = {
      order       = 3
      title       = "2. Read what it wrote"
      description = "The page the function fetched, read back from the bucket. An error saying the key does not exist means the invocation above did not succeed"
      value       = "aws s3 cp s3://${module.result_bucket.bucket_name}/${var.result_object_key} -"
    }
    presign_command = {
      order       = 4
      title       = "3. Open it in a browser"
      description = "A link valid for an hour. The bucket blocks public access, so this is how the page is viewed without making it public"
      value       = "aws s3 presign s3://${module.result_bucket.bucket_name}/${var.result_object_key} --expires-in 3600"
    }
    function_logs_command = {
      order       = 5
      title       = "4. The function's logs"
      description = "One START, END and REPORT line per invocation, and the traceback if the handler raised"
      value       = module.lambda_function.logs_command
    }
    rebuild_command = {
      order       = 6
      title       = "5. Change the handler and redeploy"
      description = "Edit ${local.build_directory}/index.py, then run this. The push alone changes nothing: Lambda resolved the tag to a digest when the function was created and keeps running that digest, so the second command points it at the new one. Keep src/index.py in this repository in step - the next apply ships that file, not the edited copy"
      value       = "${local.build_directory}/build.sh && ${module.lambda_function.update_code_command}"
    }
    resolved_image_command = {
      order       = 7
      title       = "6. Which image is the function running"
      description = "The tag it was created from and the digest Lambda actually runs. Different digests in the repository and here mean the step above was only half done"
      value       = module.lambda_function.resolved_image_command
    }
    list_images_command = {
      order       = 8
      title       = "7. What is in the repository"
      description = "One image from the bootstrap, and one per rebuild. Empty means the bootstrap never got as far as pushing"
      value       = module.ecr_repository.list_images_command
    }
    function_name = {
      order       = 9
      title       = "Function name"
      description = "Name of the Lambda function"
      value       = module.lambda_function.function_name
    }
    ecr_repository_url = {
      order       = 10
      title       = "ECR repository"
      description = "Where the workbench pushes and the function's image comes from"
      value       = module.ecr_repository.repository_url
    }
    result_bucket_name = {
      order       = 11
      title       = "Result bucket"
      description = "Where the function writes the page. Emptied by terraform destroy - see bucket_force_destroy"
      value       = module.result_bucket.bucket_name
    }
    log_group_name = {
      order       = 12
      title       = "Log group"
      description = "The function's log group, declared with a retention rather than left for Lambda to create"
      value       = module.lambda_function.log_group_name
    }
    session_command = {
      order       = 13
      title       = "Shell on the workbench"
      description = "Session Manager, for when code-server is what is broken. Needs no inbound rule and no key"
      value       = module.vscode_ec2.session_command
    }
    private_key_command = {
      order       = 14
      title       = "Workbench SSH key"
      description = "Retrieves the generated private key from Parameter Store into key.pem. SSH also needs ssh_ingress_cidr_blocks, which is empty by default as the _monolithic template had it"
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
# The README, written onto the workbench because the work happens there and a browser IDE has no terraform
# output to ask (rules.md H-2). code-server opens /home/ec2-user, so this is the first file in the explorer.
#
# It waits for the image gate's marker rather than the bootstrap's: the README describes a function that exists
# only once the image was pushed, and the chain is userdata -> image_pushed -> vscode_readme, one until loop and
# one marker per association (rules.md D-5).
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  association_name                 = "${var.project_name}-vscode-readme"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The terminator is quoted and cannot occur in the body; Terraform has already substituted every value, so
    # there is nothing left for the shell to expand.
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/image_pushed ]; do sleep 10; done
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_readme
      EOT
  }
  depends_on = [aws_ssm_association.image_pushed, module.lambda_function]
}
