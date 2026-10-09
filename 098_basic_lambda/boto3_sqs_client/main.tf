data "aws_region" "current" {}
# The AMI id, from the public parameter AWS maintains for the latest Amazon Linux 2023 image.
#
# insecure_value rather than value: the provider marks a parameter's value sensitive whatever its type, and a
# sensitive value cannot be used for an instance's ami attribute without nonsensitive(). insecure_value is the
# provider's own accessor for a parameter that is not a secret, and a public AMI id is not one.
#
# Read here and passed into both instance modules as an id, so neither module has to know where it came from
# (rules.md B-6). It also keeps the lookup out of modules that carry depends_on, which would defer the read to
# apply (rules.md D-6) - harmless for an AMI id, which feeds no for_each key, but there is no reason to take
# it on.
data "aws_ssm_parameter" "al2023_ami_id" {
  name = var.al2023_ami_ssm_parameter_name
}
module "network" {
  source = "./modules/network"

  vpc_cidr_block          = var.vpc_cidr_block
  vpc_name                = "queue-vpc"
  internet_gateway_name   = "queue-igw"
  public_subnet_name      = "queue-pub"
  public_route_table_name = "queue-pub-rt"
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name_prefix = "${var.project_name}-"

  # This module uses nothing from network and does not need a VPC to create a key pair. It waits anyway,
  # because the rule is that a root with a network module has no module starting before that module finishes -
  # an exception here would mean the next reader has to decide, per module, whether the omission was reasoned
  # or forgotten (rules.md D-3).
  depends_on = [module.network]
}
module "sqs_queue" {
  source = "./modules/sqs_queue"

  name                       = var.queue_name
  message_retention_seconds  = var.queue_message_retention_seconds
  visibility_timeout_seconds = var.queue_visibility_timeout_seconds

  # A regional service with no VPC involvement at all, so this is the same case as key_pair: no dependency
  # exists, and it waits for network regardless so that every module in this root is behind it (rules.md D-3).
  depends_on = [module.network]
}
module "log_metric_filter" {
  source = "./modules/log_metric_filter"

  log_group_name        = var.log_group_name
  retention_in_days     = var.log_retention_days
  filter_name           = "queue-filter"
  filter_pattern        = var.metric_filter_pattern
  metric_name           = var.metric_name
  metric_namespace      = var.metric_namespace
  metric_window_minutes = var.metrics_window_minutes

  # Also independent of the VPC, and also ordered after network for the same reason (rules.md D-3). What it is
  # genuinely ahead of is the worker instance, which is expressed on that module rather than here.
  depends_on = [module.network]
}
module "lambda_function" {
  source = "./modules/lambda_function"

  function_name                   = var.lambda_function_name
  role_name                       = var.lambda_role_name
  source_directory                = "${path.root}/${var.lambda_source_directory}"
  runtime                         = var.lambda_runtime
  timeout                         = var.lambda_timeout
  function_url_authorization_type = var.lambda_function_url_authorization_type
  log_retention_days              = var.log_retention_days
  metrics_window_minutes          = var.metrics_window_minutes

  # Both forms of the same queue: the URL for the handler's environment, the ARN for the IAM statement. They
  # come from the queue module rather than being assembled from queue_name, which is what makes it impossible
  # to grant the function access to one queue while pointing it at another (rules.md B-6).
  queue_url = module.sqs_queue.queue_url
  queue_arn = module.sqs_queue.queue_arn

  # The function is not in the VPC - it reaches SQS over the public endpoint - so the only ordering it needs
  # is the queue, which the value references above already give it. network is listed because this root has a
  # network module and nothing starts before it finishes (rules.md D-3).
  depends_on = [module.network, module.sqs_queue]
}
locals {
  # Rendered once and consumed twice: the workbench's user data writes it on first boot, and the SSM
  # association at the bottom of this file rewrites it on any later apply whose rendering changed (rules.md
  # B-5). Keeping the body in one place matters here more than usual, because user_data runs exactly once per
  # instance - editing the generator's sizing without the association produces a plan that says the instance
  # is updated in place while the file on the running host stays at its first-boot contents.
  #
  # function_name is passed in rather than left as the literal the script used to carry, so the name the
  # generator looks up cannot fall behind lambda_function_name.
  message_app_py = templatefile("${path.root}/scripts/message_app.py.tftpl", {
    function_name  = module.lambda_function.function_name
    total_requests = var.load_test_total_requests
    concurrency    = var.load_test_concurrency
    batch_delay    = var.load_test_batch_delay_seconds
    max_retries    = var.load_test_max_retries
  })
  # The worker, rendered here because this is the only place that holds every value it needs: the queue URL
  # from one module, the region from the provider, and the log file path that the agent configuration in
  # another module also has to agree with.
  #
  # It is a template file rather than a heredoc inside a module for the same reason the generator is: Python
  # embedded in HCL is Python that nothing can check, and the _monolithic template's copy of this script
  # carried a bug for exactly that reason - logging.basicConfig with no level, which silently discarded every
  # success line the metric filter was supposed to count. The template file notes it where it happens.
  worker_py = templatefile("${path.root}/scripts/worker.py.tftpl", {
    queue_url          = module.sqs_queue.queue_url
    region             = data.aws_region.current.region
    log_file           = var.worker_log_file_path
    visibility_timeout = var.queue_visibility_timeout_seconds
    max_workers        = var.worker_max_workers
    wait_time          = var.worker_wait_time_seconds
    max_messages       = var.worker_max_messages
  })
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  vpc_id    = module.network.vpc_id
  subnet_id = module.network.public_subnet_a_id
  ami_id    = data.aws_ssm_parameter.al2023_ami_id.insecure_value
  key_name  = module.key_pair.key_name

  instance_name       = var.vscode_instance_name
  instance_type       = var.vscode_instance_type
  code_server_port    = var.code_server_port
  code_server_version = var.code_server_version
  ingress_cidr_blocks = var.workbench_ingress_cidr_blocks

  load_generator_script = local.message_app_py

  # Lets the associations below know when the bootstrap has finished (rules.md D-5/H-2). The module touches
  # <path>/userdata as its very last step, after code-server, pip and the generator are all in place.
  marker_file_path = var.marker_file_path

  # Referencing module.network.vpc_id and one subnet orders this after those two resources and after nothing
  # else in that module - not after the route to the internet gateway, which is the one every line of this
  # instance's bootstrap depends on. cloud-init starts dnf within seconds of the launch, so losing that race
  # leaves code-server uninstalled, which is the same end state as a missing egress rule except intermittent
  # (rules.md D-3).
  depends_on = [module.network, module.key_pair]
}
module "queue_worker_ec2" {
  source = "./modules/queue_worker_ec2"

  vpc_id    = module.network.vpc_id
  subnet_id = module.network.public_subnet_a_id
  ami_id    = data.aws_ssm_parameter.al2023_ami_id.insecure_value
  key_name  = module.key_pair.key_name

  instance_name = var.worker_instance_name
  instance_type = var.worker_instance_type
  log_file_path = var.worker_log_file_path
  start_worker  = var.start_worker

  worker_script = local.worker_py

  queue_url = module.sqs_queue.queue_url
  queue_arn = module.sqs_queue.queue_arn

  # From the module that declares the group, not from var.log_group_name. Both would produce the same string
  # today, and that is the point: taking it from the output means the agent's configuration cannot name a
  # group nothing created (rules.md B-5).
  log_group_name = module.log_metric_filter.log_group_name

  # The workbench's security group as the SSH source, as a map with a key chosen here. A list would fail the
  # plan with "Invalid for_each argument", because the value is another module's output and so is unknown
  # until apply, while for_each keys have to be known at plan time (rules.md B-8). The key also becomes the
  # rule's description, so the plan reads "SSH from the vscode_ec2 security group".
  ingress_source_security_groups = {
    vscode_ec2 = module.vscode_ec2.security_group_id
  }

  # log_metric_filter is here for a real reason rather than for symmetry. The CloudWatch agent on this
  # instance is configured with the log group's name, and an agent that starts before the group exists creates
  # it itself - at which point Terraform's own create for that group fails with ResourceAlreadyExistsException,
  # and the group that survives is the agent's, with no retention and outside state. Ordering the instance
  # after the group removes the race rather than making it unlikely (rules.md D-2).
  depends_on = [module.network, module.key_pair, module.sqs_queue, module.log_metric_filter]
}
locals {
  # Every output this project exposes, defined once. outputs.tf projects these and the README written onto the
  # workbench renders them, so no value expression is written twice (rules.md B-5/H-2). Adding an entry here is
  # what makes an output possible, which is what keeps the README from falling behind outputs.tf.
  #
  # The map's keys are the output names, and order decides the README's section order - which here is the
  # order the demo is run in, not the order the resources were created.
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here. Everything below is meant to be run from its terminal, which is why this instance exists at all. No password: code-server is configured with auth: none, so the only thing protecting it is the address and whatever workbench_ingress_cidr_blocks allows"
      value       = module.vscode_ec2.vscode_url
    }
    lambda_function_url = {
      order       = 2
      title       = "Lambda function URL"
      description = "The endpoint the load generator posts to. Public and unauthenticated while the authorization type is NONE, which is how the original configured it - a POST from anywhere puts a message on the queue"
      value       = module.lambda_function.function_url
    }
    lambda_invoke_command = {
      order       = 3
      title       = "1. Send one message by hand"
      description = "The smallest end-to-end test. A literal Success body means the handler reached the queue; a 500 means it was refused, and a 403 means the invoke permission is missing or the URL now needs signing"
      value       = module.lambda_function.invoke_command
    }
    queue_depth_command = {
      order       = 4
      title       = "2. Watch the backlog"
      description = "Messages waiting, and messages currently in flight. After the command above the first number should be 1. This is not a Terraform value and never can be - it changes by the second"
      value       = module.sqs_queue.depth_command
    }
    start_worker_command = {
      order       = 5
      title       = "3. Start the drain"
      description = "Run this on the worker instance, over SSH from here or through SSM Session Manager. The unit is installed and left stopped unless start_worker was set true, so the backlog is visible before anything consumes it"
      value       = module.queue_worker_ec2.start_worker_command
    }
    run_load_generator_command = {
      order       = 6
      title       = "4. Run the load generator"
      description = "Posts load_test_total_requests requests in batches of load_test_concurrency. The per-batch counts it prints are successes; a batch short of its size means Lambda answered 429 more often than the retry budget absorbed, which is the throttling this project is built to show"
      value       = module.vscode_ec2.run_load_generator_command
    }
    lambda_throttle_metrics_command = {
      order       = 7
      title       = "5. Invocations, throttles and errors"
      description = "The measurement. A function URL is a synchronous invoke, so each in-flight request holds one concurrent execution and the excess is rejected with 429 rather than queued - which is why these three numbers, not the duration, are what the generator's sizing changes"
      value       = module.lambda_function.throttle_metrics_command
    }
    lambda_concurrency_metrics_command = {
      order       = 8
      title       = "6. The ceiling the throttles came from"
      description = "Maximum ConcurrentExecutions per minute. A value that sits flat at one number for the whole run is the concurrency limit being reached, not a slow function - raising memory moves neither it nor the throttle count"
      value       = module.lambda_function.concurrency_metrics_command
    }
    queue_metric_statistics_command = {
      order       = 9
      title       = "7. Messages the worker reported processing"
      description = "The custom metric the log filter publishes, which is the consumer's side of the same run. An empty result has three causes in order of likelihood: the worker is not started, the CloudWatch agent is not shipping, or the filter pattern lost its quotes"
      value       = module.log_metric_filter.metric_statistics_command
    }
    queue_log_tail_command = {
      order       = 10
      title       = "The raw lines behind that metric"
      description = "Run this before trusting an empty metric. Lines here with no datapoints isolates the fault to the filter pattern; no lines at all points at the worker or the agent"
      value       = module.log_metric_filter.log_tail_command
    }
    worker_status_command = {
      order       = 11
      title       = "Worker service status"
      description = "Whether the drain is running and what it last said. An AccessDenied loop naming ReceiveMessage means the inline queue policy is not in place yet"
      value       = module.queue_worker_ec2.worker_status_command
    }
    worker_log_command = {
      order       = 12
      title       = "Worker log file on the instance"
      description = "The file the agent tails, read directly. The service running while this file stays empty is what a logging call below the root logger's level looks like - which is the bug the original's worker script carried"
      value       = module.queue_worker_ec2.worker_log_command
    }
    lambda_logs_command = {
      order       = 13
      title       = "Function logs"
      description = "The handler's own output. KeyError here means QUEUE_URL never reached the environment; nothing at all after a load run means the requests never arrived"
      value       = module.lambda_function.logs_command
    }
    worker_instance_id = {
      order       = 14
      title       = "Worker instance id"
      description = "For aws ssm start-session, which is the way onto the worker that needs no key and no inbound rule"
      value       = module.queue_worker_ec2.instance_id
    }
    worker_private_ip = {
      order       = 15
      title       = "Worker private address"
      description = "SSH target from this workbench. Its security group admits this instance's group and nothing else, so this only works from here"
      value       = module.queue_worker_ec2.private_ip
    }
    private_key_command = {
      order       = 16
      title       = "Private SSH key"
      description = "Retrieves the generated key from Parameter Store, which is where CloudFormation would have put it. A command rather than the key, so terraform output does not print it"
      value       = module.key_pair.private_key_command
    }
    queue_url = {
      order       = 17
      title       = "Queue URL"
      description = "The queue both sides are configured against. Worth comparing with the function's and the worker's own copies of it, which both modules hand back out - a mismatch there is a demo where nothing appears to happen"
      value       = module.sqs_queue.queue_url
    }
    cloud_init_log_command = {
      order       = 18
      title       = "Bootstrap log for this instance"
      description = "Every line of the user data, with set -x. First place to look when code-server does not answer: connection timeouts on dnf and wget here mean the security group lost its egress rule"
      value       = module.vscode_ec2.cloud_init_log_command
    }
  }
  # Iterating local.outputs directly would order the sections by key, which puts "4. Run the load generator"
  # above "1. Send one message by hand". Re-keying by the order field and taking values() sorts by that
  # instead - values() returns a map's values ordered by key - so the README reads in the order the demo is
  # run, and the order stays fully determined by the configuration rather than shuffling between applies.
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  # Rendered from the same map, so an added output appears here without anyone remembering to edit two places
  # (rules.md H-2).
  readme_body = join("\n", concat(
    ["# ${var.project_name}", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}
# The work happens inside code-server in a browser, where "terraform output" does not exist, so every output
# above is also written to a README in the home directory the IDE opens (rules.md H-2). Combining several
# modules' outputs is the root's job, so this lives here rather than inside the instance module, which never
# learns what gets written into its home directory (rules.md C-1).
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds

  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }

  parameters = {
    # The until loop is what orders this after the bootstrap - not depends_on, which only orders it after the
    # instance's create call returns, and not wait_for_success_timeout_seconds, which is a deadline rather
    # than a dependency (rules.md D-5). The marker path comes back out of the module it was passed into, so it
    # is defined in exactly one place (rules.md B-5).
    #
    # SSM runs as root, hence the chown - without it the file is not editable from the IDE. The heredoc
    # delimiter is quoted and deliberately unlikely to appear in the body: Terraform has already substituted
    # every value, so the shell has no reason to touch a dollar sign or a backtick in a README full of CLI
    # commands.
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
# The second step of the same chain, and the reason the generator is rendered in a local rather than written
# only into user data.
#
# user_data runs once per instance. Changing load_test_concurrency therefore updates Terraform state and
# leaves the file on a running workbench at whatever it was on first boot - a plan that reports an in-place
# update which never reaches the disk. An association re-runs whenever its parameters change, and "cat >" is a
# truncating write, so an apply that changes the sizing lands on the instance without replacing it.
#
# It waits on the README association's marker rather than on the user data marker, which is what D-5 means by
# the shell enforcing the order: each step waits for the previous step's marker, does its work, and leaves its
# own. depends_on is declared as well, but only to make the intent visible in the graph - the marker is what
# actually holds the order, because a successful association says the command was accepted, not that the work
# it was waiting for is finished.
resource "aws_ssm_association" "vscode_message_app" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.message_app_timeout_seconds

  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }

  parameters = {
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/vscode_readme ]; do sleep 10; done
      cat > ${module.vscode_ec2.load_generator_path} << 'TFLOADGEN'
      ${local.message_app_py}
      TFLOADGEN
      chown ec2-user:ec2-user ${module.vscode_ec2.load_generator_path}
      touch ${module.vscode_ec2.marker_file_path}/message_app
      EOT
  }

  depends_on = [aws_ssm_association.vscode_readme]
}
