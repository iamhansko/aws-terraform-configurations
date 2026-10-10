# A code-server workbench reached through CloudFront, with the Amazon Q CLI configured to start the AWS
# documentation MCP server and the ECS MCP server - and an ECS cluster for the latter to operate on: an EC2 Auto
# Scaling group behind a managed-scaling capacity provider in two private subnets, with the Fargate providers
# attached alongside it.
#
# Nothing in the cluster is created by Terraform beyond its capacity. Deploying into it is the demo, done by Q
# through the ECS MCP server with the workbench's credentials, so whatever Q creates is not in Terraform state -
# see the before_destroy_command output.
data "aws_region" "current" {}
# The addresses CloudFront's edge locations make origin requests from, by name. The _monolithic template carried
# a mapping of seventeen hardcoded prefix list IDs keyed by region: per-region values AWS can change, and a
# region missing from the table failed the plan with an error about a map key rather than about a region.
#
# At the root rather than inside vscode_ec2, which waits on the network module - a depends_on on a module defers
# every data source inside it to apply (rules.md D-6), and this ID feeds a for_each.
data "aws_ec2_managed_prefix_list" "cloudfront_origin_facing" {
  name = var.cloudfront_prefix_list_name
}
# The managed origin request policy, by name. The original wrote its uuid - 216adef6-5c7f-47e4-b989-5492eafa07d3 -
# straight into the distribution.
data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = var.cloudfront_origin_request_policy_name
}
# The ECS-optimized AMI, resolved at the root and passed in as an ID so the capacity module never looks anything
# up itself (rules.md B-6) - and so it is read at plan rather than deferred by that module's depends_on.
data "aws_ssm_parameter" "ecs_ami_id" {
  name = var.ecs_ami_ssm_parameter_name
}
locals {
  # Read back out of the module it was passed into, so every step waits on the directory the bootstrap actually
  # writes to (rules.md B-5).
  marker = module.vscode_ec2.marker_file_path

  ecs_mcp_server_name     = "awslabs.ecs-mcp-server"
  ecs_mcp_server_log_file = "${var.ecs_mcp_server_log_dir}/ecs-mcp-server.log"
  # The Q CLI's MCP configuration, built as a typed object and serialised with jsonencode below, where the
  # _monolithic template wrote it with echo from a hand-escaped JSON string inside an SSM parameter.
  #
  # The ECS server's environment gets four values merged in here rather than written into the variable's
  # default, so each has one owner: the region is the provider's, so the server cannot be pointed at a
  # different region than the cluster is in; the log file is derived from the directory the association
  # creates; and the two permission switches are bools in variables.tf, rendered as the "true"/"false" strings
  # the server reads (rules.md B-5).
  mcp_config = {
    mcpServers = {
      for name, server in var.mcp_servers : name => {
        command = server.command
        args    = server.args
        env = name == local.ecs_mcp_server_name ? merge(server.env, {
          AWS_REGION           = data.aws_region.current.region
          FASTMCP_LOG_FILE     = local.ecs_mcp_server_log_file
          ALLOW_WRITE          = tostring(var.ecs_mcp_server_allow_write)
          ALLOW_SENSITIVE_DATA = tostring(var.ecs_mcp_server_allow_sensitive_data)
        }) : server.env
        disabled    = server.disabled
        autoApprove = server.autoApprove
      }
    }
  }
}
module "network" {
  source = "./modules/network"

  vpc_cidr_block             = var.vpc_cidr_block
  availability_zone_suffixes = var.availability_zone_suffixes
  vpc_name                   = "${var.project_name}-vpc"
  internet_gateway_name      = "${var.project_name}-igw"
  nat_gateway_name           = "${var.project_name}-natgw"
  public_subnet_name         = "${var.project_name}-public-subnet"
  private_subnet_name        = "${var.project_name}-private-subnet"
  public_route_table_name    = "${var.project_name}-public-rt"
  private_route_table_name   = "${var.project_name}-private-rt"
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name_prefix = "${var.project_name}-key-"

  # Uses nothing from network and waits anyway, so the root has no exception to reason about (rules.md D-3).
  depends_on = [module.network]
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name                   = "${var.project_name}-vscode"
  vpc_id                 = module.network.vpc_id
  subnet_id              = module.network.public_subnet_a_id
  key_name               = module.key_pair.key_name
  instance_type          = var.vscode_instance_type
  ami_ssm_parameter_name = var.vscode_ami_ssm_parameter_name
  code_server_version    = var.code_server_version
  security_group_name    = "${var.project_name}-vscode-sg"
  # The one ingress rule: code-server's port from CloudFront's edge locations, as the _monolithic template had
  # it. Nothing opens the port to 0.0.0.0/0, so the distribution below is the only way into the IDE.
  ingress_prefix_lists = {
    cloudfront = data.aws_ec2_managed_prefix_list.cloudfront_origin_facing.id
  }
  marker_file_path = var.marker_file_path
  # Docker, which the ECS MCP server needs for its containerize and build-and-push tools. In the bootstrap
  # rather than in the Q CLI association, where the _monolithic template installed it, so that the association
  # can re-run without restarting code-server under the person using it.
  #
  # Group membership and a code-server restart rather than the template's chmod 666 on /var/run/docker.sock,
  # which handed the daemon - and with it root on the host - to every process on the instance. code-server is
  # already running when this executes and predates the group, so its terminals only see the group after the
  # restart.
  additional_user_data = <<-EOT
    dnf install -yq docker bash-completion
    systemctl enable --now docker
    usermod -aG docker ec2-user
    systemctl restart code-server
  EOT
  # AdministratorAccess, as the _monolithic template attached - and here it is worth naming as a risk rather than
  # a convenience. The ECS MCP server runs with ALLOW_WRITE and ALLOW_SENSITIVE_DATA on by default, so a
  # language model driving this instance can deploy and delete with these credentials and read what running
  # containers are configured with; and code-server runs with auth: none behind a distribution with no
  # authentication of its own, so that language model is available to anyone with the URL.
  iam_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"]

  depends_on = [module.network, module.key_pair]
}
module "cloudfront" {
  source = "./modules/cloudfront_code_server"

  name               = var.project_name
  origin_domain_name = module.vscode_ec2.public_dns
  # The port from the module that configured code-server, so the origin and the listener cannot disagree
  # (rules.md B-5).
  origin_port              = module.vscode_ec2.code_server_port
  origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id
  price_class              = var.cloudfront_price_class

  depends_on = [module.network]
}
# --- The cluster the ECS MCP server operates on ----------------------------------------------------------
module "ecs_cluster" {
  source = "./modules/ecs_cluster"

  # As the _monolithic template derived it from the stack name.
  name               = "${var.project_name}-ecs-cluster"
  container_insights = var.container_insights

  depends_on = [module.network]
}
module "ecs_capacity" {
  source = "./modules/ecs_asg_capacity_provider"

  vpc_id = module.network.vpc_id
  # Private subnets, so outbound goes through the zonal NAT gateways. The ECS agent cannot register an instance
  # it cannot reach the ECS endpoint from, and an instance that never registers is absent rather than broken -
  # see the module for what that looks like.
  subnet_ids   = module.network.private_subnet_ids
  cluster_name = module.ecs_cluster.cluster_name
  ami_id       = data.aws_ssm_parameter.ecs_ami_id.insecure_value
  key_name     = module.key_pair.key_name

  capacity_provider_name = "${var.project_name}-ecs-ec2-capacity-provider"
  instance_name          = "${var.project_name}-container-instance"
  security_group_name    = "${var.project_name}-container-instance-sg"
  instance_type          = var.container_instance_type
  min_size               = var.container_instance_min_size
  desired_capacity       = var.container_instance_desired_capacity
  max_size               = var.container_instance_max_size
  # The VPC's default security group, which the _monolithic template admitted all traffic from. Nothing this
  # project creates carries it; what does is anything launched into this VPC without naming a group - which is
  # what keeps the rule from being dead weight once Q starts deploying.
  ingress_source_security_groups = {
    vpc_default = module.network.default_security_group_id
  }

  # The cluster has to exist before an instance tries to join it, and before the association in this module can
  # attach a capacity provider to it. The cluster name arrives as a variable and is interpolated into the launch
  # template userdata, so that part is already ordered; module-level depends_on is what covers the rest of the
  # cluster module (rules.md D-2, D-3).
  depends_on = [module.network, module.ecs_cluster, module.key_pair]
}
# The Amazon Q CLI, its runtimes, and the MCP configuration.
#
# What changed from the _monolithic template's association, besides the configuration file itself:
#
#   - It waits for the bootstrap's marker. The template's ran as soon as the instance registered with SSM,
#     concurrently with a bootstrap still running dnf update, and with 180 seconds to finish everything.
#   - It fails when a step fails. set -e in both shells, where the template had none, so a failed install
#     reported Success.
#   - It can run again. The association re-runs whenever its parameters change - mcp_servers and the two
#     permission switches are the usual reasons - so every step tolerates having run before (rules.md E-9
#     makes the same demand of its own SSM steps).
resource "aws_ssm_association" "q_developer_cli" {
  name                             = "AWS-RunShellScript"
  association_name                 = "${var.project_name}-q-developer-cli"
  wait_for_success_timeout_seconds = var.q_cli_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    commands = <<-EOT
      set -euo pipefail
      until [ -f ${local.marker}/userdata ]; do sleep 10; done
      # Cleared first, so that on a re-run the README association waits for this run rather than finding the
      # previous run's marker (rules.md D-5).
      rm -f ${local.marker}/q_developer_cli
      # pip comes from python3.13-pip, which is how AL2023 ships pip for its additional Pythons, rather than the
      # template's python -m ensurepip --upgrade run as root, which bootstraps a second copy that rpm does not
      # track.
      dnf install -yq python3.13 python3.13-pip unzip
      # python on the PATH, as the template linked it. AL2023 itself has no /usr/bin/python - its own tools call
      # python3, which stays 3.9 - so nothing system-side reads this link.
      ln -sf /usr/bin/python3.13 /usr/bin/python

      # As ec2-user with HOME set, so uv, nvm and the Q CLI install into the home directory code-server opens.
      # SSM runs this as root and does not set HOME, which would put all three under /root or nowhere.
      sudo -u ec2-user bash << 'STEP'
      set -euo pipefail
      export HOME=/home/ec2-user
      cd /home/ec2-user
      # uv provides uvx, which is how every MCP server is started - Q launches them as child processes.
      curl -LsSf https://astral.sh/uv/${var.uv_version}/install.sh | sh
      curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/${var.nvm_version}/install.sh | bash
      export NVM_DIR=/home/ec2-user/.nvm
      # nvm is not safe under set -u - it references unset variables, and nvm install for a version already
      # present fails with "ALIAS: unbound variable", which is exactly the re-run case.
      set +u
      . "$NVM_DIR/nvm.sh"
      nvm install ${var.node_version}
      set -u
      # Installed once. The CLI updates itself afterwards, so a re-run that reinstalled it would only replace a
      # newer build with whatever the download URL serves.
      if [ ! -x /home/ec2-user/.local/bin/q ]; then
        curl --proto '=https' --tlsv1.2 -fsSL "${var.q_cli_download_url}" -o q.zip
        unzip -q -o q.zip
        ./q/install.sh --no-confirm
        rm -rf q q.zip
      fi
      # The ECS MCP server opens its log file at start and does not create the directory.
      mkdir -p ${var.ecs_mcp_server_log_dir}
      mkdir -p /home/ec2-user/.aws/amazonq
      # jsonencode emits a single line with no shell metacharacters that matter inside a quoted heredoc, so the
      # file is exactly the object in local.mcp_config.
      cat > /home/ec2-user/.aws/amazonq/mcp.json << 'TFMCP'
      ${jsonencode(local.mcp_config)}
      TFMCP
      STEP
      touch ${local.marker}/q_developer_cli
      EOT
  }

  depends_on = [module.vscode_ec2]
}
# --- README on the workbench ------------------------------------------------------------------------------
locals {
  # Every output this root exposes, defined once. outputs.tf projects this map and the README on the workbench
  # renders it, so an output cannot exist without also appearing in that README (rules.md H-2).
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server, through CloudFront"
      description = "Open the IDE here. The instance accepts its code-server port only from CloudFront's origin-facing prefix list, so this URL is the only way in"
      value       = module.cloudfront.url
    }
    security_note = {
      order       = 2
      title       = "What this gives a language model"
      description = "Worth reading before using it. code-server runs with auth: none and CloudFront adds no authentication of its own, so anyone with the URL has the IDE. The instance holds AdministratorAccess, and the ECS MCP server runs with the write and sensitive-data switches shown here. Both are true by default, which lets Q build and push images, deploy and delete services, and read container logs and configuration. That is the demo working as intended; it is also why this should not be left running"
      value       = "instance role: AdministratorAccess | ecs-mcp-server: ALLOW_WRITE=${tostring(var.ecs_mcp_server_allow_write)} ALLOW_SENSITIVE_DATA=${tostring(var.ecs_mcp_server_allow_sensitive_data)} | code-server auth: none"
    }
    ecs_cluster_name = {
      order       = 3
      title       = "ECS cluster"
      description = "The cluster Q inspects and deploys into through the ECS MCP server"
      value       = module.ecs_cluster.cluster_name
    }
    capacity_providers = {
      order       = 4
      title       = "Capacity providers on the cluster"
      description = "The EC2 Auto Scaling capacity provider, which is the cluster default, and the Fargate providers attached alongside it, as the _monolithic template attached them"
      value       = join(", ", module.ecs_capacity.cluster_capacity_providers)
    }
    mcp_servers = {
      order       = 5
      title       = "MCP servers configured for Q"
      description = "What Q can reach. Built from a typed object rather than the escaped JSON the original embedded in an SSM parameter"
      value       = join("\n", [for name, server in local.mcp_config.mcpServers : "${name}: ${server.command} ${join(" ", server.args)}"])
    }
    mcp_config_command = {
      order       = 6
      title       = "1. Read the MCP configuration on the instance"
      description = "The file Q loads. If a server is missing from Q's tool list, compare this against the list above"
      value       = "cat /home/ec2-user/.aws/amazonq/mcp.json"
    }
    q_login_command = {
      order       = 7
      title       = "2. Sign in to Q"
      description = "Run this in the IDE terminal. The CLI is installed but not authenticated - it needs a Builder ID or an IAM Identity Center sign-in, which is an interactive step Terraform cannot do"
      value       = "q login"
    }
    q_chat_command = {
      order       = 8
      title       = "3. Ask Q about the cluster"
      description = "The demo. Q calls the ECS MCP server, which uses the instance's credentials - so the answer comes from the live cluster rather than from the model's training data"
      value       = "q chat \"Describe the ${module.ecs_cluster.cluster_name} ECS cluster: its capacity providers, its container instances and what is running on it\""
    }
    q_mcp_status_command = {
      order       = 9
      title       = "4. Check which MCP servers Q started"
      description = "A server whose uvx package failed to download is reported here rather than in the config. The first thing to check when Q answers from training data instead of from the cluster"
      value       = "q mcp list"
    }
    ecs_mcp_server_log_command = {
      order       = 10
      title       = "5. The ECS MCP server's log"
      description = "Where the server records the AWS calls it made and why one failed. It writes nothing until Q has started it at least once"
      value       = "tail -n 50 ${local.ecs_mcp_server_log_file}"
    }
    container_instances_command = {
      order       = 11
      title       = "6. Container instances in the cluster"
      description = "Which instances registered and whether their agent is connected. Managed scaling moves the group to its minimum while nothing is running, so one instance on an idle cluster is expected"
      value       = module.ecs_capacity.container_instance_status_command
    }
    capacity_provider_status_command = {
      order       = 12
      title       = "7. The EC2 capacity provider"
      description = "The provider as ECS holds it, with its managed scaling settings"
      value       = module.ecs_capacity.capacity_provider_status_command
    }
    scaling_activities_command = {
      order       = 13
      title       = "8. What the Auto Scaling group has been doing"
      description = "Managed scaling shows up here as the group's desired count moving - which is why Terraform ignores changes to it - and a launch that failed shows up here rather than in ECS"
      value       = module.ecs_capacity.scaling_activities_command
    }
    cluster_status_command = {
      order       = 14
      title       = "9. Cluster totals"
      description = "Registered instances and running versus pending task counts in one call"
      value       = module.ecs_cluster.cluster_status_command
    }
    q_cli_association_command = {
      order       = 15
      title       = "10. How the Q CLI installation went"
      description = "When it failed, aws ssm describe-association-execution-targets with the execution ID shown here gives the command ID, and aws ssm get-command-invocation on that command ID shows the script output"
      value       = "aws ssm describe-association-executions --association-id ${aws_ssm_association.q_developer_cli.association_id} --query 'AssociationExecutions[0].[ExecutionId,Status,DetailedStatus,CreatedTime]' --output table"
    }
    cloudfront_status_command = {
      order       = 16
      title       = "11. Is the distribution deployed"
      description = "A 502 with the distribution Deployed means code-server did not answer - not started yet, or the instance was stopped and started and the origin still names its old public DNS name until the next apply"
      value       = module.cloudfront.status_command
    }
    prefix_list_command = {
      order       = 17
      title       = "12. The prefix list the instance trusts"
      description = "The addresses CloudFront makes origin requests from, looked up by name rather than from the hardcoded per-region table the _monolithic template carried"
      value       = "aws ec2 describe-managed-prefix-lists --filters Name=prefix-list-name,Values=${var.cloudfront_prefix_list_name} --query 'PrefixLists[].[PrefixListId,PrefixListName,MaxEntries]' --output table"
    }
    before_destroy_command = {
      order       = 18
      title       = "Before terraform destroy"
      description = "What Q deployed is not in Terraform state. ECS refuses to delete a cluster that still has active services, and the ECS MCP server creates ECR repositories through CloudFormation stacks of its own - list both, and remove what Q created, before destroying"
      value       = "aws ecs list-services --cluster ${module.ecs_cluster.cluster_name} --query serviceArns --output table && aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --query 'StackSummaries[].[StackName,CreationTime]' --output table"
    }
    private_key_command = {
      order       = 19
      title       = "SSH key"
      description = "Retrieves the generated private key, shared by the workbench and the container instances, from Parameter Store, where CloudFormation puts a generated key pair. No security group opens port 22; this is for the case where the SSM agent is what is broken"
      value       = module.key_pair.private_key_command
    }
  }
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  readme_body = join("\n", concat(
    ["# ECS MCP Server", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}
# The work happens inside code-server in a browser, where terraform output is not available, so every output
# above is also written to a README in the home directory the IDE opens (rules.md H-2).
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  association_name                 = "${var.project_name}-vscode-readme"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # Waits for the Q CLI step, which the README describes (rules.md D-5).
    commands = <<-EOT
      until [ -f ${local.marker}/q_developer_cli ]; do sleep 10; done
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${local.marker}/vscode_readme
      EOT
  }

  depends_on = [aws_ssm_association.q_developer_cli]
}
