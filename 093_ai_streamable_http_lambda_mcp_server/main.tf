# An MCP server on Lambda, reached over streamable HTTP through API Gateway with a bearer token, and the
# Amazon Q CLI on a code-server workbench configured to use it.
#
# The _monolithic template is a machine conversion of the workshop's SAM template, and most of what made it
# work did not survive the conversion: the API had no resources, methods, authorizer or stage; the function
# code was written to disk as a Python repr of {'Fn::Sub': ...}; the server function had no permissions on
# its own table; the layer was published once and never again; and the workbench security group had no egress
# rule, so nothing on the instance could be downloaded. The comments below say where each of those went.
data "aws_region" "current" {}
# The addresses CloudFront's edge locations make origin requests from, looked up by name rather than through
# the 17-region table of hardcoded prefix list ids the _monolithic template carried.
data "aws_ec2_managed_prefix_list" "cloudfront_origin_facing" {
  name = var.cloudfront_prefix_list_name
}
# The managed origin request policy, by name. The original wrote its uuid straight into the distribution.
data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = var.cloudfront_origin_request_policy_name
}
locals {
  region = data.aws_region.current.region
  # Read back out of the module it was passed into, so every step waits on the directory the bootstrap
  # actually writes to (rules.md B-5).
  marker         = module.vscode_ec2.marker_file_path
  lambda_runtime = "python${var.lambda_python_version}"
  # The wheel platform pip fetches for, from the architecture the functions run on - one value, so the layer
  # cannot be built for a machine the function is not (rules.md B-1 on deriving rather than validating).
  pip_platform = {
    x86_64 = "manylinux2014_x86_64"
    arm64  = "manylinux2014_aarch64"
  }[var.lambda_architecture]
  q_config_dir = "/home/ec2-user/.aws/amazonq"
  # The token's only copy on the workbench, read by mcp-remote through --header-file. The _monolithic template
  # put it in mcp-remote's arguments inside mcp.json - so in a file the IDE opens, in the process list of
  # every user on the instance, and in the association's command document in clear.
  mcp_header_file = "${local.q_config_dir}/${var.mcp_server_name}.headers"
  # The Q CLI's MCP configuration as a typed object. The Lambda server's entry is added here because its URL
  # is the API's, and it holds a path to the header file rather than the token (rules.md B-5).
  mcp_config = {
    mcpServers = merge(
      {
        for name, server in var.mcp_servers : name => {
          command     = server.command
          args        = server.args
          env         = server.env
          disabled    = server.disabled
          autoApprove = server.autoApprove
        }
      },
      {
        (var.mcp_server_name) = {
          # Installed globally at a pinned version by the association below, rather than fetched unpinned by npx
          # on the first start - that download inside Q's server start-up is the likely reason the original
          # README says to restart Q when a server fails to load.
          command = "mcp-remote"
          # http-only: the endpoint speaks streamable HTTP and nothing else, so falling back to SSE would turn
          # a failure into a second, misleading one.
          args = [module.mcp_api.url, "--header-file", local.mcp_header_file, "--transport", "http-only"]
        }
      },
    )
  }
}
module "network" {
  source = "./modules/network"

  vpc_cidr_block = var.vpc_cidr_block
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name_prefix = "${var.project_name}-"

  # Uses nothing from network and waits anyway, so the root has no exception to reason about (rules.md D-3).
  depends_on = [module.network]
}
# The workbench - the _monolithic template's bastion. Reached through CloudFront; its only ingress rule is the
# CloudFront origin-facing prefix list.
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name                        = "${var.project_name}-vscode"
  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  code_server_version         = var.code_server_version
  security_group_name         = "${var.project_name}-vscode-sg"
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  ingress_prefix_list_ids     = [data.aws_ec2_managed_prefix_list.cloudfront_origin_facing.id]
  iam_policy_arns             = var.vscode_iam_policy_arns
  marker_file_path            = var.marker_file_path
  # docker, as the _monolithic template installed it, with the group membership and a code-server restart
  # instead of its chmod 666 on /var/run/docker.sock, which handed the root-equivalent socket to every process
  # on the instance. code-server predates the group change, so its terminals only see it after the restart.
  additional_user_data = <<-EOT
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    systemctl restart code-server
    runuser -u ec2-user -- env HOME=/home/ec2-user aws configure set default.region ${local.region}
  EOT

  depends_on = [module.network]
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

  depends_on = [module.network, module.vscode_ec2]
}
# --- The MCP server -----------------------------------------------------------------------------------------
module "mcp_auth_token" {
  source = "./modules/mcp_auth_token"

  parameter_name = "/${var.project_name}/mcp-auth-token"
  length         = var.mcp_auth_token_length

  depends_on = [module.network]
}
module "mcp_sessions_table" {
  source = "./modules/mcp_sessions_table"

  name = "${var.project_name}-mcp-sessions"

  depends_on = [module.network]
}
# awslabs.mcp_lambda_handler, which the server function imports. Its package is built on the workbench
# (lambda_layer_build below) and its checksum read back from S3 once lambda_layer_package_waiter has seen it
# there, which is what holds the layer - and so the function - until the package exists.
module "lambda_layer" {
  source = "./modules/lambda_layer"

  layer_name               = "${var.project_name}-lambda-layer"
  description              = "awslabs.mcp_lambda_handler ${var.mcp_lambda_handler_version} for ${local.lambda_runtime} on ${var.lambda_architecture}"
  package_sha256           = data.aws_s3_object.lambda_layer_package.checksum_sha256
  compatible_runtimes      = [local.lambda_runtime]
  compatible_architectures = [var.lambda_architecture]

  depends_on = [module.network]
}
module "mcp_authorizer_function" {
  source = "./modules/python_lambda_function"

  function_name         = "${var.project_name}-mcp-authorizer-function"
  description           = "TOKEN authorizer for the MCP API"
  source_dir            = "${path.root}/lambda_src/mcp_authorizer_function"
  runtime               = local.lambda_runtime
  architecture          = var.lambda_architecture
  timeout               = var.authorizer_timeout_seconds
  log_retention_in_days = var.log_retention_in_days
  # Where to read the token, not the token. The version is here so that a new token is a configuration change,
  # which retires the warm execution environments holding the old one.
  environment = {
    MCP_AUTH_TOKEN_PARAMETER_NAME    = module.mcp_auth_token.parameter_name
    MCP_AUTH_TOKEN_PARAMETER_VERSION = tostring(module.mcp_auth_token.parameter_version)
  }
  # The one permission the authorizer needs. The upstream SAM template gave it lambda:InvokeFunction on every
  # function in the account, which an authorizer has no use for: API Gateway invokes it, it invokes nothing.
  inline_policies = {
    read_token = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid      = "ReadToken"
        Effect   = "Allow"
        Action   = "ssm:GetParameter"
        Resource = module.mcp_auth_token.parameter_arn
      }]
    })
  }

  depends_on = [module.network]
}
module "mcp_server_function" {
  source = "./modules/python_lambda_function"

  function_name         = "${var.project_name}-mcp-server-function"
  description           = "MCP server over streamable HTTP (awslabs.mcp_lambda_handler)"
  source_dir            = "${path.root}/lambda_src/mcp_server_function"
  runtime               = local.lambda_runtime
  architecture          = var.lambda_architecture
  timeout               = var.mcp_server_timeout_seconds
  log_retention_in_days = var.log_retention_in_days
  layers                = [module.lambda_layer.layer_version_arn]
  environment = {
    MCP_SESSION_TABLE = module.mcp_sessions_table.name
  }
  # The permissions the upstream SAM template gives this function and the _monolithic template lacks: with only
  # AWSLambdaBasicExecutionRole, the first initialize would have failed writing its session, and count_s3_buckets
  # would have been AccessDenied. Narrowed to what the code calls - the library's session store uses
  # these four item operations and nothing else, so the upstream template's dynamodb:CreateTable and
  # DescribeTable are gone, as is s3:ListBuckets, which is not an IAM action.
  inline_policies = {
    session_items = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid      = "SessionItems"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem"]
        Resource = module.mcp_sessions_table.arn
      }]
    })
    # The count_s3_buckets tool. ListBuckets has no resource-level scoping, so * is the only form it takes.
    count_s3_buckets = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid      = "ListAllMyBuckets"
        Effect   = "Allow"
        Action   = "s3:ListAllMyBuckets"
        Resource = "*"
      }]
    })
  }

  depends_on = [module.network]
}
module "mcp_api" {
  source = "./modules/mcp_rest_api"

  name                             = "${var.project_name}-mcp-api"
  stage_name                       = var.api_stage_name
  authorizer_function_name         = module.mcp_authorizer_function.function_name
  authorizer_invoke_arn            = module.mcp_authorizer_function.invoke_arn
  server_function_name             = module.mcp_server_function.function_name
  server_invoke_arn                = module.mcp_server_function.invoke_arn
  authorizer_result_ttl_in_seconds = var.authorizer_result_ttl_in_seconds

  depends_on = [module.network]
}
# --- The workbench steps ------------------------------------------------------------------------------------
#
# Three associations, sequenced by marker files (rules.md D-5). The _monolithic template had two and nothing
# ordering them: both started the moment the instance existed, alongside a user data script still running
# dnf update - so the layer build raced it for the dnf lock, the Q CLI step ran unzip on an instance that might
# not have it yet, and each had 180 seconds to finish.
#
# Step one: build the layer package. What sam build would have done for a function with a requirements.txt,
# done here because pip has to run somewhere and Terraform does not run it.
resource "aws_ssm_association" "lambda_layer_build" {
  name                             = "AWS-RunShellScript"
  association_name                 = "${var.project_name}-lambda-layer-build"
  wait_for_success_timeout_seconds = var.lambda_layer_build_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # Re-runs when anything that goes into the package changes, which publishes a new layer version through the
    # checksum read below - on the apply after the one that re-ran it (see the read).
    #
    # --python-version and --platform, where the original relied on the interpreter running pip: the layer is
    # built for the runtime the function runs, not for whichever python is on the instance. put-object with
    # --checksum-algorithm SHA256 rather than s3 cp, so the object carries a whole-object SHA-256 for the data
    # source below to read - s3 cp uploads large files in parts, whose checksum is of the parts.
    commands = <<-EOT
      set -euo pipefail
      until [ -f ${local.marker}/userdata ]; do sleep 10; done
      dnf install -yq python${var.lambda_python_version} zip
      python${var.lambda_python_version} -m ensurepip --upgrade
      sudo -Eu ec2-user bash << 'EOF'
      set -euo pipefail
      export HOME=/home/ec2-user
      build_dir=/home/ec2-user/lambda-layer
      # From empty each run: pip install --target into a directory that already holds the packages leaves the
      # old ones in place and only warns.
      rm -rf "$build_dir"
      mkdir -p "$build_dir/python"
      python${var.lambda_python_version} -m pip install --quiet --no-cache-dir \
        --target "$build_dir/python" \
        --platform ${local.pip_platform} --implementation cp --python-version ${var.lambda_python_version} \
        --only-binary=:all: \
        "awslabs.mcp_lambda_handler==${var.mcp_lambda_handler_version}"
      cd "$build_dir"
      zip -qr layer.zip python
      aws s3api put-object --region ${local.region} \
        --bucket ${module.lambda_layer.package_bucket} --key ${module.lambda_layer.package_key} \
        --body layer.zip --checksum-algorithm SHA256 --query ChecksumSHA256 --output text
      rm -f layer.zip
      EOF
      touch ${local.marker}/lambda_layer_build
      EOT
  }

  depends_on = [module.vscode_ec2]
}
# Holds the apply until the build's package is in S3.
#
# The read below used to wait on lambda_layer_build through depends_on, trusting
# wait_for_success_timeout_seconds to hold the association's create until the build had finished. It cannot:
# an association whose target has not registered with Systems Manager reports Success at once, and this one is
# created as soon as the instance is, before its SSM agent has registered - so every first apply would read
# the package minutes before the upload and fail with "couldn't find resource". That is the provider issue
# rules.md D-5 warns about. 073_cognito_identity_pool and 074_cognito_authenticator_api_gateway, which build
# their web app package on the workbench the same way, both failed like this; their root main.tf has the
# CloudTrail timelines.
#
# So the wait is a function that asks S3 for the object until it is there, and stops early only when the
# association's current run has failed - never on its Success. It reaches network through depends_on, which is
# what D-3 asks for; the association and the bucket arrive through the values below.
module "lambda_layer_package_waiter" {
  source = "./modules/s3_object_waiter"

  function_name         = "${var.project_name}-layer-package-waiter"
  bucket_name           = module.lambda_layer.package_bucket
  bucket_arn            = module.lambda_layer.package_bucket_arn
  object_key            = module.lambda_layer.package_key
  association_id        = aws_ssm_association.lambda_layer_build.association_id
  association_arn       = aws_ssm_association.lambda_layer_build.arn
  log_retention_in_days = var.log_retention_in_days
  # The same number as the association's own wait, so "how long the build may take" stays one value, capped
  # at the 900 seconds a Lambda function can run. The cap is applied here rather than by lowering the variable:
  # the association's wait_for_success_timeout_seconds reads it too, and the provider sends any change to that
  # as an UpdateAssociation, which re-runs the whole build on the workbench.
  timeout_seconds = min(var.lambda_layer_build_timeout_seconds, 900)

  depends_on = [module.network]
}
# The package the build uploaded, read for its SHA-256 - the layer's source_code_hash.
#
# Named through the waiter's result rather than module.lambda_layer's outputs, and that is the whole ordering:
# while the waiter is being invoked its result is unknown, so this read is deferred to apply and runs after
# the wait; once the waiter is in state the read happens at plan. No depends_on, which would defer the read on
# every change to the waiter's module (rules.md D-6).
#
# A rebuild - the association re-run because its commands changed, a new mcp_lambda_handler_version for one -
# is not waited for, because the previous package is still at the key. That apply reads the previous package
# and the next one publishes the rebuilt layer. The depends_on this replaces did no better: the provider does
# not wait on an association update at all, so the read ran straight after UpdateAssociation returned.
data "aws_s3_object" "lambda_layer_package" {
  bucket        = module.lambda_layer_package_waiter.bucket
  key           = module.lambda_layer_package_waiter.key
  checksum_mode = "ENABLED"
}
# Step two: the Amazon Q CLI and its MCP servers.
resource "aws_ssm_association" "q_developer_cli" {
  name                             = "AWS-RunShellScript"
  association_name                 = "${var.project_name}-q-developer-cli"
  wait_for_success_timeout_seconds = var.q_cli_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The token is read from Parameter Store on the instance and never appears in this document - which, unlike
    # the parameter, anyone with ssm:DescribeAssociation can read. Its version does appear, so a rotation
    # changes the document and re-runs this step, rewriting the header file.
    #
    # Safe to re-run: every installer below is idempotent or skipped once present, and both files are
    # overwritten. No set -x, which would put the token in the command output.
    #
    # set +u around nvm, whose script reads unset variables.
    commands = <<-EOT
      # mcp auth token parameter version ${module.mcp_auth_token.parameter_version}
      set -euo pipefail
      until [ -f ${local.marker}/lambda_layer_build ]; do sleep 10; done
      dnf install -yq unzip
      sudo -Eu ec2-user bash << 'EOF'
      set -euo pipefail
      export HOME=/home/ec2-user
      cd /home/ec2-user
      # uv provides uvx, which the documentation MCP server is started with. As ec2-user: the original installed
      # it as root, into /root/.local/bin, where Q - running as ec2-user - could not find it.
      curl -LsSf https://astral.sh/uv/install.sh | sh
      curl -LsSf https://raw.githubusercontent.com/nvm-sh/nvm/${var.nvm_version}/install.sh | bash
      export NVM_DIR=/home/ec2-user/.nvm
      set +u
      # --no-use skips activating a default version while sourcing, which on a first run does not exist yet.
      # nvm install then activates the one it installs, and makes it the default later shells start with.
      . "$NVM_DIR/nvm.sh" --no-use
      nvm install --lts
      npm install -g --no-fund --no-audit mcp-remote@${var.mcp_remote_version}
      set -u
      if [ ! -x /home/ec2-user/.local/bin/q ]; then
        curl -sSf --proto '=https' --tlsv1.2 "${var.q_cli_download_url}" -o q.zip
        # -o, so a re-run does not stop at unzip asking whether to overwrite.
        unzip -q -o q.zip
        ./q/install.sh --no-confirm
        rm -rf q q.zip
      fi
      mkdir -p ${local.q_config_dir}
      umask 077
      token=$(aws ssm get-parameter --region ${local.region} --name ${module.mcp_auth_token.parameter_name} --with-decryption --query Parameter.Value --output text)
      printf 'Authorization: Bearer %s\n' "$token" > ${local.mcp_header_file}
      # Written from a typed object rather than assembled as an escaped JSON string, which is what the
      # _monolithic template did inside this same document.
      cat > ${local.q_config_dir}/mcp.json << 'TFMCP'
      ${jsonencode(local.mcp_config)}
      TFMCP
      EOF
      touch ${local.marker}/q_developer_cli
      EOT
  }

  # The API, so the URL written into mcp.json answers by the time anyone starts Q.
  depends_on = [aws_ssm_association.lambda_layer_build, module.mcp_api]
}
# --- README on the workbench ------------------------------------------------------------------------------
locals {
  # Every output this root exposes, defined once. outputs.tf projects this map and the README on the
  # workbench renders it, so an output cannot exist without also appearing in that README (rules.md H-2).
  #
  # The token is the one value that is not here. The _monolithic template output it in clear, as
  # McpRequestHeader; here the map holds the command that reads it (rules.md H-2 on sensitive values), and no
  # output carries the value itself.
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server, through CloudFront"
      description = "Open the IDE here. The instance accepts its port only from CloudFront, so this URL is the way in. It answers once the distribution reads Deployed, several minutes after apply returns"
      value       = module.cloudfront.url
    }
    security_note = {
      order       = 2
      title       = "What this gives a language model"
      description = "Worth reading before using it. code-server runs with auth: none and CloudFront adds no authentication, so anyone with the URL has the IDE - and the instance role, and the token below. Started with --trust-all-tools, Q runs every tool without asking, with these credentials"
      value       = "instance role: ${join(", ", var.vscode_iam_policy_arns)} | code-server auth: none | MCP token: readable by the instance role"
    }
    mcp_server_url = {
      order       = 3
      title       = "MCP server endpoint"
      description = "The MCPServerApi output of the SAM template: ANY on this path, through the TOKEN authorizer to the MCP server function"
      value       = module.mcp_api.url
    }
    mcp_auth_token_command = {
      order       = 4
      title       = "Read the bearer token"
      description = "The token the authorizer accepts, generated by Terraform and kept in Parameter Store. A command rather than the value, so neither this README nor terraform output contains it. Requests carry it as Authorization: Bearer <token>. To rotate it, apply with -replace=module.mcp_auth_token.random_password.token: the authorizer and the header file on this instance follow, and the old token keeps working until the authorizer cache expires"
      value       = module.mcp_auth_token.retrieve_command
    }
    mcp_initialize_command = {
      order       = 5
      title       = "1. Call the endpoint without Q"
      description = "An MCP initialize request with curl. A JSON-RPC result with serverInfo and a Mcp-Session-Id header means the API, the authorizer, the layer and the session table all work. A 401 is the token, a 500 is the authorizer failing to read it, and a 502 is the server function failing - its log is below"
      value       = "curl -si -X POST ${module.mcp_api.url} -H \"Authorization: Bearer $(${module.mcp_auth_token.retrieve_command})\" -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}'"
    }
    q_login_command = {
      order       = 6
      title       = "2. Sign in to Q"
      description = "Run this in the IDE terminal. The CLI is installed but not signed in - it needs a Builder ID or an IAM Identity Center sign-in, which is interactive"
      value       = "q login"
    }
    q_chat_command = {
      order       = 7
      title       = "3. Start Q with the MCP servers"
      description = "As the original README had it. Ask for the weather in a city, the S3 bucket count, or the time twice - the second answer says how long since the first, from the session in DynamoDB. If a server fails to load, /exit and start again"
      value       = "q chat --trust-all-tools"
    }
    q_mcp_status_command = {
      order       = 8
      title       = "4. Check which MCP servers Q started"
      description = "A server that failed to start shows here rather than in the configuration"
      value       = "q mcp list"
    }
    mcp_servers = {
      order       = 9
      title       = "MCP servers configured for Q"
      description = "What Q can reach, from the typed object mcp.json is written from. The Lambda server reads its Authorization header from a file beside mcp.json, readable only by ec2-user, so the token is in neither the configuration nor the process list"
      value       = join("\n", [for name, server in local.mcp_config.mcpServers : "${name}: ${server.command} ${join(" ", server.args)}"])
    }
    mcp_config_command = {
      order       = 10
      title       = "The configuration Q loaded"
      description = "mcp.json as the Q CLI association wrote it. It holds no token"
      value       = "cat ${local.q_config_dir}/mcp.json"
    }
    mcp_sessions_table_name = {
      order       = 11
      title       = "MCP sessions table"
      description = "The McpSessionsTableName output of the SAM template. Each initialize stores a session here, kept for 24 hours"
      value       = module.mcp_sessions_table.name
    }
    mcp_sessions_scan_command = {
      order       = 12
      title       = "List the stored sessions"
      description = "The get_time tool writes last_time_asked into its session, which is how its second answer knows the first"
      value       = module.mcp_sessions_table.scan_command
    }
    mcp_server_log_command = {
      order       = 13
      title       = "MCP server function log"
      description = "An ImportModuleError here means the layer did not provide awslabs.mcp_lambda_handler; AccessDenied on DynamoDB means the session permissions"
      value       = module.mcp_server_function.log_tail_command
    }
    mcp_authorizer_log_command = {
      order       = 14
      title       = "Authorizer function log"
      description = "It logs only failures. An error reading the parameter here is a 500 at the endpoint; a rejected token raises Unauthorized, which API Gateway turns into a 401"
      value       = module.mcp_authorizer_function.log_tail_command
    }
    lambda_layer_version_arn = {
      order       = 15
      title       = "Lambda layer version"
      description = "awslabs.mcp_lambda_handler and its dependencies, built on this instance and published from the package below. A rebuilt package with a different checksum publishes the next version"
      value       = module.lambda_layer.layer_version_arn
    }
    lambda_layer_package = {
      order       = 16
      title       = "Lambda layer package"
      description = "Where the layer build uploaded the package, and the SHA-256 S3 recorded for it - the value the layer version is published for"
      value       = "${module.lambda_layer.package_s3_uri} (sha256 ${data.aws_s3_object.lambda_layer_package.checksum_sha256})"
    }
    cloudfront_status_command = {
      order       = 17
      title       = "Is the distribution deployed"
      description = "It has to read Deployed before the IDE URL answers. A 502 straight after apply is usually this, or code-server not yet started"
      value       = module.cloudfront.status_command
    }
    private_key_command = {
      order       = 18
      title       = "The workbench SSH private key"
      description = "Written to Parameter Store as a SecureString, where CloudFormation puts a generated key pair. No security group rule opens port 22; this is for an instance reached some other way"
      value       = module.key_pair.private_key_command
    }
  }
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
# The work happens inside code-server, where terraform output is not available, so every output above is also
# written to a README in the home directory the IDE opens (rules.md H-2).
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  association_name                 = "${var.project_name}-vscode-readme"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # Waits for the Q CLI step, the last one before it (rules.md D-5).
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
