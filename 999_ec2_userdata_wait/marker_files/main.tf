data "aws_region" "current" {}

data "aws_ssm_parameter" "amazon_linux2023_ami_id" {
  name = var.amazon_linux2023_ami_id
}

module "network" {
  source = "./modules/network"
}

module "key_pair" {
  source   = "./modules/key_pair"
  key_name = var.key_pair_name

  # module.network's value references only order this after the specific aws_subnet or
  # aws_vpc that produced them, not after the NAT gateway and route tables the network
  # module also owns. depends_on states "after the whole network" (rules.md D-3).
  depends_on = [module.network]
}

module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name          = var.vscode_instance_name
  instance_type = var.vscode_instance_type
  ami_id        = data.aws_ssm_parameter.amazon_linux2023_ami_id.insecure_value
  key_name      = module.key_pair.key_name

  vpc_id           = module.network.vpc_id
  subnet_id        = module.network.public_subnet_a_id
  marker_file_path = var.marker_file_path

  additional_user_data = <<-EOT
    date > /home/ec2-user/BEFORE_MARK.md
    sleep 120
    date > /home/ec2-user/AFTER_MARK.md
  EOT

  # module.network's value references only order this after the specific aws_subnet or
  # aws_vpc that produced them, not after the NAT gateway and route tables the network
  # module also owns. depends_on states "after the whole network" (rules.md D-3).
  depends_on = [module.network]
}

resource "aws_ssm_association" "vscode_association_1" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 300
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/userdata ]; do sleep 10; done
      sleep 10
      date > /home/ec2-user/COMMAND1.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_association_1
      EOT
  }
}

resource "aws_ssm_association" "vscode_association_2" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 300
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  depends_on = [
    aws_ssm_association.vscode_association_1
  ]
  parameters = {
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/vscode_association_1 ]; do sleep 10; done
      sleep 20
      date > /home/ec2-user/COMMAND2.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_association_2
      EOT
  }
}

resource "aws_ssm_association" "vscode_association_3" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 300
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  depends_on = [
    aws_ssm_association.vscode_association_2
  ]
  parameters = {
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/vscode_association_2 ]; do sleep 10; done
      sleep 30
      date > /home/ec2-user/COMMAND3.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_association_3
      EOT
  }
}

locals {
  # Every output this project exposes, defined once. outputs.tf projects these and the README below
  # renders them, so no value expression is written twice (rules.md B-5/H-2).
  outputs = {
    vscode = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here. The timestamp files this project writes are in the home directory the IDE opens, which is the whole point - the demonstration is what order they carry"
      value       = "http://${module.vscode_ec2.public_ip}:8000"
    }
    instance_id = {
      order       = 2
      title       = "Instance"
      description = "The instance every SSM Association here targets"
      value       = module.vscode_ec2.instance_id
    }
    marker_file_path = {
      order       = 3
      title       = "Marker directory"
      description = "Where each stage drops its completion marker. Read back from the module rather than restated from the variable, so the until loops and the module cannot disagree about the path (rules.md B-5)"
      value       = module.vscode_ec2.marker_file_path
    }
    timestamps_command = {
      order       = 4
      title       = "1. Read the timestamps in order"
      description = "BEFORE_MARK and AFTER_MARK are written by user data 120 seconds apart; COMMAND1 through COMMAND3 by the three associations. Every timestamp later than the one before it is the demonstration - the marker file is what makes each stage observe that the previous one finished, which depends_on alone does not"
      value       = "for f in /home/ec2-user/BEFORE_MARK.md /home/ec2-user/AFTER_MARK.md /home/ec2-user/COMMAND1.md /home/ec2-user/COMMAND2.md /home/ec2-user/COMMAND3.md; do printf '%-40s ' \"$f\"; cat \"$f\" 2>/dev/null || echo 'not written yet'; done"
    }
    markers_command = {
      order       = 5
      title       = "2. The markers themselves"
      description = "One file per completed stage, in the order they were created. AFTER_MARK later than the userdata marker would mean the marker was touched too early, which is the failure this pattern is written to avoid (rules.md B-4)"
      value       = "ls -l --time-style=full-iso ${module.vscode_ec2.marker_file_path}"
    }
    association_status_command = {
      order       = 6
      title       = "3. What SSM thought happened"
      description = "Success for every association. This is the view that does not tell you whether the remote command finished, which is why the markers exist - an association can report success on a command that was still running work in the background"
      value       = "aws ssm describe-instance-associations-status --instance-id ${module.vscode_ec2.instance_id} --query 'InstanceAssociationStatusInfos[].[AssociationId,Status,ExecutionSummary]' --output table"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the order field and
  # taking values() sorts by that instead - values() returns a map's values ordered by key.
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  readme_body = join("\n", concat(
    ["# ${var.vscode_instance_name} - marker files", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}

# The work happens inside code-server in a browser, where "terraform output" does not exist, so every
# output above is also written to a README in the home directory the IDE opens (rules.md H-2).
#
# Last in the chain, waiting on the third association's marker - which that association now leaves
# behind for this purpose. Writing the README earlier would describe timestamps that do not exist yet.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  depends_on = [aws_ssm_association.vscode_association_3]
  parameters = {
    # The until loop, not depends_on, is what orders this after the previous stage (rules.md D-5).
    #
    # SSM runs as root, hence the chown. The heredoc delimiter is quoted and deliberately unlikely to
    # appear in the body: Terraform has already substituted every value, so the shell has no reason to
    # touch a "$" or a backtick in the README - and the commands in it contain both.
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/vscode_association_3 ]; do sleep 10; done
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_readme
      EOT
  }
}
