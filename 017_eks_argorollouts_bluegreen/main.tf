data "aws_region" "current" {}
# Resolves CloudFront's origin-facing address ranges for this region at plan
# time. Replaces the _monolithic template's AWSRegions2PrefixListId mapping,
# a hand-maintained region-to-prefix-list table that silently had no entry for
# newer regions.
data "aws_ec2_managed_prefix_list" "cloudfront_origin_facing" {
  count = var.enable_cloudfront ? 1 : 0
  name  = var.cloudfront_origin_facing_prefix_list_name
}
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
  # The discovery tag is what the EC2NodeClass subnet selector matches on, so
  # Karpenter only ever launches nodes into this cluster's private subnets. The
  # kubernetes.io/role tags are kept so the AWS Load Balancer Controller can
  # still auto-discover subnets.
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    (var.karpenter_discovery_tag_key) = var.cluster_name
  }
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name = var.key_name

  # key_pair consumes no network output, so nothing would otherwise order it
  # against the network module's resources. Every module in a root that has a
  # network module waits for all of it (rules.md D-3).
  depends_on = [module.network]
}
module "eks_cluster" {
  source = "./modules/eks_cluster"

  name                   = var.cluster_name
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  # Referencing module.network.*_subnet_ids only orders this module after the
  # specific aws_subnet resources behind those outputs, not after the NAT
  # gateways and route table associations that never surface as outputs
  # (rules.md D-3).
  depends_on = [module.network]
}
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not
  # exist until this addon creates it. As a DaemonSet it reaches ACTIVE with
  # zero nodes, so it is created before any node capacity - worker nodes need it
  # running to join the cluster Ready (rules.md C-4).
  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as eks_vpc_cni_addon: kube-proxy is a DaemonSet and must
  # exist before any node capacity (rules.md C-4).
  depends_on = [module.network, module.eks_cluster]
}
module "eks_pod_identity_agent_addon" {
  source = "./modules/eks_pod_identity_agent_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Also a DaemonSet, so it becomes ACTIVE with zero nodes (rules.md C-4).
  depends_on = [module.network, module.eks_cluster]
}
# Karpenter cannot provision the nodes its own controller runs on, so a small
# managed node group is a prerequisite for it, not a duplicate of it. Everything
# beyond this baseline is left to Karpenter.
module "eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name    = module.eks_cluster.cluster_name
  node_group_name = var.node_group_name
  instance_types  = var.node_group_instance_types
  desired_size    = var.node_group_desired_size
  min_size        = var.node_group_min_size
  max_size        = var.node_group_max_size
  subnet_ids      = module.network.private_subnet_ids
  key_name        = module.key_pair.key_name

  # Nodes need vpc-cni and kube-proxy running to join the cluster Ready
  # (rules.md C-4).
  depends_on = [module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.eks_cluster.cluster_name

  # coredns is a Deployment and needs schedulable node capacity to leave its
  # DEGRADED state and become ACTIVE, so it is created after the node group
  # rather than before it (rules.md C-4).
  depends_on = [
  module.network, module.eks_node_group]
}
module "eks_metrics_server_addon" {
  source = "./modules/eks_metrics_server_addon"

  cluster_name = module.eks_cluster.cluster_name

  # metrics-server is a Deployment, so like coredns it needs schedulable node
  # capacity to become ACTIVE rather than DEGRADED (rules.md C-4).
  depends_on = [
  module.network, module.eks_node_group]
}
module "karpenter" {
  source = "./modules/karpenter"

  cluster_name      = module.eks_cluster.cluster_name
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  chart_version     = var.karpenter_chart_version
  capacity_types    = var.karpenter_capacity_types
  # Selector tags are injected rather than discovered, so the module never has
  # to know which network module tagged the subnets or that EKS owns the
  # security group (rules.md B-6).
  subnet_selector_tags = {
    (var.karpenter_discovery_tag_key) = var.cluster_name
  }
  # EKS tags the cluster security group it creates with aws:eks:cluster-name,
  # so selecting on it attaches Karpenter's nodes to the same group the managed
  # node group's nodes use.
  security_group_selector_tags = {
    "aws:eks:cluster-name" = module.eks_cluster.cluster_name
  }
  instance_categories = var.karpenter_instance_categories
  instance_types      = var.karpenter_instance_types
  cpu_limit           = var.karpenter_cpu_limit
  # Every node from this pool carries these labels, and the stress demo below
  # selects on them, which is what keeps its pods off the managed node group.
  node_labels = var.karpenter_node_labels
  node_tags = {
    Name = "${var.prefix}-karpenter-node"
  }

  # The controller pod needs schedulable capacity on the managed node group and
  # working cluster DNS before it can reach the EKS API, and wait = true on its
  # Helm release would otherwise time out. Ordering the module after coredns
  # also makes terraform destroy remove the NodePool - letting Karpenter drain
  # its nodes - while the controller is still running (rules.md D-2/D-4).
  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}
# The workload that makes Karpenter do something. Created at zero replicas, so
# it provisions nothing until someone scales it up.
# The AWS Load Balancer Controller. Installed with helm_release and its own IRSA
# role in one module (rules.md C-2), rather than by the 00_install_lbc.sh script the
# _monolithic template cloned from a GitHub repository and ran over SSM. It is what
# reconciles the TargetGroupBinding the workload declares, which is what actually
# puts pod IPs into the target group Terraform created.
module "aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"

  cluster_name      = module.eks_cluster.cluster_name
  vpc_id            = module.network.vpc_id
  aws_region        = data.aws_region.current.region
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  chart_version     = var.load_balancer_controller_chart_version
  # False, as in every project in this repository. No workload here sets the
  # manage-backend-security-group-rules annotation, so nothing asks the controller to
  # write rules onto the cluster security group and the shared k8s-traffic group it
  # would need as a source is never required (rules.md G-2). The load balancer this
  # project creates carries the cluster security group instead, which already reaches
  # pod IPs.
  enable_backend_security_group = var.enable_backend_security_group
  # Off, because no Service in this project is of type LoadBalancer - the workload's
  # active and preview Services are both ClusterIP. Left on, the webhook it installs
  # gates every Service creation in the cluster behind a controller pod being Ready,
  # and module.karpenter and module.argo_rollouts share no ordering with this module,
  # so their Services can land in exactly that window (rules.md G-4).
  enable_service_mutator_webhook = var.enable_service_mutator_webhook

  # The controller is a Deployment with wait = true, so it needs schedulable capacity
  # and working cluster DNS before the release can report ready (rules.md D-2).
  depends_on = [module.network, module.eks_coredns_addon]
}
# Argo Rollouts, from helm_release rather than the 00_install_argorollouts.sh script
# the _monolithic template cloned and ran (rules.md E-1).
module "argo_rollouts" {
  source = "./modules/argo_rollouts"

  chart_version = var.argo_rollouts_chart_version
  namespace     = var.argo_rollouts_namespace

  depends_on = [module.network, module.eks_coredns_addon]
}
# The load balancer the Rollout switches traffic on. Terraform owns the shell -
# load balancer, target group, listener - because a blue/green Rollout names an
# existing target group ARN rather than provisioning one. What it does not own is
# the target group's membership or the listener's forward action: Argo Rollouts
# changes both during a promotion, so the module leaves them alone.
module "blue_green_alb" {
  source = "./modules/blue_green_alb"

  name              = var.alb_name
  target_group_name = var.alb_target_group_name
  vpc_id            = module.network.vpc_id
  # Private subnets, as the _monolithic template had it. That is why the demo is
  # reached from the bastion rather than from a browser.
  subnet_ids = module.network.private_subnet_ids
  # The EKS cluster security group, which already permits the traffic between the
  # load balancer and the pod ENIs. The module receives IDs and never learns whose
  # they are (rules.md B-6).
  security_group_ids = [module.eks_cluster.cluster_security_group_id]

  depends_on = [module.network]
}
# The Rollout, its two Services, and the TargetGroupBinding that attaches the active
# Service to the target group above. The target group ARN is interpolated from the
# module output - the _monolithic template sed-substituted it into a YAML file on the
# bastion's disk, so nothing connected the manifest to the load balancer afterwards
# (rules.md B-5).
module "bluegreen_workload" {
  source = "./modules/bluegreen_workload"

  namespace               = var.bluegreen_namespace
  rollout_name            = var.bluegreen_rollout_name
  image                   = var.bluegreen_image
  replica_count           = var.bluegreen_replica_count
  active_target_group_arn = module.blue_green_alb.target_group_arn

  # These are kubectl_manifest resources talking straight to the API server. The
  # Rollout needs the Argo Rollouts CRD, which its chart installs, and the
  # TargetGroupBinding needs the AWS Load Balancer Controller's CRD and a running
  # controller to reconcile it. Ordering the module after both, and after the node
  # group, also makes terraform destroy remove these objects while the controllers
  # that clean up after them are still alive (rules.md D-4).
  depends_on = [
    module.network,
    module.eks_node_group,
    module.argo_rollouts,
    module.aws_load_balancer_controller,
  ]
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  vpc_id        = module.network.vpc_id
  subnet_id     = module.network.public_subnet_a_id
  key_name      = module.key_pair.key_name
  instance_type = var.vscode_instance_type
  # With CloudFront in front, only CloudFront's origin-facing ranges may reach
  # code-server, so the editor is never directly exposed to the internet.
  ingress_prefix_list_ids     = var.enable_cloudfront ? [data.aws_ec2_managed_prefix_list.cloudfront_origin_facing[0].id] : []
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  # Lets the README association below know when the bootstrap has finished
  # (rules.md H-2). The module touches <path>/userdata as its last step.
  marker_file_path = var.marker_file_path
  # Joining the cluster security group is what lets this instance reach the
  # private API server endpoint (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]
  # An EKS cluster and this instance live in the same root module, so the
  # instance is the workbench for that cluster and carries all five tools:
  # code-server (the module itself), plus kubectl, eksctl, helm and docker
  # (rules.md H-1). None of them is behind a flag, and none of them is used to
  # create resources - that stays with the helm and kubectl providers.
  #
  # Plus the kubectl-argo-rollouts plugin, which is this project's own tool
  # rather than one of the five. It belongs in that same list for the same
  # reason: six of the README steps written onto this instance are
  # "kubectl argo rollouts ..." commands, and kubectl answers
  # 'unknown command "argo" for "kubectl"' until the plugin binary exists. The
  # steps were written and the install was not, so the demo had no runnable
  # steps at all.
  additional_user_data = <<-EOT
    dnf install -yq python3.13
    ln -sf /usr/bin/python3.13 /usr/bin/python
    python -m ensurepip --upgrade
    # Building container images needs a real daemon on the host, so unlike the
    # kubectl/helm steps this cannot become a provider resource (rules.md E-1).
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server is already running from the module's bootstrap, so its process
    # predates the docker group and its integrated terminals inherit the groups
    # that process started with. Restarting picks the group up, which is what
    # makes docker usable from the IDE without loosening the socket's
    # permissions (rules.md H-1).
    systemctl restart code-server
    su - ec2-user << 'EOF'
    export HOME=/home/ec2-user
    cd $HOME
    curl -sO https://s3.us-west-2.amazonaws.com/amazon-eks/${var.kubectl_download_version}/bin/linux/amd64/kubectl
    chmod +x ./kubectl
    mkdir -p $HOME/bin && mv ./kubectl $HOME/bin/kubectl && export PATH=$HOME/bin:$PATH
    echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc
    echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
    echo 'source <(kubectl completion bash)' >> ~/.bashrc
    echo 'alias k=kubectl' >> ~/.bashrc
    echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
    ARCH=amd64
    PLATFORM=$(uname -s)_$ARCH
    curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
    tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
    sudo install -m 0755 /tmp/eksctl /usr/local/bin && rm /tmp/eksctl
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    # The Argo Rollouts kubectl plugin. Named kubectl-argo-rollouts because that
    # is how kubectl resolves "kubectl argo rollouts": an unknown subcommand
    # sends it looking for an executable called kubectl-<subcommand> on PATH, so
    # the filename is the interface and renaming it breaks the commands.
    #
    # Installed into $HOME/bin next to the kubectl it extends - that directory is
    # already on PATH and exported in .bashrc above, and a plugin is only useful
    # to whoever runs that kubectl, so unlike eksctl it needs no sudo.
    #
    # -f so a wrong version tag fails here rather than leaving a 404 body saved
    # as an executable, which would report "unknown command" just like having no
    # plugin at all.
    curl -fsSL -o $HOME/bin/kubectl-argo-rollouts https://github.com/argoproj/argo-rollouts/releases/download/${var.argo_rollouts_plugin_version}/kubectl-argo-rollouts-linux-amd64
    chmod +x $HOME/bin/kubectl-argo-rollouts
    aws configure set default.region ${data.aws_region.current.region}
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}
    EOF
  EOT

  depends_on = [module.network]
}
module "vscode_cloudfront" {
  count  = var.enable_cloudfront ? 1 : 0
  source = "./modules/vscode_cloudfront"

  origin_domain_name = module.vscode_ec2.public_dns
  # Taken from the instance module rather than restating 8000, so the origin
  # port cannot drift from what code-server binds to (rules.md B-5).
  origin_http_port = module.vscode_ec2.code_server_port
  # The stem of a generated name, not the name. Passing an exact name here is what broke this apply:
  # 007_eks_karpenter and 016_eks_argocd_github_action build the same "${var.prefix}-vscode-code-server"
  # string with the same default prefix, cache policy names are unique per account, and the second project
  # applied into the account fails on CachePolicyAlreadyExists - partway through, with the VPC, the cluster
  # and the instance already built. Nothing reads the policy by name, so there was nothing to lose by
  # generating it (rules.md G-3).
  cache_policy_name_prefix = "${var.prefix}-vscode-code-server"
  comment                  = "code-server on ${var.prefix} bastion"

  depends_on = [module.network]
}
# Granting the instance role cluster access joins two modules that know nothing
# about each other, so it belongs in the root rather than inside either one
# (rules.md C-1).
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
  # Every output this project exposes, defined once. outputs.tf projects these
  # and the README below renders them, so no value is written twice (rules.md
  # #5/#35). Adding an entry here is what makes an output possible, which is
  # what keeps the README from silently falling behind outputs.tf.
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server (CloudFront)"
      description = "Open the IDE here. Every command below is meant to be run from its terminal - the load balancer is internal, so it is only reachable from inside the VPC. Falls back to the instance address when enable_cloudfront is false"
      value       = var.enable_cloudfront ? module.vscode_cloudfront[0].url : module.vscode_ec2.vscode_url
    }
    cluster_name = {
      order       = 2
      title       = "EKS cluster name"
      description = "Name of the EKS cluster"
      value       = module.eks_cluster.cluster_name
    }
    alb_url = {
      order       = 3
      title       = "Load balancer URL"
      description = "Internal, so curl it from the bastion. Known from Terraform state because Terraform created the load balancer rather than a controller - the point of owning the shell (contrast rules.md G-1)"
      value       = module.blue_green_alb.url
    }
    target_group_arn = {
      order       = 4
      title       = "Active target group"
      description = "The ARN the Rollout's TargetGroupBinding names. The _monolithic template sed-substituted this into a YAML file; here it is interpolated into the manifest"
      value       = module.blue_green_alb.target_group_arn
    }
    argo_rollouts_status_command = {
      order       = 5
      title       = "1. The controller is up"
      description = "Nothing reconciles a Rollout until this reports Available"
      value       = module.argo_rollouts.controller_status_command
    }
    rollout_watch_command = {
      order       = 6
      title       = "2. Watch the rollout"
      description = "Leave this running in one terminal. It shows the active and preview ReplicaSets and which one the Services point at"
      value       = module.bluegreen_workload.watch_command
    }
    target_health_command = {
      order       = 7
      title       = "3. Confirm pods are behind the load balancer"
      description = "Pod IPs registered by the TargetGroupBinding. Empty means the AWS Load Balancer Controller has not reconciled it - check its logs before anything else"
      value       = module.blue_green_alb.target_health_command
    }
    new_version_command = {
      order       = 8
      title       = "4. Start a rollout"
      description = "Changes the image, which brings up a second version behind the preview Service. The active Service keeps serving the load balancer - nothing in production traffic moves yet"
      value       = module.bluegreen_workload.new_version_command
    }
    preview_check_command = {
      order       = 9
      title       = "5. Check the new version before promoting"
      description = "Reaches the preview Service directly. This is what blue/green buys: the new version is verifiable while the old one still takes traffic"
      value       = module.bluegreen_workload.preview_check_command
    }
    promote_command = {
      order       = 10
      title       = "6. Promote"
      description = "Swaps the Services. Watch the target group membership change in step 3 as the load balancer moves to the new pods"
      value       = module.bluegreen_workload.promote_command
    }
    argo_rollouts_dashboard_command = {
      order       = 11
      title       = "Dashboard (optional)"
      description = "Serves the Argo Rollouts UI on localhost:3100 on the bastion, which shows the same promotion graphically. Another plugin command, so it depends on the same binary as steps 2, 4 and 6"
      value       = module.argo_rollouts.dashboard_command
    }
    rollouts_versions = {
      order       = 12
      title       = "Plugin and controller versions"
      description = "Every numbered step above except 1 and 3 is a 'kubectl argo rollouts' command, which is a separate binary named kubectl-argo-rollouts that user data put in ~/bin - kubectl resolves an unknown subcommand by looking for kubectl-<subcommand> on PATH. If those commands report 'unknown command \"argo\"', the plugin is missing rather than the cluster being wrong, and the first line below is what to check. The two versions are pinned independently because the plugin is installed before the chart exists, so they are printed together: they should be the same minor version, since both sides read and write the same Rollout CRD"
      value = join("\n", [
        "plugin     : ${var.argo_rollouts_plugin_version}   (kubectl argo rollouts version)",
        "controller : ${module.argo_rollouts.controller_version}   (appVersion of chart ${module.argo_rollouts.chart_version})",
      ])
    }
    update_kubeconfig_command = {
      order       = 13
      title       = "Re-point kubectl"
      description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
  }
  # Iterating local.outputs directly would order sections by key, which puts
  # "2. Watch nodes arrive" above "1. Scale the demo up". Re-keying by the order
  # field and taking values() sorts by that instead - values() returns a map's
  # values ordered by key - so the README reads in the order the demo is run,
  # and the order is still fully determined by the configuration rather than
  # shuffling between applies.
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  # Rendered from the same map, so an added output shows up here without anyone
  # remembering to edit two places (rules.md H-2).
  readme_body = join("\n", concat(
    ["# ${var.cluster_name}", ""],
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
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is what
    # orders this after the instance bootstrap, and the marker this command
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
