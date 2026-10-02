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

  # key_pair consumes no network output, so nothing would otherwise order it against the
  # network module's resources. Every module in a root that has a network module waits for all
  # of it (rules.md D-3).
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
  # resources behind those outputs, not after the NAT gateways and route table associations that
  # never surface as outputs (rules.md D-3).
  depends_on = [module.network]
}
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not exist until this
  # addon creates it. As a DaemonSet it reaches ACTIVE with zero nodes, so it comes before any
  # capacity - and nodes need it to join Ready (rules.md C-4). Relevant here because the demo
  # deliberately loses a node and the replacement has to join the same way.
  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as eks_vpc_cni_addon (rules.md C-4).
  depends_on = [module.network, module.eks_cluster]
}
# The capacity the demo interrupts. Spot, because a spot interruption notice is the event this
# variant is about and an on-demand instance cannot receive one.
module "eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name    = module.eks_cluster.cluster_name
  node_group_name = var.node_group_name
  capacity_type   = var.node_group_capacity_type
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

  # coredns is a Deployment and needs schedulable capacity to leave DEGRADED and become ACTIVE
  # (rules.md C-4).
  depends_on = [
  module.network, module.eks_node_group]
}
# The subject of this variant. A DaemonSet, so it needs nodes to run on before wait = true can
# succeed, and it has to be running before an interruption is sent or there is nothing to
# observe (rules.md D-2).
module "node_termination_handler" {
  source = "./modules/node_termination_handler"

  chart_version             = var.node_termination_handler_chart_version
  enable_rebalance_draining = var.enable_rebalance_draining

  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}
# The workload that makes the drain visible. Without it a node being cordoned and terminated
# looks identical whether the handler acted or not.
module "nginx_workload" {
  source = "./modules/nginx_workload"

  name     = var.workload_name
  replicas = var.workload_replicas
  image    = var.workload_image
  # No node selector: the handler covers every node in this cluster, so there is nothing to pin
  # these pods to and the spread constraint in the module does the placing (rules.md B-4).
  min_available = var.workload_min_available

  # These are kubectl_manifest resources against the cluster's API server. Ordering the module
  # after the node group means terraform destroy removes the Deployment and its budget while the
  # nodes are still there, so the delete does not hang against an API server whose nodes have
  # already gone (rules.md D-4).
  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}
# The role the amazon-ec2-spot-interrupter CLI runs its experiments as. There is no
# aws_fis_experiment_template in this project: the CLI builds one from a list of instance IDs,
# runs it and deletes it again, so the role is the only durable piece - and its name is fixed by
# the tool rather than chosen here (see the module).
module "spot_interrupter_role" {
  source = "./modules/spot_interrupter_role"

  interrupt_delay = var.spot_interrupt_delay

  depends_on = [module.network]
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
  # module is handed an ID list and never learns it belongs to an EKS cluster (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]

  # An EKS cluster and this instance share a root module, so it is the workbench for that
  # cluster and carries all five tools (rules.md H-1). None of them creates anything: the
  # handler and the demo Deployment that the _monolithic template installed from here are
  # Terraform resources now (rules.md E-1). eks-node-viewer and ec2-spot-interrupter are the
  # exceptions worth keeping - one only reads, and the other is how the demo is triggered, which
  # is deliberately a manual act rather than something an apply does.
  #
  # Three bugs from that template are fixed rather than carried over. It ran "exec bash" partway
  # through the user data, which replaces the shell and discards every line after it -
  # update-kubeconfig, eksctl, helm and a whole AWS Load Balancer Controller install were all
  # below that line, so none of them ever ran. It pulled eksctl from weaveworks; eksctl-io is
  # the project's own org (rules.md H-1). And it wrote "complete -o default -F __start_kubectl k"
  # into .bashrc before the line that sources kubectl's completion, so every login printed a
  # "function not found" error.
  #
  # The controller install is dropped rather than repaired: nothing in this project creates an
  # Ingress or a Service of type LoadBalancer, so the controller had nothing to reconcile. Its
  # IAM role and policy are dropped with it.
  additional_user_data = <<-EOT
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server is already running and predates the docker group, so its terminals would not
    # have it without a restart.
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
    # Order matters: kubectl's completion defines __start_kubectl, and that has to exist before
    # complete names it, or every login prints "function not found" (rules.md H-1).
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
    # Reads the cluster and prints nodes as they come and go, which is the view a drain is
    # watched through.
    curl -sL -o eks-node-viewer https://github.com/awslabs/eks-node-viewer/releases/download/${var.eks_node_viewer_version}/eks-node-viewer_Linux_x86_64
    chmod +x eks-node-viewer
    sudo install -m 0755 eks-node-viewer /usr/local/bin/eks-node-viewer
    rm eks-node-viewer
    # Sends the interruption. The release assets no longer carry the version in their filenames,
    # which the _monolithic template's URL depended on - so the version appears only in the tag
    # path here.
    curl -sL -o ec2-spot-interrupter.tar.gz https://github.com/aws/amazon-ec2-spot-interrupter/releases/download/${var.spot_interrupter_version}/ec2-spot-interrupter_linux_amd64.tar.gz
    tar -xzf ec2-spot-interrupter.tar.gz -C /tmp ec2-spot-interrupter
    sudo install -m 0755 /tmp/ec2-spot-interrupter /usr/local/bin/ec2-spot-interrupter
    rm ec2-spot-interrupter.tar.gz /tmp/ec2-spot-interrupter
    aws configure set default.region ${data.aws_region.current.region}
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}
    EOF
  EOT

  depends_on = [module.network]
}
# Granting the bastion's instance role cluster access joins two modules that know nothing about
# each other, so it belongs in the root (rules.md C-1).
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
  # Every output this project exposes, defined once. outputs.tf projects these and the README
  # below renders them, so no value expression is written twice (rules.md B-5/H-2). Adding an
  # entry here is what makes an output possible, which is what keeps the README from falling
  # behind outputs.tf.
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here. Every command below is meant to be run from its terminal, where kubectl, helm, eksctl, eks-node-viewer and ec2-spot-interrupter are already installed"
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
      description = "API server endpoint. Public so the helm and kubectl providers could reach it during apply - narrow public_access_cidrs to your own address"
      value       = module.eks_cluster.cluster_endpoint
    }
    handler_mode = {
      order       = 4
      title       = "Which mode the handler is in"
      description = "IMDS mode: a DaemonSet with one pod per node, each reading only its own instance metadata. It needs no queue, no IAM role and no credentials - and it cannot see an Auto Scaling scale-in, because no instance can learn that about itself. nth_queue_processor is the variant that can"
      value       = "IMDS mode, chart ${module.node_termination_handler.chart_version}, DaemonSet in ${module.node_termination_handler.namespace}"
    }
    handler_status_command = {
      order       = 5
      title       = "1. Confirm a handler pod is on every node"
      description = "desired and ready should both equal the node count. A node without a handler pod is a node that will vanish without being drained, and nothing else reports that"
      value       = module.node_termination_handler.status_command
    }
    node_view_command = {
      order       = 6
      title       = "2. Watch the nodes"
      description = "Leave this running in one terminal for the whole demo. A node going away and a replacement joining is the result, and neither is visible from the FIS console the CLI drives"
      value       = "eks-node-viewer --resources cpu,memory"
    }
    workload_placement_command = {
      order       = 7
      title       = "3. See where the pods are"
      description = "Run this before interrupting anything and keep the output. The replicas are spread across the nodes by a topologySpreadConstraint, which the _monolithic template had no equivalent of - without it the scheduler could stack most of them on one node and interrupting another would drain nothing"
      value       = module.nginx_workload.pod_placement_command
    }
    spot_instance_list_command = {
      order       = 8
      title       = "4. Pick a spot instance to interrupt"
      description = "The CLI takes instance IDs, so this is how to get one. Every node here is spot, which is why the node group's capacity type is not a free choice in this variant"
      value       = module.spot_interrupter_role.list_spot_instances_command
    }
    spot_interrupt_command = {
      order       = 9
      title       = "5. Send the interruption"
      description = "Substitute an instance ID from the list above. The CLI sends a rebalance recommendation immediately and the two-minute interruption notice after the delay, building a FIS experiment template, running it and deleting it again. Not something the apply does: it takes a node away"
      value       = module.spot_interrupter_role.interrupt_command
    }
    handler_log_command = {
      order       = 10
      title       = "6. Read what the handler saw"
      description = "The notice it read from instance metadata and the drain it performed. With rebalance draining on, the first entry is the rebalance recommendation rather than the interruption - the node is already empty by the time the notice arrives"
      value       = module.node_termination_handler.log_command
    }
    drain_events_command = {
      order       = 11
      title       = "7. Read the cordon and the evictions"
      description = "The record that the handler acted rather than the node simply vanishing. An instance reclaimed without a drain leaves no such events, which is exactly what this project is here to make visible"
      value       = module.nginx_workload.drain_events_command
    }
    workload_recovery_command = {
      order       = 12
      title       = "8. Confirm the workload came back"
      description = "Same command as step 3. The pods that were on the interrupted node should be elsewhere and the total back at the replica count - with the disruption budget in place they moved in stages rather than all at once"
      value       = module.nginx_workload.pod_placement_command
    }
    spot_interrupter_role_arn = {
      order       = 13
      title       = "FIS role the CLI uses"
      description = "Named aws-fis-itn because the CLI looks for that exact name and would create its own if it were missing. The CLI prints this ARN in its experiment summary, which is the quickest confirmation it found this role rather than making one of its own"
      value       = module.spot_interrupter_role.role_arn
    }
    update_kubeconfig_command = {
      order       = 14
      title       = "Re-point kubectl"
      description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the order field
  # and taking values() - which returns a map's values ordered by key - makes the README read top
  # to bottom while the order stays decided by configuration.
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
# The work happens inside code-server in a browser, where terraform output is not available, so
# every output above is also written to a README in the home directory the IDE opens
# (rules.md H-2). Combining several modules' outputs is the root's job, so this lives here rather
# than inside the instance module.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is what orders this
    # after the bootstrap (rules.md D-5). The marker path comes back out of the module it was
    # passed into, so it is defined once (rules.md B-5).
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
