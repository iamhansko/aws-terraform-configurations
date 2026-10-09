# The consumer: an instance that drains the queue and writes one line per message, which the CloudWatch agent
# ships to the log group the metric filter watches.
#
# This is the other half of what the _monolithic template called queue-ec2, and the name is kept. It is not a
# workbench - no IDE, no inbound rule except SSH from the workbench's group - which is why its role is
# narrowed rather than left at AdministratorAccess (see iam_policy_arns).
resource "aws_security_group" "queue_worker_security_group" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
# Standalone rules, both directions, never inline blocks (rules.md F-2).
#
# The egress rule is the one that has to be here. CloudFormation leaves the VPC's default allow-all egress in
# place when a template declares only SecurityGroupIngress, which is all this template declared; Terraform
# revokes it, and an inline block set is authoritative over the whole group, so a conversion that copies only
# the ingress rules produces a group with no outbound access.
#
# On this host that failure is quieter than on the workbench. The apply succeeds and the instance runs, but
# dnf cannot reach the repositories, so the CloudWatch agent is never installed and pip never gets boto3 - and
# the visible symptom is a log group that stays empty and a metric with no datapoints, which reads as "the
# worker is not processing anything" rather than as a networking problem.
resource "aws_vpc_security_group_egress_rule" "queue_worker_egress" {
  security_group_id = aws_security_group.queue_worker_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
# for_each straight over the map, with no toset() - the keys are literals in the caller's configuration and
# the values are the unknown part, which is the only arrangement for_each accepts when the IDs come from
# another module (rules.md B-8). each.key in the description is what makes a plan readable here: "SSH from the
# vscode_ec2 security group" rather than a rule whose source shows as a token that is only resolved on apply.
resource "aws_vpc_security_group_ingress_rule" "queue_worker_source_group_ssh_ingress" {
  for_each = var.ingress_source_security_groups

  security_group_id            = aws_security_group.queue_worker_security_group.id
  description                  = "SSH from the ${each.key} security group"
  ip_protocol                  = "tcp"
  from_port                    = var.ssh_port
  to_port                      = var.ssh_port
  referenced_security_group_id = each.value
}
# Empty by default. toset is correct for this one because CIDRs are configuration literals (rules.md B-7), and
# the contrast with the rule above is the whole of B-8: same shape, different origin, different type.
resource "aws_vpc_security_group_ingress_rule" "queue_worker_cidr_ssh_ingress" {
  for_each = toset(var.ingress_cidr_blocks)

  security_group_id = aws_security_group.queue_worker_security_group.id
  description       = "SSH from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.ssh_port
  to_port           = var.ssh_port
  cidr_ipv4         = each.value
}
resource "aws_iam_role" "queue_worker_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "queue_worker_iam_role" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.queue_worker_iam_role.name
  policy_arn = each.value
}
# The queue access this host actually needs, written out rather than covered by a managed policy.
#
# Four actions, and each one is in the script: receive_message needs ReceiveMessage, delete_message needs
# DeleteMessage, GetQueueAttributes is what the depth command this module exposes calls, and
# ChangeMessageVisibility is what SQS requires if a consumer ever extends a message's timeout. SendMessage is
# deliberately absent - this host consumes, the Lambda function produces, and a worker that can also send is a
# worker that can hide a bug by refilling the queue it is draining.
resource "aws_iam_role_policy" "queue_worker_queue_access" {
  name = "SQSConsume"
  role = aws_iam_role.queue_worker_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
        "sqs:ChangeMessageVisibility",
      ]
      Resource = var.queue_arn
    }]
  })
}
resource "aws_iam_instance_profile" "queue_worker_instance_profile" {
  # A single role name, not CloudFormation's Roles list (rules.md A-3). There were two defects here in the
  # conversion, and only one of them was the jsonencode: the profile also named the workbench's role rather
  # than this one, which left this role created, granted a policy, and attached to nothing - while the worker
  # ran with the workbench's AdministratorAccess. Both are corrected in _monolithic/main.tf and preserved
  # here, which is why this module's narrowed policy set is the one that actually takes effect.
  role = aws_iam_role.queue_worker_iam_role.name
}
locals {
  # Built with jsonencode rather than embedded as a JSON literal, which is what the _monolithic template did
  # with an echo of a multi-line single-quoted string. Two reasons: this cannot produce invalid JSON, and the
  # interpolated paths cannot break out of it - a log file path containing a quote would have terminated the
  # echo string and left the agent with a truncated configuration file.
  #
  # "{instance_id}" is not a Terraform interpolation and is not meant to be one. It is the agent's own
  # placeholder, which it expands to the real instance id when it creates the log stream, so one configuration
  # works on any number of instances.
  cloudwatch_agent_config = jsonencode({
    agent = {
      # root, as the template had it. The worker runs as ec2-user and the log file is chowned to it, but the
      # agent has to read a file in /var/log and tail it as it rotates.
      run_as_user = "root"
    }
    logs = {
      logs_collected = {
        files = {
          collect_list = [{
            file_path       = var.log_file_path
            log_group_name  = var.log_group_name
            log_stream_name = "{instance_id}"
          }]
        }
      }
    }
  })
  user_data = <<-EOT
    #!/bin/bash
    set -x

    dnf update -yq
    dnf groupinstall -yq "Development Tools"
    dnf install -yq ${join(" ", var.dnf_packages)}

    # No "ln -s /usr/bin/python3.13 /usr/bin/python3" here, which the _monolithic template ran between the
    # package installs above. It always failed with "File exists" so it changed nothing - and this is the host
    # where forcing it would have done real damage, because the amazon-cloudwatch-agent install is a dnf call
    # that comes after it and dnf is a Python program bound to the system interpreter.

    cat > /opt/aws/amazon-cloudwatch-agent/bin/config.json << 'CWAGENTCONFIG'
    ${local.cloudwatch_agent_config}
    CWAGENTCONFIG

    # The log file has to exist and be writable by the worker before either side starts. The worker runs as
    # ec2-user and cannot create a file in /var/log, and Python's logging module does not report that it
    # could not open its destination - it discards the records, so the worker deletes messages and the metric
    # filter counts nothing.
    touch ${var.log_file_path}
    chown ec2-user:ec2-user ${var.log_file_path}

    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json

    ${var.python_command} -m ensurepip --upgrade
    ${var.python_command} -m pip install --quiet ${join(" ", var.pip_packages)}

    %{if var.worker_script != null~}
    # A quoted heredoc delimiter, where the _monolithic template used an unquoted one. Terraform substitutes
    # the queue URL and the region into the body either way, so quoting costs nothing and stops the shell
    # expanding anything in the Python source - the original worked only because that source happened to
    # contain no dollar sign or backtick.
    #
    # rules.md A-4 applies with full force: with CRLF line endings the terminator below becomes TFWORKER\r,
    # which the shell does not accept, and the heredoc then swallows the rest of this script - the agent
    # never gets its configuration and the unit file is never written.
    cat > ${var.worker_script_path} << 'TFWORKER'
    ${var.worker_script}
    TFWORKER
    chown ec2-user:ec2-user ${var.worker_script_path}

    # A unit file, where the _monolithic template left "# python3 /home/ec2-user/worker.py" commented out in
    # the user data. That comment is the honest state of the original: the worker was something a person
    # started by hand over SSH, in a foreground process that died with the session.
    #
    # ExecStart has to name the interpreter by absolute path. systemd rejects a relative one outright, and the
    # unit then fails to load with "Executable path is not absolute" - which looks like a broken worker rather
    # than a broken unit file.
    cat > /etc/systemd/system/${var.worker_service_name}.service << 'TFWORKERUNIT'
    [Unit]
    Description=SQS queue worker
    Wants=network-online.target
    After=network-online.target
    [Service]
    Type=simple
    User=ec2-user
    ExecStart=/usr/bin/${var.python_command} ${var.worker_script_path}
    Restart=always
    RestartSec=5
    [Install]
    WantedBy=multi-user.target
    TFWORKERUNIT
    systemctl daemon-reload
    %{if var.start_worker~}
    systemctl enable --now ${var.worker_service_name}
    %{else~}
    # start_worker is false, so the unit is installed and left stopped - the queue fills and nothing drains
    # it until someone runs "sudo systemctl start ${var.worker_service_name}", which is the sequence the demo
    # is built around.
    %{endif~}
    %{endif~}

    timedatectl set-timezone ${var.timezone}

    # No cfn-signal, which the _monolithic template ended with: there is no CloudFormation stack to signal and
    # aws-cfn-bootstrap is not present on Amazon Linux 2023, so the call could only fail and make cloud-init
    # record the whole script as unsuccessful.
    %{if var.additional_user_data != null~}
    ${var.additional_user_data}
    %{endif~}

    %{if var.marker_file_path != null~}
    mkdir -p ${var.marker_file_path}
    touch ${var.marker_file_path}/userdata
    %{endif~}
    EOT
}
resource "aws_instance" "queue_worker_ec2" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = var.subnet_id
  iam_instance_profile   = aws_iam_instance_profile.queue_worker_instance_profile.name
  vpc_security_group_ids = [aws_security_group.queue_worker_security_group.id]
  user_data              = local.user_data
  tags = {
    Name = var.instance_name
  }
  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size
    encrypted   = true
  }
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = var.metadata_http_tokens
  }

  # The instance profile reference orders this after the profile and the role, and after neither the managed
  # policy attachments nor the inline queue policy (rules.md D-1). Both matter at boot: the CloudWatch agent
  # starts during cloud-init and needs CloudWatchAgentServerPolicy to publish, and a worker started by systemd
  # on a role without the inline policy loops on AccessDenied for ReceiveMessage - a failure visible only in
  # journalctl, since the thing that would have logged it is the queue it cannot read.
  depends_on = [
    aws_iam_role_policy_attachment.queue_worker_iam_role,
    aws_iam_role_policy.queue_worker_queue_access,
  ]
}
