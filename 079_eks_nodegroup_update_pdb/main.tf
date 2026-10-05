data "aws_region" "current" {}
module "network" {
  source = "./modules/network"

  # Two availability zones, as the _monolithic template had them. Three would cost a
  # third NAT gateway for nothing here: the node group spreads over the private subnets
  # and two zones already show the update moving pods between zones (rules.md C-3).
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

  key_name = var.key_name

  # key_pair consumes no network output, so nothing would otherwise order it against the
  # network module's resources (rules.md D-3).
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

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not exist
  # until this addon creates it. As a DaemonSet it reaches ACTIVE with zero nodes, so it
  # comes before any capacity - and nodes need it to join Ready (rules.md C-4). It matters
  # again during the update: each replacement node has to reach Ready before the next old
  # one can be drained.
  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as eks_vpc_cni_addon (rules.md C-4).
  depends_on = [module.network, module.eks_vpc_cni_addon]
}
# The node group this project updates. Everything above exists to give it somewhere to
# run and everything below exists to make its update visible.
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
  # The marker that makes old and new nodes tellable apart in the EC2 console. Rewriting
  # this tag is what creates a new launch template version, and that new version is what
  # EKS rolls the node group onto - so this one variable is the whole trigger. The
  # _monolithic template produced the same second version with an
  # aws ec2 create-launch-template-version call inside the instance's user data, outside
  # Terraform's knowledge entirely.
  instance_tags = {
    Name = var.node_group_instance_name_tag
  }
  # Null by default, so the node group follows the template's latest version and the tag
  # change and the roll happen in one apply. Pinned, it lags the template on purpose
  # (rules.md B-4).
  launch_template_version = var.node_group_launch_template_version
  # False, so the drain goes through the eviction API and the budget below can hold it up.
  # The _monolithic template forced it, which deletes pods instead and makes the budget
  # irrelevant.
  force_update_version   = var.node_group_force_update_version
  update_max_unavailable = var.node_group_update_max_unavailable

  # Nodes need vpc-cni and kube-proxy running to join the cluster Ready (rules.md C-4).
  depends_on = [module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.eks_cluster.cluster_name

  # coredns is a Deployment and needs schedulable capacity to leave DEGRADED and become
  # ACTIVE (rules.md C-4).
  depends_on = [
  module.network, module.eks_node_group]
}
# The Deployment the update has to drain and the budget that decides how fast it may.
module "nginx_pdb_workload" {
  source = "./modules/nginx_pdb_workload"

  name                            = var.workload_name
  namespace                       = var.workload_namespace
  replicas                        = var.workload_replicas
  readiness_initial_delay_seconds = var.workload_readiness_initial_delay_seconds
  pdb_max_unavailable             = var.workload_pdb_max_unavailable

  # These are kubectl_manifest resources against the cluster's API server, so ordering the
  # module after the nodes is what makes terraform destroy remove them while there is
  # still a kubelet to delete the pods - and, more to the point here, makes destroy take
  # the budget away before the nodes it would otherwise hold up (rules.md D-4).
  depends_on = [
  module.network, module.eks_node_group, module.eks_coredns_addon]
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  marker_file_path            = var.marker_file_path
  # Joining the cluster security group is what lets this instance reach the API server.
  # The module is handed an ID list and never learns it belongs to an EKS cluster
  # (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]

  # An EKS cluster and this instance share a root module, so it is the workbench for that
  # cluster and carries all five tools (rules.md H-1). None of them creates anything: the
  # Deployment, the budget and the second launch template version that the _monolithic
  # template produced from here are Terraform resources now (rules.md E-1).
  #
  # Three bugs from that template are fixed here rather than carried over. It ran
  # "exec bash" partway through, which replaces the shell and silently discarded every
  # remaining line - update-kubeconfig, eksctl, helm, the kubectl apply of the Deployment
  # and the budget, and the create-launch-template-version call were all after it, so on a
  # real boot none of them ran and the demo had nothing to demonstrate. It pulled eksctl
  # from weaveworks rather than eksctl-io. And it wrote the "complete" line for the k alias
  # into .bashrc before the line that defines __start_kubectl, so every login printed a
  # "function not found" error (rules.md H-1).
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
    # Order matters: kubectl's completion defines __start_kubectl, and that has to exist
    # before complete names it, or every login prints "function not found"
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
  # README below renders them, so no value expression is written twice (rules.md B-5/H-2).
  # Adding an entry here is what makes an output possible, which is what keeps the README
  # from falling behind outputs.tf.
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here. Every kubectl command below is meant to be run from its terminal, and the update itself is watched from there"
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
      description = "API server endpoint. Public so the kubectl provider could reach it during apply - narrow public_access_cidrs to your own address"
      value       = module.eks_cluster.cluster_endpoint
    }
    node_group = {
      order       = 4
      title       = "Managed node group"
      description = "The node group this project updates, and how many of its nodes EKS is allowed to take out of service at once. Raising that number does not speed the update up on its own: the budget below still decides how many pods may be unavailable"
      value       = "${module.eks_node_group.node_group_name} (update maxUnavailable=${module.eks_node_group.update_max_unavailable})"
    }
    launch_template = {
      order       = 5
      title       = "Launch template state"
      description = "The template, the version the node group is running, and the newest version that exists. The two version numbers are equal in a settled state. They differ while an update is pending - which is what changing node_group_instance_name_tag with node_group_launch_template_version pinned produces"
      value       = "${module.eks_node_group.launch_template_name}: node group on version ${module.eks_node_group.launch_template_version}, latest version ${module.eks_node_group.launch_template_latest_version}, instances tagged Name=${var.node_group_instance_name_tag}"
    }
    disruption_budget = {
      order       = 6
      title       = "Pod disruption budget in force"
      description = "What the update has to respect. One pod per node and one permitted disruption means the drain is strictly serial: evict a pod, wait for its replacement to turn Ready, evict the next"
      value       = "${module.nginx_pdb_workload.budget} on ${module.nginx_pdb_workload.replicas} replicas, replacement pods NotReady for ${module.nginx_pdb_workload.readiness_initial_delay_seconds}s"
    }
    force_update_version = {
      order       = 7
      title       = "Does the budget actually apply"
      description = "False means the update drains through the eviction API and the budget gates it, failing with PodEvictionFailure if a node still holds pods after fifteen minutes. True means EKS deletes the pods instead and no budget can hold anything up - which is what the _monolithic template did, making the budget it created purely decorative"
      value       = "force_update_version=${module.eks_node_group.force_update_version}"
    }
    rollout_status_command = {
      order       = 8
      title       = "1. Let the workload settle"
      description = "Run this first. With a sixty-second readiness delay the Deployment is not fully Ready until a minute after apply, and starting the update before then means the budget is gating on pods that were never Ready in the first place"
      value       = module.nginx_pdb_workload.rollout_status_command
    }
    pod_placement_command = {
      order       = 9
      title       = "2. Note where the pods are"
      description = "One pod per node is what makes the rest of the demo readable. Run this again during the update: pods should leave the node being replaced one at a time, never two at once"
      value       = module.nginx_pdb_workload.pod_placement_command
    }
    node_marker_command = {
      order       = 10
      title       = "3. Read the node markers"
      description = "Every instance in the node group with its Name tag. All of them read v1 now. During the update they turn over to the new value one at a time, which is the same story the pod list tells, seen from the EC2 side"
      value       = "aws ec2 describe-instances --filters Name=tag:eks:nodegroup-name,Values=${module.eks_node_group.node_group_name} Name=instance-state-name,Values=pending,running --query 'Reservations[].Instances[].[InstanceId,LaunchTime,Tags[?Key==`Name`]|[0].Value]' --output table"
    }
    trigger_update_command = {
      order       = 11
      title       = "4. Start the update"
      description = "Rewrites the launch template, which creates version 2, which EKS rolls the node group onto. This is the managed node group update: a plan, not a console click and not a CLI call buried in user data. Expect it to take several minutes - the scale-up phase adds nodes first, then each old node is cordoned and drained in turn"
      value       = "terraform apply -var node_group_instance_name_tag=v2"
    }
    pdb_status_command = {
      order       = 12
      title       = "5. Watch the budget gate it"
      description = "ALLOWED DISRUPTIONS is the number the drain waits on. It reads 1 while every pod is Ready and drops to 0 the moment one is evicted, staying there until the replacement passes its readiness probe. That zero is the update waiting, not the update stuck"
      value       = module.nginx_pdb_workload.pdb_status_command
    }
    eviction_events_command = {
      order       = 13
      title       = "6. Read the cordons and evictions"
      description = "The record that EKS drained each node rather than terminating it. A forced update deletes pods instead of evicting them and leaves no eviction events at all, which is the quickest way to tell the two apart after the fact"
      value       = module.nginx_pdb_workload.eviction_events_command
    }
    describe_update_command = {
      order       = 14
      title       = "7. Read the update from the EKS side"
      description = "The update's own status and phase, and where a PodEvictionFailure would appear. This is the authoritative view: terraform apply blocking tells you it is still running, but only this says which phase it is in and why"
      value       = "aws eks describe-update --name ${module.eks_cluster.cluster_name} --nodegroup-name ${module.eks_node_group.node_group_name} --update-id $(aws eks list-updates --name ${module.eks_cluster.cluster_name} --nodegroup-name ${module.eks_node_group.node_group_name} --query 'updateIds[-1]' --output text)"
    }
    block_update_command = {
      order       = 15
      title       = "8. Make the update fail on purpose"
      description = "A budget of zero allows no voluntary disruption, so the drain can never satisfy it. The upgrade phase waits the full fifteen minutes per node and then fails with PodEvictionFailure - the error the budget exists to be able to cause, and the one a real upgrade hits when a budget is set tighter than the cluster can honour"
      value       = "terraform apply -var workload_pdb_max_unavailable=0 -var node_group_instance_name_tag=v3"
    }
    force_update_command = {
      order       = 16
      title       = "9. Push it through anyway"
      description = "The escape hatch, and the reason the _monolithic template's demo showed nothing: with force the drain becomes a delete, the budget is ignored, and the update completes. Worth running once after step 8, to see that the same configuration behaves completely differently depending on this one flag"
      value       = "terraform apply -var workload_pdb_max_unavailable=0 -var node_group_instance_name_tag=v3 -var node_group_force_update_version=true"
    }
    update_kubeconfig_command = {
      order       = 17
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
    # this after the bootstrap (rules.md D-5). The marker path comes back out of the
    # module it was passed into, so it is defined once (rules.md B-5).
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
