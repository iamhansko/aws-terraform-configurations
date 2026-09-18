data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
# Six clusters, one per condition the EKS Node Monitoring Agent reports. The
# _monolithic template wrote every one of them out by hand: six aws_eks_cluster, six
# aws_eks_node_group, six aws_launch_template, six OIDC providers, six Karpenter roles
# and thirty-six aws_eks_addon blocks, differing only in a name and a tag. Everything
# below is for_each over var.scenarios instead, so adding a seventh condition is a map
# entry rather than sixty lines (rules.md B-7).
#
# for_each keys are literal strings in the configuration, so they are known at plan
# time - which is what for_each requires of keys (rules.md B-8).
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

  # key_pair consumes no network output, so nothing would otherwise order it against
  # the network module's resources (rules.md D-3).
  depends_on = [module.network]
}
# One security group for all six clusters and the bastion, as the _monolithic template
# had it. That is what lets one instance reach six API servers.
module "cluster_security_group" {
  source = "./modules/cluster_security_group"

  vpc_id = module.network.vpc_id
  name   = "${var.prefix}-cluster-sg"

  depends_on = [module.network]
}
module "eks_cluster" {
  source   = "./modules/eks_cluster"
  for_each = var.scenarios

  name               = "${var.prefix}-${each.value.cluster_suffix}"
  kubernetes_version = var.kubernetes_version
  subnet_ids         = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  # Public as well as private, as the _monolithic template had it: the demo is driven
  # from the bastion, but a public endpoint is what lets an operator watch six clusters
  # from their own machine.
  endpoint_public_access = true
  # The shared group, so every cluster's managed ENIs and the bastion sit in one group
  # (rules.md B-6 - the module is handed IDs and never learns whose they are).
  additional_security_group_ids = [module.cluster_security_group.security_group_id]

  depends_on = [module.network]
}
module "eks_vpc_cni_addon" {
  source   = "./modules/eks_vpc_cni_addon"
  for_each = var.scenarios

  cluster_name = module.eks_cluster[each.key].cluster_name

  # A DaemonSet that reaches ACTIVE with zero nodes, so it is created before any node
  # capacity - nodes need it running to join Ready (rules.md C-4).
  depends_on = [module.network]
}
module "eks_kube_proxy_addon" {
  source   = "./modules/eks_kube_proxy_addon"
  for_each = var.scenarios

  cluster_name = module.eks_cluster[each.key].cluster_name

  depends_on = [module.network]
}
# Pod Identity has to be running before the CloudWatch addon below can use the
# association it declares, which is why it is a separate addon module ordered ahead of
# it rather than something bundled in (rules.md C-4).
module "eks_pod_identity_agent_addon" {
  source   = "./modules/eks_pod_identity_agent_addon"
  for_each = var.scenarios

  cluster_name = module.eks_cluster[each.key].cluster_name

  depends_on = [module.network]
}
module "eks_node_group" {
  source   = "./modules/eks_node_group"
  for_each = var.scenarios

  cluster_name    = module.eks_cluster[each.key].cluster_name
  node_group_name = "${var.prefix}-${each.value.cluster_suffix}-mng"
  instance_types  = var.node_instance_types
  desired_size    = var.node_desired_size
  min_size        = var.node_desired_size
  max_size        = var.node_desired_size
  subnet_ids      = module.network.private_subnet_ids
  key_name        = module.key_pair.key_name
  # The nodes join the shared group too, so the bastion reaches them directly when a
  # scenario has to be reproduced on a specific node.
  vpc_security_group_ids = [module.cluster_security_group.security_group_id]

  # Nodes need vpc-cni and kube-proxy running to join the cluster Ready
  # (rules.md C-4).
  depends_on = [
    module.network,
    module.eks_vpc_cni_addon,
    module.eks_kube_proxy_addon,
  ]
}
module "eks_coredns_addon" {
  source   = "./modules/eks_coredns_addon"
  for_each = var.scenarios

  cluster_name = module.eks_cluster[each.key].cluster_name

  # coredns is a Deployment and needs schedulable capacity to leave DEGRADED and become
  # ACTIVE, so it comes after the node group rather than before it (rules.md C-4).
  depends_on = [module.eks_node_group]
}
# The agent this project exists for. It reports node conditions - the six in
# var.scenarios among them - and the managed node group's node_repair_config is what
# acts on them.
module "eks_node_monitoring_agent_addon" {
  source   = "./modules/eks_node_monitoring_agent_addon"
  for_each = var.scenarios

  cluster_name = module.eks_cluster[each.key].cluster_name

  # The agent runs as a DaemonSet, so it needs nodes to run on before it reports
  # anything (rules.md C-4).
  depends_on = [module.eks_node_group]
}
# Ships the agent's own log to a per-cluster CloudWatch log group, which is how a
# detected condition is readable without kubectl.
module "eks_cloudwatch_observability_addon" {
  source   = "./modules/eks_cloudwatch_observability_addon"
  for_each = var.scenarios

  cluster_name          = module.eks_cluster[each.key].cluster_name
  pod_identity_role_arn = aws_iam_role.cloudwatch_observability.arn
  # Carries the ordering rather than a value: the association this addon declares is
  # resolved by eks-pod-identity-agent, which therefore has to exist first
  # (rules.md D-1).
  pod_identity_agent_dependency = module.eks_pod_identity_agent_addon[each.key].pod_identity_agent_addon_arn

  depends_on = [module.eks_node_group]
}
# One role shared by all six clusters' CloudWatch agents. Pod Identity scopes it per
# cluster through the association, so a single role is enough - and the _monolithic
# template did the same.
resource "aws_iam_role" "cloudwatch_observability" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["pods.eks.amazonaws.com"]
      }
      # TagSession alongside AssumeRole is what Pod Identity requires - it tags the
      # session with the cluster and service account it issued the credentials for.
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}
resource "aws_iam_role_policy_attachment" "cloudwatch_observability" {
  for_each   = toset(var.cloudwatch_observability_policy_arns)
  role       = aws_iam_role.cloudwatch_observability.name
  policy_arn = each.value
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  marker_file_path            = var.marker_file_path
  # Joining the shared cluster group is what lets one instance reach all six API
  # servers and every node (rules.md B-6).
  extra_security_group_ids = [module.cluster_security_group.security_group_id]
  # An EKS cluster and this instance live in the same root module, so it carries all
  # five tools (rules.md H-1). Six clusters means six kubeconfig contexts, which is why
  # the loop below runs update-kubeconfig once per cluster with an explicit alias -
  # without aliases the six contexts are distinguishable only by ARN.
  additional_user_data = <<-EOT
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    systemctl restart code-server
    sudo -Eu ec2-user bash << 'EOF'
    export HOME=/home/ec2-user
    cd /home/ec2-user
    mkdir -p /home/ec2-user/bin
    curl -sO https://s3.us-west-2.amazonaws.com/amazon-eks/${var.kubectl_download_version}/bin/linux/amd64/kubectl
    chmod +x kubectl
    mv kubectl /home/ec2-user/bin/kubectl
    export PATH=/home/ec2-user/bin:$PATH
    echo 'export PATH=/home/ec2-user/bin:$PATH' >> ~/.bashrc
    # bash_completion has to be sourced before kubectl's completion, which defines
    # __start_kubectl, and that function has to exist before complete references it
    # (rules.md H-1).
    echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
    echo 'source <(kubectl completion bash)' >> ~/.bashrc
    echo 'alias k=kubectl' >> ~/.bashrc
    echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
    PLATFORM=$(uname -s)_amd64
    curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
    tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
    sudo install -m 0755 /tmp/eksctl /usr/local/bin && rm /tmp/eksctl
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    aws configure set default.region ${data.aws_region.current.region}
    ${join("\n", [for key, s in var.scenarios :
  "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${var.prefix}-${s.cluster_suffix} --alias ${s.cluster_suffix}"
])}
    EOF
  EOT

depends_on = [module.network]
}
# Granting the bastion's role access to every cluster joins modules that know nothing
# about each other, so it belongs in the root (rules.md C-1). for_each over the same
# scenarios means a seventh cluster gets its access entry without a new block.
resource "aws_eks_access_entry" "vscode" {
  for_each = var.scenarios

  cluster_name  = module.eks_cluster[each.key].cluster_name
  principal_arn = module.vscode_ec2.iam_role_arn
  type          = "STANDARD"
}
resource "aws_eks_access_policy_association" "vscode" {
  for_each = var.scenarios

  cluster_name  = module.eks_cluster[each.key].cluster_name
  principal_arn = module.vscode_ec2.iam_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.vscode]
}
locals {
  # Every output this project exposes, defined once. outputs.tf projects these and the
  # README below renders them, so no value expression is written twice
  # (rules.md B-5/H-2).
  #
  # The per-scenario entries are built by iterating var.scenarios, so the README grows a
  # section per cluster automatically - the alternative would be six near-identical
  # entries written out by hand, which is the thing this project's _monolithic version
  # did everywhere.
  scenario_lines = join("\n", [for key, s in var.scenarios :
    "  ${s.condition}: kubectl --context ${s.cluster_suffix} get nodes -o json | jq -r '.items[].status.conditions[] | select(.type==\"${s.condition}\") | \"\\(.type)=\\(.status)\"'"
  ])
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here. Its kubeconfig already has a context per cluster, named after the scenario"
      value       = module.vscode_ec2.vscode_url
    }
    cluster_names = {
      order       = 2
      title       = "Clusters"
      description = "One per condition the Node Monitoring Agent reports. All six share a VPC and a security group, which is what lets one bastion reach them all"
      value       = join(" ", [for key in keys(var.scenarios) : "${var.prefix}-${var.scenarios[key].cluster_suffix}"])
    }
    contexts_command = {
      order       = 3
      title       = "1. The kubeconfig contexts"
      description = "Six contexts, aliased to the scenario names by user data. Everything below selects one with --context"
      value       = "kubectl config get-contexts -o name"
    }
    node_conditions_command = {
      order       = 4
      title       = "2. Read each cluster's node conditions"
      description = "The Node Monitoring Agent adds these conditions to every node. All False on a healthy cluster - reproducing a scenario on a node is what flips one"
      value       = "kubectl --context <scenario> get nodes -o custom-columns='NODE:.metadata.name,READY:.status.conditions[?(@.type==\"Ready\")].status'"
    }
    per_scenario_conditions = {
      order       = 5
      title       = "3. The condition each cluster is for"
      description = "One command per scenario, checking the specific condition that cluster exists to demonstrate"
      value       = local.scenario_lines
    }
    node_repair_command = {
      order       = 6
      title       = "4. Node repair is armed"
      description = "The managed node groups have node_repair_config enabled, which is what turns a reported condition into a replaced node. This shows the setting as EKS has it"
      value       = "aws eks describe-nodegroup --cluster-name <cluster> --nodegroup-name <cluster>-mng --query 'nodegroup.nodeRepairConfig'"
    }
    agent_log_command = {
      order       = 7
      title       = "5. Read the agent's log from CloudWatch"
      description = "The amazon-cloudwatch-observability addon ships the agent's own log to a per-cluster group. This is the detected condition without kubectl - the log group does not exist until the agent has written to it"
      value       = "aws logs tail /aws/eks/<cluster>/node-monitoring-agent --follow"
    }
    agent_pods_command = {
      order       = 8
      title       = "6. The agent is running"
      description = "A DaemonSet, so one pod per node. If a condition never appears, check here before anything else"
      value       = "kubectl --context <scenario> -n kube-system get pods -l app.kubernetes.io/name=eks-node-monitoring-agent -o wide"
    }
    destroy_note = {
      order       = 9
      title       = "Cost"
      description = "Six clusters and eighteen nodes run continuously. This project is the most expensive in the repository by a wide margin, and terraform destroy is what stops the meter"
      value       = "terraform destroy"
    }
  }
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  readme_body = join("\n", concat(
    ["# ${var.prefix} - EKS Node Monitoring Agent", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}
# Every output above is also written to a README in the home directory code-server
# opens, because "terraform output" is not available inside the browser session
# (rules.md H-2). The _monolithic template used six SSM associations to stage six
# per-scenario shell scripts here; this one association writes one document describing
# all six.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on, is what orders this after the instance bootstrap
    # (rules.md D-5). SSM runs as root, hence the chown. The heredoc delimiter is quoted
    # and unlikely to appear in the body - Terraform has already substituted every
    # value, so the shell has no reason to touch a "$" in the README.
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
