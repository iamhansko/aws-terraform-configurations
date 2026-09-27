data "aws_region" "current" {}
module "network" {
  source = "./modules/network"

  vpc_cidr_block      = var.vpc_cidr_block
  public_subnet_tags  = var.public_subnet_tags
  private_subnet_tags = var.private_subnet_tags
  # The second CIDR and the pod subnets carved out of it are what this project is
  # about: nodes keep addresses in the primary range, pods take theirs from here.
  secondary_cidr_block        = var.secondary_cidr_block
  enable_pod_subnet_nat_route = var.enable_pod_subnet_nat_route
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

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version
  # Public and private subnets, not the pod subnets. The control plane's interfaces
  # belong in the primary range; the pod subnets exist only for pod ENIs.
  subnet_ids             = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  # Referencing module.network.*_subnet_ids only orders this after the specific
  # aws_subnet resources behind those outputs, not after the NAT gateways, the
  # secondary CIDR association or the pod subnets (rules.md D-3).
  depends_on = [module.network]
}
# The group every pod ENI joins. Created before the ENIConfigs, which name it.
module "pod_security_group" {
  source = "./modules/pod_security_group"

  vpc_id = module.network.vpc_id
  name   = var.pod_security_group_name
  # The control plane has to be able to reach admission webhooks, which with custom
  # networking run on ENIs in this group rather than sharing the node's interface.
  cluster_security_group_id = module.eks_cluster.cluster_security_group_id

  depends_on = [module.network, module.eks_cluster]
}
# The other direction of the same conversation, and it modifies a group neither
# module owns - the cluster's - so it belongs in the root (rules.md C-1). Without it
# pods can open connections to the control plane but nothing comes back.
resource "aws_vpc_security_group_ingress_rule" "cluster_from_pods" {
  security_group_id            = module.eks_cluster.cluster_security_group_id
  description                  = "All traffic from pod ENIs in the secondary CIDR"
  ip_protocol                  = "-1"
  referenced_security_group_id = module.pod_security_group.security_group_id
}
# The path from the load balancer to the pods, which nothing else creates now. With
# its backend security group turned off the controller does not write a reduced set of
# pod-side rules - it leaves the networking spec out of the TargetGroupBinding
# altogether, so not one rule is created and every target reports unhealthy while the
# load balancer itself looks fine (rules.md G-2).
#
# On this cluster the rule belongs on the pod security group rather than the cluster
# one: custom networking places pods on ENIs in the pod subnets carrying the groups
# from the ENIConfig, so that is where traffic addressed to a pod IP arrives. Putting
# it on the cluster group instead would leave the targets just as unhealthy.
#
# It modifies a group this root assembles from two modules, so it belongs here rather
# than inside either of them (rules.md C-1).
resource "aws_vpc_security_group_ingress_rule" "load_balancer_to_pods" {
  # Exactly one owner. When the annotation is on, the controller writes these rules
  # and this must not (rules.md F-2).
  count = var.manage_backend_security_group_rules ? 0 : 1

  security_group_id = module.pod_security_group.security_group_id
  description       = "Container port from the ALB frontend security group"
  ip_protocol       = "tcp"
  # target-type ip sends traffic to the container port on the pod, and the ALB health
  # check uses traffic-port, so this one rule covers both.
  from_port                    = var.workload_container_port
  to_port                      = var.workload_container_port
  referenced_security_group_id = module.alb_security_group.security_group_id
}
# Custom networking is switched on here, through the addon's configuration_values
# rather than by running "kubectl set env daemonset aws-node" from a shell
# (rules.md E-5).
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name
  env = {
    # Stops the CNI taking pod addresses from the node's own subnet and makes it
    # read an ENIConfig instead. On its own, with no ENIConfig to read, this leaves
    # pods unable to get an address at all - which is why the ENIConfigs below are
    # ordered before the node group.
    AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG = "true"
    # Which ENIConfig applies to which node: the CNI looks for one named after the
    # value of this label on the node, so with the zone label each ENIConfig is
    # named after an availability zone.
    ENI_CONFIG_LABEL_DEF = var.eni_config_label_def
  }

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not
  # exist until this addon creates it. As a DaemonSet it reaches ACTIVE with zero
  # nodes, so it comes before any capacity (rules.md C-4) - and nodes need it to
  # join Ready. It also installs the ENIConfig CRD the module below depends on.
  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as eks_vpc_cni_addon (rules.md C-4).
  depends_on = [module.network, module.eks_cluster]
}
# One ENIConfig per zone, which is what the CNI reads to place pod ENIs.
module "eni_config" {
  source = "./modules/eni_config"

  # Keyed by zone, with the keys coming from the region rather than from a subnet
  # attribute, so they are known at plan time and can drive for_each (rules.md B-8).
  pod_subnets_by_az  = module.network.pod_subnets_by_az
  security_group_ids = [module.pod_security_group.security_group_id]

  # Ordered after the vpc-cni addon because that addon installs the ENIConfig CRD -
  # a manifest for an unregistered kind is rejected rather than queued.
  #
  # And ordered BEFORE the node group, which is the opposite of the usual direction
  # for a kubectl_manifest (rules.md D-4). D-4 exists so a manifest managed by a
  # controller gets deleted while that controller is still alive; an ENIConfig has
  # no controller and no finalizer - it is configuration the CNI reads - so nothing
  # is stuck on destroy. What does matter is the apply direction: the CNI decides a
  # pod's address when the pod is scheduled, so a node that joins before its zone's
  # ENIConfig exists gives its pods no addresses, and existing pods keep the
  # addresses they already have until they are recreated.
  depends_on = [module.eks_vpc_cni_addon, module.pod_security_group]
}
module "eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name   = module.eks_cluster.cluster_name
  instance_types = var.node_group_instance_types
  desired_size   = var.node_group_desired_size
  min_size       = var.node_group_min_size
  max_size       = var.node_group_max_size
  # Nodes go in the private subnets, not the pod subnets. Only pod ENIs live in the
  # secondary CIDR.
  subnet_ids = module.network.private_subnet_ids

  # The ENIConfigs have to exist first, or the first pods scheduled onto these nodes
  # get no addresses (see the eni_config module block above).
  depends_on = [
    module.network,
    module.eks_vpc_cni_addon,
    module.eks_kube_proxy_addon,
    module.eni_config,
  ]
}
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.eks_cluster.cluster_name

  # coredns is a Deployment and needs schedulable capacity to leave DEGRADED and
  # become ACTIVE (rules.md C-4). Its pods get addresses from the pod subnets, which
  # is why the pod security group has to allow DNS between its own members.
  depends_on = [module.eks_node_group]
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
  # be true - the controller refuses that combination otherwise, and only says so in
  # its own log (rules.md G-2).
  enable_backend_security_group = var.enable_backend_security_group

  # The controller's webhook runs in a pod, which on this cluster means an ENI in the
  # pod security group - so that group's webhook rule has to be in place, and there
  # has to be a node to schedule it on.
  depends_on = [module.network, module.eks_node_group, module.pod_security_group]
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
# The demo workload. Declared before the load balancer module so the ALB can take its
# adoption stack tag from this module's output rather than the root restating
# "<namespace>/<name>" (rules.md B-5/G-3).
module "nginx_workload" {
  source = "./modules/nginx_workload"

  name                                = var.workload_name
  namespace                           = var.workload_namespace
  image                               = var.workload_image
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
  # internet-facing, so public subnets - never the pod subnets, which are CGNAT
  # space. This has to agree with the Ingress's scheme annotation or the controller
  # builds a second load balancer (rules.md G-3).
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
  # anything here: the ENIConfigs, the workload and the controller's chart that the
  # _monolithic template applied from this instance are Terraform resources now
  # (rules.md E-1).
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
      description = "API server endpoint. Public so the kubectl provider could create the ENIConfig custom resources during apply - narrow public_access_cidrs to your own address, or see 041_eks_private_cluster for the variant that keeps it private"
      value       = module.eks_cluster.cluster_endpoint
    }
    vpc_cidr_block = {
      order       = 4
      title       = "Primary VPC CIDR (nodes)"
      description = "Node addresses come from subnets carved out of this range"
      value       = module.network.vpc_cidr_block
    }
    secondary_cidr_block = {
      order       = 5
      title       = "Secondary CIDR (pods)"
      description = "Pod addresses come from here instead. CGNAT space, so they do not have to be unique across peered or on-premises networks - which is the reason to move pods out of the primary range at all"
      value       = var.secondary_cidr_block
    }
    ingress_url = {
      order       = 6
      title       = "Demo workload URL"
      description = "The pre-created ALB the controller adopted from the demo Ingress. The page prints the address of the pod that served it, which will be in the secondary CIDR"
      value       = module.synced_load_balancer.url
    }
    pod_address_check_command = {
      order       = 7
      title       = "1. Compare pod and node addresses"
      description = "The whole project in one command: the IP column comes from the secondary CIDR, the NODE_IP column from the primary one"
      value       = module.nginx_workload.pod_address_check_command
    }
    eni_config_check_command = {
      order       = 8
      title       = "2. Confirm the ENIConfigs"
      description = "One per zone, named after the zone because ENI_CONFIG_LABEL_DEF points at topology.kubernetes.io/zone. Cross-check against 'kubectl get nodes -L topology.kubernetes.io/zone' - a node in a zone with no ENIConfig gives its pods no addresses"
      value       = module.eni_config.check_command
    }
    all_pod_address_check_command = {
      order       = 9
      title       = "3. Check every pod, not just the demo"
      description = "Pods that existed before custom networking was switched on keep their old addresses until they are recreated, so a mix of primary and secondary addresses here is expected rather than wrong"
      value       = module.eni_config.pod_address_check_command
    }
    ingress_hostname_command = {
      order       = 10
      title       = "4. Read the address the controller attached"
      description = "Compare against the workload URL above. They should be the same load balancer - if they differ, the controller built its own instead of adopting the pre-created one (rules.md G-3)"
      value       = module.nginx_workload.load_balancer_hostname_command
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
