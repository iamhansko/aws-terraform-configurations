data "aws_region" "current" {}

module "network" {
  source = "./modules/network"

  region                         = data.aws_region.current.region
  vpc_cidr_block                 = var.vpc_cidr_block
  availability_zone_suffixes     = var.availability_zone_suffixes
  nat_availability_zone_suffixes = var.nat_availability_zone_suffixes
  vpc_name                       = "${var.project_name}-vpc"
  # Tagged for the AWS Load Balancer Controller, which this project installs. Nothing here
  # creates an Ingress, but discovery has to work for the first one someone adds
  # (rules.md G-1).
  subnet_tags = {
    "kubernetes.io/role/elb"          = "1"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

module "key_pair" {
  source = "./modules/key_pair"

  key_name = "${var.project_name}-key"

  # Nothing here reads a network output, but the root orders every module after the network so
  # the whole VPC - NAT gateway and route tables included - is finished before anything starts
  # in it (rules.md D-3).
  depends_on = [module.network]
}

module "eks_cluster" {
  source = "./modules/eks_cluster"

  name                   = var.cluster_name
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs
  # Stated rather than left to the EKS default, because the node below is told this block and
  # the DNS address inside it. Both travel as outputs of this module, so a change here reaches
  # the node (rules.md B-5).
  service_ipv4_cidr = var.service_ipv4_cidr

  depends_on = [module.network]
}

# vpc-cni is what gives a pod its address, and on this project it carries the setting the whole
# variant depends on: ENABLE_MULTI_NIC. The node asks its kubelet to accept 110 pods, and
# without additional network interfaces a t3.large runs out of addresses long before that - so
# the extra pods sit in ContainerCreating with no IP rather than being refused by the scheduler
# (rules.md E-5).
#
# A DaemonSet, so it reaches ACTIVE with zero nodes and comes before any node capacity
# (rules.md C-4).
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name
  env          = var.vpc_cni_env

  depends_on = [module.network, module.eks_cluster]
}

module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  depends_on = [module.network, module.eks_cluster]
}

# The Pod Identity agent, which is how the load balancer controller gets its credentials
# (rules.md C-4).
module "eks_pod_identity_agent_addon" {
  source = "./modules/eks_pod_identity_agent_addon"

  cluster_name = module.eks_cluster.cluster_name

  depends_on = [module.network, module.eks_cluster]
}

# The subject of this variant: a launch template and an Auto Scaling group whose instances join
# the cluster because their user data tells them how.
#
# What the group adds over the single-instance variant is replacement and capacity; what it does
# not add is EKS knowing about any of it. Nothing drains a node the group is about to terminate,
# so a scale-in or an instance refresh kills pods rather than evicting them - which is the line
# between this and a managed node group.
module "self_managed_node_group" {
  source = "./modules/self_managed_node_group"

  name          = "${var.project_name}-node"
  cluster_name  = module.eks_cluster.cluster_name
  instance_type = var.node_instance_type
  # The four values a self-managed node cannot discover for itself. Every one of them comes from
  # the cluster module, so none is restated as a literal - which is what the _monolithic template
  # did with the Service CIDR and the DNS address (rules.md B-5).
  cluster_endpoint           = module.eks_cluster.cluster_endpoint
  certificate_authority_data = module.eks_cluster.certificate_authority_data
  service_ipv4_cidr          = module.eks_cluster.service_ipv4_cidr
  cluster_dns_ip             = module.eks_cluster.cluster_dns_ip
  ami_ssm_parameter_name     = var.node_ami_ssm_parameter_name
  max_pods                   = var.node_max_pods
  key_name                   = module.key_pair.key_name
  # Both private subnets, unlike the single-instance variant: the group spreads its instances
  # across the zones it is given, which is what makes a second instance land somewhere else.
  subnet_ids = module.network.private_subnet_ids
  # The cluster security group, handed over as an ID list - the module never learns what it
  # belongs to (rules.md B-6).
  vpc_security_group_ids    = [module.eks_cluster.cluster_security_group_id]
  min_size                  = var.node_min_size
  max_size                  = var.node_max_size
  desired_capacity          = var.node_desired_capacity
  default_cooldown          = var.node_default_cooldown
  health_check_grace_period = var.node_health_check_grace_period
  additional_user_data      = <<-EOT
    dnf update -yq
    timedatectl set-timezone ${var.node_timezone}
  EOT

  # A node cannot join Ready without vpc-cni and kube-proxy, and nothing in the value references
  # says so (rules.md C-4).
  depends_on = [
    module.network,
    module.eks_vpc_cni_addon,
    module.eks_kube_proxy_addon,
  ]
}

# coredns is a Deployment, so unlike the DaemonSets it needs schedulable node capacity to leave
# DEGRADED and become ACTIVE. Here that capacity comes from the Auto Scaling group
# (rules.md C-4).
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name          = module.eks_cluster.cluster_name
  coredns_replica_count = var.coredns_replica_count

  depends_on = [
  module.network, module.self_managed_node_group]
}

# The controller, installed even though nothing here creates an Ingress - the
# _monolithic template installed it, and it is what an Ingress from the workbench would need.
# Its IAM role, its Pod Identity association and its Helm release stay in one module because
# they reference each other (rules.md C-2).
module "aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"

  cluster_name  = module.eks_cluster.cluster_name
  vpc_id        = module.network.vpc_id
  aws_region    = data.aws_region.current.region
  chart_version = var.load_balancer_controller_chart_version

  depends_on = [
    module.network,
    module.self_managed_node_group,
    module.eks_coredns_addon,
    module.eks_pod_identity_agent_addon,
  ]
}

# The demo workload. With the group at one instance some replicas will not fit; scaling the
# group is what makes the rest schedule, and the pod distribution command is where the second
# node becomes visible.
module "nginx_demo_workload" {
  source = "./modules/nginx_demo_workload"

  replicas = var.workload_replicas
  image    = var.workload_image

  # There has to be a node before any of these can be scheduled, and DNS before they are useful.
  # Ordering the module after them is also what makes `terraform destroy` remove the pods before
  # the group that runs them disappears (rules.md D-4).
  depends_on = [
  module.network, module.self_managed_node_group, module.eks_coredns_addon]
}

module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name                        = "${var.project_name}-vscode"
  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_ids_by_zone[var.availability_zone_suffixes[0]]
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  code_server_version         = var.code_server_version
  security_group_name         = "${var.project_name}-vscode-sg"
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  marker_file_path            = var.marker_file_path
  # Carrying the cluster security group is what lets kubectl on this instance reach the API
  # server without leaving the VPC (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]
  # An EKS cluster and this instance share a root module, so this instance is the workbench for
  # that cluster and carries all five tools (rules.md H-1).
  #
  # None of them creates anything. The _monolithic template used an SSM Association from here
  # to helm-install the controller and to run `kubectl create deployment nginx`; both are
  # provider resources now (rules.md E-1).
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
    # Order matters: bash_completion has to be sourced before kubectl's own completion, which
    # is what defines __start_kubectl, and that function has to exist before complete
    # references it (rules.md H-1).
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
    rm -f get_helm.sh
    aws configure set default.region ${data.aws_region.current.region}
    # The _monolithic template had this line commented out in both its user data and its SSM
    # Association, so kubectl on the workbench had no kubeconfig at all - every command there
    # failed until someone ran it by hand (rules.md H-1).
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}
    EOF
  EOT

  depends_on = [module.network]
}

# Granting the workbench's instance role cluster access joins two modules that know nothing
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

  # EKS rejects a policy association for a principal with no access entry yet, and the two
  # resources share only literal argument values, so nothing orders them (rules.md D-1).
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
      description = "Open the IDE here and run every command below from its terminal. kubectl is already pointed at the cluster, which the _monolithic template left commented out"
      value       = module.vscode_ec2.vscode_url
    }
    cluster_name = {
      order       = 2
      title       = "EKS cluster name"
      description = "Name of the EKS cluster. It has no managed node group at all - its nodes come from a plain Auto Scaling group whose instances joined because their user data told them how"
      value       = module.eks_cluster.cluster_name
    }
    node_group_name = {
      order       = 3
      title       = "Self-managed Auto Scaling group"
      description = "The group holding the cluster's nodes. EKS knows nothing about it, so an instance that is InService here and absent from kubectl get nodes is a kubelet that was refused"
      value       = module.self_managed_node_group.autoscaling_group_name
    }
    service_cidr = {
      order       = 4
      title       = "Service CIDR and cluster DNS"
      description = "Both are written into every node's NodeConfig, because a self-managed node has no way to discover them. The _monolithic template hardcoded them as literal YAML, so they were correct only as long as nobody changed the cluster"
      value       = "${module.eks_cluster.service_ipv4_cidr} / ${module.eks_cluster.cluster_dns_ip}"
    }
    node_status_command = {
      order       = 5
      title       = "1. The nodes joined"
      description = "One entry per InService instance, all Ready. Fewer nodes than instances means some kubelet was refused; nodes present but NotReady means vpc-cni or kube-proxy is not running on them"
      value       = "kubectl get nodes -o wide"
    }
    instances_command = {
      order       = 6
      title       = "2. What the group holds"
      description = "The group's own view. Compare the count against the previous command - the group reports healthy whether or not its instances joined the cluster"
      value       = module.self_managed_node_group.instances_command
    }
    deployment_status_command = {
      order       = 7
      title       = "3. How many replicas fit"
      description = "Ten are requested. With the group at one instance some will not be ready, which is what the next two steps are for"
      value       = module.nginx_demo_workload.deployment_status_command
    }
    pending_pods_command = {
      order       = 8
      title       = "4. Which pods did not fit, and why"
      description = "Run kubectl describe on one of these. \"Too many pods\" is the kubelet's ceiling; a pod that is scheduled but stuck in ContainerCreating with no IP is address exhaustion, which is what ENABLE_MULTI_NIC on the vpc-cni addon exists to push back"
      value       = module.nginx_demo_workload.pending_pods_command
    }
    scale_command = {
      order       = 9
      title       = "5. Scale the group out"
      description = "Adds the second instance. Terraform ignores desired_capacity after creation, so this does not fight the next plan (rules.md E-8) - and it is the whole difference between this variant and the single-instance one"
      value       = module.self_managed_node_group.scale_command
    }
    pod_distribution_command = {
      order       = 10
      title       = "6. Where the pods landed"
      description = "Run it before and after scaling. Nothing reschedules the pods that were already Pending onto the new node automatically fast - the scheduler picks them up on its next pass, which is usually seconds"
      value       = module.nginx_demo_workload.pod_distribution_command
    }
    bootstrap_log_command = {
      order       = 11
      title       = "7. Read nodeadm's log"
      description = "The only place a rejected NodeConfig is explained. A self-managed node reports nothing to EKS, so there is no console page that shows this"
      value       = module.self_managed_node_group.bootstrap_log_command
    }
    api_server_probe_command = {
      order       = 12
      title       = "8. Talk to the API server directly"
      description = "Useful when kubectl behaves oddly and the question is whether the endpoint or the client is at fault - this bypasses the kubeconfig entirely"
      value       = "kubectl get --raw /api/v1/nodes | jq '.items[].metadata.name'"
    }
    update_kubeconfig_command = {
      order       = 13
      title       = "Re-point kubectl"
      description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the order field
  # and taking values() sorts by that instead - values() returns a map's values ordered by key -
  # so the README reads in the order the demo is run.
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  readme_body = join("\n", concat(
    ["# ${var.project_name}", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}

# The work happens inside code-server in a browser, where "terraform output" does not exist, so
# every output above is also written to a README in the home directory the IDE opens
# (rules.md H-2). The _monolithic template wrote none.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is what orders this
    # after the instance bootstrap (rules.md D-5). The marker path comes back out of the module
    # it was passed into, so it is defined in exactly one place (rules.md B-5).
    #
    # SSM runs as root, hence the chown. The heredoc delimiter is quoted and deliberately
    # unlikely to appear in the body: Terraform has already substituted every value, so the
    # shell has no reason to touch a "$" or a backtick in the README.
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
