data "aws_region" "current" {}
module "network" {
  source = "./modules/network"

  vpc_name                 = "${var.cluster_name}-vpc"
  internet_gateway_name    = "${var.cluster_name}-igw"
  public_subnet_name       = "${var.cluster_name}-public"
  private_subnet_name      = "${var.cluster_name}-private"
  public_route_table_name  = "${var.cluster_name}-public-rt"
  private_route_table_name = "${var.cluster_name}-private-rt"
  nat_gateway_name         = "${var.cluster_name}-natgw"
  # The tags the AWS Load Balancer Controller discovers subnets by. Without them it refuses
  # the dashboard's load balancer with "couldn't auto-discover subnets" (rules.md G-1).
  public_subnet_tags  = var.public_subnet_tags
  private_subnet_tags = var.private_subnet_tags
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
  # resources behind those outputs, not after the NAT gateways and route table associations
  # that never surface as outputs (rules.md D-3).
  depends_on = [module.network]
}
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not exist until
  # this addon creates it. As a DaemonSet it reaches ACTIVE with zero nodes, so it comes
  # before any capacity - and nodes need it to join Ready (rules.md C-4). That matters
  # repeatedly here rather than once: every node the autoscaler adds has to reach Ready
  # before the pods waiting on it can be scheduled.
  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as eks_vpc_cni_addon (rules.md C-4).
  depends_on = [module.network, module.eks_vpc_cni_addon]
}
# The node group the autoscaler resizes. EKS tags its Auto Scaling group with
# k8s.io/cluster-autoscaler/enabled and k8s.io/cluster-autoscaler/<cluster name> on its own,
# which is what makes the autoscaler's auto-discovery find it and what the IAM policy's
# resource-tag condition narrows write access to - so nothing here has to tag anything.
#
# One group spanning all three private subnets, as the _monolithic template had it. Worth
# knowing the consequence: the Auto Scaling group picks the zone for each new instance, so the
# autoscaler cannot aim a scale-up at the zone whose pods are Pending. AWS's own guidance for
# zone-sensitive workloads is one node group per zone plus balance-similar-node-groups, which
# is the shape this project would grow into next.
module "eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name    = module.eks_cluster.cluster_name
  node_group_name = "core-nodegroup"
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
# Not in the _monolithic template, and added because something there was already paying for it:
# the dashboard's ClusterRole asks for read access to metrics.k8s.io so it can colour nodes and
# pods by utilization, and without a metrics API those calls fail and the dashboard draws plain
# boxes. A granted permission that does nothing is worth either removing or making real, and in
# a project about capacity the utilization view is the more useful half of the picture.
#
# A Deployment, so it needs schedulable capacity to leave DEGRADED (rules.md C-4).
module "eks_metrics_server_addon" {
  source = "./modules/eks_metrics_server_addon"

  cluster_name = module.eks_cluster.cluster_name

  depends_on = [
  module.network, module.eks_node_group]
}
# The subject of this project. Its IRSA role and Helm release are one module, because the
# release has to annotate the service account with the role's ARN (rules.md C-2).
module "cluster_autoscaler" {
  source = "./modules/cluster_autoscaler"

  cluster_name      = module.eks_cluster.cluster_name
  aws_region        = data.aws_region.current.region
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  chart_version     = var.cluster_autoscaler_chart_version
  # False on both, as the _monolithic template set them. On a demo cluster of one to four nodes
  # almost every node hosts a kube-system pod or something with an emptyDir, so leaving either
  # at its upstream default of true means the cluster grows and then never shrinks - and the
  # scale-down half of the demo silently does not exist.
  skip_nodes_with_system_pods   = false
  skip_nodes_with_local_storage = false
  scale_down_unneeded_time      = var.scale_down_unneeded_time
  balance_similar_node_groups   = var.balance_similar_node_groups

  # The autoscaler resolves Service DNS names and talks to the API server, so CoreDNS has to be
  # answering before its pod is useful (rules.md D-2). It also reads the metrics API when
  # deciding utilization, though it falls back to requests without it.
  depends_on = [
  module.network, module.eks_node_group, module.eks_coredns_addon]
}
# Two Deployments that want more capacity than one node has. This is what the autoscaler
# reacts to, and the _monolithic template left both as unapplied files on the bastion
# (rules.md E-1).
module "spread_workload" {
  source   = "./modules/spread_workload"
  for_each = var.spread_workloads

  name         = each.key
  namespace    = var.workload_namespace
  image        = each.value.image
  topology_key = each.value.topology_key
  # The per-entry count unless the root-level override is set, which is how the scale-down half
  # of the demo is driven from a single flag rather than by restating the whole map.
  replicas = var.spread_workload_replicas == null ? each.value.replicas : var.spread_workload_replicas

  # kubectl_manifest resources against the cluster's API server. Ordering the module after the
  # nodes is what makes terraform destroy remove these Deployments while there is still a
  # kubelet to delete their pods (rules.md D-4). The autoscaler is here so that the pods these
  # create are Pending with something already watching for them, rather than sitting
  # unschedulable until the release lands.
  depends_on = [
  module.network, module.eks_node_group, module.eks_coredns_addon, module.cluster_autoscaler]
}
# What turns the dashboard's Service into an NLB. Its IRSA role and Helm release are one module
# (rules.md C-2).
module "aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"

  cluster_name      = module.eks_cluster.cluster_name
  vpc_id            = module.network.vpc_id
  aws_region        = data.aws_region.current.region
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  chart_version     = var.aws_load_balancer_controller_chart_version
  # The dashboard Service does not set manage-backend-security-group-rules, so nothing asks the
  # controller to write node-side rules and this can stay false. The path from the load balancer
  # to the pod is declared below instead (rules.md G-2).
  enable_backend_security_group = false
  # Off: the one Service of type LoadBalancer here names the controller itself with
  # aws-load-balancer-type, so the webhook has nothing to mutate, and its failurePolicy: Fail
  # would otherwise gate every Service creation in the cluster behind a controller pod being
  # Ready (rules.md G-4).
  enable_service_mutator_webhook = var.enable_service_mutator_webhook

  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}
locals {
  # The stack tag the pre-created load balancer must carry to be adopted rather than duplicated
  # (rules.md G-3). The _monolithic template wrote this as the literal string
  # "default/kube-ops-view" on the load balancer while the Service's name and namespace came
  # from elsewhere, so renaming either silently produced a second load balancer.
  #
  # Derived here rather than read from the dashboard module's output: the load balancer needs
  # the value before that module runs, and taking it from the module would make the load
  # balancer depend on the dashboard while the dashboard has to wait for the load balancer
  # (rules.md B-5).
  dashboard_stack_tag = "${var.dashboard_namespace}/${var.dashboard_name}"
}
# Standalone rule resources rather than inline blocks, and revoke_rules_on_delete, because the
# controller may add its own rules to this group (rules.md F-2).
module "load_balancer_security_group" {
  source = "./modules/load_balancer_security_group"

  vpc_id      = module.network.vpc_id
  name        = var.load_balancer_security_group_name
  description = "Frontend security group for the NLB fronting the kube-ops-view dashboard"
  # Only the Service port. The dashboard publishes one port, so there is one listener and one
  # rule (rules.md G-1).
  ports = {
    http = var.dashboard_service_port
  }
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere

  depends_on = [module.network]
}
# Created here and adopted by the controller, which is what the _monolithic template was
# reaching for with its own aws_lb carrying the three controller tags - but it built that load
# balancer with the VPC's default security group while the Service's annotation asked for two
# different ones, and gave it only two of the three public subnets. Both are fixed by handing
# the same values to the load balancer and to the Service (rules.md B-5/G-3).
module "synced_load_balancer" {
  source = "./modules/synced_load_balancer"

  cluster_name       = module.eks_cluster.cluster_name
  load_balancer_type = "network"
  internal           = false
  # internet-facing, so public subnets - this has to agree with the scheme the Service
  # annotates, or the controller builds a second load balancer instead of adopting this one
  # (rules.md G-3).
  subnet_ids         = module.network.public_subnet_ids
  security_group_ids = [module.load_balancer_security_group.security_group_id]
  # service.k8s.aws/*, not ingress.k8s.aws/*: this fronts a Service of type LoadBalancer. The
  # wrong prefix is not an error - the controller simply does not adopt (rules.md G-3).
  resource_tag_prefix = "service"
  stack               = local.dashboard_stack_tag

  depends_on = [module.network]
}
# The dashboard that makes the scaling visible: nodes as boxes, pods as squares inside them.
# The _monolithic template installed it by cloning the upstream repository on the bastion,
# writing a kustomize overlay, and running kubectl apply -k - so none of it was in state, and
# the install depended on a git host staying reachable (rules.md E-1/E-3).
module "kube_ops_view" {
  source = "./modules/kube_ops_view"

  name           = var.dashboard_name
  namespace      = var.dashboard_namespace
  container_port = var.dashboard_container_port
  service_port   = var.dashboard_service_port
  service_type   = "LoadBalancer"
  service_annotations = {
    # The switch the _monolithic template's kustomize patch left out, and the one that decides
    # whether any of the others mean anything. Without it the in-tree cloud provider claims the
    # Service and builds a Classic Load Balancer, ignoring the scheme, the target type and the
    # security groups - and the pre-created NLB is never adopted, because the AWS Load Balancer
    # Controller never looks at the Service at all (rules.md G-1).
    "service.beta.kubernetes.io/aws-load-balancer-type" = "external"
    # Has to agree with internal = false and the public subnets above, or the controller builds
    # its own load balancer rather than adopting (rules.md G-3).
    "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
    # nlb-target-type, not target-type: the Service spelling carries the nlb- prefix while the
    # Ingress spelling does not, and the wrong one is ignored rather than rejected
    # (rules.md G-1).
    "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
    # Naming the group here is what makes the controller keep it on the load balancer. Only the
    # frontend group, unlike the original's frontend-plus-cluster-group list: the path to the
    # pod is a declared rule below rather than a side effect of the load balancer being a member
    # of the pods' own security group (rules.md G-2).
    "service.beta.kubernetes.io/aws-load-balancer-security-groups" = module.load_balancer_security_group.security_group_id
  }

  # The load balancer has to exist before the controller reconciles this Service, or the
  # controller creates its own and the pre-created one is orphaned (rules.md G-3). Ordering
  # this after the controller also means terraform destroy removes the Service while the
  # controller is still alive, so the load balancer is cleaned up rather than left behind
  # (rules.md D-4).
  depends_on = [
    module.network,
    module.eks_node_group,
    module.eks_coredns_addon,
    module.eks_metrics_server_addon,
    module.aws_load_balancer_controller,
    module.synced_load_balancer,
  ]
}
# With manage-backend-security-group-rules unset the controller writes no node-side rules at
# all, so the path from load balancer to pod has to be declared here or the target stays
# unhealthy with no error anywhere (rules.md G-2). nlb-target-type is ip, so traffic arrives at
# the dashboard pod's container port rather than the Service port, and pods on this cluster use
# the cluster security group.
#
# It modifies the cluster security group, which no module here owns outright, so it belongs in
# the root (rules.md C-1).
resource "aws_vpc_security_group_ingress_rule" "load_balancer_to_pods" {
  security_group_id            = module.eks_cluster.cluster_security_group_id
  description                  = "Dashboard container port from the NLB frontend security group"
  ip_protocol                  = "tcp"
  from_port                    = var.dashboard_container_port
  to_port                      = var.dashboard_container_port
  referenced_security_group_id = module.load_balancer_security_group.security_group_id
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
  # controller, the autoscaler, the dashboard and the two demo Deployments the _monolithic
  # template installed from here are Terraform resources now (rules.md E-1).
  #
  # Three bugs from that template are fixed here rather than carried over. It ran "exec bash"
  # partway through, which replaces the shell and silently discarded every remaining line -
  # update-kubeconfig, eksctl, helm and the AWS Load Balancer Controller install were all after
  # it, so on a real boot none of them ran. It pulled eksctl from weaveworks rather than
  # eksctl-io. And it wrote the "complete" line for the k alias into .bashrc before the line
  # that defines __start_kubectl, so every login printed a "function not found" error
  # (rules.md H-1). The "sleep 60" that followed the helm install is gone too: the release now
  # waits for its Deployment to be Available instead.
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
      description = "Open the IDE here. The kubectl commands below are meant to be run from its terminal"
      value       = module.vscode_ec2.vscode_url
    }
    kube_ops_view_url = {
      order       = 2
      title       = "kube-ops-view dashboard"
      description = "Watch the scaling here: every box is a node and every square inside it a pod. The address is known from state because Terraform created the load balancer and the controller adopted it (rules.md G-3)"
      value       = module.synced_load_balancer.url
    }
    cluster_name = {
      order       = 3
      title       = "EKS cluster name"
      description = "Name of the EKS cluster. This is also what the autoscaler's auto-discovery matches on: EKS tags the node group's Auto Scaling group with k8s.io/cluster-autoscaler/<this name>, and a mismatch here means the autoscaler manages nothing while reporting no error"
      value       = module.eks_cluster.cluster_name
    }
    cluster_endpoint = {
      order       = 4
      title       = "EKS cluster endpoint"
      description = "API server endpoint. Public so the helm and kubectl providers could reach it during apply - narrow public_access_cidrs to your own address"
      value       = module.eks_cluster.cluster_endpoint
    }
    node_group_bounds = {
      order       = 5
      title       = "What the autoscaler may do"
      description = "The floor and ceiling it works between, and where it starts. It will not go below the minimum however unneeded the last node looks, and at the maximum it logs that it wants more capacity and stops - which reads exactly like an autoscaler that is not working"
      value       = "desired=${var.node_group_desired_size}, min=${var.node_group_min_size}, max=${var.node_group_max_size} on ${join(",", var.node_group_instance_types)} across ${length(module.network.availability_zones)} zones (${join(", ", module.network.availability_zones)})"
    }
    workload_demand = {
      order       = 6
      title       = "What is asking for capacity"
      description = "The two Deployments and how they spread. Both are applied by Terraform, unlike the _monolithic template's two unapplied files, so an apply already puts the cluster under pressure. The autoscaler schedules against these requests rather than against any actual usage - the containers do nothing at all"
      value       = join("\n", [for name in sort(keys(var.spread_workloads)) : "${name}: ${module.spread_workload[name].total_cpu_request} spread on ${module.spread_workload[name].topology_key}"])
    }
    scale_down_wait = {
      order       = 7
      title       = "How long scale-down takes"
      description = "A node has to sit underutilized this long before it is removed, and both skip-nodes-with-system-pods and skip-nodes-with-local-storage are off so that a small cluster can actually shrink. With either at its upstream default the cluster grows and never comes back down"
      value       = "scale-down-unneeded-time=${module.cluster_autoscaler.scale_down_unneeded_time}"
    }
    autoscaler_status_command = {
      order       = 8
      title       = "1. Confirm the autoscaler found the node group"
      description = "The status ConfigMap lists every node group under management with its current and target size. An empty list means auto-discovery matched nothing, which looks identical to a cluster that simply needs no more nodes - check it before reading anything into the rest"
      value       = module.cluster_autoscaler.status_command
    }
    pending_pods_command = {
      order       = 9
      title       = "2. See what cannot be scheduled"
      description = "The pods with nowhere to go, which is the autoscaler's only input. Run it right after apply: one t3.medium cannot hold twenty-four 100m pods, so this list starts long and empties as nodes arrive"
      value       = join("\n", [for name in sort(keys(var.spread_workloads)) : module.spread_workload[name].pending_pods_command])
    }
    node_watch_command = {
      order       = 10
      title       = "3. Watch the nodes arrive"
      description = "Each new node takes a minute or two: an EC2 launch, then the kubelet joining, then vpc-cni and kube-proxy making it Ready. The zone column is worth watching - the Auto Scaling group spans three of them and picks for itself, so the autoscaler cannot aim a scale-up at the zone whose pods are Pending"
      value       = "kubectl get nodes -L topology.kubernetes.io/zone,node.kubernetes.io/instance-type -w"
    }
    pod_distribution_command = {
      order       = 11
      title       = "4. Read the two spreads against each other"
      description = "Same replica count, same cluster, different topologyKey. The hostname-spread Deployment balances across individual nodes; the zone-spread one treats three nodes in one zone as one bucket, so it can leave them unevenly loaded and still be satisfied"
      value       = join("\n", [for name in sort(keys(var.spread_workloads)) : module.spread_workload[name].pod_distribution_command])
    }
    autoscaler_logs_command = {
      order       = 12
      title       = "5. Read the autoscaler's reasoning"
      description = "Which node groups it found, which pods it could not place, what it decided and why. A scale-up that never happens is explained here and nowhere else"
      value       = module.cluster_autoscaler.logs_command
    }
    scale_in_command = {
      order       = 13
      title       = "6. Trigger the scale-down"
      description = "Takes every demo Deployment to zero replicas, which leaves the nodes underutilized rather than empty - the autoscaler still has to decide they are unneeded and drain them. Expect to wait the scale-down time above before the first node goes. Re-apply without the flag to push the cluster back up"
      value       = "terraform apply -var spread_workload_replicas=0"
    }
    adopted_load_balancer_check_command = {
      order       = 14
      title       = "7. Confirm the load balancer was adopted, not duplicated"
      description = "Lists every load balancer tagged for this cluster. One is correct. Two means the controller did not adopt the pre-created one and built its own, which is a tag mismatch rather than an error (rules.md G-3)"
      value       = "aws resourcegroupstaggingapi get-resources --tag-filters Key=elbv2.k8s.aws/cluster,Values=${module.eks_cluster.cluster_name} --resource-type-filters elasticloadbalancing:loadbalancer --query 'ResourceTagMappingList[].ResourceARN' --output table"
    }
    dashboard_hostname_command = {
      order       = 15
      title       = "8. Read the address the controller attached"
      description = "Compare this against the dashboard URL above. They should be the same load balancer"
      value       = module.kube_ops_view.load_balancer_hostname_command
    }
    update_kubeconfig_command = {
      order       = 16
      title       = "Re-point kubectl"
      description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the order field
  # and taking values() - which returns a map's values ordered by key - makes the README read
  # top to bottom while the order stays decided by configuration.
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
# The work happens inside code-server in a browser, where terraform output is not available,
# so every output above is also written to a README in the home directory the IDE opens
# (rules.md H-2). Combining several modules' outputs is the root's job, so this lives here
# rather than inside the instance module.
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
