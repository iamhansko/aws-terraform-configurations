# A code-server workbench reached through CloudFront, with the Amazon Q CLI configured to start two MCP servers:
# the AWS documentation server and the AWS diagram server, which turns a description of an architecture into a
# PNG drawn with the Python diagrams package.
#
# Everything Q does happens on the workbench. The MCP servers are child processes of the CLI, started with uvx,
# and they run with the instance's credentials - so the instance role is what the language model can do.
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
locals {
  # Read back out of the module it was passed into, so every step waits on the directory the bootstrap actually
  # writes to (rules.md B-5).
  marker = module.vscode_ec2.marker_file_path
  # The Q CLI's MCP configuration, built as a typed object and serialised with jsonencode below. The
  # _monolithic template wrote this file with echo from a hand-escaped JSON string inside an SSM parameter, and
  # that string had one closing brace too many - see mcp_servers in variables.tf.
  mcp_config = {
    mcpServers = {
      for name, server in var.mcp_servers : name => {
        command     = server.command
        args        = server.args
        env         = server.env
        disabled    = server.disabled
        autoApprove = server.autoApprove
      }
    }
  }
}
module "network" {
  source = "./modules/network"

  vpc_cidr_block           = var.vpc_cidr_block
  availability_zone_suffix = var.availability_zone_suffix
  vpc_name                 = "${var.project_name}-vpc"
  internet_gateway_name    = "${var.project_name}-igw"
  public_subnet_name       = "${var.project_name}-public-subnet-${var.availability_zone_suffix}"
  public_route_table_name  = "${var.project_name}-public-rt"
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
  # Docker in the bootstrap rather than in the Q CLI association, where the _monolithic template installed it,
  # so that the association can re-run without restarting code-server under the person using it.
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
  # AdministratorAccess, as the _monolithic template attached, and the reason the security note in the outputs
  # exists. code-server runs with auth: none behind a distribution with no authentication of its own, so
  # anyone with the URL holds these credentials - and so does every MCP server Q starts. The two configured
  # here only read (public documentation, and diagrams rendered locally), but Q itself can run shell commands
  # with them.
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
# The Amazon Q CLI, its runtimes, and the MCP configuration.
#
# What changed from the _monolithic template's association, besides the configuration file itself:
#
#   - It waits for the bootstrap's marker. The template's ran as soon as the instance registered with SSM,
#     concurrently with a bootstrap still running dnf update, and with 180 seconds to finish everything.
#   - It installs GraphViz. The diagram server renders with dot, and without it every diagram request fails
#     after the server has started - Q lists the tool and the tool cannot work.
#   - It fails when a step fails. set -e in both shells, where the template had none, so a failed install
#     reported Success.
#   - It can run again. The association re-runs whenever its parameters change - mcp_servers above is the
#     usual reason - so every step tolerates having run before (rules.md E-9 makes the same demand of its own
#     SSM steps).
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
      # graphviz provides dot, which the diagram MCP server renders with. pip comes from python3.13-pip, which is
      # how AL2023 ships pip for its additional Pythons, rather than the template's python -m ensurepip --upgrade
      # run as root, which bootstraps a second copy that rpm does not track.
      dnf install -yq python3.13 python3.13-pip graphviz unzip
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
      description = "Worth reading before using it. code-server runs with auth: none and CloudFront adds no authentication of its own, so anyone with the URL has the IDE - and the instance holds AdministratorAccess. Both MCP servers configured here only read, but Q can also run shell commands with the same credentials. That is the demo working as intended; it is also why this should not be left running"
      value       = "instance role: AdministratorAccess | code-server auth: none | MCP servers: aws-documentation (read), aws-diagram (renders locally)"
    }
    mcp_servers = {
      order       = 3
      title       = "MCP servers configured for Q"
      description = "What Q can reach. Built from a typed object rather than the escaped JSON the original embedded in an SSM parameter, which closed one more brace than it opened"
      value       = join("\n", [for name, server in local.mcp_config.mcpServers : "${name}: ${server.command} ${join(" ", server.args)}"])
    }
    mcp_config_command = {
      order       = 4
      title       = "1. Read the MCP configuration on the instance"
      description = "The file Q loads. If a server is missing from Q's tool list, compare this against the list above"
      value       = "cat /home/ec2-user/.aws/amazonq/mcp.json"
    }
    q_login_command = {
      order       = 5
      title       = "2. Sign in to Q"
      description = "Run this in the IDE terminal. The CLI is installed but not authenticated - it needs a Builder ID or an IAM Identity Center sign-in, which is an interactive step Terraform cannot do"
      value       = "q login"
    }
    q_chat_command = {
      order       = 6
      title       = "3. Ask Q for a diagram"
      description = "The demo. Q writes Python for the diagrams package and the diagram server renders it with GraphViz. Started from a directory of its own, so the generated-diagrams folder it writes lands somewhere code-server shows"
      value       = "mkdir -p ~/diagrams && cd ~/diagrams && q chat \"Draw an AWS architecture diagram of a browser reaching code-server on an EC2 instance in a public subnet through a CloudFront distribution\""
    }
    q_mcp_status_command = {
      order       = 7
      title       = "4. Check which MCP servers Q started"
      description = "A server whose uvx package failed to download is reported here rather than in the config. The first thing to check when Q answers without calling a tool"
      value       = "q mcp list"
    }
    diagrams_command = {
      order       = 8
      title       = "5. Find the rendered diagrams"
      description = "The diagram server writes PNGs into a generated-diagrams directory under the workspace Q passes it, or under the system temporary directory when Q passes none"
      value       = "find /home/ec2-user /tmp -path '*generated-diagrams*' -name '*.png' 2>/dev/null"
    }
    graphviz_command = {
      order       = 9
      title       = "6. Is GraphViz installed"
      description = "The diagram server renders with dot. The _monolithic template never installed it, so the server started and every diagram request failed"
      value       = "dot -V"
    }
    q_cli_association_command = {
      order       = 10
      title       = "7. How the Q CLI installation went"
      description = "When it failed, aws ssm describe-association-execution-targets with the execution ID shown here gives the command ID, and aws ssm get-command-invocation on that command ID shows the script output"
      value       = "aws ssm describe-association-executions --association-id ${aws_ssm_association.q_developer_cli.association_id} --query 'AssociationExecutions[0].[ExecutionId,Status,DetailedStatus,CreatedTime]' --output table"
    }
    cloudfront_status_command = {
      order       = 11
      title       = "8. Is the distribution deployed"
      description = "A 502 with the distribution Deployed means code-server did not answer - not started yet, or the instance was stopped and started and the origin still names its old public DNS name until the next apply"
      value       = module.cloudfront.status_command
    }
    prefix_list_command = {
      order       = 12
      title       = "9. The prefix list the instance trusts"
      description = "The addresses CloudFront makes origin requests from, looked up by name rather than from the hardcoded per-region table the _monolithic template carried"
      value       = "aws ec2 describe-managed-prefix-lists --filters Name=prefix-list-name,Values=${var.cloudfront_prefix_list_name} --query 'PrefixLists[].[PrefixListId,PrefixListName,MaxEntries]' --output table"
    }
    private_key_command = {
      order       = 13
      title       = "Workbench SSH key"
      description = "Retrieves the generated private key from Parameter Store, where CloudFormation puts a generated key pair. No security group opens port 22; this is for the case where the SSM agent is what is broken"
      value       = module.key_pair.private_key_command
    }
  }
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  readme_body = join("\n", concat(
    ["# AWS Diagram MCP Server", ""],
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
