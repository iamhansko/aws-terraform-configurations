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
  # The discovery tag the EC2NodeClass subnet selector matches on, so Karpenter only ever
  # launches into this cluster's private subnets. The _monolithic template listed the two
  # subnet IDs literally inside the YAML it echoed into a file on the bastion, which meant
  # the pool could not follow a change to the network without editing that string.
  private_subnet_tags = {
    (var.karpenter_discovery_tag_key) = var.cluster_name
  }
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name = var.key_name

  # key_pair consumes no network output, so nothing would otherwise order it against the
  # network module's resources. Every module in a root that has a network module waits for
  # all of it (rules.md D-3).
  depends_on = [module.network]
}
module "eks_cluster" {
  source = "./modules/eks_cluster"

  name                   = var.cluster_name
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  # Referencing module.network.*_subnet_ids only orders this after the specific aws_subnet
  # resources behind those outputs, not after the NAT gateways and route table
  # associations that never surface as outputs (rules.md D-3).
  depends_on = [module.network]
}
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not exist until
  # this addon creates it. As a DaemonSet it reaches ACTIVE with zero nodes, so it comes
  # before any capacity - and nodes need it to join Ready (rules.md C-4). That matters more
  # here than usual: the spot node is meant to be taken away and replaced, and each
  # replacement has to join the same way.
  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as eks_vpc_cni_addon (rules.md C-4).
  depends_on = [module.network, module.eks_cluster]
}
# Karpenter cannot provision the nodes its own controller runs on, so this group is a
# prerequisite for it rather than a duplicate. It is also the capacity the Node Termination
# Handler covers that Karpenter does not, which is the reason both mechanisms are here.
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

  # Nodes need vpc-cni and kube-proxy running to join the cluster Ready (rules.md C-4).
  depends_on = [module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.eks_cluster.cluster_name

  # coredns is a Deployment and needs schedulable capacity to leave DEGRADED and become
  # ACTIVE (rules.md C-4). The Karpenter controller also resolves the EKS endpoint by DNS,
  # so nothing below this works until it is up.
  depends_on = [
  module.network, module.eks_node_group]
}
# The queue that turns an EC2 interruption notice into something Karpenter can act on
# before the instance is gone. This variant exists to exercise exactly that path, so the
# queue is the subject rather than a supporting part: the experiment below sends the real
# spot interruption warning, EventBridge delivers it here, and Karpenter reads it.
#
# All four event rules stay on at their defaults. Only the spot interruption rule is
# strictly needed for the experiment, but the others cost nothing idle and the experiments
# variant - which stops an instance outright, producing no warning at all - depends on the
# instance state change rule. Keeping the queue identical across the two makes the
# difference between them purely the experiment.
module "karpenter_interruption_queue" {
  source = "./modules/karpenter_interruption_queue"

  name = var.karpenter_interruption_queue_name

  depends_on = [module.network]
}
# The controller: its IRSA role, the role its nodes run as, and the Helm release. One
# module, because the release annotates the service account with the controller role's ARN
# and the node pool below derives its instance profile from the node role's name
# (rules.md C-2).
module "karpenter" {
  source = "./modules/karpenter"

  cluster_name      = module.eks_cluster.cluster_name
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  chart_version     = var.karpenter_chart_version
  # The name, not the URL and not the ARN - all three identify the same queue, and the
  # chart wants the name. Taken from the queue module's output so the two cannot disagree
  # (rules.md B-5). Without it the controller still provisions nodes; it just learns a spot
  # node is gone only once it stops responding, and by then the pods went with it - which
  # is precisely what this variant is set up to show working.
  interruption_queue_name = module.karpenter_interruption_queue.queue_name
  # The ARN as well as the name, so the controller policy this module creates can scope
  # sqs:ReceiveMessage and sqs:DeleteMessage to this one queue instead of every queue in the
  # account (rules.md B-5).
  interruption_queue_arn = module.karpenter_interruption_queue.queue_arn

  # The controller pod needs schedulable capacity on the managed node group and working
  # cluster DNS before it can reach the EKS API, and wait = true on its Helm release would
  # otherwise time out (rules.md D-2).
  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}
# The one pool. Its Name tag is what the spot interruption experiment searches for.
module "karpenter_node_pool_spot" {
  source = "./modules/karpenter_node_pool"

  node_role_name  = module.karpenter.node_role_name
  node_class_name = var.spot_pool_name
  node_pool_name  = var.spot_pool_name
  # Selector tags are injected rather than discovered, so the module never has to know
  # which network module tagged the subnets or that EKS owns the security group
  # (rules.md B-6).
  subnet_selector_tags = {
    (var.karpenter_discovery_tag_key) = var.cluster_name
  }
  # EKS tags the cluster security group it creates with aws:eks:cluster-name, so selecting
  # on it attaches Karpenter's nodes to the same group the managed node group's nodes use.
  security_group_selector_tags = {
    "aws:eks:cluster-name" = module.eks_cluster.cluster_name
  }
  # Spot only. That is the whole difference from the experiments variant, which runs this
  # pool alongside an on-demand one so it can also stop an instance outright.
  capacity_types = ["spot"]
  # The family and size restrictions the _monolithic template pinned, as NodePool
  # requirements intersecting the category and generation ones the module always writes.
  additional_requirements = [
    {
      key      = "karpenter.k8s.aws/instance-family"
      operator = "In"
      values   = var.karpenter_instance_families
    },
    {
      key      = "karpenter.k8s.aws/instance-size"
      operator = "In"
      values   = var.karpenter_instance_sizes
    },
  ]
  root_volume_size = var.karpenter_node_volume_size
  node_labels      = var.spot_node_labels
  # The tag the FIS target is keyed on. Karpenter writes it onto every instance this pool
  # launches, including the replacement it makes after an interruption, so an experiment
  # run twice finds a target both times.
  node_tags = {
    Name = var.spot_pool_name
  }
  consolidation_policy = var.karpenter_consolidation_policy
  consolidate_after    = var.karpenter_consolidate_after

  # The CRDs these manifests instantiate ship with the Karpenter chart, and nothing in the
  # module can express that (rules.md D-2/E-2). Ordering the module after the controller
  # also makes terraform destroy delete the NodePool first, so Karpenter drains its own
  # nodes while it is still running (rules.md D-4).
  depends_on = [module.network, module.karpenter]
}
# Something for the pool to hold a node for, and something to reschedule when that node is
# taken away. An empty pool provisions nothing, and an experiment against nothing fails on
# empty target resolution rather than showing anything.
module "karpenter_workload" {
  source = "./modules/karpenter_workload"

  name     = var.workload_name
  replicas = var.workload_replicas
  image    = var.workload_image
  # The labels the pool actually writes onto its nodes, not a restatement of them. A
  # selector that matches nothing leaves every pod Pending, and Karpenter will not
  # provision for a label no pool applies (rules.md B-5).
  node_selector = module.karpenter_node_pool_spot.node_labels
  min_available = var.workload_min_available

  depends_on = [module.network, module.karpenter_node_pool_spot]
}
# Covers what Karpenter's queue does not: the managed node group's nodes. It reads each
# node's own instance metadata rather than a queue, so it needs no IAM and no EventBridge.
# On a Karpenter node both react to the same notice, which is duplicated draining rather
# than a conflict.
module "node_termination_handler" {
  source = "./modules/node_termination_handler"

  chart_version = var.node_termination_handler_chart_version

  # A DaemonSet, so it needs nodes to run on, and wait = true would otherwise time out
  # (rules.md D-2).
  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}
# Experiment logging, which the _monolithic template had no equivalent of. Worth the log
# group: an experiment otherwise reports a final state and nothing about which instance it
# resolved to, so a target tag matching the wrong node is indistinguishable from one
# matching the right one. Terraform owns the group, so it carries a retention and is
# removed on destroy - a group FIS created on its own would keep its logs forever.
resource "aws_cloudwatch_log_group" "fis_experiments" {
  count = var.enable_fis_experiment_logging ? 1 : 0

  name              = "/aws/fis/${var.cluster_name}"
  retention_in_days = var.fis_log_retention_days
}
module "fis_experiment_templates" {
  source = "./modules/fis_experiment_templates"

  # One experiment in this variant. stop_instance_experiment is left null rather than made
  # switchable: there is no on-demand pool here for it to target, so a template for it
  # would be created successfully and then fail on empty target resolution the first time
  # it ran. Making the wrong combination inexpressible beats validating against it
  # (rules.md B-1). The experiments variant is the one that has both.
  spot_interruption_experiment = {
    # The Name tag comes from the pool that writes it rather than being restated here.
    # This is the join most likely to be silently wrong, and taking it from the pool is
    # what makes it impossible (rules.md B-5).
    name_tag                     = module.karpenter_node_pool_spot.node_name_tag
    duration_before_interruption = var.spot_interruption_duration
  }
  # FIS wants the ARN *with* a trailing :*, and this trimmed it off - which is backwards. The API
  # rejects the template outright:
  #
  #   Error: invalid value for log_configuration.0.cloudwatch_logs_configuration.0
  #            .log_group_arn (ARN must end with `:*`)
  #
  # Trim then append rather than append alone, so the result is the same whichever form the provider
  # hands over. aws_cloudwatch_log_group.arn has carried both across versions; here it comes without
  # the suffix, which is why the trim was a no-op and the bug reached apply instead of being obvious
  # at this line.
  log_group_arn = var.enable_fis_experiment_logging ? "${trimsuffix(aws_cloudwatch_log_group.fis_experiments[0].arn, ":*")}:*" : null

  # A template is created, not run, so nothing here needs a live node. The dependency is on
  # the pool only because the Name tag comes from it, which the value reference already
  # expresses - this makes the ordering explicit for a reader (rules.md D-2).
  depends_on = [
  module.network, module.karpenter_node_pool_spot]
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  marker_file_path            = var.marker_file_path
  # Joining the cluster security group is what lets this instance reach the API server. The
  # module is handed an ID list and never learns it belongs to an EKS cluster
  # (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]

  # An EKS cluster and this instance share a root module, so it is the workbench for that
  # cluster and carries all five tools (rules.md H-1). None of them creates anything here:
  # the Node Termination Handler, Karpenter, the node pool and the Deployment that the
  # _monolithic template installed from this instance are Terraform resources now
  # (rules.md E-1). eks-node-viewer is the exception worth keeping - it only reads.
  #
  # Two bugs from that template are fixed rather than carried over. It ran "exec bash"
  # partway through the user data, which replaces the shell and discards every line after
  # it - update-kubeconfig, eksctl, helm and an entire AWS Load Balancer Controller install
  # were all below that line, so none of them ever ran. And it pulled eksctl from
  # weaveworks; eksctl-io is the project's own org (rules.md H-1).
  #
  # The controller install is dropped rather than repaired: nothing in this project creates
  # an Ingress or a Service of type LoadBalancer, so the controller had nothing to
  # reconcile. Its IAM role and policy are dropped with it.
  additional_user_data = <<-EOT
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server is already running and predates the docker group, so its terminals would
    # not have it without a restart.
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
    # Order matters: kubectl's completion defines __start_kubectl, and that has to exist
    # before complete names it, or every login prints "function not found" (rules.md H-1).
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
    # Reads the cluster and prints nodes as they come and go, which is the view an
    # interruption is watched through. Pinned, where the _monolithic template also pinned
    # it - the one version it did pin.
    curl -sL -o eks-node-viewer https://github.com/awslabs/eks-node-viewer/releases/download/${var.eks_node_viewer_version}/eks-node-viewer_Linux_x86_64
    chmod +x eks-node-viewer
    sudo install -m 0755 eks-node-viewer /usr/local/bin/eks-node-viewer
    rm eks-node-viewer
    aws configure set default.region ${data.aws_region.current.region}
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}
    EOF
  EOT

  depends_on = [module.network]
}
# Granting the bastion's instance role cluster access joins two modules that know nothing
# about each other, so it belongs in the root (rules.md C-1).
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
  # Every output this project exposes, defined once. outputs.tf projects these and the
  # README below renders them, so no value expression is written twice
  # (rules.md B-5/H-2). Adding an entry here is what makes an output possible, which is
  # what keeps the README from falling behind outputs.tf.
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here. Every command below is meant to be run from its terminal, where kubectl, helm, eksctl and eks-node-viewer are already installed"
      value       = module.vscode_ec2.vscode_url
    }
    cluster_name = {
      order       = 2
      title       = "EKS cluster name"
      description = "Name of the EKS cluster. Also the value of the karpenter.sh/discovery subnet tag and the aws:eks:cluster-name security group tag the EC2NodeClass selects on"
      value       = module.eks_cluster.cluster_name
    }
    cluster_endpoint = {
      order       = 3
      title       = "EKS cluster endpoint"
      description = "API server endpoint. Public so the helm and kubectl providers could reach it during apply - narrow public_access_cidrs to your own address"
      value       = module.eks_cluster.cluster_endpoint
    }
    node_view_command = {
      order       = 4
      title       = "1. Watch the nodes"
      description = "Leave this running in one terminal for the whole demo. It is the view the interruption is judged by: the spot node disappearing and a replacement appearing is the result, and neither is visible in the FIS console"
      value       = "eks-node-viewer --resources cpu,memory"
    }
    node_list_command = {
      order       = 5
      title       = "2. Confirm the spot pool provisioned"
      description = "One node with capacity-type spot, alongside the managed node group's two on-demand nodes. The experiment targets instances by the Name tag Karpenter wrote onto it, so if the pool provisioned nothing the experiment fails on empty target resolution rather than doing nothing"
      value       = module.karpenter_workload.node_list_command
    }
    workload_placement_command = {
      order       = 6
      title       = "3. Confirm the pods landed on Karpenter capacity"
      description = "All of them on the spot node, not on the managed node group. A Pending pod means its nodeSelector matched no pool, and Karpenter does not provision for a label no pool applies"
      value       = module.karpenter_workload.pod_placement_command
    }
    interruption_queue_name = {
      order       = 7
      title       = "Karpenter interruption queue"
      description = "The queue EventBridge delivers interruption notices to and Karpenter polls. This pairing is the subject of the variant: without it Karpenter learns the node is gone only once it stops responding, and by then the pods went with it"
      value       = module.karpenter_interruption_queue.queue_name
    }
    interruption_queue_depth_command = {
      order       = 8
      title       = "Check the queue is being drained"
      description = "Normally zero, because Karpenter deletes each message as it acts on it. A number that stays above zero means the controller is not polling - usually a wrong settings.interruptionQueue or missing SQS permissions, neither of which produces an error anywhere"
      value       = module.karpenter_interruption_queue.queue_depth_command
    }
    node_termination_handler_status_command = {
      order       = 9
      title       = "Node Termination Handler"
      description = "Covers the managed node group, which Karpenter does not manage and would not replace. desired and ready should match the node count - a node without a handler pod is a node that will vanish without being drained"
      value       = module.node_termination_handler.status_command
    }
    experiment_target_tags = {
      order       = 10
      title       = "What the experiment targets"
      description = "The Name tag the experiment searches for, next to the tag the pool actually applies. These come from the same value, so they cannot disagree - shown because a mismatch is the failure this project is most likely to hit and the only symptom is an experiment that fails on empty target resolution"
      value       = join(", ", [for kind, tag in module.fis_experiment_templates.target_name_tags : "${kind} -> Name=${tag}"])
    }
    spot_interruption_start_command = {
      order       = 11
      title       = "4. Interrupt the spot node"
      description = "Sends the real two-minute warning to the spot instance. Karpenter picks it up from the queue, launches a replacement and drains the old node - watch the node view, not this command's output. Not started by the apply, because starting an experiment takes a node away and costs money"
      value       = module.fis_experiment_templates.start_commands["spot_interruption"]
    }
    karpenter_log_command = {
      order       = 12
      title       = "5. Read what Karpenter did about it"
      description = "The controller logs the notice it read from the queue and the replacement it launched. This is where to look if the node went away but nothing took its place, which usually means the queue name or the SQS permissions are wrong rather than anything about the experiment"
      value       = "kubectl -n kube-system logs -l app.kubernetes.io/name=karpenter --tail 100"
    }
    experiment_list_command = {
      order       = 13
      title       = "6. Read what the experiment did"
      description = "Every run with its final state. failed against a template whose target looks right is almost always empty target resolution: the tag matched no instance, which the configuration deliberately treats as a failure rather than a success against nothing"
      value       = module.fis_experiment_templates.experiment_list_command
    }
    experiment_detail_command = {
      order       = 14
      title       = "7. Read which instance one run picked"
      description = "Substitute an ID from the list above. The Targets section names the instance the experiment resolved to, which is the only record of whether the Name tag found what was intended"
      value       = module.fis_experiment_templates.experiment_detail_command
    }
    experiment_log_command = {
      order       = 15
      title       = "8. Read the experiment's own log"
      description = "FIS delivers a per-experiment log to this group, which the _monolithic template had no equivalent of - it recorded only a final state. Empty right after an apply, because no experiment has run yet"
      value       = var.enable_fis_experiment_logging ? "aws logs tail ${aws_cloudwatch_log_group.fis_experiments[0].name} --since 1h" : "disabled (enable_fis_experiment_logging = false)"
    }
    update_kubeconfig_command = {
      order       = 16
      title       = "Re-point kubectl"
      description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the order
  # field and taking values() - which returns a map's values ordered by key - makes the
  # README read top to bottom while the order stays decided by configuration.
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
# available, so every output above is also written to a README in the home directory the
# IDE opens (rules.md H-2). Combining several modules' outputs is the root's job, so this
# lives here rather than inside the instance module.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is what orders
    # this after the bootstrap (rules.md D-5). The marker path comes back out of the module
    # it was passed into, so it is defined once (rules.md B-5).
    #
    # SSM runs as root, hence the chown.
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
