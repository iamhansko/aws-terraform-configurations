data "aws_region" "current" {}
module "network" {
  source = "./modules/network"

  vpc_cidr_block           = var.vpc_cidr_block
  vpc_name                 = "${var.prefix}-vpc"
  internet_gateway_name    = "${var.prefix}-igw"
  public_subnet_name       = "${var.prefix}-public"
  private_subnet_name      = "${var.prefix}-private"
  public_route_table_name  = "${var.prefix}-public-rt"
  private_route_table_name = "${var.prefix}-private-rt"
  nat_gateway_name         = "${var.prefix}-natgw"
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name = var.key_name

  # key_pair consumes no network output, so nothing would otherwise order it
  # against the network module's resources. Every module in a root that has a
  # network module waits for all of it (rules.md D-3).
  depends_on = [module.network]
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name                        = var.vscode_name
  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  iam_policy_arns             = var.vscode_iam_policy_arns
  security_group_name         = "${var.prefix}-vscode-sg"
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  # Lets the README association below know when the bootstrap has finished
  # (rules.md H-2). The module touches <path>/userdata as its last step.
  marker_file_path = var.marker_file_path
  # The _monolithic project kept two hand-swapped bootstrap scripts,
  # scripts/default.sh and scripts/kubectl.sh, identical except that the second
  # also installed kubectl, eksctl and helm. Choosing between them meant editing
  # the template. Here the difference is a variable rendered with template
  # directives, so both variants come from one configuration and nothing has to
  # be kept in sync by hand (rules.md B-4).
  additional_user_data = <<-EOT
    dnf install -yq python3.13
    ln -sf /usr/bin/python3.13 /usr/bin/python
    python -m ensurepip --upgrade
    %{if var.install_docker~}
    # Building container images needs a real daemon on the host, so this is the
    # one tool here that cannot become a provider resource (rules.md E-1/H-1).
    dnf install -yq docker
    systemctl enable --now docker
    # Adds ec2-user to the docker group rather than the _monolithic script's
    # "chmod 666 /var/run/docker.sock", which hands every local user
    # root-equivalent control of the daemon (rules.md H-1).
    usermod -aG docker ec2-user
    # code-server is already running from the module's bootstrap, so its process
    # predates the docker group and its integrated terminals inherit the groups
    # that process started with. Restarting picks the group up, which is what
    # makes docker usable from the IDE without loosening the socket's
    # permissions (rules.md H-1).
    systemctl restart code-server
    %{endif~}
    %{if var.install_kubernetes_tools~}
    # Runs as ec2-user with HOME pinned: user data runs as root, so "~" can
    # still resolve to /root and the tools would land somewhere the code-server
    # session cannot see (rules.md H-1). No "aws eks update-kubeconfig" follows,
    # unlike the EKS projects in this repository: there is no cluster in this
    # root module to point at.
    sudo -Eu ec2-user bash << 'EOF'
    export HOME=/home/ec2-user
    cd $HOME
    mkdir -p $HOME/bin
    curl -sO https://s3.us-west-2.amazonaws.com/amazon-eks/${var.kubectl_download_version}/bin/linux/amd64/kubectl
    chmod +x ./kubectl && mv ./kubectl $HOME/bin/kubectl
    export PATH=$HOME/bin:$PATH
    echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc
    # Order matters: sourcing the completion defines __start_kubectl, so a
    # "complete" line placed before it fails on every login.
    echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
    echo 'source <(kubectl completion bash)' >> ~/.bashrc
    echo 'alias k=kubectl' >> ~/.bashrc
    echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
    PLATFORM=$(uname -s)_amd64
    curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
    tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
    sudo install -m 0755 /tmp/eksctl /usr/local/bin && rm /tmp/eksctl
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh && ./get_helm.sh
    aws configure set default.region ${data.aws_region.current.region}
    EOF
    %{endif~}
  EOT

  depends_on = [module.network]
}
locals {
  # Every output this project exposes, defined once. outputs.tf projects these
  # and the README below renders them, so no value is written twice (rules.md
  # #5/#35). Adding an entry here is what makes an output possible, which is
  # what keeps the README from silently falling behind outputs.tf.
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here. It runs with auth disabled, so treat the URL itself as the credential"
      value       = module.vscode_ec2.vscode_url
    }
    instance_id = {
      order       = 2
      title       = "Instance ID"
      description = "ID of the VS Code EC2 instance"
      value       = module.vscode_ec2.instance_id
    }
    private_key_parameter = {
      order       = 3
      title       = "SSH private key"
      description = "SSM parameter holding the generated private key. Fetch it with: aws ssm get-parameter --with-decryption --name <this> --query Parameter.Value --output text"
      value       = "/ec2/keypair/${module.key_pair.key_pair_id}"
    }
    session_manager_command = {
      order       = 4
      title       = "Shell without opening a port"
      description = "Starts a shell on the instance through SSM, which works even with allow_inbound_from_anywhere set to false"
      value       = "aws ssm start-session --target ${module.vscode_ec2.instance_id}"
    }
    port_forward_command = {
      order       = 5
      title       = "Reach code-server without opening a port"
      description = "Forwards the code-server port to localhost through SSM, then open http://localhost:8000. The safe way to use this instance with allow_inbound_from_anywhere set to false"
      value       = "aws ssm start-session --target ${module.vscode_ec2.instance_id} --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"${module.vscode_ec2.code_server_port}\"],\"localPortNumber\":[\"${module.vscode_ec2.code_server_port}\"]}'"
    }
    docker_check_command = {
      order       = 6
      title       = "Check Docker works from the IDE terminal"
      description = "Run this in a code-server terminal. It works without sudo because ec2-user was added to the docker group and code-server was restarted to pick it up"
      value       = "docker run --rm public.ecr.aws/amazonlinux/amazonlinux echo ok"
    }
    bootstrap_log_command = {
      order       = 7
      title       = "Read the bootstrap log"
      description = "The user data script runs with set -x, so this is the first place to look if a tool is missing"
      value       = "sudo tail -n 100 /var/log/cloud-init-output.log"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by
  # the order field and taking values() sorts by that instead - values() returns
  # a map's values ordered by key - so the README reads top to bottom in a useful
  # order, still fully determined by the configuration rather than shuffling
  # between applies.
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  # Rendered from the same map, so an added output shows up here without anyone
  # remembering to edit two places (rules.md H-2).
  readme_body = join("\n", concat(
    ["# ${var.vscode_name}", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}
# The work happens inside code-server in a browser, where "terraform output" is
# not available, so every output above is also written to a README in the home
# directory the IDE opens (rules.md H-2).
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is
    # what orders this after the instance bootstrap, and the marker this command
    # leaves behind is what a later association would wait on (rules.md D-5).
    # SSM runs as root, hence the chown - without it the file is not editable
    # from the IDE.
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
