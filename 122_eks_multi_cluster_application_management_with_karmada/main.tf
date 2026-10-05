data "aws_region" "current" {}
locals {
  key_name = var.key_name == null ? "${var.cluster_name_prefix}-key" : var.key_name
  # The three cluster names, built from one prefix exactly as the guidance script built them:
  # "${CLUSTERS_NAME}-parent" and "${CLUSTERS_NAME}-member-${i}". They are declared one by one rather than
  # generated because each member needs its own helm provider alias and provider aliases cannot come from a
  # for_each - see the member_cluster_count variable.
  parent_cluster_name   = "${var.cluster_name_prefix}-parent"
  member_1_cluster_name = "${var.cluster_name_prefix}-member-1"
  member_2_cluster_name = "${var.cluster_name_prefix}-member-2"
  # Keys are literal strings and values are module outputs, which is what for_each needs: the keys become
  # resource addresses and have to be known during plan, while the values can be resolved during apply
  # (rules.md B-8). Referencing the outputs here is also what orders the access entries after the clusters.
  cluster_names = {
    parent   = module.parent_eks_cluster.cluster_name
    member_1 = module.member_1_eks_cluster.cluster_name
    member_2 = module.member_2_eks_cluster.cluster_name
  }
  member_cluster_names = [
    module.member_1_karmada_agent.cluster_name,
    module.member_2_karmada_agent.cluster_name,
  ]
  # Where the workbench keeps its kubeconfigs. The Karmada path is the one `kubectl karmada init --karmada-data
  # /home/ec2-user` produced, kept so that every command in this project's outputs and in the guidance's own
  # documentation reads the same.
  kube_config_path    = "/home/ec2-user/.kube/config"
  karmada_config_dir  = "/home/ec2-user/.karmada"
  karmada_config_path = "${local.karmada_config_dir}/karmada-apiserver.config"
  # Where karmada init kept the PKI it generated, reproduced here because the workbench's kubeconfig is
  # assembled from files rather than from one pre-rendered document - see the parameters below.
  karmada_pki_dir = "${local.karmada_config_dir}/pki"
  # Named after the parent cluster rather than the project prefix, which would read /karmada/karmada/...
  karmada_parameter_prefix = "/${local.parent_cluster_name}/karmada/pki"
  # The context name inside the Karmada kubeconfig. The chart's own generated kubeconfig uses
  # <release>-apiserver, and this matches it so that switching between the four contexts on the workbench
  # reads consistently.
  karmada_context_name = "karmada-apiserver"
}
module "network" {
  source = "./modules/network"

  region                         = data.aws_region.current.region
  vpc_cidr_block                 = var.vpc_cidr_block
  availability_zone_suffixes     = var.availability_zone_suffixes
  nat_availability_zone_suffixes = var.nat_availability_zone_suffixes
  vpc_name                       = var.cluster_name_prefix
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name = local.key_name

  # key_pair consumes no network output, so nothing would otherwise order it against the network module's
  # resources (rules.md D-3).
  depends_on = [module.network]
}
# =========================================================================================================
# Parent cluster - carries the Karmada control plane
# =========================================================================================================
module "parent_eks_cluster" {
  source = "./modules/eks_cluster"

  name                   = local.parent_cluster_name
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  # Referencing module.network.*_subnet_ids only orders this after the specific aws_subnet resources behind
  # those outputs, not after the NAT gateways and route table associations that never surface as outputs
  # (rules.md D-3).
  depends_on = [module.network]
}
module "parent_eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.parent_eks_cluster.cluster_name

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not exist until this addon
  # creates it. As a DaemonSet it reaches ACTIVE with zero nodes, so it comes before any capacity - and
  # nodes need it to join Ready (rules.md C-4).
  depends_on = [module.network, module.parent_eks_cluster]
}
module "parent_eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.parent_eks_cluster.cluster_name

  # Same reasoning as the vpc-cni addon, and with one extra consequence on this cluster: kube-proxy is what
  # opens the Karmada API server's nodePort on each node, which is what the load balancer's target group
  # health-checks (rules.md C-4).
  depends_on = [module.network, module.parent_eks_cluster]
}
# Only the parent gets this. It exists for the EBS CSI driver below, which exists for Karmada's etcd volume,
# and the member clusters claim no volumes at all.
module "parent_eks_pod_identity_agent_addon" {
  source = "./modules/eks_pod_identity_agent_addon"

  cluster_name = module.parent_eks_cluster.cluster_name

  depends_on = [module.network, module.parent_eks_cluster]
}
module "parent_eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name    = module.parent_eks_cluster.cluster_name
  node_group_name = "${local.parent_cluster_name}-nodes"
  instance_types  = var.node_instance_types
  desired_size    = var.parent_node_count
  min_size        = var.parent_node_count
  max_size        = var.node_max_count
  subnet_ids      = module.network.private_subnet_ids
  key_name        = module.key_pair.key_name

  # Nodes need vpc-cni and kube-proxy running to join the cluster Ready (rules.md C-4).
  depends_on = [
    module.network,
    module.parent_eks_vpc_cni_addon,
    module.parent_eks_kube_proxy_addon,
  ]
}
module "parent_eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.parent_eks_cluster.cluster_name

  # coredns is a Deployment and needs schedulable capacity to leave DEGRADED and become ACTIVE
  # (rules.md C-4). It is also a hard prerequisite for Karmada rather than a nicety: every control plane
  # component reaches the others by Service name, so without working DNS the apiserver cannot find etcd and
  # the whole release stalls in init containers.
  depends_on = [module.network, module.parent_eks_node_group]
}
module "parent_eks_ebs_csi_driver_addon" {
  source = "./modules/eks_ebs_csi_driver_addon"

  cluster_name     = module.parent_eks_cluster.cluster_name
  role_name_prefix = "${var.cluster_name_prefix}-ebs-csi-"

  # The addon's pod_identity_association needs the agent already installed, and its controller is a
  # Deployment so it needs schedulable capacity (rules.md C-4/D-2).
  depends_on = [
    module.network,
    module.parent_eks_pod_identity_agent_addon,
    module.parent_eks_node_group,
  ]
}
module "parent_ebs_storage_class" {
  source    = "./modules/ebs_storage_class"
  providers = { kubectl = kubectl.parent }

  name = var.etcd_storage_class_name

  # After the driver, because a class whose provisioner has no driver behind it provisions nothing - and
  # after the node group, so that `terraform destroy` removes this object while the cluster can still serve
  # a delete (rules.md D-4).
  depends_on = [
    module.network,
    module.parent_eks_ebs_csi_driver_addon,
    module.parent_eks_node_group,
  ]
}
# =========================================================================================================
# Member clusters - registered with Karmada, and where the demo workload's pods actually run
# =========================================================================================================
module "member_1_eks_cluster" {
  source = "./modules/eks_cluster"

  name                   = local.member_1_cluster_name
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  depends_on = [module.network]
}
module "member_1_eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.member_1_eks_cluster.cluster_name

  depends_on = [module.network, module.member_1_eks_cluster]
}
module "member_1_eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.member_1_eks_cluster.cluster_name

  depends_on = [module.network, module.member_1_eks_cluster]
}
module "member_1_eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name    = module.member_1_eks_cluster.cluster_name
  node_group_name = "${local.member_1_cluster_name}-nodes"
  instance_types  = var.node_instance_types
  desired_size    = var.member_node_count
  min_size        = var.member_node_count
  max_size        = var.node_max_count
  subnet_ids      = module.network.private_subnet_ids
  key_name        = module.key_pair.key_name

  depends_on = [
    module.network,
    module.member_1_eks_vpc_cni_addon,
    module.member_1_eks_kube_proxy_addon,
  ]
}
module "member_1_eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.member_1_eks_cluster.cluster_name

  depends_on = [module.network, module.member_1_eks_node_group]
}
module "member_2_eks_cluster" {
  source = "./modules/eks_cluster"

  name                   = local.member_2_cluster_name
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  depends_on = [module.network]
}
module "member_2_eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.member_2_eks_cluster.cluster_name

  depends_on = [module.network, module.member_2_eks_cluster]
}
module "member_2_eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.member_2_eks_cluster.cluster_name

  depends_on = [module.network, module.member_2_eks_cluster]
}
module "member_2_eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name    = module.member_2_eks_cluster.cluster_name
  node_group_name = "${local.member_2_cluster_name}-nodes"
  instance_types  = var.node_instance_types
  desired_size    = var.member_node_count
  min_size        = var.member_node_count
  max_size        = var.node_max_count
  subnet_ids      = module.network.private_subnet_ids
  key_name        = module.key_pair.key_name

  depends_on = [
    module.network,
    module.member_2_eks_vpc_cni_addon,
    module.member_2_eks_kube_proxy_addon,
  ]
}
module "member_2_eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.member_2_eks_cluster.cluster_name

  depends_on = [module.network, module.member_2_eks_node_group]
}
# =========================================================================================================
# Karmada
# =========================================================================================================
# The load balancer comes first, before the certificates and before the control plane, and the order is
# forced rather than chosen: its DNS name has to be a SAN on the certificate that the chart is then
# installed with. The guidance script had the same ordering problem and solved it the other way round - it
# created the Service, waited for the load balancer to go active, then ran `ping` on its DNS name to scrape
# an IP address out of the output and passed that to karmada init.
module "karmada_api_load_balancer" {
  source = "./modules/karmada_api_load_balancer"

  vpc_id   = module.network.vpc_id
  internal = false
  # Public subnets, because the scheme is internet-facing - which it has to be for the kubectl provider
  # aimed at the Karmada API server to reach it from outside the VPC. See the module's internal variable for
  # what that exposes and what the alternative costs.
  subnet_ids = module.network.public_subnet_ids
  # The parent cluster's nodes are the targets, registered through their Auto Scaling group so that replaced
  # nodes re-register themselves.
  autoscaling_group_name = module.parent_eks_node_group.autoscaling_group_name
  # The EKS cluster security group, which EKS attaches to managed nodes itself. The module adds the rule
  # opening the node port to it, as a standalone rule rather than an inline block, because EKS adds its own
  # rules to this group (rules.md F-2).
  node_security_group_id = module.parent_eks_cluster.cluster_security_group_id
  ingress_cidr_block     = module.network.vpc_cidr_block
  port                   = var.karmada_api_port
  name_prefix            = "karm-"

  depends_on = [module.network, module.parent_eks_node_group]
}
module "karmada_certificates" {
  source = "./modules/karmada_certificates"

  namespace = var.karmada_namespace
  # The load balancer's own name, and the wildcard the guidance script used for the same purpose through
  # `kubectl karmada init --cert-external-dns "*.elb.<region>.amazonaws.com"`. The wildcard alone would be
  # enough - a Network Load Balancer's name is one label under elb.<region>.amazonaws.com - but naming the
  # load balancer explicitly makes the certificate self-describing, so a client that cannot verify it can be
  # diagnosed by reading the SANs rather than by reasoning about wildcards.
  external_dns_names = [
    module.karmada_api_load_balancer.dns_name,
    "*.elb.${data.aws_region.current.region}.amazonaws.com",
  ]

  depends_on = [module.network]
}
module "karmada_control_plane" {
  source    = "./modules/karmada_control_plane"
  providers = { helm = helm.parent }

  namespace             = var.karmada_namespace
  chart_version         = var.karmada_chart_version
  karmada_image_version = var.karmada_image_version
  apiserver_replicas    = var.karmada_apiserver_replicas
  etcd_replicas         = var.etcd_replicas
  etcd_volume_size      = var.etcd_volume_size
  # Both taken from the modules that own them rather than from the variables directly, so the class the
  # claim names is the class that was created and the nodePort the Service publishes is the port the
  # listener forwards to (rules.md B-5).
  etcd_storage_class_name = module.parent_ebs_storage_class.name
  node_port               = module.karmada_api_load_balancer.port
  timeout_seconds         = var.karmada_control_plane_timeout_seconds

  ca_cert_pem                 = module.karmada_certificates.ca_cert_pem
  ca_private_key_pem          = module.karmada_certificates.ca_private_key_pem
  cert_pem                    = module.karmada_certificates.cert_pem
  private_key_pem             = module.karmada_certificates.private_key_pem
  front_proxy_ca_cert_pem     = module.karmada_certificates.front_proxy_ca_cert_pem
  front_proxy_cert_pem        = module.karmada_certificates.front_proxy_cert_pem
  front_proxy_private_key_pem = module.karmada_certificates.front_proxy_private_key_pem

  # CoreDNS is the one that is easy to leave out and expensive to debug: the control plane's components find
  # each other by Service name, so without it the apiserver never resolves etcd and the release stalls in
  # init containers with no certificate or volume problem to find (rules.md D-2).
  depends_on = [
    module.network,
    module.parent_eks_coredns_addon,
    module.parent_ebs_storage_class,
    module.karmada_api_load_balancer,
  ]
}
module "member_1_karmada_agent" {
  source    = "./modules/karmada_member_agent"
  providers = { helm = helm.member_1 }

  cluster_name     = module.member_1_eks_cluster.cluster_name
  cluster_endpoint = module.member_1_eks_cluster.cluster_endpoint
  namespace        = var.karmada_namespace

  karmada_api_endpoint    = module.karmada_api_load_balancer.endpoint
  karmada_ca_cert_pem     = module.karmada_certificates.ca_cert_pem
  karmada_cert_pem        = module.karmada_certificates.cert_pem
  karmada_private_key_pem = module.karmada_certificates.private_key_pem

  chart_version         = var.karmada_chart_version
  karmada_image_version = var.karmada_image_version
  timeout_seconds       = var.karmada_agent_timeout_seconds

  # The control plane has to be answering before the agent can register, and this member's own CoreDNS has
  # to be up before the agent pod can resolve anything at all - including the load balancer's name
  # (rules.md D-2).
  #
  # The same edge is what makes `terraform destroy` work: the agent is removed while the control plane is
  # still running, so the Cluster object it created is cleaned up rather than left behind for a control plane
  # that is being torn down (rules.md D-4).
  depends_on = [
    module.network,
    module.member_1_eks_coredns_addon,
    module.karmada_control_plane,
  ]
}
module "member_2_karmada_agent" {
  source    = "./modules/karmada_member_agent"
  providers = { helm = helm.member_2 }

  cluster_name     = module.member_2_eks_cluster.cluster_name
  cluster_endpoint = module.member_2_eks_cluster.cluster_endpoint
  namespace        = var.karmada_namespace

  karmada_api_endpoint    = module.karmada_api_load_balancer.endpoint
  karmada_ca_cert_pem     = module.karmada_certificates.ca_cert_pem
  karmada_cert_pem        = module.karmada_certificates.cert_pem
  karmada_private_key_pem = module.karmada_certificates.private_key_pem

  chart_version         = var.karmada_chart_version
  karmada_image_version = var.karmada_image_version
  timeout_seconds       = var.karmada_agent_timeout_seconds

  depends_on = [
    module.network,
    module.member_2_eks_coredns_addon,
    module.karmada_control_plane,
  ]
}
# A pause between the agents being installed and the demo workload being created, and the one resource here
# that is a timer rather than a signal. It is worth explaining at length because a sleep in a Terraform
# configuration is normally a sign that something was not understood, and because what it fixes was measured
# rather than guessed.
#
# What goes wrong without it. helm_release with wait = true returns when the agent's Deployment is
# Available, which is when its pod is Ready. Registering the cluster is what the agent does next: it creates
# the Cluster object on the Karmada API server and then reports status, and only that report sets the Ready
# condition. Karmada's scheduler considers Ready clusters only. So there is a gap between "the agent module
# has finished" - which is all depends_on can wait for - and "this cluster can be scheduled onto".
#
# The gap is small, and that is exactly why it bites. Measured on the first successful apply of this
# configuration:
#
#   20:46:37  karmada-member-1 Cluster created
#   20:46:37  ResourceBinding for karmada-demo-nginx created   <- scheduled here
#   20:46:39  karmada-member-1 Ready
#   20:46:39  karmada-member-2 Cluster created, Ready
#
# The binding was computed two seconds before the second cluster existed, so the scheduler divided four
# replicas across the one cluster it could see and gave karmada-member-1 all four. Nothing failed: the
# Deployment reported 4/4 ready, both clusters came up Ready moments later, and `kubectl get clusters` looked
# perfect. Only the per-cluster split was wrong, and only the ResourceBinding shows it - which is why that
# command is in the outputs. Karmada does not rebalance a Divided binding when a cluster joins later.
#
# Why this is a timer. The condition to wait for is the Ready condition on an object Terraform does not
# manage, on an API server it reaches through a provider with no data source for reading arbitrary objects -
# alekc/kubectl has none, and hashicorp/kubernetes cannot be configured in this root at all (rules.md E-2).
# kubectl_manifest's wait_for only watches the object the resource itself creates, so it cannot be pointed at
# a Cluster the agent owns. There is no signal available to wait on, so what is left is a bounded wait that
# is generous against a two-second gap.
#
# rules.md D-5 rejects timeouts in place of a completion signal, and that still holds wherever a signal
# exists - the marker files on the workbench are that argument. This is the case where one does not.
resource "time_sleep" "karmada_member_registration" {
  create_duration = "${var.member_registration_wait_seconds}s"

  # Re-waits if the set of member clusters changes, rather than being a one-off that a later apply skips.
  triggers = {
    member_clusters = join(",", local.member_cluster_names)
  }

  depends_on = [
    module.member_1_karmada_agent,
    module.member_2_karmada_agent,
  ]
}
# The demo workload, and the only thing in this configuration that proves the rest of it worked. It is
# applied to the Karmada API server through the load balancer, which is the one provider in this root that
# authenticates with a client certificate rather than with aws eks get-token.
module "karmada_demo_workload" {
  source    = "./modules/karmada_demo_workload"
  providers = { kubectl = kubectl.karmada }

  # Taken from the agent modules rather than rebuilt from the prefix, so the policy cannot name a cluster
  # that was never registered - which is not an error Karmada reports: the policy is accepted and simply
  # schedules nothing (rules.md B-5).
  member_cluster_names = local.member_cluster_names
  replicas             = var.demo_replicas
  image_tag            = var.demo_image_tag

  # The agents for the destroy ordering, and the wait above for the create ordering. Both are needed and
  # they are not the same edge:
  #
  #   the agent modules make `terraform destroy` remove this workload while the agents are still running,
  #   so Karmada can unbind it from the members (rules.md D-4);
  #
  #   the time_sleep makes the scheduler see both clusters as Ready before it divides the replicas. Without
  #   it the apply succeeds with every replica on whichever cluster registered first - see the measured
  #   timeline on that resource.
  depends_on = [
    module.network,
    module.member_1_karmada_agent,
    module.member_2_karmada_agent,
    time_sleep.karmada_member_registration,
  ]
}
# =========================================================================================================
# Workbench
# =========================================================================================================
# Access for the workbench's instance role on all three clusters, declared here rather than inside either
# module: the cluster modules do not know who should be allowed in, and the instance module does not know
# that any cluster exists (rules.md C-1).
resource "aws_eks_access_entry" "vscode" {
  for_each = local.cluster_names

  cluster_name  = each.value
  principal_arn = module.vscode_ec2.iam_role_arn
  type          = "STANDARD"
}
resource "aws_eks_access_policy_association" "vscode" {
  for_each = local.cluster_names

  cluster_name  = each.value
  principal_arn = module.vscode_ec2.iam_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.vscode]
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name      = "vscode"
  vpc_id    = module.network.vpc_id
  subnet_id = module.network.public_subnet_ids[0]
  key_name  = module.key_pair.key_name
  # All three clusters' primary security groups, on top of the one the module creates for code-server. The
  # instance therefore carries four.
  #
  # What this buys. EKS attaches the cluster security group to its own managed network interfaces and to
  # managed nodes, and the group permits all traffic from itself. Being a member of it is what lets this
  # instance reach a cluster's private API server endpoint and talk to its nodes and pods directly, rather
  # than only over the public endpoint. With three clusters there are three such groups and no relationship
  # between them, so membership has to be granted three times - one cluster's group says nothing about
  # another's.
  #
  # Injected as IDs rather than looked up. The module has no idea these are EKS cluster groups, or that
  # there are three, or that a Karmada control plane is involved; it concatenates whatever it is handed onto
  # its own group. Connecting the two modules is the root's job (rules.md B-6/C-1).
  #
  # The reference also fixes the destroy order, which is the part worth not losing. Attaching an
  # EKS-managed group to an instance Terraform owns puts a reference on a group EKS deletes as part of
  # deleting the cluster; if the instance still held it, that deletion would be refused with a
  # DependencyViolation and the cluster would be left half-removed. Reading the IDs here makes this module
  # depend on all three clusters, so destroy takes the instance down first. Nothing else in this root
  # expresses that - depends_on = [module.network] alone would let them go in either order.
  extra_security_group_ids = [
    module.parent_eks_cluster.cluster_security_group_id,
    module.member_1_eks_cluster.cluster_security_group_id,
    module.member_2_eks_cluster.cluster_security_group_id,
  ]
  # Amazon Linux 2023, as the _monolithic template used, and the module is the AL2023 one that goes with
  # it - dnf, ec2-user, /home/ec2-user.
  #
  # It was not, until this was found the hard way. This project's modules/vscode_ec2 was a copy of
  # 066_ai_comfyui_on_eks's, which is deliberately Ubuntu - that blueprint ships an env_prepare.sh written
  # for apt - while the root passed it this AL2023 parameter. The module's own variable description said the
  # two were not interchangeable and nothing enforced it, so the bootstrap ran apt-get on Amazon Linux,
  # every package install failed, code-server was never downloaded, and because the script runs under set -x
  # rather than set -e it carried on to the end and created its marker file anyway. The apply succeeded. The
  # instance had no IDE on it.
  ami_ssm_parameter_name      = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  instance_type               = var.instance_type
  root_volume_size            = var.root_volume_size
  security_group_name         = "${var.cluster_name_prefix}-vscode-sg"
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  marker_file_path            = var.marker_file_path
  # AdministratorAccess, as the _monolithic template attached. It is worth re-reading now that this instance
  # no longer builds anything: it is a place to run kubectl and read a Karmada kubeconfig out of Parameter
  # Store, which needs far less. It is kept because this is a teaching workbench and narrowing it to the
  # point where every demo command still works is a project of its own - but the honest note is that
  # rules.md A-5 is about not widening IAM during a conversion, and this is inherited width rather than new
  # width. code-server in front of it has no authentication.
  iam_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"]

  # kubectl, eksctl, helm and docker, all four, because this root declares EKS clusters alongside the
  # workbench (rules.md H-1). An earlier version of this configuration left docker out on the grounds that
  # no cluster resource existed here - that is no longer true.
  #
  # What these are for has changed, and it is worth being clear about: they are for inspecting and
  # demonstrating, not for building. Nothing in this bootstrap creates a Kubernetes object any more. The
  # Karmada control plane, the agents, the StorageClass and the demo workload are all Terraform resources,
  # and the whole deployment script this instance used to run is gone (rules.md E-1, and H-1's note that
  # having the tools installed is not a licence to create resources with them).
  #
  # Bugs from the _monolithic template that are not carried over:
  #
  #   It ran "exec bash" partway through. That replaces the shell, so every remaining line was discarded -
  #   eksctl, helm, the git clone, the etcd patch and the entire Karmada deployment were all after it. On a
  #   real boot the instance came up with kubectl and nothing else, and the project did nothing at all.
  #
  #   Its heredoc was unquoted ("<< EOF" rather than "<< 'EOF'"), so $PATH and $(uname -s) were expanded by
  #   root's shell before the block was handed to ec2-user - which baked root's PATH into ec2-user's .bashrc.
  #
  #   It pulled eksctl from weaveworks rather than eksctl-io.
  #
  #   It wrote the "complete" line for the k alias into .bashrc before the line that defines __start_kubectl,
  #   so every login printed a "function not found" error (rules.md H-1).
  additional_user_data = <<-EOT
    dnf install -yq bind-utils jq unzip tar gzip

    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server is already running by the time usermod adds the group, so its session does not have it.
    # Restarting is what makes the docker socket usable from the IDE terminal - opening /var/run/docker.sock
    # to 666 would also work and is not done here.
    systemctl restart code-server

    sudo -Eu ec2-user bash << 'EOF'
    set -euo pipefail
    export HOME=/home/ec2-user
    cd /home/ec2-user
    mkdir -p /home/ec2-user/bin
    curl -sO https://s3.us-west-2.amazonaws.com/amazon-eks/${var.kubectl_download_version}/bin/linux/amd64/kubectl
    chmod +x kubectl
    mv kubectl /home/ec2-user/bin/kubectl
    export PATH=/home/ec2-user/bin:$PATH
    echo 'export PATH=/home/ec2-user/bin:$PATH' >> ~/.bashrc
    # Order matters: kubectl's completion defines __start_kubectl, and that has to exist before complete
    # names it, or every login prints "function not found" (rules.md H-1).
    echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
    echo 'source <(kubectl completion bash)' >> ~/.bashrc
    echo 'alias k=kubectl' >> ~/.bashrc
    echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
    # Two files, colon-separated, which kubectl merges into one view. The EKS clusters are reached through
    # the first and the Karmada API server through the second, so `kubectl config get-contexts` lists all
    # four and switching between them is `kubectl config use-context`. The guidance script instead pointed
    # KUBECONFIG at the Karmada file alone, which left the member clusters reachable only by passing
    # --kubeconfig on every command.
    echo 'export KUBECONFIG=${local.kube_config_path}:${local.karmada_config_path}' >> ~/.bashrc
    PLATFORM=$(uname -s)_amd64
    curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
    tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
    sudo install -m 0755 /tmp/eksctl /usr/local/bin && rm /tmp/eksctl
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm get_helm.sh
    aws configure set default.region ${data.aws_region.current.region}
    EOF
  EOT

  # network only, and the three clusters are reached by value reference instead - which looks like the thing
  # rules.md D-3 argues against, so it is worth saying why a reference is enough here. D-3 exists because
  # module.network.vpc_id orders this module after one aws_vpc and says nothing about the NAT gateway or the
  # route tables, which are never outputs. The cluster security group is not like that: it is an attribute of
  # aws_eks_cluster itself, so reading it orders this module against the very resource whose deletion would
  # otherwise collide with the attachment.
  depends_on = [module.network]
}
# The Karmada credentials, carried to the workbench through Parameter Store rather than through the SSM
# Association that assembles them into a kubeconfig.
#
# The association would be the shorter route, and it is the wrong one: an association's parameters are
# stored by SSM in plaintext and readable with `aws ssm describe-association`, so putting a cluster-admin
# private key there publishes it to anyone with read access to Systems Manager. A SecureString parameter is
# encrypted at rest, and the association below only carries the commands that fetch it.
#
# This is the same reasoning rules.md H-2 applies to the README: a value that needs sensitive = true does not
# belong in a file the workbench writes, and what goes in its place is the command to retrieve it.
#
# Three parameters, one PEM each, rather than one parameter holding a finished kubeconfig - and that is a
# size limit rather than a preference. A kubeconfig embeds its certificates base64-encoded, which adds a
# third to each one, and with 3072-bit keys the result is around 7.5 KB. A Standard tier parameter holds
# 4 KB; Advanced holds 8 KB, costs money per parameter per month, and would leave no room for a larger key.
# Split up, the largest of the three is the private key at roughly 2.5 KB, so all three fit in Standard with
# room to spare. The association then builds the kubeconfig with `kubectl config`, which is also what leaves
# a pki directory next to it - the same layout `kubectl karmada init --karmada-pki` produced.
#
# Separate resources rather than for_each over a map of the three PEMs: two of the three values are marked
# sensitive, which would make the whole map sensitive, and Terraform refuses a sensitive for_each.
resource "aws_ssm_parameter" "karmada_ca_certificate" {
  name        = "${local.karmada_parameter_prefix}/ca.crt"
  description = "Karmada server CA certificate for ${local.parent_cluster_name}"
  type        = "SecureString"
  value       = module.karmada_certificates.ca_cert_pem

  depends_on = [module.network]
}
resource "aws_ssm_parameter" "karmada_client_certificate" {
  name        = "${local.karmada_parameter_prefix}/karmada.crt"
  description = "Karmada cluster-admin client certificate for ${local.parent_cluster_name}"
  type        = "SecureString"
  value       = module.karmada_certificates.cert_pem

  depends_on = [module.network]
}
resource "aws_ssm_parameter" "karmada_client_key" {
  name        = "${local.karmada_parameter_prefix}/karmada.key"
  description = "Private key for the Karmada cluster-admin client certificate of ${local.parent_cluster_name}"
  type        = "SecureString"
  value       = module.karmada_certificates.private_key_pem

  depends_on = [module.network]
}
# Two associations rather than one, because they do different things and the second has to be able to say
# that the first has happened. Order between them is the marker file and the until loop, not depends_on:
# wait_for_success_timeout_seconds does not reliably wait for the remote command to finish (rules.md D-5).
resource "aws_ssm_association" "vscode_kubeconfig" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.workbench_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The marker path comes back out of the module it was passed into, so the path is defined once
    # (rules.md B-5).
    #
    # A bounded wait rather than a bare `until ... sleep`, which is what this was and what cost an apply.
    # An unbounded loop turns every reason the marker is missing - a bootstrap that failed, a bootstrap
    # that was edited and never re-ran, a marker on a tmpfs that a restart cleared - into the same
    # symptom: the command runs forever, the association sits at Pending, and Terraform gives up after
    # thirty minutes with a message naming only the association's own UUID. Giving up here instead means
    # SSM reports Failed and these two lines are in the invocation's standard error, which is the
    # difference between a UUID and a sentence (rules.md D-5 keeps the marker; this only adds a ceiling).
    commands = <<-EOT
      deadline=$(( $(date +%s) + ${var.marker_wait_timeout_seconds} ))
      until [ -f ${module.vscode_ec2.marker_file_path}/userdata ]; do
        if [ "$(date +%s)" -ge "$deadline" ]; then
          echo "gave up after ${var.marker_wait_timeout_seconds}s waiting for ${module.vscode_ec2.marker_file_path}/userdata" >&2
          echo "the instance bootstrap never reached its end - read /var/log/cloud-init-output.log on this instance" >&2
          exit 1
        fi
        sleep 10
      done
      sudo -Eu ec2-user bash << 'STEP'
      set -euo pipefail
      export HOME=/home/ec2-user
      export PATH=/home/ec2-user/bin:$PATH
      install -d -m 700 /home/ec2-user/.kube
      install -d -m 700 ${local.karmada_config_dir}
      # One context per cluster, aliased to the cluster's own name so that `kubectl config get-contexts`
      # reads as parent / member-1 / member-2 rather than as three ARNs.
      aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.parent_eks_cluster.cluster_name} --alias ${module.parent_eks_cluster.cluster_name} --kubeconfig ${local.kube_config_path}
      aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.member_1_eks_cluster.cluster_name} --alias ${module.member_1_eks_cluster.cluster_name} --kubeconfig ${local.kube_config_path}
      aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.member_2_eks_cluster.cluster_name} --alias ${module.member_2_eks_cluster.cluster_name} --kubeconfig ${local.kube_config_path}
      # The Karmada credentials are fetched rather than written inline, so the private key never appears in
      # this association's parameters - see the SecureString parameters above. umask first, so the files
      # are created 600 rather than being widened and narrowed again.
      umask 077
      install -d -m 700 ${local.karmada_pki_dir}
      aws ssm get-parameter --region ${data.aws_region.current.region} --name ${aws_ssm_parameter.karmada_ca_certificate.name} --with-decryption --query Parameter.Value --output text > ${local.karmada_pki_dir}/ca.crt
      aws ssm get-parameter --region ${data.aws_region.current.region} --name ${aws_ssm_parameter.karmada_client_certificate.name} --with-decryption --query Parameter.Value --output text > ${local.karmada_pki_dir}/karmada.crt
      aws ssm get-parameter --region ${data.aws_region.current.region} --name ${aws_ssm_parameter.karmada_client_key.name} --with-decryption --query Parameter.Value --output text > ${local.karmada_pki_dir}/karmada.key
      # Built with kubectl config rather than written as a document, which is what keeps the three PEMs in
      # separate parameters small enough for Standard tier. --embed-certs puts them into the file as well,
      # so the result is self-contained and the pki directory is a copy rather than a dependency.
      rm -f ${local.karmada_config_path}
      kubectl config --kubeconfig ${local.karmada_config_path} set-cluster ${local.karmada_context_name} --server=${module.karmada_api_load_balancer.endpoint} --certificate-authority=${local.karmada_pki_dir}/ca.crt --embed-certs=true
      kubectl config --kubeconfig ${local.karmada_config_path} set-credentials ${local.karmada_context_name} --client-certificate=${local.karmada_pki_dir}/karmada.crt --client-key=${local.karmada_pki_dir}/karmada.key --embed-certs=true
      kubectl config --kubeconfig ${local.karmada_config_path} set-context ${local.karmada_context_name} --cluster=${local.karmada_context_name} --user=${local.karmada_context_name}
      kubectl config --kubeconfig ${local.karmada_config_path} use-context ${local.karmada_context_name}
      chmod 600 ${local.karmada_config_path}
      # Proves the whole chain in one call: the load balancer is reachable, the certificate verifies, and
      # the client certificate authenticates as something that can read Karmada's own API group. If this
      # fails, the step fails here rather than leaving a kubeconfig that looks fine and does not work.
      kubectl --kubeconfig ${local.karmada_config_path} get clusters
      STEP
      touch ${module.vscode_ec2.marker_file_path}/vscode_kubeconfig
      EOT
  }

  # The access entries, not the clusters: update-kubeconfig succeeds without them and then every kubectl
  # command fails with "You must be logged in to the server", which looks like a cluster problem rather than
  # a permissions one (rules.md C-1/D-2).
  depends_on = [
    module.vscode_ec2,
    aws_eks_access_policy_association.vscode,
    module.karmada_demo_workload,
  ]
}
locals {
  # Every output this project exposes, defined once. outputs.tf projects these and the README below renders
  # them, so no value expression is written twice and an output cannot be added without also appearing in
  # that README (rules.md B-5/H-2).
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here. Every command below is meant to be run in its terminal, where KUBECONFIG already names both the three EKS clusters and the Karmada API server - switch between them with kubectl config use-context"
      value       = module.vscode_ec2.vscode_url
    }
    what_terraform_manages = {
      order       = 2
      title       = "What Terraform manages"
      description = "All of it, which is the change this configuration represents. The three clusters, their node groups and addons, the Karmada control plane, both member registrations and the demo workload are Terraform resources - terraform destroy removes them. The previous version of this project ran the guidance installer from this instance instead, which left three EKS clusters running after a destroy and needed the installer's own teardown flag to remove them"
      value       = "VPC ${module.network.vpc_id}\nclusters ${module.parent_eks_cluster.cluster_name}, ${module.member_1_eks_cluster.cluster_name}, ${module.member_2_eks_cluster.cluster_name}\nKarmada ${module.karmada_control_plane.chart_version} (images ${module.karmada_control_plane.karmada_image_version}) in namespace ${module.karmada_control_plane.namespace}\nworkbench ${module.vscode_ec2.instance_id}"
    }
    karmada_api_endpoint = {
      order       = 3
      title       = "Karmada API server endpoint"
      description = "The address every piece of this configuration is arranged around: the certificate carries it as a SAN, both member agents connect to it, and the Terraform provider that created the demo workload used it as its host. It is internet-facing - authenticated only by a client certificate - because that provider runs outside the VPC"
      value       = module.karmada_api_load_balancer.endpoint
    }
    karmada_credentials_command = {
      order       = 4
      title       = "1. The Karmada credentials"
      description = "Already assembled into ${local.karmada_config_path} on the workbench, so nothing needs to be run there. This is how to fetch them elsewhere - three PEMs rather than a finished kubeconfig, because an embedded one exceeds a Standard tier parameter. They amount to cluster-admin on the Karmada API server, which is why they are SecureStrings and why the values are not in this output or in the workbench's README (rules.md H-2)"
      value       = "aws ssm get-parameters-by-path --path ${local.karmada_parameter_prefix} --with-decryption --query 'Parameters[].Name' --output table"
    }
    member_clusters_command = {
      order       = 5
      title       = "2. Ask Karmada which clusters it manages"
      description = "The check that the deployment worked. Expect both members Ready, with MODE reading Pull - the guidance installer's karmadactl join produced Push instead, and the difference is which side opens the connection rather than what Karmada can do with the cluster (see modules/karmada_member_agent)"
      value       = "kubectl --kubeconfig ${local.karmada_config_path} get clusters"
    }
    propagation_policy_command = {
      order       = 6
      title       = "3. Read the propagation policy"
      description = "A PropagationPolicy is how Karmada decides which member clusters a workload lands on. This one divides the demo Deployment's replicas between the two members at equal weight, which is what the installer's sample-propagation policy did"
      value       = "kubectl --kubeconfig ${local.karmada_config_path} -n default get propagationpolicy ${module.karmada_demo_workload.propagation_policy_name} -o yaml"
    }
    aggregate_workload_command = {
      order       = 7
      title       = "4. Look at the workload through Karmada"
      description = "The Deployment as the Karmada API server sees it. The replica counts here are collected from the member clusters - no pod runs on this API server, and nothing on the parent cluster runs nginx at all"
      value       = "kubectl --kubeconfig ${local.karmada_config_path} -n default get deployment ${module.karmada_demo_workload.deployment_name} -o wide"
    }
    scheduling_decision_command = {
      order       = 8
      title       = "5. See how the replicas were divided"
      description = "The scheduler's actual decision, cluster by cluster. ${module.karmada_demo_workload.expected_replicas_per_cluster}. This is also where a policy that matched nothing shows up: no ResourceBinding means the Deployment was never governed by any policy"
      value       = "kubectl --kubeconfig ${local.karmada_config_path} -n default get resourcebinding ${module.karmada_demo_workload.deployment_name}-deployment -o jsonpath='{range .spec.clusters[*]}{.name}{\"=\"}{.replicas}{\"  \"}{end}{\"\\n\"}'"
    }
    member_workload_command = {
      order       = 9
      title       = "6. Find the pods in a member cluster"
      description = "Where the pods actually run. Compare the count against step 5 - that comparison is the whole demonstration, and it is the one thing a healthy-looking control plane with a broken policy will not satisfy"
      value       = "kubectl --context ${module.member_1_eks_cluster.cluster_name} -n default get pods -o wide"
    }
    karmada_control_plane_command = {
      order       = 10
      title       = "7. The control plane's own pods"
      description = "Karmada's components on the parent cluster. A pod stuck in its wait-for-etcd init container means etcd never got a volume, not that the component is broken - check the claim before the component"
      value       = "kubectl --context ${module.parent_eks_cluster.cluster_name} -n ${module.karmada_control_plane.namespace} get pods"
    }
    agent_logs_command = {
      order       = 11
      title       = "8. An agent's log, if a member never registers"
      description = "Read against the member cluster rather than the control plane. A TLS error means the Karmada certificate does not carry the load balancer's name as a SAN, a timeout means the member's nodes cannot reach that endpoint, and Forbidden means the client certificate's groups are wrong"
      value       = "kubectl --context ${module.member_1_eks_cluster.cluster_name} -n ${module.member_1_karmada_agent.namespace} logs deploy/${module.member_1_karmada_agent.release_name} --tail 50"
    }
    load_balancer_health_command = {
      order       = 12
      title       = "9. The load balancer's target health"
      description = "The first thing to read when the Karmada endpoint is unreachable but the control plane's pods are Running. All targets unhealthy means nothing is listening on the node port, which is the Service's nodePort not matching the listener - the two come from one variable here, so it should not happen"
      value       = module.karmada_api_load_balancer.target_health_command
    }
    certificate_command = {
      order       = 13
      title       = "10. The Karmada certificate's subject and SANs"
      description = "Reads the certificate back out of the cluster. Its Organization has to include system:masters, or it authenticates and can read nothing; its SANs have to include the load balancer's name, or no client outside the cluster can verify it. Both are generated by Terraform rather than by the chart - see modules/karmada_certificates for why"
      value       = "kubectl --context ${module.parent_eks_cluster.cluster_name} -n ${module.karmada_control_plane.namespace} get secret ${module.karmada_control_plane.release_name}-cert -o jsonpath='{.data.karmada\\.crt}' | base64 -d | openssl x509 -noout -subject -ext subjectAltName"
    }
    workbench_security_groups_command = {
      order       = 14
      title       = "11. The workbench's security groups"
      description = "Four expected: its own code-server group, plus the primary security group of each of the three clusters. Membership of a cluster's group is what lets this instance reach that cluster's private API endpoint and its nodes and pods directly. Worth a command rather than a value because the failure is silent - a missing group is not an error anywhere, it is kubectl timing out against one cluster while the other two answer"
      value       = "aws ec2 describe-instances --instance-ids ${module.vscode_ec2.instance_id} --query 'Reservations[].Instances[].SecurityGroups[].{Id:GroupId,Name:GroupName}' --output table"
    }
    private_key_command = {
      order       = 15
      title       = "The workbench's SSH private key"
      description = "Written to SSM Parameter Store as a SecureString, which is where CloudFormation puts a generated key pair's private half. Needed only for SSH - code-server is reached over HTTP"
      value       = "aws ssm get-parameter --name /ec2/keypair/${module.key_pair.key_pair_id} --with-decryption --query Parameter.Value --output text"
    }
  }
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  readme_body = join("\n", concat(
    ["# ${var.cluster_name_prefix} - EKS + Karmada", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}
# The work happens inside code-server in a browser, where terraform output is not available, so every output
# above is also written to a README in the home directory the IDE opens (rules.md H-2).
#
# The _monolithic template wrote a README too, with an echo whose message contained unescaped double quotes
# around a kubectl command - so the shell closed the string early and the file came out mangled.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.workbench_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # Waits for the kubeconfig step's marker, so the README lands once the commands in it are usable
    # (rules.md D-5), and gives up with a message rather than running forever - same reasoning as the
    # step above.
    commands = <<-EOT
      deadline=$(( $(date +%s) + ${var.marker_wait_timeout_seconds} ))
      until [ -f ${module.vscode_ec2.marker_file_path}/vscode_kubeconfig ]; do
        if [ "$(date +%s)" -ge "$deadline" ]; then
          echo "gave up after ${var.marker_wait_timeout_seconds}s waiting for ${module.vscode_ec2.marker_file_path}/vscode_kubeconfig" >&2
          echo "the kubeconfig step did not finish - read its result with aws ssm get-command-invocation" >&2
          exit 1
        fi
        sleep 10
      done
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_readme
      EOT
  }

  depends_on = [aws_ssm_association.vscode_kubeconfig]
}
