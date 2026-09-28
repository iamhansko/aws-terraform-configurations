data "aws_region" "current" {}
module "network" {
  source = "./modules/network"
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name = var.key_name

  # key_pair consumes no network output, so nothing would otherwise order it
  # against the network module's resources (rules.md D-3).
  depends_on = [module.network]
}
module "eks_cluster" {
  source = "./modules/eks_cluster"

  name                   = var.cluster_name
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  # Referencing module.network.*_subnet_ids only orders this after the specific
  # aws_subnet resources behind those outputs, not after the NAT gateways and route
  # table associations that never surface as outputs (rules.md D-3).
  depends_on = [module.network]
}
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not exist
  # until this addon creates it. As a DaemonSet it reaches ACTIVE with zero nodes, so
  # it comes before any capacity (rules.md C-4) - and nodes need it to join Ready.
  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as eks_vpc_cni_addon (rules.md C-4).
  depends_on = [module.network, module.eks_cluster]
}
module "eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name   = module.eks_cluster.cluster_name
  instance_types = var.node_group_instance_types
  desired_size   = var.node_group_desired_size
  min_size       = var.node_group_min_size
  max_size       = var.node_group_max_size
  subnet_ids     = module.network.private_subnet_ids

  depends_on = [module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}
# No replica count is sent, so the addon keeps its own default and nothing in
# Terraform holds an opinion about how many CoreDNS pods there should be. That is
# deliberate: the autoscaler below owns this Deployment's replica count, and a
# replicaCount pinned in the addon's configuration_values would be a second opinion
# about the same number, reasserted by EKS on every addon update.
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.eks_cluster.cluster_name

  # coredns is a Deployment and needs schedulable capacity to leave DEGRADED and
  # become ACTIVE (rules.md C-4).
  depends_on = [
  module.network, module.eks_node_group]
}
# The variant. CoreDNS scales with the node count because a
# cluster-proportional-autoscaler release watches the nodes and resizes the
# Deployment. Compare addon_autoscaling_coredns, which gets the same outcome from the
# coredns addon's own autoScaling configuration and therefore needs no helm provider,
# no chart version to track and no extra Deployment to keep healthy (rules.md E-5).
module "cluster_proportional_autoscaler" {
  source = "./modules/cluster_proportional_autoscaler"

  chart_version     = var.cpa_chart_version
  target            = "deployment/coredns"
  nodes_per_replica = var.cpa_nodes_per_replica
  min_replicas      = var.cpa_min_replicas
  max_replicas      = var.cpa_max_replicas

  # The release has wait = true, so the apply blocks until its Deployment is
  # Available - which needs node capacity. It also has to come after the coredns
  # addon, because the first thing it does is resize deployment/coredns, and that
  # Deployment is created by the addon.
  depends_on = [
  module.network, module.eks_node_group, module.eks_coredns_addon]
}
# Not what drives CoreDNS scaling here - the autoscaler counts nodes, it does not
# measure load - but it is what makes "kubectl top" work, and the demo is more
# legible when the CoreDNS pods' resource use is visible while the node count
# changes.
module "eks_metrics_server_addon" {
  source = "./modules/eks_metrics_server_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Also a Deployment, so it needs node capacity for the same reason as coredns
  # (rules.md C-4).
  depends_on = [
  module.network, module.eks_node_group]
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  marker_file_path            = var.marker_file_path
  # Joining the cluster security group is what lets this instance reach the API
  # server. The module is handed an ID list and never learns it belongs to an EKS
  # cluster (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]

  # An EKS cluster and this instance share a root module, so it is the workbench for
  # that cluster and carries all five tools (rules.md H-1). helm is here to inspect
  # the release - "helm list", "helm history" - not to create it: the autoscaler is a
  # helm_release above, so nothing on this instance installs anything (rules.md E-1).
  additional_user_data = <<-EOT
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server is already running and predates the docker group, so its terminals
    # would not have it without a restart.
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
    # Order matters: kubectl's completion defines __start_kubectl, and that has to
    # exist before complete names it, or every login prints "function not found"
    # (rules.md H-1).
    echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
    echo 'source <(kubectl completion bash)' >> ~/.bashrc
    echo 'alias k=kubectl' >> ~/.bashrc
    echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
    # eksctl-io is the project's own org; the weaveworks URL the _monolithic template
    # used still redirects, but the current name is what gets used (rules.md H-1).
    PLATFORM=$(uname -s)_amd64
    curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
    tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
    sudo install -m 0755 /tmp/eksctl /usr/local/bin && rm /tmp/eksctl
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    aws configure set default.region ${data.aws_region.current.region}
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}
    EOF
  EOT

  depends_on = [module.network]
}
# Granting the bastion's instance role cluster access joins two modules that know
# nothing about each other, so it belongs in the root (rules.md C-1).
resource "aws_eks_access_entry" "vscode_access_entry" {
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.vscode_ec2.iam_role_arn
  type          = "STANDARD"
}
resource "aws_eks_access_policy_association" "vscode_access_policy_association" {
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.vscode_ec2.iam_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.vscode_access_entry]
}
locals {
  # Every output this project exposes, defined once. outputs.tf projects these and
  # the README below renders them, so no value expression is written twice
  # (rules.md B-5/H-2). Adding an entry here is what makes an output possible, which
  # is what keeps the README from falling behind outputs.tf.
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here. The kubectl commands below are meant to be run from its terminal"
      value       = module.vscode_ec2.vscode_url
    }
    cluster_name = {
      order       = 2
      title       = "EKS cluster name"
      description = "Name of the EKS cluster"
      value       = module.eks_cluster.cluster_name
    }
    cluster_endpoint = {
      order       = 3
      title       = "EKS cluster endpoint"
      description = "API server endpoint. Public here because the helm provider installs the autoscaler from wherever terraform runs"
      value       = module.eks_cluster.cluster_endpoint
    }
    autoscaler_release = {
      order       = 4
      title       = "Autoscaler release"
      description = "The chart that does the scaling, and its pinned version. This is what separates this variant from addon_autoscaling_coredns, where no release exists at all"
      value       = "${module.cluster_proportional_autoscaler.release_name} ${module.cluster_proportional_autoscaler.chart_version} in ${module.cluster_proportional_autoscaler.namespace}, scaling ${module.cluster_proportional_autoscaler.target}"
    }
    autoscaler_ladder = {
      order       = 5
      title       = "Scaling ladder"
      description = "One CoreDNS replica per this many nodes, clamped to the replica range. replicas = ceil(nodes / nodesPerReplica), so the replica count steps rather than tracking the node count smoothly"
      value       = "${module.cluster_proportional_autoscaler.nodes_per_replica} nodes per replica, ${module.cluster_proportional_autoscaler.replica_range} replicas"
    }
    node_group_range = {
      order       = 6
      title       = "Node group size range"
      description = "The room the demo has to move the node count in. Nothing scales the node group automatically, so crossing a rung of the ladder is a deliberate step"
      value       = "${var.node_group_min_size}-${var.node_group_max_size}"
    }
    coredns_replicas_command = {
      order       = 7
      title       = "1. Watch the CoreDNS replica count"
      description = "Leave this running. It is the thing the demo changes, and here an autoscaler pod is what changes it"
      value       = "kubectl -n kube-system get deployment coredns -w"
    }
    scale_nodes_command = {
      order       = 8
      title       = "2. Scale the node group"
      description = "Raise the desired count past a rung of the ladder - with the defaults, 4 nodes asks for 2 replicas and 6 asks for 3 - and the autoscaler should resize CoreDNS within a minute. Scale back down and it removes them again"
      value       = "aws eks update-nodegroup-config --cluster-name ${module.eks_cluster.cluster_name} --nodegroup-name ${module.eks_node_group.node_group_name} --scaling-config minSize=${var.node_group_min_size},maxSize=${var.node_group_max_size},desiredSize=6"
    }
    autoscaler_logs_command = {
      order       = 9
      title       = "3. Watch the autoscaler decide"
      description = "The replica count it computed and why. Unlike addon_autoscaling_coredns there is a pod here to ask, which is the upside of this approach - and the thing that can break, which is the downside"
      value       = "kubectl -n ${module.cluster_proportional_autoscaler.namespace} logs deploy/${module.cluster_proportional_autoscaler.release_name} -f"
    }
    autoscaler_configmap_command = {
      order       = 10
      title       = "4. Read the ladder the autoscaler is using"
      description = "The chart writes the ladder into a ConfigMap and the autoscaler unmarshals it as JSON. The booleans have to appear unquoted: a quoted \"true\" is valid JSON that the autoscaler cannot parse, which is why those two chart values are not forced to strings (rules.md E-7)"
      value       = module.cluster_proportional_autoscaler.configmap_command
    }
    top_pods_command = {
      order       = 11
      title       = "5. Check CoreDNS resource use"
      description = "Needs metrics-server, which is installed as an addon here. Useful for seeing whether the replica count the ladder produced is actually warranted - the autoscaler itself never looks at this"
      value       = "kubectl -n kube-system top pods -l k8s-app=kube-dns"
    }
    update_kubeconfig_command = {
      order       = 12
      title       = "Re-point kubectl"
      description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the
  # order field and taking values() - which returns a map's values ordered by key -
  # makes the README read top to bottom while the order stays decided by
  # configuration.
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
# The work happens inside code-server in a browser, where terraform output is not
# available, so every output above is also written to a README in the home directory
# the IDE opens (rules.md H-2). Combining several modules' outputs is the root's job,
# so this lives here rather than inside the instance module.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is what
    # orders this after the bootstrap (rules.md D-5). The marker path comes back out
    # of the module it was passed into, so it is defined once (rules.md B-5).
    #
    # SSM runs as root, hence the chown. The heredoc delimiter is quoted and unlikely
    # to appear in the body: Terraform has already substituted every value, so the
    # shell has no reason to touch a "$" or a backtick.
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
