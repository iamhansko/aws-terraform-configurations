data "aws_region" "current" {}

locals {
  # The first zone suffix, which is where each VPC's workbench goes.
  first_zone = var.availability_zone_suffixes[0]

  # Subnet tags, identical in both VPCs. Only the public tier is tagged for load balancer
  # discovery: the controller has to find a public subnet for an internet-facing scheme, and the
  # non-routable tiers must never be chosen - an ALB in the cluster tier would be created and
  # unreachable, since that tier has no route off the VPC (rules.md G-1).
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  # The adoption tag, defined here rather than taken from a workload module's output so the
  # pre-created load balancers can be created before the Ingresses that adopt them. Both clusters
  # use the same namespace and name, and that is fine: the tag is only meaningful together with
  # elbv2.k8s.aws/cluster, which differs (rules.md B-5/G-3).
  ingress_stack_tag = "${var.workload_namespace}/${var.workload_name}"

  # The two Ingress annotations that are the same in both clusters. The security groups differ, so
  # they are merged in per cluster below.
  common_ingress_annotations = {
    "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
    "alb.ingress.kubernetes.io/target-type" = "ip"
  }
}

# One transit gateway for both VPCs, created before either of them: the peer routes inside each
# VPC point at it, so its ID has to exist first.
#
# The attachments live here rather than in the network module because an attachment is a property
# of the gateway, and because putting them in the network module would make each VPC depend on a
# gateway that depends on both VPCs (rules.md C-1).
module "transit_gateway" {
  source = "./modules/transit_gateway"

  name        = "${var.project_name}-tgw"
  description = "Routes traffic between the two EKS VPCs"
  # Keyed by a label, because every value inside is another module's output and unknown at plan
  # time (rules.md B-8). The attachments go in the private tier: routable, which the other VPC
  # needs in order to address them.
  attachments = {
    vpc-a = {
      vpc_id     = module.vpc_a_network.vpc_id
      subnet_ids = module.vpc_a_network.private_subnet_ids
      cidr_block = var.vpc_a_cidr_block
    }
    vpc-b = {
      vpc_id     = module.vpc_b_network.vpc_id
      subnet_ids = module.vpc_b_network.private_subnet_ids
      cidr_block = var.vpc_b_cidr_block
    }
  }
}

# --- VPC A ---

module "vpc_a_network" {
  source = "./modules/cross_vpc_network"

  region                     = data.aws_region.current.region
  name                       = "${var.project_name}-a"
  vpc_cidr_block             = var.vpc_a_cidr_block
  secondary_cidr_block       = var.secondary_cidr_block
  availability_zone_suffixes = var.availability_zone_suffixes
  public_subnet_cidr_blocks  = var.vpc_a_public_subnet_cidr_blocks
  private_subnet_cidr_blocks = var.vpc_a_private_subnet_cidr_blocks
  cluster_subnet_cidr_blocks = var.cluster_subnet_cidr_blocks
  node_subnet_cidr_blocks    = var.node_subnet_cidr_blocks
  # The other VPC's primary block, as a configuration value rather than module.vpc_b_network's
  # output. Taking it from the other module would make each network depend on the other, which is
  # a cycle Terraform refuses.
  peer_cidr_blocks   = [var.vpc_b_cidr_block]
  transit_gateway_id = module.transit_gateway.transit_gateway_id
  # A route may not point at the gateway before this VPC's attachment exists. It would be accepted
  # and then blackhole, which is a timeout rather than an error (rules.md D-2).
  transit_gateway_attachment_dependency = module.transit_gateway.attachments["vpc-a"]
  public_subnet_tags                    = local.public_subnet_tags
}

module "key_pair" {
  source = "./modules/key_pair"

  key_name = "${var.project_name}-key"

  # One key pair for both VPCs, as the _monolithic template had it. Nothing here reads a network
  # output, but the root orders every module after the networks so both VPCs - NAT gateways and
  # route tables included - are finished before anything starts in them (rules.md D-3).
  depends_on = [module.vpc_a_network, module.vpc_b_network]
}

module "vpc_a_eks_cluster" {
  source = "./modules/eks_cluster"

  name               = "${var.project_name}-a"
  kubernetes_version = var.kubernetes_version
  # Cluster and node subnets only, not the public tier. The control plane's ENIs belong in the
  # non-routable range with the nodes they talk to; putting them in the routable public tier would
  # spend routable addresses on something nothing outside the VPC reaches.
  subnet_ids             = concat(module.vpc_a_network.cluster_subnet_ids, module.vpc_a_network.node_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  depends_on = [module.vpc_a_network]
}

# vpc-cni and kube-proxy are DaemonSets, so they reach ACTIVE with zero nodes and come before any
# node capacity - a node cannot join Ready without them, and with
# bootstrap_self_managed_addons = false nothing installs them otherwise (rules.md C-4).
module "vpc_a_eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.vpc_a_eks_cluster.cluster_name

  depends_on = [module.vpc_a_network, module.vpc_a_eks_cluster]
}

module "vpc_a_eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.vpc_a_eks_cluster.cluster_name

  depends_on = [module.vpc_a_network, module.vpc_a_eks_cluster]
}

module "vpc_a_eks_pod_identity_agent_addon" {
  source = "./modules/eks_pod_identity_agent_addon"

  cluster_name = module.vpc_a_eks_cluster.cluster_name

  depends_on = [module.vpc_a_network, module.vpc_a_eks_cluster]
}

module "vpc_a_eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name    = module.vpc_a_eks_cluster.cluster_name
  node_group_name = var.node_group_name
  instance_types  = var.node_instance_types
  desired_size    = var.node_desired_size
  min_size        = var.node_min_size
  max_size        = var.node_max_size
  key_name        = module.key_pair.key_name
  # The node tier, out of the non-routable block. Every pod address comes from here, which is the
  # whole reason this VPC has a secondary CIDR.
  subnet_ids = module.vpc_a_network.node_subnet_ids

  depends_on = [
    module.vpc_a_network,
    module.vpc_a_eks_vpc_cni_addon,
    module.vpc_a_eks_kube_proxy_addon,
  ]
}

module "vpc_a_eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name          = module.vpc_a_eks_cluster.cluster_name
  coredns_replica_count = var.coredns_replica_count

  depends_on = [module.vpc_a_eks_node_group]
}

module "vpc_a_aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"
  providers = {
    # The helm provider for this cluster. There is no default one, so a module that omitted this
    # would fail at init rather than installing into whichever cluster came first.
    helm = helm.vpc_a
  }

  cluster_name                  = module.vpc_a_eks_cluster.cluster_name
  vpc_id                        = module.vpc_a_network.vpc_id
  aws_region                    = data.aws_region.current.region
  chart_version                 = var.load_balancer_controller_chart_version
  enable_backend_security_group = var.enable_backend_security_group

  depends_on = [
    module.vpc_a_network,
    module.vpc_a_eks_node_group,
    module.vpc_a_eks_coredns_addon,
    module.vpc_a_eks_pod_identity_agent_addon,
  ]
}

module "vpc_a_alb_security_group" {
  source = "./modules/load_balancer_security_group"

  vpc_id      = module.vpc_a_network.vpc_id
  name        = "${var.project_name}-a-${var.alb_security_group_name}"
  description = "Frontend security group for the ALB in front of the VPC A workload"
  ports = {
    http = var.workload_container_port
  }
  allow_inbound_from_anywhere = var.alb_allow_inbound_from_anywhere

  depends_on = [module.vpc_a_network]
}

# The pre-created ALB the controller adopts. Pre-created so its address is known from state at
# apply time - which is what lets this project's outputs say "call VPC B's ALB from inside VPC A"
# without querying either cluster first (rules.md G-3).
module "vpc_a_synced_load_balancer" {
  source = "./modules/synced_load_balancer"

  cluster_name       = module.vpc_a_eks_cluster.cluster_name
  load_balancer_type = "application"
  internal           = false
  # internet-facing, so the public tier. This has to agree with the scheme the Ingress annotates,
  # or the controller builds a second load balancer instead of adopting this one (rules.md G-3).
  subnet_ids          = module.vpc_a_network.public_subnet_ids
  security_group_ids  = [module.vpc_a_alb_security_group.security_group_id]
  resource_tag_prefix = "ingress"
  stack               = local.ingress_stack_tag

  depends_on = [module.vpc_a_network]
}

# The path from the ALB to the pods. With the shared backend security group off, the controller
# leaves the networking spec out of the TargetGroupBinding altogether, so not one rule is created
# and every target reports unhealthy while the ALB itself looks fine (rules.md G-2).
#
# It modifies the cluster security group, which no module here owns outright, so it belongs in the
# root (rules.md C-1).
resource "aws_vpc_security_group_ingress_rule" "vpc_a_load_balancer_to_pods" {
  security_group_id            = module.vpc_a_eks_cluster.cluster_security_group_id
  description                  = "Container port from the VPC A ALB frontend security group"
  ip_protocol                  = "tcp"
  from_port                    = var.workload_container_port
  to_port                      = var.workload_container_port
  referenced_security_group_id = module.vpc_a_alb_security_group.security_group_id
}

module "vpc_a_workload" {
  source = "./modules/nginx_ingress_workload"
  providers = {
    kubectl = kubectl.vpc_a
  }

  name           = var.workload_name
  namespace      = var.workload_namespace
  image          = var.workload_image
  replicas       = var.workload_replicas
  container_port = var.workload_container_port
  ingress_annotations = merge(local.common_ingress_annotations, {
    # Both groups, as the _monolithic template's annotation had them: the frontend group that
    # admits the internet, and the cluster group the pods carry.
    "alb.ingress.kubernetes.io/security-groups" = join(",", [
      module.vpc_a_alb_security_group.security_group_id,
      module.vpc_a_eks_cluster.cluster_security_group_id,
    ])
  })

  # The load balancer has to exist before the controller reconciles this Ingress, or the controller
  # builds its own and the pre-created one is orphaned (rules.md G-3). Ordering the module after
  # the controller is also what makes `terraform destroy` remove the Ingress while the controller
  # is still alive, so the load balancer is cleaned up rather than left behind (rules.md D-4).
  depends_on = [
    module.vpc_a_synced_load_balancer,
    module.vpc_a_aws_load_balancer_controller,
    module.vpc_a_eks_coredns_addon,
  ]
}

module "vpc_a_vscode_ec2" {
  source = "./modules/vscode_ec2"

  name   = "${var.project_name}-a-vscode"
  vpc_id = module.vpc_a_network.vpc_id
  # The public tier: this instance needs a public address to be reached and a routable one to reach
  # the other VPC across the transit gateway.
  subnet_id                   = module.vpc_a_network.public_subnet_ids_by_zone[local.first_zone]
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  code_server_version         = var.code_server_version
  security_group_name         = "${var.project_name}-a-vscode-sg"
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  marker_file_path            = var.marker_file_path
  extra_security_group_ids    = [module.vpc_a_eks_cluster.cluster_security_group_id]
  additional_user_data        = local.vpc_a_workbench_user_data

  depends_on = [module.vpc_a_network]
}

resource "aws_eks_access_entry" "vpc_a_vscode" {
  cluster_name  = module.vpc_a_eks_cluster.cluster_name
  principal_arn = module.vpc_a_vscode_ec2.iam_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "vpc_a_vscode" {
  cluster_name  = module.vpc_a_eks_cluster.cluster_name
  principal_arn = module.vpc_a_vscode_ec2.iam_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }

  # EKS rejects a policy association for a principal with no access entry yet, and the two
  # resources share only literal argument values, so nothing orders them (rules.md D-1).
  depends_on = [aws_eks_access_entry.vpc_a_vscode]
}

# --- VPC B ---
#
# Identical to VPC A apart from its CIDRs, its provider aliases and the peer it routes to. Written
# out rather than produced with for_each because a module's providers argument cannot be keyed by
# an instance - there is no way to hand each iteration a different aliased provider.

module "vpc_b_network" {
  source = "./modules/cross_vpc_network"

  region                                = data.aws_region.current.region
  name                                  = "${var.project_name}-b"
  vpc_cidr_block                        = var.vpc_b_cidr_block
  secondary_cidr_block                  = var.secondary_cidr_block
  availability_zone_suffixes            = var.availability_zone_suffixes
  public_subnet_cidr_blocks             = var.vpc_b_public_subnet_cidr_blocks
  private_subnet_cidr_blocks            = var.vpc_b_private_subnet_cidr_blocks
  cluster_subnet_cidr_blocks            = var.cluster_subnet_cidr_blocks
  node_subnet_cidr_blocks               = var.node_subnet_cidr_blocks
  peer_cidr_blocks                      = [var.vpc_a_cidr_block]
  transit_gateway_id                    = module.transit_gateway.transit_gateway_id
  transit_gateway_attachment_dependency = module.transit_gateway.attachments["vpc-b"]
  public_subnet_tags                    = local.public_subnet_tags
}

module "vpc_b_eks_cluster" {
  source = "./modules/eks_cluster"

  name                   = "${var.project_name}-b"
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = concat(module.vpc_b_network.cluster_subnet_ids, module.vpc_b_network.node_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  depends_on = [module.vpc_b_network]
}

module "vpc_b_eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.vpc_b_eks_cluster.cluster_name

  depends_on = [module.vpc_b_network, module.vpc_b_eks_cluster]
}

module "vpc_b_eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.vpc_b_eks_cluster.cluster_name

  depends_on = [module.vpc_b_network, module.vpc_b_eks_cluster]
}

module "vpc_b_eks_pod_identity_agent_addon" {
  source = "./modules/eks_pod_identity_agent_addon"

  cluster_name = module.vpc_b_eks_cluster.cluster_name

  depends_on = [module.vpc_b_network, module.vpc_b_eks_cluster]
}

module "vpc_b_eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name    = module.vpc_b_eks_cluster.cluster_name
  node_group_name = var.node_group_name
  instance_types  = var.node_instance_types
  desired_size    = var.node_desired_size
  min_size        = var.node_min_size
  max_size        = var.node_max_size
  key_name        = module.key_pair.key_name
  subnet_ids      = module.vpc_b_network.node_subnet_ids

  depends_on = [
    module.vpc_b_network,
    module.vpc_b_eks_vpc_cni_addon,
    module.vpc_b_eks_kube_proxy_addon,
  ]
}

module "vpc_b_eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name          = module.vpc_b_eks_cluster.cluster_name
  coredns_replica_count = var.coredns_replica_count

  depends_on = [module.vpc_b_eks_node_group]
}

module "vpc_b_aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"
  providers = {
    helm = helm.vpc_b
  }

  cluster_name                  = module.vpc_b_eks_cluster.cluster_name
  vpc_id                        = module.vpc_b_network.vpc_id
  aws_region                    = data.aws_region.current.region
  chart_version                 = var.load_balancer_controller_chart_version
  enable_backend_security_group = var.enable_backend_security_group

  depends_on = [
    module.vpc_b_network,
    module.vpc_b_eks_node_group,
    module.vpc_b_eks_coredns_addon,
    module.vpc_b_eks_pod_identity_agent_addon,
  ]
}

module "vpc_b_alb_security_group" {
  source = "./modules/load_balancer_security_group"

  vpc_id      = module.vpc_b_network.vpc_id
  name        = "${var.project_name}-b-${var.alb_security_group_name}"
  description = "Frontend security group for the ALB in front of the VPC B workload"
  ports = {
    http = var.workload_container_port
  }
  allow_inbound_from_anywhere = var.alb_allow_inbound_from_anywhere

  depends_on = [module.vpc_b_network]
}

module "vpc_b_synced_load_balancer" {
  source = "./modules/synced_load_balancer"

  cluster_name        = module.vpc_b_eks_cluster.cluster_name
  load_balancer_type  = "application"
  internal            = false
  subnet_ids          = module.vpc_b_network.public_subnet_ids
  security_group_ids  = [module.vpc_b_alb_security_group.security_group_id]
  resource_tag_prefix = "ingress"
  stack               = local.ingress_stack_tag

  depends_on = [module.vpc_b_network]
}

resource "aws_vpc_security_group_ingress_rule" "vpc_b_load_balancer_to_pods" {
  security_group_id            = module.vpc_b_eks_cluster.cluster_security_group_id
  description                  = "Container port from the VPC B ALB frontend security group"
  ip_protocol                  = "tcp"
  from_port                    = var.workload_container_port
  to_port                      = var.workload_container_port
  referenced_security_group_id = module.vpc_b_alb_security_group.security_group_id
}

module "vpc_b_workload" {
  source = "./modules/nginx_ingress_workload"
  providers = {
    kubectl = kubectl.vpc_b
  }

  name           = var.workload_name
  namespace      = var.workload_namespace
  image          = var.workload_image
  replicas       = var.workload_replicas
  container_port = var.workload_container_port
  ingress_annotations = merge(local.common_ingress_annotations, {
    "alb.ingress.kubernetes.io/security-groups" = join(",", [
      module.vpc_b_alb_security_group.security_group_id,
      module.vpc_b_eks_cluster.cluster_security_group_id,
    ])
  })

  depends_on = [
    module.vpc_b_synced_load_balancer,
    module.vpc_b_aws_load_balancer_controller,
    module.vpc_b_eks_coredns_addon,
  ]
}

module "vpc_b_vscode_ec2" {
  source = "./modules/vscode_ec2"

  name                        = "${var.project_name}-b-vscode"
  vpc_id                      = module.vpc_b_network.vpc_id
  subnet_id                   = module.vpc_b_network.public_subnet_ids_by_zone[local.first_zone]
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  code_server_version         = var.code_server_version
  security_group_name         = "${var.project_name}-b-vscode-sg"
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  marker_file_path            = var.marker_file_path
  extra_security_group_ids    = [module.vpc_b_eks_cluster.cluster_security_group_id]
  additional_user_data        = local.vpc_b_workbench_user_data

  depends_on = [module.vpc_b_network]
}

resource "aws_eks_access_entry" "vpc_b_vscode" {
  cluster_name  = module.vpc_b_eks_cluster.cluster_name
  principal_arn = module.vpc_b_vscode_ec2.iam_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "vpc_b_vscode" {
  cluster_name  = module.vpc_b_eks_cluster.cluster_name
  principal_arn = module.vpc_b_vscode_ec2.iam_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.vpc_b_vscode]
}

locals {
  # One bootstrap script, rendered per cluster. The _monolithic template carried two copies of it
  # inside two SSM Associations, differing only in a cluster name and a VPC ID - and both of those
  # associations also installed the load balancer controller and applied the workload, which are
  # provider resources now (rules.md E-1).
  #
  # An EKS cluster and these instances share a root module, so each is the workbench for its own
  # cluster and carries all five tools (rules.md H-1). None of them creates anything here.
  workbench_user_data = {
    for label, cluster in {
      a = module.vpc_a_eks_cluster.cluster_name
      b = module.vpc_b_eks_cluster.cluster_name
    } : label => <<-EOT
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
      # Order matters: bash_completion has to be sourced before kubectl's own completion, which is
      # what defines __start_kubectl, and that function has to exist before complete references it
      # (rules.md H-1).
      echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
      echo 'source <(kubectl completion bash)' >> ~/.bashrc
      echo 'alias k=kubectl' >> ~/.bashrc
      echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
      # eksctl-io is the project's own org; the weaveworks URL the _monolithic template used still
      # redirects, but the current name is what gets used (rules.md H-1).
      PLATFORM=$(uname -s)_amd64
      curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
      tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
      sudo install -m 0755 /tmp/eksctl /usr/local/bin && rm /tmp/eksctl
      curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
      chmod 700 get_helm.sh
      ./get_helm.sh
      rm -f get_helm.sh
      aws configure set default.region ${data.aws_region.current.region}
      # The _monolithic template's associations never ran this - the line was there and commented
      # out - so kubectl on both workbenches had no kubeconfig at all (rules.md H-1).
      aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${cluster}
      EOF
    EOT
  }
  vpc_a_workbench_user_data = local.workbench_user_data["a"]
  vpc_b_workbench_user_data = local.workbench_user_data["b"]

  # Every output this project exposes, defined once. outputs.tf projects these and the READMEs
  # render them, so no value expression is written twice (rules.md B-5/H-2).
  outputs = {
    vpc_a_vscode_url = {
      order       = 1
      title       = "code-server in VPC A"
      description = "The workbench for VPC A's cluster. kubectl there is pointed at that cluster only - the other one has its own"
      value       = module.vpc_a_vscode_ec2.vscode_url
    }
    vpc_b_vscode_url = {
      order       = 2
      title       = "code-server in VPC B"
      description = "The workbench for VPC B's cluster"
      value       = module.vpc_b_vscode_ec2.vscode_url
    }
    vpc_a_url = {
      order       = 3
      title       = "VPC A workload URL"
      description = "The pre-created ALB in VPC A. Known from state at apply time, which is what lets the cross-VPC request below be written down rather than discovered (rules.md G-3)"
      value       = module.vpc_a_synced_load_balancer.url
    }
    vpc_b_url = {
      order       = 4
      title       = "VPC B workload URL"
      description = "The pre-created ALB in VPC B"
      value       = module.vpc_b_synced_load_balancer.url
    }
    address_plan = {
      order       = 5
      title       = "Address plan"
      description = "The routable primary blocks differ; the non-routable secondary block is the same in both VPCs on purpose. Pod addresses come out of the secondary block, which is why they have to be translated before they cross the transit gateway"
      value       = "A ${var.vpc_a_cidr_block} / B ${var.vpc_b_cidr_block} / pods ${var.secondary_cidr_block} (both)"
    }
    transit_gateway_routes_command = {
      order       = 6
      title       = "1. The transit gateway routes are active"
      description = "Two routes, one per VPC, both active. A route in blackhole state is the failure mode here: it exists, so nothing errors, and traffic to it is dropped"
      value       = module.transit_gateway.routes_check_command
    }
    vpc_a_route_tables_command = {
      order       = 7
      title       = "2. VPC A's route tables"
      description = "This is where the design is visible: the node tier reaches VPC B through a private NAT gateway, while the private tier reaches it through the transit gateway directly"
      value       = module.vpc_a_network.route_tables_command
    }
    vpc_a_pods_command = {
      order       = 8
      title       = "3. The pod addresses are non-routable"
      description = "Every address is in 100.64/16. Both clusters use the same block, so these addresses mean nothing outside their own VPC - which is the problem the private NAT gateway solves"
      value       = module.vpc_a_workload.pod_ips_command
    }
    vpc_a_ingress_command = {
      order       = 9
      title       = "4. VPC A's ALB was adopted"
      description = "Compare the address this prints against the VPC A URL above. Two different names mean the controller did not adopt the pre-created load balancer and built its own (rules.md G-3)"
      value       = module.vpc_a_workload.load_balancer_hostname_command
    }
    cross_vpc_request_command = {
      order       = 10
      title       = "5. Call VPC B from inside VPC A"
      description = "The demonstration. The request leaves a pod at a 100.64 address, the private NAT gateway rewrites the source to a routable 192.168 address, the transit gateway carries it to VPC B, and VPC B's ALB answers - because it has a route back to that 192.168 address and would have none to the pod's own"
      value       = "${module.vpc_a_workload.curl_command} ${module.vpc_b_synced_load_balancer.url}"
    }
    reverse_request_command = {
      order       = 11
      title       = "6. And the other direction"
      description = "Same path in reverse, from VPC B's cluster to VPC A's ALB. Run from VPC B's workbench"
      value       = "${module.vpc_b_workload.curl_command} ${module.vpc_a_synced_load_balancer.url}"
    }
    private_nat_addresses = {
      order       = 12
      title       = "The addresses the far side sees"
      description = "What a packet capture or a security group rule in the other VPC observes as the source - not the pod's address. Worth knowing before writing a rule that names one"
      value       = "A ${join(", ", values(module.vpc_a_network.private_nat_gateway_addresses))} / B ${join(", ", values(module.vpc_b_network.private_nat_gateway_addresses))}"
    }
    attachments_check_command = {
      order       = 13
      title       = "7. The attachments are in routable subnets"
      description = "An attachment placed in the non-routable tier is created, reports available, and is unreachable from the other side - a timeout rather than an error"
      value       = module.transit_gateway.attachments_check_command
    }
  }
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

# One README per workbench, both rendered from the same map - the commands for both VPCs are useful
# from either side (rules.md H-2). The _monolithic template wrote a four-line README on each
# instance holding two curl commands.
#
# for_each over a map keyed by a label, with the instance ID as the value: the IDs are unknown at
# plan time and cannot be for_each keys (rules.md B-8).
resource "aws_ssm_association" "vscode_readme" {
  for_each = {
    vpc-a = module.vpc_a_vscode_ec2.instance_id
    vpc-b = module.vpc_b_vscode_ec2.instance_id
  }

  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [each.value]
  }
  parameters = {
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is what orders this after
    # the instance bootstrap (rules.md D-5). Both instances were given the same marker path, so one
    # expression covers both.
    #
    # SSM runs as root, hence the chown. The heredoc delimiter is quoted and deliberately unlikely
    # to appear in the body: Terraform has already substituted every value, so the shell has no
    # reason to touch a "$" or a backtick in the README.
    commands = <<-EOT
      until [ -f ${var.marker_file_path}/userdata ]; do sleep 10; done
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${var.marker_file_path}/vscode_readme
      EOT
  }
}
