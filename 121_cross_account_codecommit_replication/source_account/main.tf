# Resolve the public IPv4 address of the machine running Terraform once at the root. The child security
# group modules are ordered after other modules, so putting this plan-time read inside them could defer it
# until apply; passing only the resulting CIDR also keeps the modules independent of the lookup service
# (rules.md B-6/D-6).
data "http" "my_ip" {
  url = var.my_ip_lookup_url

  lifecycle {
    postcondition {
      condition = (
        self.status_code == 200 &&
        can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$", trimspace(self.response_body))) &&
        can(cidrhost("${trimspace(self.response_body)}/32", 0))
      )
      error_message = "my_ip_lookup_url must return HTTP 200 with one bare IPv4 address. Set it to a trusted HTTPS address-reflection endpoint reachable from the machine running Terraform."
    }
  }
}
locals {
  my_ip_cidr = "${trimspace(data.http.my_ip.response_body)}/32"
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

resource "terraform_data" "account_guard" {
  input = var.source_account_id

  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.source_account_id
      error_message = "This root must be planned and applied with source_account_id credentials. The active caller belongs to a different AWS account."
    }
  }
}

module "network" {
  source = "./modules/network"

  vpc_cidr_block           = var.vpc_cidr_block
  availability_zone_suffix = var.availability_zone_suffix
  vpc_name                 = var.vpc_name
  internet_gateway_name    = var.internet_gateway_name
  public_subnet_name       = var.public_subnet_name
  public_route_table_name  = var.public_route_table_name

  depends_on = [terraform_data.account_guard]
}

module "key_pair" {
  source = "./modules/key_pair"

  key_name        = var.key_name
  key_name_prefix = var.key_name_prefix
  rsa_bits        = var.key_rsa_bits

  # This module has no VPC inputs but still waits for the complete network (rules.md D-3).
  depends_on = [module.network]
}

module "codecommit_replication_source" {
  source = "./modules/codecommit_replication_source"

  partition                              = data.aws_partition.current.partition
  dns_suffix                             = data.aws_partition.current.dns_suffix
  source_account_id                      = var.source_account_id
  source_region                          = data.aws_region.current.region
  target_account_id                      = var.target_account_id
  target_region                          = var.target_region
  source_account_repository              = var.source_account_repository
  target_account_repository              = var.target_account_repository
  cross_account_role_name                = var.cross_account_role_name
  source_codebuild_role_name             = var.source_codebuild_role_name
  main_branch                            = var.main_branch
  project_name                           = var.project_name
  pipeline_name                          = var.pipeline_name
  build_project_name                     = var.build_project_name
  event_rule_name                        = var.event_rule_name
  artifact_bucket_prefix                 = var.artifact_bucket_prefix
  codebuild_image                        = var.codebuild_image
  codebuild_compute_type                 = var.codebuild_compute_type
  build_timeout_minutes                  = var.build_timeout_minutes
  build_log_retention_days               = var.build_log_retention_days
  initial_commit_file_path               = var.initial_commit_file_path
  initial_commit_file_content            = var.initial_commit_file_content
  initial_commit_message                 = var.initial_commit_message
  pipeline_role_propagation_wait_seconds = var.pipeline_role_propagation_wait_seconds

  # CodeCommit and delivery services are not VPC resources, but this root has no network-order exception
  # (rules.md D-3).
  depends_on = [module.network]
}

module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name                        = var.vscode_name
  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  ami_ssm_parameter_name      = var.vscode_ami_ssm_parameter_name
  root_volume_size            = var.vscode_root_volume_size
  code_server_version         = var.code_server_version
  code_server_port            = var.code_server_port
  security_group_name_prefix  = var.vscode_security_group_name_prefix
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  my_ip_cidr                  = local.my_ip_cidr
  ingress_prefix_list_ids     = var.ingress_prefix_list_ids
  iam_policy_arns             = var.vscode_iam_policy_arns
  marker_file_path            = var.marker_file_path

  # System packages are available to ec2-user; the Python package and all user configuration are installed
  # as ec2-user. No staging upload or cfn-signal remains, and this content runs before the module's final
  # userdata marker.
  additional_user_data = <<-EOT
    dnf install -yq python3 python3-pip
    sudo -Eu ec2-user env HOME=/home/ec2-user bash << 'WORKBENCH_SETUP'
    set -euo pipefail
    python3 -m pip install --user --no-warn-script-location git-remote-codecommit
    grep -qxF 'export PATH=$HOME/.local/bin:$PATH' "$HOME/.bashrc" || echo 'export PATH=$HOME/.local/bin:$PATH' >> "$HOME/.bashrc"
    aws configure set default.region ${data.aws_region.current.region}
    git config --global credential.helper '!aws codecommit credential-helper $@'
    git config --global credential.UseHttpPath true
    WORKBENCH_SETUP
  EOT

  depends_on = [module.network, module.key_pair]
}

locals {
  # Every source-root output is defined once here. outputs.tf projects this map, and the same ordered entries
  # are rendered into the workbench README (rules.md B-5/H-2).
  outputs = {
    apply_order = {
      order       = 1
      title       = "Apply order"
      description = "The two account roots have separate state and credentials, so Terraform cannot create a cross-state dependency"
      value       = "1. Apply ../target_account with target-account credentials. 2. Pass its source_root_handoff values here and apply this root with source-account credentials. This root initializes main before creating the pipeline, so no manual seed step is required."
    }
    destroy_order = {
      order       = 2
      title       = "Destroy order"
      description = "Stop and remove the source pipeline before removing the target role and repository"
      value       = "1. Destroy source_account with source-account credentials. 2. Destroy target_account with target-account credentials."
    }
    vscode_url = {
      order       = 3
      title       = "VS Code workbench URL"
      description = "Public code-server URL, restricted to the detected My IP by default; setting allow_inbound_from_anywhere true admits every IPv4 source"
      value       = module.vscode_ec2.vscode_url
    }
    source_region = {
      order       = 4
      title       = "Source region"
      description = "Region containing the source repository, pipeline, build, and artifact bucket"
      value       = module.codecommit_replication_source.source_region
    }
    source_repository = {
      order       = 5
      title       = "Source repository"
      description = "Repository whose main branch Terraform initializes before CodePipeline is created"
      value       = module.codecommit_replication_source.source_repository_name
    }
    source_clone_command = {
      order       = 6
      title       = "Clone the source repository"
      description = "Run on the workbench; git-remote-codecommit is installed for ec2-user and uses the instance role"
      value       = "git clone codecommit::${module.codecommit_replication_source.source_region}://${module.codecommit_replication_source.source_repository_name}"
    }
    target_region = {
      order       = 8
      title       = "Target region"
      description = "Region explicitly used in the target Git remote URL"
      value       = module.codecommit_replication_source.target_region
    }
    target_repository = {
      order       = 9
      title       = "Target repository"
      description = "Repository receiving the source repository's complete mirrored ref set"
      value       = module.codecommit_replication_source.target_repository_name
    }
    source_codebuild_role_arn = {
      order       = 10
      title       = "Source CodeBuild role"
      description = "The only source-account principal allowed by the target role trust condition"
      value       = module.codecommit_replication_source.source_codebuild_role_arn
    }
    target_cross_account_role_arn = {
      order       = 11
      title       = "Target cross-account role"
      description = "The exact target role the build may assume; it can pull and push only the target repository"
      value       = module.codecommit_replication_source.target_cross_account_role_arn
    }
    pipeline_name = {
      order       = 12
      title       = "Replication pipeline"
      description = "Two-stage Source plus Build pipeline; the build emits no output artifact"
      value       = module.codecommit_replication_source.pipeline_name
    }
    pipeline_status_command = {
      order       = 13
      title       = "Check pipeline status"
      description = "Run with source-account credentials"
      value       = "aws codepipeline get-pipeline-state --name ${module.codecommit_replication_source.pipeline_name} --region ${module.codecommit_replication_source.source_region}"
    }
    build_project_name = {
      order       = 14
      title       = "Mirror build project"
      description = "CodeBuild clones the source with its own role, assumes the target role, then pushes all refs with --mirror"
      value       = module.codecommit_replication_source.build_project_name
    }
    build_status_command = {
      order       = 15
      title       = "Check the latest mirror build"
      description = "Run with source-account credentials; the output includes build status and timestamps"
      value       = "BUILD_ID=$(aws codebuild list-builds-for-project --project-name ${module.codecommit_replication_source.build_project_name} --sort-order DESCENDING --query 'ids[0]' --output text --region ${module.codecommit_replication_source.source_region}) && aws codebuild batch-get-builds --ids \"$BUILD_ID\" --query 'builds[0].[buildStatus,startTime,endTime]' --output table --region ${module.codecommit_replication_source.source_region}"
    }
    source_head_command = {
      order       = 16
      title       = "Read the source main commit"
      description = "Run with source-account credentials and compare the commit ID with the target command below"
      value       = "aws codecommit get-branch --repository-name ${module.codecommit_replication_source.source_repository_name} --branch-name ${module.codecommit_replication_source.main_branch} --query 'branch.commitId' --output text --region ${module.codecommit_replication_source.source_region}"
    }
    target_repository_verification_command = {
      order       = 17
      title       = "Verify the target repository"
      description = "Run in a shell holding target-account credentials, not from the source workbench role"
      value       = "aws codecommit get-repository --repository-name ${module.codecommit_replication_source.target_repository_name} --region ${module.codecommit_replication_source.target_region}"
    }
    target_head_command = {
      order       = 18
      title       = "Read the target main commit"
      description = "Run with target-account credentials. It must equal the source commit ID after a successful mirror build"
      value       = "aws codecommit get-branch --repository-name ${module.codecommit_replication_source.target_repository_name} --branch-name ${module.codecommit_replication_source.main_branch} --query 'branch.commitId' --output text --region ${module.codecommit_replication_source.target_region}"
    }
    artifact_bucket_name = {
      order       = 19
      title       = "Pipeline artifact bucket"
      description = "Private encrypted generated-name bucket. force_destroy removes pipeline artifacts during source teardown"
      value       = module.codecommit_replication_source.artifact_bucket_name
    }
    vscode_port_forward_command = {
      order       = 20
      title       = "Optional SSM workbench tunnel"
      description = "Alternative to the public URL that forwards code-server to localhost through the SSM agent's outbound connection and needs no inbound rule"
      value       = "aws ssm start-session --target ${module.vscode_ec2.instance_id} --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"${var.code_server_port}\"],\"localPortNumber\":[\"${var.code_server_port}\"]}' --region ${data.aws_region.current.region}"
    }
    private_key_command = {
      order       = 21
      title       = "Workbench recovery key"
      description = "Retrieves the generated private key; port 22 is not opened by this project"
      value       = module.key_pair.private_key_command
    }
  }

  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })

  readme_body = join("\n", concat(
    ["# Cross-account CodeCommit replication", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}

resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds

  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }

  parameters = {
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/userdata ]; do sleep 10; done
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_readme
      EOT
  }

  # The remote until loop, not this graph edge, proves userdata finished (rules.md D-5/H-2).
  depends_on = [module.vscode_ec2, module.codecommit_replication_source]
}
