# Everything that has to be read before the modules, gathered here rather than inside them.
#
# The account id and the region are injected into the modules that need them instead of being read
# again with data.aws_caller_identity and data.aws_region in each one. They would be correct either
# way, but modules/config_rule_lambda carries depends_on, and a module that does has every data
# source inside it deferred to apply - so the invoke permission's source ARN and every verification
# command built from the region would read "(known after apply)" in a plan for no reason (rules.md
# D-6, B-6).
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
# The workbench AMI. In the root so the module takes an ami- id and does not care where it came from
# (rules.md B-6).
data "aws_ssm_parameter" "ami_id" {
  name = var.ami_ssm_parameter_name
}
# The rule's Lambda deployment package.
#
# This one is in the root because it has to be, for two independent reasons - and the second is the
# one that matters here.
#
# archive_file resolves source_file against path.module, and the Python lives at the root of the
# project, so a copy of this data source inside modules/config_rule_lambda would look for
# modules/config_rule_lambda/lambda_src and fail with "no file or directory".
#
# And that module carries depends_on = [module.config_recorder], which defers every data source inside
# it to apply. output_base64sha256 would then be unknown at plan, which does not merely look untidy:
# source_code_hash is the only thing that tells Terraform the function's code changed, so an edited
# index.py would stop appearing as a diff. Plan would report no change to the function, apply would
# upload the new zip anyway, and the two would disagree about what is deployed (rules.md D-6).
#
# The zip is written into build/ as a side effect of reading this during plan, which is why that
# directory appears and why nothing in it should be edited.
data "archive_file" "lambda_function" {
  type        = "zip"
  source_file = "${path.module}/${var.lambda_source_relative_path}"
  output_path = "${path.module}/${var.lambda_build_relative_path}"
}
# On module ordering in this root.
#
# Every module starts after the whole of module.network, including the ones that take nothing from
# it - the key pair, the IAM fixtures and the Config recorder have no use for a VPC. The rule is that
# a root with a network module has no exceptions, so that nobody has to decide per module whether an
# omission was reasoned or forgotten, and so destroy takes the network down last (rules.md D-3).
#
# Adding those edges is safe for plan here, which is worth checking rather than assuming: depends_on
# on a module defers every data source inside it to apply (rules.md D-6), and none of these modules
# declares one - everything they read is read in this root and passed in.
#
# The one ordering edge besides that is real: the rule cannot exist before a configuration recorder
# does. config_rule_lambda reaches network through it.
module "network" {
  source = "./modules/network"

  region                   = data.aws_region.current.region
  availability_zone_suffix = var.availability_zone_suffix
  vpc_cidr_block           = var.vpc_cidr_block
  # Derived from project_name, as the Config bucket prefix is, rather than four more name variables.
  name_prefix = var.project_name
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name = var.key_name

  depends_on = [module.network]
}
module "governed_instance_profiles" {
  source = "./modules/governed_instance_profiles"

  profiles = var.governed_instance_profiles

  depends_on = [module.network]
}
module "config_recorder" {
  source = "./modules/config_recorder"

  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  recorder_name               = var.config_recorder_name
  recorder_enabled            = var.config_recorder_enabled
  delivery_channel_name       = var.config_delivery_channel_name
  snapshot_delivery_frequency = var.config_snapshot_delivery_frequency
  excluded_resource_types     = var.config_excluded_resource_types
  role_policy_arns            = var.config_service_role_policy_arns
  bucket_force_destroy        = var.config_bucket_force_destroy
  # Derived from project_name rather than taken as its own variable, so the bucket is recognisable
  # without a second name to keep in step. S3 appends a unique suffix to a prefix, which is what the
  # _monolithic template was doing by hand with a uuid.
  bucket_name_prefix = "${var.project_name}-config-"

  depends_on = [module.network]
}
module "config_rule_lambda" {
  source = "./modules/config_rule_lambda"

  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  rule_name           = var.config_rule_name
  rule_resource_types = var.config_rule_resource_types
  function_name       = var.lambda_function_name
  runtime             = var.lambda_runtime
  handler             = var.lambda_handler
  timeout_seconds     = var.lambda_timeout_seconds
  log_group_name      = var.lambda_log_group_name
  create_log_group    = var.create_lambda_log_group
  log_retention_days  = var.lambda_log_retention_days
  # Built above, not in the module, for the two reasons on the data source.
  filename         = data.archive_file.lambda_function.output_path
  source_code_hash = data.archive_file.lambda_function.output_base64sha256

  # PutConfigRule is rejected with NoAvailableConfigurationRecorderException when the account has no
  # configuration recorder, and nothing in this module's inputs refers to the recorder, so the edge
  # has to be stated (rules.md D-2). It also gives the right destroy order: the rule goes before the
  # recorder, which is the direction that works - deleting a recorder out from under a rule leaves the
  # rule unevaluatable rather than failing.
  #
  # module.network is not listed. config_recorder already waits for it, and a module's depends_on
  # means after all of that module, so this is after the network too (rules.md D-3).
  depends_on = [module.config_recorder]
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name                        = var.vscode_instance_name
  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_id
  ami_id                      = data.aws_ssm_parameter.ami_id.insecure_value
  instance_type               = var.vscode_instance_type
  key_name                    = module.key_pair.key_name
  security_group_name         = var.vscode_security_group_name
  security_group_description  = var.vscode_security_group_description
  ingress_cidr_blocks         = var.vscode_ingress_cidr_blocks
  ssh_port                    = var.vscode_ssh_port
  code_server_port            = var.vscode_code_server_port
  code_server_version         = var.code_server_version
  associate_public_ip_address = var.vscode_associate_public_ip_address
  iam_policy_arns             = var.vscode_iam_policy_arns
  # Derived from the instance name rather than given its own variable, so the role and the instance
  # profile are recognisably this instance's without a second name to keep in step.
  role_name_prefix = "${var.vscode_instance_name}-"
  # Lets the README association below know when the bootstrap has finished (rules.md H-2). The module
  # touches <path>/userdata as its very last step.
  marker_file_path = var.marker_file_path
  # No kubectl, eksctl or helm. rules.md H-1 requires all five tools only in a root that also declares
  # an EKS cluster, and there is no cluster here - the five-tool rule exists because a workbench next
  # to a cluster is useless without them, and installing them next to an AWS Config rule would only
  # add a few minutes to every boot. Everything this demo does from the instance is the AWS CLI, which
  # Amazon Linux 2023 ships.
  #
  # Setting the CLI's default region is worth the one line: the commands in the README pass --region
  # explicitly, but anything typed by hand in a code-server terminal will not.
  additional_user_data = <<-EOT
    sudo -Eu ec2-user bash << 'EOF'
    export HOME=/home/ec2-user
    aws configure set default.region ${data.aws_region.current.region}
    EOF
  EOT

  # The subnet ID orders the instance after the subnet only - not after the route to the internet
  # gateway or the subnet's route table association, neither of which is an output. An instance that
  # boots before those exist starts its bootstrap with no way out of the VPC (rules.md D-3).
  depends_on = [module.network]
}
locals {
  # Every output this project exposes, defined once. outputs.tf projects these and the README
  # association below renders them, so no value is written in two places (rules.md B-5, H-2). Adding
  # an entry here is what makes an output possible, which is what stops the README from falling behind
  # outputs.tf.
  #
  # Almost nothing interesting about this project is knowable to Terraform. Whether the recorder is
  # recording, whether the rule ever evaluated anything, what verdict it reached and whether it
  # rewrote the fixture it judged are all facts about a running service, so most of these entries are
  # commands to ask rather than values to read - and their descriptions carry what the answer means,
  # because for this rule "nothing" is the expected answer for a while.
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here. It runs with authentication disabled on an instance whose role carries AdministratorAccess, so the URL is the credential"
      value       = module.vscode_ec2.vscode_url
    }
    instance_id = {
      order       = 2
      title       = "Workbench instance ID"
      description = "ID of the code-server instance. Also the one EC2 instance in this project that the Config rule deliberately ignores"
      value       = module.vscode_ec2.instance_id
    }
    session_manager_command = {
      order       = 3
      title       = "Shell without opening a port"
      description = "Starts a shell through SSM, which works even with vscode_ingress_cidr_blocks narrowed to nothing. Requires the SSM agent to have registered, which it can only do with outbound access - if this hangs, read bootstrap_log_command"
      value       = "aws ssm start-session --target ${module.vscode_ec2.instance_id}"
    }
    port_forward_command = {
      order       = 4
      title       = "Reach code-server without opening a port"
      description = "Forwards the IDE port to localhost through SSM, then open http://localhost:${module.vscode_ec2.code_server_port}. The safe way to use this instance with the ingress list narrowed"
      value       = "aws ssm start-session --target ${module.vscode_ec2.instance_id} --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"${module.vscode_ec2.code_server_port}\"],\"localPortNumber\":[\"${module.vscode_ec2.code_server_port}\"]}'"
    }
    private_key_parameter = {
      order       = 5
      title       = "SSH private key"
      description = "SSM parameter holding the generated private key. Read it with: aws ssm get-parameter --with-decryption --name <this> --query Parameter.Value --output text"
      value       = module.key_pair.private_key_parameter_name
    }
    config_recorder_status_command = {
      order       = 6
      title       = "1. Check that AWS Config is recording"
      description = "Start here, because everything downstream is silent when this is wrong. recording: true with lastStatus: SUCCESS is working. recording: false means the recorder exists but was never started, and a change-triggered rule with no configuration items evaluates nothing, forever, with no error. lastStatus: FAILURE naming the bucket is the delivery permissions rather than the rule"
      value       = module.config_recorder.recorder_status_command
    }
    config_rule_name = {
      order       = 7
      title       = "The rule"
      description = "What the rule checks: an EC2 instance is compliant when the instance profile it carries holds exactly one role, and that role's attached managed policies are exactly AmazonS3ReadOnlyAccess. No profile, no policies, or any other policy is non-compliant. One instance is exempt by Name tag - this project's own workbench, whose role holds AdministratorAccess"
      value       = module.config_rule_lambda.rule_name
    }
    governed_instance_profiles = {
      order       = 8
      title       = "The fixtures the rule is here to judge"
      description = "Instance profiles created for this demo, with what each one is supposed to show. They are attached to nothing: the rule is change-triggered on EC2 instances, so an instance has to carry one before there is anything to evaluate"
      value = join("\n", [for key, name in module.governed_instance_profiles.instance_profile_names :
        "${name} (${key})\n    ${module.governed_instance_profiles.demonstrates[key]}\n    started with: ${length(module.governed_instance_profiles.initial_policy_arns[key]) == 0 ? "no policies" : join(", ", module.governed_instance_profiles.initial_policy_arns[key])}"
      ])
    }
    launch_test_instance_commands = {
      order       = 9
      title       = "2. Give the rule something to evaluate"
      description = "Launches one t3.micro per fixture into this project's public subnet, each carrying one of the governed instance profiles. These instances are what the rule evaluates; terminate them with the command further down when finished, because nothing here cleans them up and terraform destroy does not know about them"
      value = join("\n", [for key, name in module.governed_instance_profiles.instance_profile_names :
        "aws ec2 run-instances --region ${data.aws_region.current.region} --image-id ${data.aws_ssm_parameter.ami_id.insecure_value} --instance-type ${var.test_instance_type} --subnet-id ${module.network.public_subnet_id} --iam-instance-profile Name=${name} --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=governance-test-${key}}]' --query 'Instances[0].InstanceId' --output text"
      ])
    }
    force_evaluation_command = {
      order       = 10
      title       = "3. Make the rule evaluate now"
      description = "A change-triggered rule reacts to recorded changes, and recording a new instance takes a few minutes. This replays the rule against what has already been recorded. It returns immediately and evaluates asynchronously, so wait a minute before reading the results"
      value       = module.config_rule_lambda.force_evaluation_command
    }
    compliance_details_command = {
      order       = 11
      title       = "4. Read the verdicts"
      description = "One row per evaluated instance. An empty table right after apply is the expected state rather than a failure - the rule has had nothing to judge yet. Once the test instances are evaluated, expect both to read COMPLIANT with the annotation \"Only AmazonS3ReadOnlyAccess Attached\": that is the rule working rather than the rule letting them through, because the handler rewrote the roles before it finished. An empty table after launching the instances and forcing an evaluation is the real failure, and step 6 is where it is explained"
      value       = module.config_rule_lambda.compliance_details_command
    }
    fixture_policy_check_command = {
      order       = 12
      title       = "5. See that the rule rewrote the fixture"
      description = "The handler does not only report. On finding a role carrying anything other than AmazonS3ReadOnlyAccess it detaches it, attaches AmazonS3ReadOnlyAccess and then reports compliant - so after one evaluation this lists AmazonS3ReadOnlyAccess where the fixture started with AdministratorAccess. Two consequences. The non-compliant verdict is mostly invisible in step 4: the handler reports NON_COMPLIANT and then COMPLIANT within the same invocation, using the same result token and the same ordering timestamp, so the second overwrites the first - read the log in step 6 to see the verdict it actually reached. And terraform plan will afterwards want to reattach what the handler removed, because the attachment is still in state; applying that hands the rule the same fixture to strip again"
      value = join("\n", [for key, role in module.governed_instance_profiles.role_names :
        "aws iam list-attached-role-policies --role-name ${role} --query 'AttachedPolicies[].PolicyName' --output text   # ${key}"
      ])
    }
    lambda_log_command = {
      order       = 13
      title       = "6. When nothing happened at all"
      description = "The handler's log, and the only place a rule that never evaluates leaves evidence. Runtime.HandlerNotFound, an AccessDenied from a missing permission and a timeout all look identical from the Config side - the rule simply reports nothing. A log group that exists but is empty means Config has never invoked the function, which points back at the recorder"
      value       = module.config_rule_lambda.log_command
    }
    terminate_test_instances_command = {
      order       = 14
      title       = "7. Clean up the test instances"
      description = "Terminates everything launched by step 2 and waits until it is gone. Run this before terraform destroy: those instances are not in Terraform's state, an instance still holding one of the governed instance profiles blocks deleting that profile, and one still holding a network interface in this project's subnet stops the destroy at the subnet and the internet gateway with DependencyViolation. The wait is there because a terminating instance holds its interface until it reaches terminated. Fails with \"expected at least one argument\" when there is nothing left to terminate"
      # Filtered by this project's VPC as well as the tag, now that the VPC is this project's own: an
      # instance someone else named governance-test-* elsewhere in the region is not this command's to
      # terminate.
      value = "ids=$(aws ec2 describe-instances --region ${data.aws_region.current.region} --filters 'Name=tag:Name,Values=governance-test-*' 'Name=vpc-id,Values=${module.network.vpc_id}' 'Name=instance-state-name,Values=pending,running,stopping,stopped' --query 'Reservations[].Instances[].InstanceId' --output text) && aws ec2 terminate-instances --region ${data.aws_region.current.region} --instance-ids $ids && aws ec2 wait instance-terminated --region ${data.aws_region.current.region} --instance-ids $ids"
    }
    config_bucket_name = {
      order       = 15
      title       = "Config delivery bucket"
      description = "Where configuration history and snapshots are written. Holds objects Terraform never created, which is why config_bucket_force_destroy defaults to true - with it false, destroy stops here with everything else already gone"
      value       = module.config_recorder.bucket_name
    }
    config_snapshot_list_command = {
      order       = 16
      title       = "What has been delivered"
      description = "Empty for the first hour is normal, because that is the snapshot frequency. Empty together with a FAILURE in the recorder status is the bucket policy or the delivery policy on the Config role"
      value       = module.config_recorder.snapshot_list_command
    }
    bootstrap_log_command = {
      order       = 17
      title       = "Read the workbench bootstrap log"
      description = "The user data script runs with set -x, so this is the first place to look when code-server does not answer or the SSM agent never registered"
      value       = "sudo tail -n 100 /var/log/cloud-init-output.log"
    }
  }
  # Iterating local.outputs directly would order the README's sections by key. Re-keying by the order
  # field and taking values() sorts by that instead - values() returns a map's values ordered by key -
  # so the numbered steps above read top to bottom, still decided entirely by the configuration rather
  # than shuffling between applies.
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
# The work happens inside code-server in a browser, where "terraform output" does not exist, so every
# output above is also written to a README in the home directory the IDE opens (rules.md H-2).
#
# This association works because the instance's role carries AdministratorAccess, which subsumes
# AmazonSSMManagedInstanceCore - the policy this pattern normally depends on is not in the list
# because it would add nothing.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop is what orders this after the bootstrap, not depends_on and not
    # wait_for_success_timeout_seconds, and the marker this command leaves behind is what a later
    # association would wait on (rules.md D-5). The marker path comes back out of the module rather
    # than being restated from var.marker_file_path here (rules.md B-5).
    #
    # SSM runs this as root, hence the chown: without it the file is not editable from the IDE.
    #
    # The heredoc delimiter is quoted, so the shell expands nothing in the body - the README contains
    # command substitutions and single quotes that Terraform has already resolved, and TFREADME is
    # long enough not to appear in any of them. If this association ever fails with "unexpected state
    # 'Failed'" and an execution time under a tenth of a second, the cause is CRLF in a .tf file: the
    # terminator becomes TFREADME\r, the heredoc runs to the end of the script and nothing executes at
    # all (rules.md A-4).
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/userdata ]; do sleep 10; done
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_readme
      EOT
  }
}
