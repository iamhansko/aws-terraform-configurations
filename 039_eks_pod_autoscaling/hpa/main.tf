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
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.eks_cluster.cluster_name

  # coredns is a Deployment and needs schedulable capacity to leave DEGRADED and
  # become ACTIVE (rules.md C-4).
  depends_on = [module.eks_node_group]
}
# Not optional here, unlike in the CoreDNS variants where it only makes "kubectl top"
# work. A CPU-target HPA reads its measurements from the metrics API, so without this
# the HPA's target column shows <unknown> and the replica count never moves - the
# demo simply does not happen.
module "eks_metrics_server_addon" {
  source = "./modules/eks_metrics_server_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Also a Deployment, so it needs node capacity for the same reason as coredns
  # (rules.md C-4).
  depends_on = [module.eks_node_group]
}
# The variant. A Deployment with a CPU request, a Service, and a HorizontalPodAutoscaler
# holding average CPU at a target - the _monolithic template built all three with
# imperative kubectl calls from an SSM Association, so nothing tracked them and a
# second run failed on the existing Deployment (rules.md E-1).
module "php_apache_hpa" {
  source = "./modules/php_apache_hpa"

  name                              = var.workload_name
  namespace                         = var.workload_namespace
  container_port                    = 80
  cpu_request                       = var.workload_cpu_request
  target_cpu_utilization_percentage = var.hpa_target_cpu_utilization_percentage
  min_replicas                      = var.hpa_min_replicas
  max_replicas                      = var.hpa_max_replicas

  # metrics-server has to be answering before the HPA is created, or its first
  # reconciles fail on missing metrics. Ordering the module after the node group also
  # makes terraform destroy remove these manifests while the nodes are still there,
  # so the deletes reach a live API server (rules.md D-4).
  depends_on = [module.eks_node_group, module.eks_metrics_server_addon]
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
  # that cluster and carries all five tools (rules.md H-1), plus eks-node-viewer,
  # which the _monolithic template also installed here. All six are for watching and
  # driving the demo: the Deployment, Service and HPA are Terraform resources, so
  # nothing on this instance creates cluster resources (rules.md E-1/H-1).
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
    # eks-node-viewer: nodes, the pods on them and their cost, in one screen. The
    # version is pinned rather than tracking latest, so a demo that worked keeps
    # working.
    curl -sL -o eks-node-viewer https://github.com/awslabs/eks-node-viewer/releases/download/${var.eks_node_viewer_version}/eks-node-viewer_Linux_x86_64
    chmod +x eks-node-viewer
    sudo mv eks-node-viewer /usr/local/bin/eks-node-viewer
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
      description = "Open the IDE here. The commands below are meant to be run from its terminal"
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
      description = "API server endpoint. Public here because the kubectl provider applies the Deployment, Service and HPA from wherever terraform runs"
      value       = module.eks_cluster.cluster_endpoint
    }
    hpa_target = {
      order       = 4
      title       = "What the HPA holds"
      description = "Average CPU utilisation, measured against the container's CPU request - so the absolute number to beat is the second figure. Utilisation is a ratio, not a raw core count, which is why a container with no request breaks this entirely"
      value       = "${module.php_apache_hpa.target_cpu_utilization_percentage}% of ${module.php_apache_hpa.cpu_request} per pod"
    }
    hpa_replica_range = {
      order       = 5
      title       = "Replica range"
      description = "The range the HPA may move the Deployment within. The ceiling is deliberately past what this node group holds, so the last few replicas stay Pending"
      value       = module.php_apache_hpa.replica_range
    }
    node_group_range = {
      order       = 6
      title       = "Node group size range"
      description = "Nothing scales the node group here, so this is fixed unless resized by hand. Pods Pending at the top of the HPA's range is the expected end state, and where node autoscaling would take over"
      value       = "${var.node_group_min_size}-${var.node_group_max_size}"
    }
    hpa_watch_command = {
      order       = 7
      title       = "1. Watch the HPA"
      description = "Leave this running. TARGETS shows observed utilisation against the target; <unknown> there means metrics-server is not answering rather than that load is low"
      value       = module.php_apache_hpa.hpa_watch_command
    }
    node_viewer_command = {
      order       = 8
      title       = "2. Watch the nodes fill up"
      description = "eks-node-viewer, installed on this instance by user data. A second terminal for this one: it shows pods landing on nodes as the HPA adds replicas, and then stopping when there is nowhere left to put them"
      value       = "eks-node-viewer --resources cpu,memory"
    }
    load_generator_command = {
      order       = 9
      title       = "3. Generate load"
      description = "Creates a pod that requests the Service in a tight loop. Utilisation should cross the target within a minute, and the HPA then starts adding replicas - a few at a time, not all at once"
      value       = module.php_apache_hpa.load_generator_command
    }
    pods_command = {
      order       = 10
      title       = "4. See where the replicas went"
      description = "Pods and the nodes they landed on. Once the nodes are full the remaining replicas sit Pending, which is the honest limit of scaling pods alone"
      value       = module.php_apache_hpa.pods_command
    }
    load_generator_cleanup_command = {
      order       = 11
      title       = "5. Stop the load"
      description = "The HPA scales back down afterwards, but not straight away: it holds the higher count through a stabilisation window of about five minutes, so a slow scale-down is correct behaviour rather than a stuck autoscaler"
      value       = module.php_apache_hpa.load_generator_cleanup_command
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
