# Resolve the public IPv4 address of the machine running Terraform once at the root. The child security
# group modules are ordered after other modules, so putting this plan-time read inside them could defer it
# until apply; passing only the resulting CIDR also keeps the modules independent of the lookup service
# (rules.md B-6/D-6).
data "http" "my_ip" {
  url = var.my_ip_lookup_url

  lifecycle {
    postcondition {
      condition = (
        self.status_code == 200 &&
        can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$", trimspace(self.response_body))) &&
        can(cidrhost("${trimspace(self.response_body)}/32", 0))
      )
      error_message = "my_ip_lookup_url must return HTTP 200 with one bare IPv4 address. Set it to a trusted HTTPS address-reflection endpoint reachable from the machine running Terraform."
    }
  }
}
locals {
  my_ip_cidr = "${trimspace(data.http.my_ip.response_body)}/32"
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# The blueprint's VPC: public subnets for the NAT gateway, the Grafana ALB and the workbench, RFC 1918
# private subnets, and data plane subnets in a secondary CIDR for the cluster, its nodes and its pods.
# modules/network/main.tf records the layout and the one place it departs from the blueprint.
module "network" {
  source = "./modules/network"

  region                        = data.aws_region.current.region
  name_prefix                   = var.network_name_prefix
  vpc_cidr_block                = var.vpc_cidr_block
  secondary_cidr_block          = var.secondary_cidr_block
  public_subnet_cidr_blocks     = var.public_subnet_cidr_blocks
  private_subnet_cidr_blocks    = var.private_subnet_cidr_blocks
  data_plane_subnet_cidr_blocks = var.data_plane_subnet_cidr_blocks
  # The AWS Load Balancer Controller discovers subnets by tag, and a scheme that does not match the tags
  # fails with "couldn't auto-discover subnets" (rules.md G-1). The blueprint's tags; its
  # karpenter.sh/discovery tag is not carried, because the Karpenter pools select subnets by ID.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

module "key_pair" {
  source = "./modules/key_pair"

  key_name = var.key_name

  # Nothing here reads a network output, but the root orders every module after the network so the
  # whole VPC - NAT gateway and route tables included - is finished before anything starts in it
  # (rules.md D-3).
  depends_on = [module.network]
}

# The control plane ENIs go in the data plane subnets only, as the blueprint placed them.
module "eks_cluster" {
  source = "./modules/eks_cluster"

  name                      = var.cluster_name
  kubernetes_version        = var.kubernetes_version
  subnet_ids                = module.network.data_plane_subnet_ids
  endpoint_public_access    = var.endpoint_public_access
  public_access_cidrs       = var.public_access_cidrs
  enabled_cluster_log_types = var.cluster_log_types

  depends_on = [module.network]
}

# vpc-cni and kube-proxy are DaemonSets, so they reach ACTIVE with zero nodes. They come before the node
# group because a node cannot join Ready without them, and with bootstrap_self_managed_addons = false
# nothing installs them otherwise (rules.md C-4).
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  depends_on = [module.network, module.eks_cluster]
}

module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  depends_on = [module.network, module.eks_cluster]
}

# The blueprint's core node group. Everything that has to run before Karpenter can provision a node lands
# here - Karpenter itself, CoreDNS, the EBS CSI controller, the Strimzi operator, the load balancer
# controller - because a controller that provisions nodes cannot depend on the nodes it provisions.
module "eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name     = module.eks_cluster.cluster_name
  node_group_name  = var.core_node_group_name
  ami_type         = var.core_node_ami_type
  instance_types   = var.core_node_instance_types
  desired_size     = var.core_node_desired_size
  min_size         = var.core_node_min_size
  max_size         = var.core_node_max_size
  labels           = var.core_node_labels
  root_volume_size = var.core_node_root_volume_size
  # The data plane subnets, as the blueprint's node group inherited them from the cluster. No key pair:
  # the blueprint attached none, and the nodes carry AmazonSSMManagedInstanceCore for Session Manager.
  subnet_ids = module.network.data_plane_subnet_ids

  depends_on = [module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}

# coredns, the EBS CSI controller and metrics-server are Deployments, so unlike the DaemonSets they need
# schedulable node capacity to leave DEGRADED and become ACTIVE (rules.md C-4).
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name          = module.eks_cluster.cluster_name
  coredns_replica_count = var.coredns_replica_count

  depends_on = [module.network, module.eks_node_group]
}

module "eks_ebs_csi_driver_addon" {
  source = "./modules/eks_ebs_csi_driver_addon"

  cluster_name      = module.eks_cluster.cluster_name
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host

  depends_on = [module.network, module.eks_node_group]
}

module "eks_metrics_server_addon" {
  source = "./modules/eks_metrics_server_addon"

  cluster_name  = module.eks_cluster.cluster_name
  replica_count = var.metrics_server_replica_count

  depends_on = [module.network, module.eks_node_group]
}

# The default gp3 class every volume in this project is provisioned from - the Kafka pools' claims name
# no class at all. After the driver, so a claim made against it is provisioned rather than left Pending.
module "csi_storage_classes" {
  source = "./modules/csi_storage_classes"

  depends_on = [module.network, module.eks_node_group, module.eks_ebs_csi_driver_addon]
}

# Holds the EBS CSI driver in place for a while after the volume-owning namespaces are gone, on destroy
# only - creating it takes no time.
#
# Deleting the kafka and kube-prometheus-stack namespaces deletes their PersistentVolumeClaims, and wait =
# true on those namespaces holds terraform destroy until the claims are gone. The EBS volumes behind them
# are not gone yet: each one is deleted afterwards, asynchronously, by this driver, once the volume has
# detached from the node its pod ran on. The driver is the next thing destroy would remove, so without
# this the volumes can outlive the cluster - still billed, and with nothing left that remembers them.
# kafka_cluster and kube_prometheus_stack depend on this, so they are destroyed first, then this waits,
# then the driver goes.
resource "time_sleep" "ebs_volume_release" {
  destroy_duration = var.ebs_volume_release_wait

  depends_on = [module.eks_ebs_csi_driver_addon]
}

# The queue EventBridge sends spot interruption, rebalance, scheduled change and instance state change
# notices to, so Karpenter can drain a node before EC2 takes it. eks-blueprints-addons created it for the
# blueprint under this name (karpenter_enable_spot_termination).
module "karpenter_interruption_queue" {
  source = "./modules/karpenter_interruption_queue"

  name = "karpenter-${var.cluster_name}"

  depends_on = [module.network]
}

# Karpenter's controller, its IAM role and the node role its instances assume, in their own namespace as
# eks-blueprints-addons installed them. The pools are separate modules below.
module "karpenter" {
  source = "./modules/karpenter"

  cluster_name      = module.eks_cluster.cluster_name
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  chart_version     = var.karpenter_chart_version
  namespace         = var.karpenter_namespace
  create_namespace  = true
  # Both from the queue module, so the chart setting and the IAM grant name the same queue (rules.md B-5).
  interruption_queue_name = module.karpenter_interruption_queue.queue_name
  interruption_queue_arn  = module.karpenter_interruption_queue.queue_arn

  # The controller runs on the core node group, and its pods need DNS to reach the EKS, EC2 and SQS APIs.
  # Neither is expressed by a value reference (rules.md D-2).
  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}

# One module per pool. for_each over a map whose keys are literals in this configuration, so they are
# known at plan time and safe as resource addresses - the values inside (subnet IDs, the security group
# ID, the node role name) are what come from other modules (rules.md B-7/B-8).
module "karpenter_node_pool" {
  source   = "./modules/karpenter_node_pool"
  for_each = var.karpenter_node_pools

  name               = each.key
  node_iam_role_name = module.karpenter.node_role_name
  subnet_ids         = module.network.data_plane_subnet_ids
  # The cluster security group, which is what the core nodes and the control plane carry too.
  security_group_ids = [module.eks_cluster.cluster_security_group_id]

  instance_categories   = each.value.instance_categories
  node_architectures    = each.value.node_architectures
  capacity_types        = each.value.capacity_types
  node_labels           = each.value.node_labels
  instance_store_policy = each.value.instance_store_policy
  cpu_limit             = each.value.cpu_limit
  consolidation_policy  = each.value.consolidation_policy
  consolidate_after     = each.value.consolidate_after
  disruption_budgets    = each.value.disruption_budgets

  # The CRDs these instantiate ship with the Karpenter chart, so the release has to be installed first -
  # and on destroy, the pools and every node they launched are gone before the controller that would
  # terminate those nodes is uninstalled (rules.md D-2/D-4/D-7).
  depends_on = [module.network, module.karpenter]
}

module "strimzi_kafka_operator" {
  source = "./modules/strimzi_kafka_operator"

  chart_version = var.strimzi_chart_version
  # The blueprint's selector - kubernetes.io/os plus the core group's NodeGroupType - built from the node
  # group's own labels, so it cannot name a label the core nodes do not carry (rules.md B-5).
  node_selector = merge({ "kubernetes.io/os" = "linux" }, module.eks_node_group.labels)

  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}

module "kube_prometheus_stack" {
  source = "./modules/kube_prometheus_stack"

  cluster_name              = module.eks_cluster.cluster_name
  aws_region                = data.aws_region.current.region
  account_id                = data.aws_caller_identity.current.account_id
  partition                 = data.aws_partition.current.partition
  oidc_provider_arn         = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host          = module.eks_cluster.oidc_issuer_host
  chart_version             = var.kube_prometheus_stack_chart_version
  storage_class_name        = module.csi_storage_classes.storage_class_name
  prometheus_storage_size   = var.prometheus_storage_size
  enable_amazon_prometheus  = var.enable_amazon_prometheus
  grafana_admin_secret_name = "${var.cluster_name}-grafana"

  # Prometheus's volume needs the driver and the class. time_sleep.ebs_volume_release is what keeps the
  # driver installed until that volume is really deleted on destroy.
  depends_on = [
    module.network,
    module.eks_node_group,
    module.eks_coredns_addon,
    module.eks_ebs_csi_driver_addon,
    module.csi_storage_classes,
    time_sleep.ebs_volume_release,
  ]
}

module "kafka_cluster" {
  source = "./modules/kafka_cluster"

  namespace              = var.kafka_namespace
  cluster_name           = var.kafka_cluster_name
  kafka_version          = var.kafka_version
  metadata_version       = var.kafka_metadata_version
  controller_replicas    = var.kafka_controller_replicas
  broker_replicas        = var.kafka_broker_replicas
  controller_volume_size = var.kafka_controller_volume_size
  broker_volume_size     = var.kafka_broker_volume_size
  # The value comes out of the pool's own labels rather than being restated, so the affinity cannot name
  # a pool that does not exist - every Kafka pod would stay Pending with Karpenter provisioning nothing
  # (rules.md B-5).
  node_selector_key   = var.kafka_node_label_key
  node_selector_value = module.karpenter_node_pool[var.kafka_node_pool].node_labels[var.kafka_node_label_key]
  ready_timeout       = var.kafka_ready_timeout
  topics              = var.kafka_topics

  # Every one of these is a runtime dependency with no value reference behind it: the operator that
  # reconciles the resources, the pool that provisions their nodes, the driver and class their volumes
  # come from. On destroy the same edges delete the cluster while all of them are still running - the
  # Topic Operator removes its finalizers, Karpenter drains the nodes, the driver deletes the volumes
  # (rules.md D-4/D-7).
  depends_on = [
    module.network,
    module.eks_node_group,
    module.eks_coredns_addon,
    module.eks_ebs_csi_driver_addon,
    module.csi_storage_classes,
    module.strimzi_kafka_operator,
    module.karpenter_node_pool,
    time_sleep.ebs_volume_release,
  ]
}

# The PodMonitors and Grafana dashboards. Needs the PodMonitor CRD from kube-prometheus-stack and the
# kafka namespace the monitors live in.
module "kafka_monitoring" {
  source = "./modules/kafka_monitoring"

  kafka_namespace    = module.kafka_cluster.namespace
  operator_namespace = module.strimzi_kafka_operator.namespace
  grafana_namespace  = module.kube_prometheus_stack.namespace

  depends_on = [module.network, module.kube_prometheus_stack, module.kafka_cluster]
}

# The controller that turns the Grafana Ingress into an ALB. Its IRSA role and its Helm release stay in
# one module because they reference each other (rules.md C-2).
module "aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"

  cluster_name      = module.eks_cluster.cluster_name
  vpc_id            = module.network.vpc_id
  aws_region        = data.aws_region.current.region
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  chart_version     = var.load_balancer_controller_chart_version
  # Both pinned false by validation in variables.tf (rules.md G-2/G-4).
  enable_backend_security_group  = var.enable_backend_security_group
  enable_service_mutator_webhook = var.enable_service_mutator_webhook

  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}

# The Grafana ALB's frontend security group. Created here and handed to the controller by ID, so the
# inbound rules are reviewable in the plan rather than written by the controller (rules.md G-1).
module "grafana_alb_security_group" {
  source = "./modules/load_balancer_security_group"

  vpc_id      = module.network.vpc_id
  name        = var.grafana_alb_security_group_name
  description = "Frontend security group for the Grafana ALB the AWS Load Balancer Controller builds from the grafana Ingress"
  # The same value becomes the Ingress's listen-ports below, so the listener and the rule that admits it
  # cannot disagree (rules.md B-5).
  ports = {
    http = var.grafana_listener_port
  }
  allow_inbound_from_anywhere = var.grafana_allow_inbound_from_anywhere
  my_ip_cidr                  = local.my_ip_cidr
  ingress_cidr_blocks         = var.grafana_ingress_cidr_blocks
  # The workbench, which is what reaches the ALB when grafana_alb_scheme is internal. A literal key,
  # because the ID is another module's output and unknown until apply (rules.md B-8).
  ingress_source_security_groups = {
    vscode_ec2 = module.vscode_ec2.security_group_id
  }

  depends_on = [module.network]
}

# With a frontend security group named on the Ingress and no manage-backend-security-group-rules
# annotation, the controller writes no rule on the pod side at all, so this one is declared here. The
# target type is ip, so traffic arrives at Grafana's container port - not the Service port - on the
# cluster security group every node and pod carries (rules.md G-2).
resource "aws_vpc_security_group_ingress_rule" "grafana_alb_to_pods" {
  security_group_id            = module.eks_cluster.cluster_security_group_id
  description                  = "Grafana container port from the Grafana ALB frontend security group"
  ip_protocol                  = "tcp"
  from_port                    = module.kube_prometheus_stack.grafana_container_port
  to_port                      = module.kube_prometheus_stack.grafana_container_port
  referenced_security_group_id = module.grafana_alb_security_group.security_group_id
}

locals {
  grafana_ingress_annotations = {
    "alb.ingress.kubernetes.io/scheme" = var.grafana_alb_scheme
    # ip, so the ALB sends traffic straight to the Grafana pod. Works because the VPC CNI gives pods VPC
    # addresses, and it is the only target type whose pod-side rule Terraform can declare - instance
    # targets arrive on a NodePort Kubernetes picks (rules.md G-1/G-2).
    "alb.ingress.kubernetes.io/target-type"     = "ip"
    "alb.ingress.kubernetes.io/listen-ports"    = jsonencode([{ HTTP = var.grafana_listener_port }])
    "alb.ingress.kubernetes.io/security-groups" = module.grafana_alb_security_group.security_group_id
    # Grafana answers / with a 302 to /login, which the ALB's default success code of 200 counts as a
    # failure - every target would stay unhealthy. /api/health answers 200 without a session.
    "alb.ingress.kubernetes.io/healthcheck-path" = "/api/health"
  }
}

module "grafana_ingress" {
  source = "./modules/grafana_ingress"

  namespace    = module.kube_prometheus_stack.namespace
  service_name = module.kube_prometheus_stack.grafana_service_name
  service_port = module.kube_prometheus_stack.grafana_service_port
  annotations  = local.grafana_ingress_annotations

  # The controller's Ingress webhooks reject every Ingress until its Deployment is Available, and on
  # destroy it has to still be running to delete the ALB and drop the Ingress's finalizer
  # (rules.md D-4/D-7). The rule comes first so the targets are healthy as soon as they register.
  depends_on = [
    module.network,
    module.aws_load_balancer_controller,
    module.kube_prometheus_stack,
    aws_vpc_security_group_ingress_rule.grafana_alb_to_pods,
  ]
}

# The workbench, now inside the cluster's VPC. The previous version of this project gave it a VPC of its
# own, because the cluster's was built later by the nested Terraform run; there is one VPC now.
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name                        = var.instance_name
  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  key_name                    = module.key_pair.key_name
  instance_type               = var.instance_type
  root_volume_size            = var.root_volume_size
  code_server_version         = var.code_server_version
  security_group_name         = var.security_group_name
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  my_ip_cidr                  = local.my_ip_cidr
  marker_file_path            = var.marker_file_path
  # The cluster security group is what lets kubectl here reach the API server's private endpoint
  # without leaving the VPC. The module is handed an ID list and never learns what it belongs to
  # (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]
  # An EKS cluster and this instance share a root module, so the instance is that cluster's workbench and
  # carries all five tools, plus eks-node-viewer for watching the Karpenter nodes (rules.md H-1).
  #
  # None of them creates anything. The _monolithic template used this script to clone the blueprint, run
  # its install.sh and kubectl apply its manifests; all of that is provider resources now (rules.md E-1).
  # Four of its bootstrap bugs are fixed rather than carried over: an "exec bash" that discarded every
  # line after it, eksctl from the old weaveworks org, a complete line written before kubectl's
  # completion was sourced, and a README body hardcoded in user data (rules.md H-1/H-2).
  additional_user_data = <<-EOT
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server is already running and predates the docker group, so its terminals would not have it
    # without a restart.
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
    # Order matters: bash_completion first, then kubectl's own completion, which defines __start_kubectl,
    # and only then the complete line that references it (rules.md H-1).
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
    curl -sL -o eks-node-viewer https://github.com/awslabs/eks-node-viewer/releases/download/${var.eks_node_viewer_version}/eks-node-viewer_Linux_x86_64
    sudo install -m 0755 eks-node-viewer /usr/local/bin/eks-node-viewer
    rm -f eks-node-viewer
    aws configure set default.region ${data.aws_region.current.region}
    # Without this - and without the access entry below - kubectl is installed but every command answers
    # "You must be logged in to the server" (rules.md H-1).
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}
    EOF
  EOT

  depends_on = [module.network]
}

# Cluster admin for the workbench's role. In the root rather than in either module, so neither the
# cluster module nor the instance module has to know the other exists (rules.md C-1).
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
  # EKS rejects a policy association for a principal with no access entry yet, and the two resources
  # share only literal argument values, so nothing else orders them (rules.md D-1).
  depends_on = [aws_eks_access_entry.vscode_access_entry]
}

locals {
  kafka_namespace = module.kafka_cluster.namespace
  # The client image the producer and consumer run: the operator release's own build of the Kafka version
  # the brokers run, so the client and the cluster cannot drift apart. The _monolithic template pinned
  # quay.io/strimzi/kafka:0.43.0-kafka-3.8.0 against a 3.9.0 cluster.
  kafka_client_image = "quay.io/strimzi/kafka:${module.strimzi_kafka_operator.version}-kafka-${module.kafka_cluster.kafka_version}"
  demo_topic         = module.kafka_cluster.topic_names[0]
  # Any broker, found by label. The _monolithic template named cluster-broker-0, but with node pools the
  # pod names carry node IDs Strimzi assigns, and nothing guarantees a broker gets 0.
  broker_pod = "$(kubectl -n ${local.kafka_namespace} get pod -l ${module.kafka_cluster.broker_pod_selector} -o jsonpath='{.items[0].metadata.name}')"

  # Every output this project exposes, defined once. outputs.tf projects these and the README below
  # renders them, so no value expression is written twice (rules.md B-5/H-2). The map key is the output
  # name. An output that is not here cannot be declared, so none can be missing from the README.
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here; the commands below are meant for its terminal unless they say otherwise. code-server runs with no authentication and the instance role behind it is AdministratorAccess, so do not leave it reachable from the internet longer than the demo needs"
      value       = module.vscode_ec2.vscode_url
    }
    cluster_name = {
      order       = 2
      title       = "EKS cluster name"
      description = "Name of the EKS cluster this project built"
      value       = module.eks_cluster.cluster_name
    }
    update_kubeconfig_command = {
      order       = 3
      title       = "Point kubectl at the cluster"
      description = "The workbench's user data already ran this. Run it on your own machine to use kubectl from there"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
    cluster_nodes_command = {
      order       = 4
      title       = "1. Look at the nodes"
      description = "The core node group plus whatever Karpenter has launched, with the label each pool is selected by. Once the cluster is up there is one node per Kafka pod in the kafka pool"
      value       = "kubectl get nodes -L ${var.kafka_node_label_key},karpenter.sh/nodepool,karpenter.sh/capacity-type,node.kubernetes.io/instance-type,topology.kubernetes.io/zone"
    }
    node_pools_command = {
      order       = 5
      title       = "2. Look at the Karpenter pools"
      description = "The pools, their node classes and every NodeClaim Karpenter has made. A Kafka pod that stays Pending with no NodeClaim behind it points at the pool's requirements or limits"
      value       = "kubectl get nodepool,ec2nodeclass,nodeclaim -o wide"
    }
    kafka_pods_command = {
      order       = 6
      title       = "3. Look at the Kafka cluster"
      description = "The Kafka resource, its controller and broker pools, and their pods with the nodes they landed on - one node each"
      value       = module.kafka_cluster.pods_command
    }
    kafka_ready_command = {
      order       = 7
      title       = "4. Read the Kafka resource's conditions"
      description = "Ready=True is what terraform apply waited for. Anything else carries the operator's reason"
      value       = module.kafka_cluster.ready_command
    }
    list_topics_command = {
      order       = 8
      title       = "5. List the topics"
      description = "First the KafkaTopic resources this project declared, then what Kafka itself reports from inside a broker - which includes the internal topics Kafka and Cruise Control create"
      value       = "kubectl -n ${local.kafka_namespace} get kafkatopic && kubectl -n ${local.kafka_namespace} exec -it ${local.broker_pod} -c kafka -- /opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092"
    }
    producer_command = {
      order       = 9
      title       = "6a. Produce messages"
      description = "Run this in one terminal and the consumer below in another, then type lines here. The pod is removed when you exit"
      value       = "kubectl -n ${local.kafka_namespace} run kafka-producer -ti --image=${local.kafka_client_image} --rm=true --restart=Never -- bin/kafka-console-producer.sh --bootstrap-server ${module.kafka_cluster.bootstrap_server} --topic ${local.demo_topic}"
    }
    consumer_command = {
      order       = 10
      title       = "6b. Consume them"
      description = "--from-beginning, so lines produced before the consumer started show up too"
      value       = "kubectl -n ${local.kafka_namespace} run kafka-consumer -ti --image=${local.kafka_client_image} --rm=true --restart=Never -- bin/kafka-console-consumer.sh --bootstrap-server ${module.kafka_cluster.bootstrap_server} --topic ${local.demo_topic} --from-beginning"
    }
    rebalance_status_command = {
      order       = 11
      title       = "7a. Read the rebalance proposal"
      description = "Cruise Control's proposal for moving partitions between brokers. It is only a proposal: the resource reaches ProposalReady and stops there until it is approved"
      value       = "kubectl -n ${local.kafka_namespace} describe kafkarebalance ${module.kafka_cluster.rebalance_name}"
    }
    rebalance_approve_command = {
      order       = 12
      title       = "7b. Approve it"
      description = "Starts moving partitions as proposed. Annotate with strimzi.io/rebalance=refresh instead to have Cruise Control compute a new proposal first"
      value       = "kubectl -n ${local.kafka_namespace} annotate kafkarebalance ${module.kafka_cluster.rebalance_name} strimzi.io/rebalance=approve"
    }
    grafana_url_command = {
      order       = 13
      title       = "8. Read the Grafana address"
      description = "The ALB the AWS Load Balancer Controller built for the grafana Ingress. The load balancer is not a Terraform resource, so the cluster is the only place its address exists (rules.md G-1). An empty host means the controller has not reconciled the Ingress yet - kubectl -n kube-system logs deploy/aws-load-balancer-controller has the reason"
      value       = "echo http://$(kubectl -n ${module.kube_prometheus_stack.namespace} get ingress ${module.grafana_ingress.name} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'):${var.grafana_listener_port}"
    }
    grafana_password_command = {
      order       = 14
      title       = "9. Read the Grafana password"
      description = "The user name is admin. The password lives in Secrets Manager rather than in this README, so nothing writes it to this instance's disk. The Kafka dashboards are under Dashboards, fed by the PodMonitors this project created"
      value       = module.kube_prometheus_stack.grafana_password_command
    }
    amp_workspace_endpoint = {
      order       = 15
      title       = "Amazon Managed Prometheus endpoint"
      description = "The workspace Prometheus remote-writes to, which Grafana also has as its AMP data source"
      value       = coalesce(module.kube_prometheus_stack.amp_workspace_endpoint, "disabled (enable_amazon_prometheus = false)")
    }
    node_viewer_command = {
      order       = 16
      title       = "Watch the nodes"
      description = "A live view of node capacity and price, with each node's pool. The Kafka pods take a node each, so this is where their cost shows"
      value       = "eks-node-viewer --resources cpu,memory --extra-labels karpenter.sh/nodepool,${var.kafka_node_label_key}"
    }
    operator_log_command = {
      order       = 17
      title       = "Strimzi operator log"
      description = "Where a Kafka, KafkaNodePool, KafkaTopic or KafkaRebalance resource the operator cannot reconcile is explained"
      value       = module.strimzi_kafka_operator.operator_log_command
    }
    teardown_command = {
      order       = 18
      title       = "Tearing this down"
      description = "Run it from the machine that ran terraform apply - not from this IDE, which has no copy of the state and is itself destroyed. First delete anything made by hand: kubectl get kafkatopic -A should list only the topics in kafka_topics, because a topic created with kubectl keeps the Kafka namespace from ever finishing deleting, and an Ingress or LoadBalancer Service created by hand leaves its load balancer behind. Destroy waits on purpose for the topics, the Grafana ALB, every Karpenter node and the EBS volumes to go before the controllers that remove them are uninstalled"
      value       = "terraform destroy"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the order field and taking
  # values() - which returns a map's values ordered by key - makes the README read top to bottom while
  # the order stays decided by configuration.
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  readme_body = join("\n", concat(
    ["# ${module.eks_cluster.cluster_name}", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}

# The work happens inside code-server in a browser, where terraform output is not available, so every
# output above is also written to a README in the home directory the IDE opens (rules.md H-2).
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is what orders this after the
    # instance bootstrap, and the marker this command leaves behind is what a later association would
    # wait on (rules.md D-5). The marker path comes back out of the module it was passed into, so it is
    # defined in exactly one place (rules.md B-5).
    #
    # SSM runs as root, hence the chown. The heredoc delimiter is quoted and unlikely to appear in the
    # body: Terraform has already substituted every value, so the shell has no reason to touch a "$" or
    # a backtick in the README - and the commands in it contain both.
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
