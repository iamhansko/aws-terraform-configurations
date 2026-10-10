data "aws_region" "current" {}
# The addresses CloudFront's edge locations make origin requests from.
#
# Looked up by name, where the _monolithic template carried a mapping of seventeen hardcoded prefix list ids
# keyed by region. Two things were wrong with that: the ids are per-region values AWS can change, and a region
# missing from the table made the lookup fail with an error about a map key rather than about a region.
data "aws_ec2_managed_prefix_list" "cloudfront_origin_facing" {
  name = var.cloudfront_prefix_list_name
}
# The managed origin request policy, by name. The original wrote its uuid - 216adef6-5c7f-47e4-b989-5492eafa07d3 -
# straight into the distribution, which is what the console shows and what most examples copy.
data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = var.cloudfront_origin_request_policy_name
}
locals {
  key_name = var.key_name == null ? "${var.cluster_name}-key" : var.key_name
  # The Q CLI's MCP configuration, built as a typed object and serialised.
  #
  # AWS_REGION is merged into the EKS server's environment here rather than being written into the variable's
  # default, so it comes from the provider's region and the MCP server cannot end up pointed at a different one
  # than the cluster is in (rules.md B-5).
  mcp_config = {
    mcpServers = {
      for name, server in var.mcp_servers : name => {
        command     = server.command
        args        = server.args
        env         = name == "awslabs.eks-mcp-server" ? merge(server.env, { AWS_REGION = data.aws_region.current.region }) : server.env
        disabled    = server.disabled
        autoApprove = server.autoApprove
      }
    }
  }
}
module "network" {
  source = "./modules/network"

  vpc_cidr_block           = var.vpc_cidr_block
  vpc_name                 = "${var.cluster_name}-vpc"
  internet_gateway_name    = "${var.cluster_name}-igw"
  public_subnet_name       = "${var.cluster_name}-public"
  private_subnet_name      = "${var.cluster_name}-private"
  public_route_table_name  = "${var.cluster_name}-public-rt"
  private_route_table_name = "${var.cluster_name}-private-rt"
  nat_gateway_name         = "${var.cluster_name}-natgw"
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name = local.key_name

  # key_pair consumes no network output, so nothing would otherwise order it against the network module's
  # resources (rules.md D-3).
  depends_on = [module.network]
}
module "eks_cluster" {
  source = "./modules/eks_cluster"

  name                   = var.cluster_name
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  # Referencing module.network.*_subnet_ids only orders this after the specific aws_subnet resources behind
  # those outputs, not after the NAT gateways and route table associations that never surface as outputs
  # (rules.md D-3).
  depends_on = [module.network]
}
# The three addons the _monolithic template did not declare at all.
#
# It created the cluster with bootstrap addons at their default, so EKS installed vpc-cni, kube-proxy and
# coredns as unmanaged self-managed addons - present in the console, absent from state, and with no version or
# configuration anything could set. The cluster module here sets bootstrap_self_managed_addons = false, which
# makes these three the only copies (rules.md C-4).
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  # A DaemonSet, so it reaches ACTIVE with zero nodes and belongs before any capacity - and nodes need it to
  # join Ready (rules.md C-4).
  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  depends_on = [module.network, module.eks_vpc_cni_addon]
}
module "eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name    = module.eks_cluster.cluster_name
  node_group_name = "core"
  instance_types  = var.node_group_instance_types
  desired_size    = var.node_group_desired_size
  min_size        = var.node_group_min_size
  max_size        = var.node_group_max_size
  labels          = var.node_group_labels
  subnet_ids      = module.network.private_subnet_ids
  key_name        = module.key_pair.key_name
  instance_tags = {
    Name = "${var.cluster_name}-core-node"
  }

  # Nodes need vpc-cni and kube-proxy running to join the cluster Ready (rules.md C-4).
  depends_on = [module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.eks_cluster.cluster_name

  # coredns is a Deployment and needs schedulable capacity to leave DEGRADED and become ACTIVE (rules.md C-4).
  depends_on = [
  module.network, module.eks_node_group]
}
# The workbench. Reached through CloudFront rather than directly, which is this project's one structural
# improvement over most of the others here - its only ingress rule is the CloudFront prefix list.
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name                = "vscode"
  vpc_id              = module.network.vpc_id
  subnet_id           = module.network.public_subnet_a_id
  key_name            = module.key_pair.key_name
  instance_type       = var.vscode_instance_type
  code_server_version = var.code_server_version
  security_group_name = "${var.cluster_name}-vscode-sg"
  # False by default, so 8000 is not open to the world. The prefix list rule below is the only way in.
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  ingress_prefix_list_ids     = [data.aws_ec2_managed_prefix_list.cloudfront_origin_facing.id]
  marker_file_path            = var.marker_file_path
  # The cluster security group, so kubectl on this instance reaches the API server without leaving the VPC.
  # Injected as an ID list so the module never learns what it belongs to (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]
  # AdministratorAccess, as the _monolithic template attached - and here it is worth naming as a risk rather
  # than a convenience. The EKS MCP server below runs with --allow-write and --allow-sensitive-data-access, so
  # a language model driving this instance inherits these credentials.
  iam_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"]

  depends_on = [module.network]
}
resource "aws_eks_access_entry" "vscode" {
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.vscode_ec2.iam_role_arn
  type          = "STANDARD"
}
resource "aws_eks_access_policy_association" "vscode" {
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.vscode_ec2.iam_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }

  # The _monolithic template declared the association and the entry as unrelated resources, so nothing ordered
  # the association after the entry it depends on (rules.md D-1).
  depends_on = [aws_eks_access_entry.vscode]
}
module "cloudfront" {
  source = "./modules/cloudfront_code_server"

  name               = var.cluster_name
  origin_domain_name = module.vscode_ec2.public_dns
  # The port from the module that configured code-server, so the origin and the listener cannot disagree
  # (rules.md B-5).
  origin_port              = module.vscode_ec2.code_server_port
  origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id
  price_class              = var.cloudfront_price_class

  depends_on = [
  module.network, module.vscode_ec2]
}
# Step one on the workbench: the Kubernetes tooling and a kubeconfig.
#
# An association rather than user data, and split from the Q CLI step below, because the two ran concurrently
# in the _monolithic template - both targeting the same instance, both calling dnf, so they raced for the
# package manager's lock. Sequencing them with marker files is what removes that (rules.md D-5).
resource "aws_ssm_association" "kubernetes_tooling" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.kubernetes_tooling_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/userdata ]; do sleep 10; done
      dnf install -yq docker bash-completion
      systemctl enable --now docker
      usermod -aG docker ec2-user
      # code-server is already running and predates the docker group, so its terminals would not have it
      # without a restart. The _monolithic template used "chmod 666 /var/run/docker.sock" instead, which opens
      # the daemon - and therefore root on the host - to every process on the instance.
      systemctl restart code-server

      sudo -Eu ec2-user bash << 'EOF'
      set -euo pipefail
      export HOME=/home/ec2-user
      cd /home/ec2-user
      mkdir -p /home/ec2-user/bin
      curl -sO https://s3.us-west-2.amazonaws.com/amazon-eks/${var.kubectl_download_version}/bin/linux/amd64/kubectl
      chmod +x kubectl
      mv kubectl /home/ec2-user/bin/kubectl
      export PATH=/home/ec2-user/bin:$PATH
      echo 'export PATH=/home/ec2-user/bin:$PATH' >> ~/.bashrc
      echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
      echo 'source <(kubectl completion bash)' >> ~/.bashrc
      echo 'alias k=kubectl' >> ~/.bashrc
      echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
      PLATFORM=$(uname -s)_amd64
      curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
      tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
      sudo install -m 0755 /tmp/eksctl /usr/local/bin && rm /tmp/eksctl
      curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
      chmod 700 get_helm.sh
      ./get_helm.sh
      rm get_helm.sh
      aws configure set default.region ${data.aws_region.current.region}
      # --region, which the _monolithic template omitted - without it the call uses whatever region the
      # instance's own configuration resolves to, which is not necessarily the cluster's.
      aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}
      EOF
      touch ${module.vscode_ec2.marker_file_path}/kubernetes_tooling
      EOT
  }

  # The access entry has to exist before update-kubeconfig produces a config that can actually authenticate -
  # kubectl would otherwise install cleanly and fail on its first call (rules.md D-2).
  depends_on = [module.vscode_ec2, aws_eks_access_policy_association.vscode, module.eks_coredns_addon]
}
# Step two: the Amazon Q CLI and its MCP servers.
resource "aws_ssm_association" "q_developer_cli" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.q_cli_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # Waits for the tooling step's marker, not the bootstrap's - so the two dnf runs never overlap
    # (rules.md D-5).
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/kubernetes_tooling ]; do sleep 10; done
      dnf install -yq python3.13 unzip
      ln -sf /usr/bin/python3.13 /usr/bin/python
      python -m ensurepip --upgrade

      sudo -Eu ec2-user bash << 'EOF'
      set -euo pipefail
      export HOME=/home/ec2-user
      cd /home/ec2-user
      # uv provides uvx, which is how every MCP server below is launched - Q starts them as child processes.
      curl -LsSf https://astral.sh/uv/install.sh | sh
      # Node, for the MCP servers distributed as npm packages rather than Python ones.
      curl -LsSf https://raw.githubusercontent.com/nvm-sh/nvm/${var.nvm_version}/install.sh | bash
      export NVM_DIR=/home/ec2-user/.nvm
      [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
      nvm install --lts
      curl -s --proto '=https' --tlsv1.2 -sSf "${var.q_cli_download_url}" -o q.zip
      unzip -q -o q.zip
      ./q/install.sh --no-confirm
      rm -rf q q.zip
      mkdir -p /home/ec2-user/.aws/amazonq
      # Written from a typed object rather than assembled as an escaped JSON string inside an SSM parameter,
      # which is what the _monolithic template did - a missing brace there was an apply-time failure in a
      # document nobody could read (rules.md E-3).
      cat > /home/ec2-user/.aws/amazonq/mcp.json << 'TFMCP'
      ${jsonencode(local.mcp_config)}
      TFMCP
      EOF
      touch ${module.vscode_ec2.marker_file_path}/q_developer_cli
      EOT
  }

  depends_on = [aws_ssm_association.kubernetes_tooling]
}
locals {
  # Every output this project exposes, defined once. outputs.tf projects these and the README below renders
  # them, so no value expression is written twice (rules.md B-5/H-2).
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server, through CloudFront"
      description = "Open the IDE here. The instance itself is not reachable from the internet - its security group accepts port 8000 only from CloudFront's origin-facing prefix list - so this URL is the only way in. It answers once the distribution reads Deployed, which is several minutes after apply returns"
      value       = module.cloudfront.url
    }
    security_note = {
      order       = 2
      title       = "What this gives a language model"
      description = "Worth reading before using it. code-server runs with auth: none and CloudFront adds no authentication of its own, so anyone with the URL has the IDE. The instance holds AdministratorAccess and cluster-admin on the cluster, and the EKS MCP server is configured with --allow-write and --allow-sensitive-data-access - so Q can create and modify Kubernetes objects and read Secrets. That is the demo working as intended; it is also why this should not be left running"
      value       = "instance role: AdministratorAccess | cluster access: AmazonEKSClusterAdminPolicy | eks-mcp-server: --allow-write --allow-sensitive-data-access | code-server auth: none"
    }
    cluster_name = {
      order       = 3
      title       = "EKS cluster name"
      description = "The cluster Q inspects and changes through the EKS MCP server"
      value       = module.eks_cluster.cluster_name
    }
    mcp_servers = {
      order       = 4
      title       = "MCP servers configured for Q"
      description = "What Q can reach. Built from a typed object rather than the escaped JSON the original embedded in an SSM parameter, so the structure is checked at plan time"
      value       = join("\n", [for name, server in local.mcp_config.mcpServers : "${name}: ${server.command} ${join(" ", server.args)}"])
    }
    mcp_config_command = {
      order       = 5
      title       = "1. Read the MCP configuration on the instance"
      description = "The file Q actually loaded. If a server does not appear in Q's tool list, compare this against the mcp_servers output above - a server that failed to start leaves no trace in the config"
      value       = "cat /home/ec2-user/.aws/amazonq/mcp.json"
    }
    q_login_command = {
      order       = 6
      title       = "2. Sign in to Q"
      description = "Run this in the IDE terminal. The CLI is installed but not authenticated - it needs a Builder ID or an IAM Identity Center sign-in, which is an interactive step Terraform cannot do"
      value       = "q login"
    }
    q_chat_command = {
      order       = 7
      title       = "3. Ask Q about the cluster"
      description = "The demo. Q calls the EKS MCP server, which uses the instance's credentials - so the answer comes from the live cluster rather than from the model's training data"
      value       = "q chat \"list the nodes and pods in the ${module.eks_cluster.cluster_name} cluster and tell me what is running\""
    }
    q_mcp_status_command = {
      order       = 8
      title       = "4. Check which MCP servers Q started"
      description = "A server whose uvx package failed to download is reported here rather than in the config. This is the first thing to check when Q answers from training data instead of from the cluster"
      value       = "q mcp list"
    }
    cluster_check_command = {
      order       = 9
      title       = "5. Check the cluster directly"
      description = "The same question without Q in the way, for telling an MCP problem apart from a cluster problem"
      value       = "kubectl get nodes,pods -A -o wide"
    }
    cloudfront_status_command = {
      order       = 10
      title       = "6. Is the distribution deployed"
      description = "It has to read Deployed before the IDE URL answers. A 502 straight after apply is usually this, or code-server not yet started"
      value       = module.cloudfront.status_command
    }
    prefix_list_command = {
      order       = 11
      title       = "7. The prefix list the instance trusts"
      description = "The addresses CloudFront makes origin requests from, looked up by name rather than from a hardcoded per-region table - which is what the _monolithic template carried for seventeen regions and had no entry for the rest"
      value       = "aws ec2 describe-managed-prefix-lists --filters Name=prefix-list-name,Values=${var.cloudfront_prefix_list_name} --query 'PrefixLists[].[PrefixListId,PrefixListName,Version]' --output table"
    }
    update_kubeconfig_command = {
      order       = 12
      title       = "Re-point kubectl"
      description = "The tooling association already ran this. Re-run it if the kubeconfig is ever lost - with --region, which the original omitted"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
    private_key_command = {
      order       = 13
      title       = "The workbench's SSH private key"
      description = "Written to SSM Parameter Store as a SecureString, which is where CloudFormation puts a generated key pair's private half. SSH is the way in if CloudFront is broken, since the prefix list rule blocks a direct browser connection"
      value       = "aws ssm get-parameter --name /ec2/keypair/${module.key_pair.key_pair_id} --with-decryption --query Parameter.Value --output text"
    }
  }
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  readme_body = join("\n", concat(
    ["# ${var.cluster_name}", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}
# The work happens inside code-server in a browser, where terraform output is not available, so every output
# above is also written to a README in the home directory the IDE opens (rules.md H-2).
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/q_developer_cli ]; do sleep 10; done
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_readme
      EOT
  }

  depends_on = [aws_ssm_association.q_developer_cli]
}
