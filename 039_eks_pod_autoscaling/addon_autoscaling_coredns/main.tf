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
# The variant. CoreDNS scales its own replica count because the addon does it, set
# through configuration_values rather than by installing anything into the cluster
# (rules.md E-5). Compare cpa_coredns, which reaches the same outcome with a
# cluster-proportional-autoscaler Helm release and therefore needs a helm provider, a
# chart version to track and a release to keep healthy.
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name             = module.eks_cluster.cluster_name
  autoscaling_enabled      = var.coredns_autoscaling_enabled
  autoscaling_min_replicas = var.coredns_autoscaling_min_replicas
  autoscaling_max_replicas = var.coredns_autoscaling_max_replicas

  # coredns is a Deployment and needs schedulable capacity to leave DEGRADED and
  # become ACTIVE (rules.md C-4). That applies to the autoscaled form too: the addon's
  # own autoscaler cannot satisfy its minimum without somewhere to put the pods.
  depends_on = [
  module.network, module.eks_node_group]
}
# metrics-server is not what drives CoreDNS autoscaling here - the addon scales on
# cluster size, not on measured load - but it is what makes "kubectl top" work, and
# the demo is more legible when the CoreDNS pods' resource use is visible while the
# node count changes.
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
  # that cluster and carries all five tools (rules.md H-1). Nothing here creates
  # cluster resources - this variant has none to create.
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
      description = "API server endpoint. Nothing in this variant needs it to be public - there is no kubectl or helm provider - so it is safe to set endpoint_public_access false here, unlike in the sibling variants"
      value       = module.eks_cluster.cluster_endpoint
    }
    coredns_autoscaling = {
      order       = 4
      title       = "CoreDNS autoscaling"
      description = "The replica range the coredns addon manages itself. Configured through the addon rather than by installing an autoscaler into the cluster, which is what separates this variant from cpa_coredns"
      value       = coalesce(module.eks_coredns_addon.autoscaling_range, "disabled")
    }
    node_group_range = {
      order       = 5
      title       = "Node group size range"
      description = "The addon scales CoreDNS with the number of nodes, so the demo is to move the node count inside this range and watch the CoreDNS Deployment follow"
      value       = "${var.node_group_min_size}-${var.node_group_max_size}"
    }
    coredns_replicas_command = {
      order       = 6
      title       = "1. Watch the CoreDNS replica count"
      description = "Leave this running. It is the thing the demo changes - no autoscaler pod is involved, the addon adjusts the Deployment directly"
      value       = "kubectl -n kube-system get deployment coredns -w"
    }
    scale_nodes_command = {
      order       = 7
      title       = "2. Scale the node group"
      description = "Raise the desired count and the addon should add CoreDNS replicas within a minute or two, up to the ceiling above. Scale back down and it removes them again"
      value       = "aws eks update-nodegroup-config --cluster-name ${module.eks_cluster.cluster_name} --nodegroup-name ${module.eks_node_group.node_group_name} --scaling-config minSize=${var.node_group_min_size},maxSize=${var.node_group_max_size},desiredSize=6"
    }
    no_autoscaler_pod_command = {
      order       = 8
      title       = "3. Confirm there is no autoscaler pod"
      description = "Empty output is the point. cpa_coredns runs a cluster-proportional-autoscaler Deployment to do this job; here the addon does it and there is nothing extra in the cluster to keep healthy"
      value       = "kubectl -n kube-system get deploy | grep -i -E 'proportional|autoscaler' || echo 'none - the addon handles it'"
    }
    addon_status_command = {
      order       = 9
      title       = "4. Read the addon's own view"
      description = "Shows the configuration_values EKS is holding for coredns. If autoScaling is missing here, the addon version predates native autoscaling support and the setting was silently dropped"
      value       = "aws eks describe-addon --cluster-name ${module.eks_cluster.cluster_name} --addon-name coredns --query 'addon.{status:status,version:addonVersion,config:configurationValues}'"
    }
    top_pods_command = {
      order       = 10
      title       = "5. Check CoreDNS resource use"
      description = "Needs metrics-server, which is installed as an addon here. Useful for seeing whether the replica count the addon chose is actually warranted"
      value       = "kubectl -n kube-system top pods -l k8s-app=kube-dns"
    }
    update_kubeconfig_command = {
      order       = 11
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
