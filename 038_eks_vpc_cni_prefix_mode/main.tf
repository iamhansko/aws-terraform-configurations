data "aws_region" "current" {}
module "network" {
  source = "./modules/network"

  public_subnet_tags  = var.public_subnet_tags
  private_subnet_tags = var.private_subnet_tags
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
# Prefix delegation is switched on here, and this is the whole project.
#
# The _monolithic template turned it on with two "kubectl set env daemonset aws-node"
# commands from the bastion, against the aws-node DaemonSet that EKS installs
# automatically when bootstrap_self_managed_addons is left at its default. That put
# the cluster's most important setting outside Terraform entirely: nothing recorded
# it, and nothing would put it back. The eks_cluster module sets
# bootstrap_self_managed_addons = false, so vpc-cni exists only because this module
# creates it, and the setting travels as addon configuration_values (rules.md C-4/E-5).
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name
  env = merge(
    {
      # Each address slot on an ENI becomes a /28 prefix instead of a single
      # address, which is what lifts the per-node pod ceiling.
      ENABLE_PREFIX_DELEGATION = tostring(var.enable_prefix_delegation)
    },
    # Only meaningful with prefix delegation on, so it is omitted otherwise rather
    # than set to a value the CNI would ignore.
    var.enable_prefix_delegation ? {
      WARM_PREFIX_TARGET = tostring(var.warm_prefix_target)
    } : {},
  )

  # As a DaemonSet it reaches ACTIVE with zero nodes, so it comes before any
  # capacity (rules.md C-4) - and here that ordering is load-bearing rather than
  # incidental: a node that joins before prefix delegation is set gets its address
  # allocation the old way, and the CNI does not retroactively re-allocate.
  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as eks_vpc_cni_addon (rules.md C-4).
  depends_on = [module.network, module.eks_cluster]
}
locals {
  # The other half of prefix mode, and the half the _monolithic template left
  # commented out.
  #
  # Turning on prefix delegation changes what the CNI can allocate. It does not
  # change the kubelet's own limit, which the node's bootstrap computes from the
  # instance type using the non-prefix formula - 17 pods on a t3.medium - because the
  # bootstrap cannot see the DaemonSet's configuration. Without raising it, the CNI
  # has addresses for a hundred pods and the kubelet still refuses the eighteenth.
  #
  # Managed node groups on AL2023 take user data as a MIME multipart document and
  # merge a NodeConfig part with the one EKS generates, so only the kubelet field
  # needs to be supplied here - the cluster endpoint and CA come from EKS's own part.
  # A bare shell script would be ignored, which is why the boundary framing matters.
  node_config_part = <<-EOT
    --==BOUNDARY==
    Content-Type: application/node.eks.aws

    apiVersion: node.eks.aws/v1alpha1
    kind: NodeConfig
    spec:
      kubelet:
        config:
          maxPods: ${var.node_max_pods}
  EOT
  # The _monolithic template also ran "yum update -y" on every node boot. Dropped:
  # it delays a node joining by minutes, makes two nodes built from the same AMI
  # differ, and the managed node group AMI is already patched at release. Only the
  # timezone remains.
  shell_part     = var.node_timezone == null ? "" : <<-EOT
    --==BOUNDARY==
    Content-Type: text/x-shellscript; charset="us-ascii"

    #!/bin/bash
    timedatectl set-timezone ${var.node_timezone}
  EOT
  node_user_data = <<-EOT
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary="==BOUNDARY=="

    ${local.node_config_part}
    ${local.shell_part}
    --==BOUNDARY==--
  EOT
}
module "eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name   = module.eks_cluster.cluster_name
  instance_types = var.node_group_instance_types
  desired_size   = var.node_group_desired_size
  min_size       = var.node_group_min_size
  max_size       = var.node_group_max_size
  subnet_ids     = module.network.private_subnet_ids
  key_name       = module.key_pair.key_name
  # The launch template the module always creates is where the NodeConfig above
  # goes. The _monolithic template built its own launch template for exactly this
  # and for the cluster security group.
  custom_user_data       = local.node_user_data
  vpc_security_group_ids = [module.eks_cluster.cluster_security_group_id]

  # vpc-cni has to carry the prefix delegation setting before this node boots, or
  # the node allocates addresses the old way (rules.md C-4).
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
module "aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"

  cluster_name      = module.eks_cluster.cluster_name
  vpc_id            = module.network.vpc_id
  aws_region        = data.aws_region.current.region
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  chart_version     = var.aws_load_balancer_controller_chart_version
  # The workload's Ingress sets manage-backend-security-group-rules, so this has to
  # be true - the controller refuses that combination otherwise and only says so in
  # its own log (rules.md G-2).
  enable_backend_security_group = var.enable_backend_security_group

  depends_on = [module.network, module.eks_node_group]
}
# Standalone rule resources rather than inline blocks, and revoke_rules_on_delete,
# because the controller adds its own rules to this group (rules.md F-2).
module "alb_security_group" {
  source = "./modules/load_balancer_security_group"

  vpc_id                      = module.network.vpc_id
  name                        = var.alb_security_group_name
  description                 = "Frontend security group for the ALB the controller adopts from the demo Ingress"
  port                        = var.alb_port
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere

  depends_on = [module.network]
}
# The path from the load balancer to the pods, which nothing else creates now. With
# its backend security group turned off the controller does not write a reduced set of
# pod-side rules - it leaves the networking spec out of the TargetGroupBinding
# altogether, so not one rule is created and every target reports unhealthy while the
# load balancer itself looks fine (rules.md G-2).
#
# It modifies the cluster security group, which no module here owns outright, so it
# belongs in the root (rules.md C-1). Pods share their node's ENIs under the default
# CNI, and those carry the cluster security group, so that is where traffic addressed
# to a pod IP arrives.
resource "aws_vpc_security_group_ingress_rule" "load_balancer_to_pods" {
  # Exactly one owner. When the annotation is on, the controller writes these rules
  # and this must not (rules.md F-2).
  count = var.manage_backend_security_group_rules ? 0 : 1

  security_group_id = module.eks_cluster.cluster_security_group_id
  description       = "Container port from the ALB frontend security group"
  ip_protocol       = "tcp"
  # target-type ip sends traffic to the container port on the pod, and the ALB health
  # check uses traffic-port, so this one rule covers both.
  from_port                    = var.workload_container_port
  to_port                      = var.workload_container_port
  referenced_security_group_id = module.alb_security_group.security_group_id
}
# Declared before the load balancer module so the ALB can take its adoption stack
# tag from this module's output rather than the root restating "<namespace>/<name>"
# (rules.md B-5/G-3).
module "nginx_workload" {
  source = "./modules/nginx_workload"

  name      = var.workload_name
  namespace = var.workload_namespace
  image     = var.workload_image
  # The measurement. A hundred replicas do not fit on one t3.medium in the default
  # CNI mode and do fit with prefix delegation plus a raised kubelet limit - so if
  # either half is missing, the surplus pods sit Pending with insufficient pods as
  # the reason.
  replicas                            = var.workload_replicas
  container_port                      = var.workload_container_port
  scheme                              = "internet-facing"
  target_type                         = "ip"
  frontend_security_group_id          = module.alb_security_group.security_group_id
  manage_backend_security_group_rules = var.manage_backend_security_group_rules

  # The controller has to be reconciling before the Ingress appears, or nothing picks
  # it up (rules.md G-1). Ordering the module after the node group also makes
  # terraform destroy remove these manifests while the nodes and the controller are
  # still there (rules.md D-4).
  depends_on = [
    module.network,
    module.eks_node_group,
    module.eks_coredns_addon,
    module.aws_load_balancer_controller,
  ]
}
# Created here and adopted by the controller, so the address is known from state at
# apply time rather than only after the controller has reconciled the Ingress
# (rules.md G-3).
module "synced_load_balancer" {
  source = "./modules/synced_load_balancer"

  cluster_name       = module.eks_cluster.cluster_name
  load_balancer_type = "application"
  internal           = false
  # internet-facing, so public subnets. This has to agree with the Ingress's scheme
  # annotation or the controller builds a second load balancer (rules.md G-3).
  subnet_ids         = module.network.public_subnet_ids
  security_group_ids = [module.alb_security_group.security_group_id]
  # ingress.k8s.aws/*, not service.k8s.aws/*: this load balancer fronts an Ingress.
  # The wrong prefix is not an error - the controller just builds its own
  # (rules.md G-3).
  resource_tag_prefix = "ingress"
  stack               = module.nginx_workload.stack_tag

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
  # Joining the cluster security group is what lets this instance reach the API
  # server. The module is handed an ID list and never learns it belongs to an EKS
  # cluster (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]

  # An EKS cluster and this instance share a root module, so it is the workbench for
  # that cluster and carries all five tools (rules.md H-1). None of them creates
  # anything here: the kubectl set env commands and the workload the _monolithic
  # template applied from this instance are addon configuration and Terraform
  # resources now (rules.md E-1/E-5).
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
    # The _monolithic user data ran "exec bash" before this line, which replaced the
    # shell so nothing after it ever ran - including this kubeconfig write. Dropped.
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
      description = "Name of the EKS cluster. The AWS Load Balancer Controller also writes this into the elbv2.k8s.aws/cluster tag it uses to find load balancers it owns"
      value       = module.eks_cluster.cluster_name
    }
    cluster_endpoint = {
      order       = 3
      title       = "EKS cluster endpoint"
      description = "API server endpoint. Public so the kubectl provider could create the demo workload during apply - narrow public_access_cidrs to your own address, or see 041_eks_private_cluster for the variant that keeps it private"
      value       = module.eks_cluster.cluster_endpoint
    }
    prefix_delegation_settings = {
      order       = 4
      title       = "CNI prefix delegation"
      description = "What the vpc-cni addon was configured with. Set as addon configuration_values, not by kubectl set env against the DaemonSet, so it is recorded in state and restored on the next apply if anything changes it"
      value       = "ENABLE_PREFIX_DELEGATION=${var.enable_prefix_delegation} WARM_PREFIX_TARGET=${var.warm_prefix_target}"
    }
    node_max_pods = {
      order       = 5
      title       = "Kubelet max pods per node"
      description = "The other half of prefix mode. Prefix delegation changes what the CNI can allocate; this changes what the kubelet will admit. The node bootstrap would otherwise compute 17 for a t3.medium from the non-prefix formula, and the surplus replicas would sit Pending"
      value       = tostring(var.node_max_pods)
    }
    ingress_url = {
      order       = 6
      title       = "Demo workload URL"
      description = "The pre-created ALB the controller adopted from the demo Ingress. The page prints the address of the pod that served it"
      value       = module.synced_load_balancer.url
    }
    pod_count_command = {
      order       = 7
      title       = "1. Count the running pods"
      description = "The measurement. All of the replicas should be Running on the single node; in the default CNI mode this node would admit 17 and the rest would be Pending"
      value       = "kubectl -n ${var.workload_namespace} get deploy ${var.workload_name} -o wide && kubectl -n ${var.workload_namespace} get pods --field-selector=status.phase=Running --no-headers | wc -l"
    }
    node_capacity_command = {
      order       = 8
      title       = "2. Read the node's pod capacity"
      description = "Shows the kubelet's own limit as the node reports it. This is the number the NodeConfig in the launch template set - if it reads 17, the user data did not take effect"
      value       = "kubectl get nodes -o custom-columns=NAME:.metadata.name,MAX_PODS:.status.allocatable.pods,INSTANCE:.metadata.labels.node\\.kubernetes\\.io/instance-type"
    }
    pending_pods_command = {
      order       = 9
      title       = "3. Check for Pending pods"
      description = "Empty output is the healthy case. Anything here with 'Insufficient pods' means the kubelet limit is the binding constraint; 'failed to assign an IP address' means prefix delegation did not take"
      value       = "kubectl -n ${var.workload_namespace} get pods --field-selector=status.phase=Pending"
    }
    cni_env_command = {
      order       = 10
      title       = "4. Confirm the CNI settings reached the DaemonSet"
      description = "What the aws-node container actually has. These come from the addon's configuration_values, so a mismatch here means the addon did not apply rather than that someone edited the DaemonSet"
      value       = "kubectl -n kube-system get daemonset aws-node -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{\"\\n\"}{end}' | grep -E 'PREFIX|WARM'"
    }
    adopted_load_balancer_check_command = {
      order       = 11
      title       = "5. Confirm the ALB was adopted, not duplicated"
      description = "Lists every load balancer tagged for this cluster. One is correct. Two means adoption failed, which is a tag mismatch rather than an error (rules.md G-3)"
      value       = "aws resourcegroupstaggingapi get-resources --tag-filters Key=elbv2.k8s.aws/cluster,Values=${module.eks_cluster.cluster_name} --resource-type-filters elasticloadbalancing:loadbalancer --query 'ResourceTagMappingList[].ResourceARN' --output table"
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
