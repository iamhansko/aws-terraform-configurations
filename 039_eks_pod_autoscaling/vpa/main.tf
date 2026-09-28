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
  depends_on = [
  module.network, module.eks_node_group]
}
# Not optional here. The VPA recommender reads usage from the metrics API, so without
# this the VerticalPodAutoscaler's status stays empty and nothing is ever recommended
# or applied - the demo simply does not happen. The chart in
# modules/vertical_pod_autoscaler can bring its own metrics-server as a subchart; that
# is turned off, because two installations contend for the same
# v1beta1.metrics.k8s.io APIService.
module "eks_metrics_server_addon" {
  source = "./modules/eks_metrics_server_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Also a Deployment, so it needs node capacity for the same reason as coredns
  # (rules.md C-4).
  depends_on = [
  module.network, module.eks_node_group]
}
# The variant. Three components - recommender, updater, admission controller - plus
# the CRD, installed as a pinned chart rather than by cloning kubernetes/autoscaler
# and running hack/vpa-up.sh on the bastion (rules.md E-1).
module "vertical_pod_autoscaler" {
  source = "./modules/vertical_pod_autoscaler"

  chart_version = var.vpa_chart_version
  namespace     = var.vpa_namespace
  # metrics-server is an EKS addon in this project, so the chart's bundled subchart
  # stays off.
  install_metrics_server = false

  # The release has wait = true, so the apply blocks until its Deployments are
  # Available - which needs node capacity. The admission controller's certificate
  # comes from a pre-install hook Job, which also has to be able to run somewhere.
  depends_on = [
  module.network, module.eks_node_group, module.eks_metrics_server_addon]
}
# The workload the VPA resizes: the upstream hamster example, a container that asks
# for less CPU than it uses.
module "hamster_workload" {
  source = "./modules/hamster_workload"

  name        = var.workload_name
  namespace   = var.workload_namespace
  replicas    = var.workload_replicas
  update_mode = var.vpa_update_mode

  # The VerticalPodAutoscaler is a custom resource, so its CRD - which arrives with
  # the chart above - has to exist before this manifest is accepted. Ordering the
  # module after the release also makes terraform destroy remove the VPA object while
  # the CRD and its webhook are still there, so the delete reaches a live API server
  # (rules.md D-4).
  depends_on = [
  module.network, module.eks_node_group, module.vertical_pod_autoscaler]
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
  # that cluster and carries all five tools (rules.md H-1). git is no longer part of
  # the workflow: the _monolithic template cloned kubernetes/autoscaler here and ran
  # vpa-up.sh from it, and both the components and the example workload are Terraform
  # resources now (rules.md E-1).
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
      description = "API server endpoint. Public here because the helm and kubectl providers install the VPA and the demo workload from wherever terraform runs"
      value       = module.eks_cluster.cluster_endpoint
    }
    vpa_release = {
      order       = 4
      title       = "VPA release"
      description = "The chart and pinned version providing the recommender, updater and admission controller. The _monolithic template got the same software from a git clone and a shell script, with no version recorded anywhere"
      value       = "${module.vertical_pod_autoscaler.release_name} ${module.vertical_pod_autoscaler.chart_version} in ${module.vertical_pod_autoscaler.namespace}"
    }
    vpa_mode = {
      order       = 5
      title       = "What the VPA may do"
      description = "Off records a recommendation only, Initial applies it to new pods, Recreate and Auto also evict running pods to apply it. Vertical scaling replaces pods - it cannot resize one in place - which is why the mode matters more here than a horizontal autoscaler's settings do"
      value       = "updateMode ${module.hamster_workload.update_mode}, within ${module.hamster_workload.allowed_range}"
    }
    workload_initial_requests = {
      order       = 6
      title       = "Where the workload starts"
      description = "The requests in the Deployment, set deliberately below what the container uses. The distance between these and the recommendation is the demo"
      value       = module.hamster_workload.initial_requests
    }
    vpa_components_command = {
      order       = 7
      title       = "1. Confirm all three components are up"
      description = "Auto mode needs all three: the recommender to produce a number, the updater to evict pods that are far from it, and the admission controller to write it onto the replacements. Two out of three silently behaves like a weaker mode"
      value       = module.vertical_pod_autoscaler.components_command
    }
    recommendation_command = {
      order       = 8
      title       = "2. Watch the recommendation appear"
      description = "Empty for the first few minutes - the recommender needs a usage history before it has an opinion. The Target figures are what will be applied"
      value       = module.hamster_workload.recommendation_command
    }
    applied_requests_command = {
      order       = 9
      title       = "3. Watch the requests actually change"
      description = "Where the demo lands. Once the updater has evicted a pod, its replacement comes back with the recommended requests rather than the ones written in the Deployment - so the AGE column moving is the signal, not the replica count"
      value       = module.hamster_workload.applied_requests_command
    }
    eviction_events_command = {
      order       = 10
      title       = "4. See the evictions behind it"
      description = "The mechanism. No events means the recommendation is still close enough to the current requests that the updater is leaving the pods alone, which is correct rather than broken"
      value       = module.hamster_workload.eviction_events_command
    }
    vpa_crd_command = {
      order       = 11
      title       = "5. Confirm the CRD"
      description = "The chart ships this in its crds/ directory, so helm installs it ahead of the templates. hack/vpa-up.sh had to arrange the same ordering by applying files in sequence"
      value       = module.vertical_pod_autoscaler.crd_command
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
