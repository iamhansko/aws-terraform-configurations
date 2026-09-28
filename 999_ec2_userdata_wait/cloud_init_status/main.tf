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

  vpc_id    = module.network.vpc_id
  subnet_id = module.network.public_subnet_a_id

  additional_user_data = <<-EOT
    date > /home/ec2-user/COMMAND0.md
  EOT

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
      cloud-init status --wait
      sleep 10
      date > /home/ec2-user/COMMAND1.md
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
    timestamps_command = {
      order       = 3
      title       = "1. Read the timestamps in order"
      description = "COMMAND0.md is written by user data, COMMAND1.md by the association. COMMAND1 later than COMMAND0 is the thing being demonstrated: `cloud-init status --wait` made the association observe that user data had finished"
      value       = "for f in /home/ec2-user/COMMAND*.md; do printf '%-40s ' \"$f\"; cat \"$f\"; done"
    }
    cloud_init_status_command = {
      order       = 4
      title       = "2. What the association waited on"
      description = "`cloud-init status --wait` blocks until cloud-init reports done, which is the alternative this variant shows. It needs no marker file - and that is why this root has no until loop, unlike the marker_files variant (rules.md D-5)"
      value       = "cloud-init status --long"
    }
    cloud_init_log_command = {
      order       = 5
      title       = "3. When user data actually finished"
      description = "The timestamp cloud-init recorded for the final stage. Comparing it against COMMAND1.md shows how much of the wait was real rather than the sleep"
      value       = "sudo grep -E 'finished at|Cloud-init .* finished' /var/log/cloud-init-output.log | tail -3"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the order field and
  # taking values() sorts by that instead - values() returns a map's values ordered by key.
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  readme_body = join("\n", concat(
    ["# ${var.vscode_instance_name} - cloud-init status --wait", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}

# The work happens inside code-server in a browser, where "terraform output" does not exist, so every
# output above is also written to a README in the home directory the IDE opens (rules.md H-2).
#
# This association uses `cloud-init status --wait` rather than an `until [ -f ... ]` loop, because that
# is the mechanism this variant exists to show. The marker_files variant next to it demonstrates the
# other one, and the difference between the two READMEs is the difference between the variants
# (rules.md D-5).
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  # No marker to wait on here, so the ordering against the first association is stated directly. That
  # is weaker than a marker - it observes that the association resource was created, not that its
  # command finished - which is exactly the limitation the sibling variant addresses.
  depends_on = [aws_ssm_association.vscode_association_1]
  parameters = {
    # SSM runs as root, hence the chown. The heredoc delimiter is quoted and deliberately unlikely to
    # appear in the body: Terraform has already substituted every value, so the shell has no reason to
    # touch a "$" or a backtick in the README - and the commands in it contain both.
    commands = <<-EOT
      cloud-init status --wait
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      EOT
  }
}
