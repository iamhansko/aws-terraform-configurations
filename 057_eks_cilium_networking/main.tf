data "aws_region" "current" {}
module "network" {
  source = "./modules/network"

  public_subnet_tags  = var.public_subnet_tags
  private_subnet_tags = var.private_subnet_tags
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name = var.key_name

  # key_pair consumes no network output, so nothing would otherwise order it against
  # the network module's resources (rules.md D-3).
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
# There is deliberately no eks_vpc_cni_addon module and no eks_kube_proxy_addon module in
# this root, and their absence is the project.
#
# Cilium replaces both: it allocates pod addresses itself in ENI mode, and it implements
# Services itself with kube-proxy replacement. The cluster module sets
# bootstrap_self_managed_addons = false, which is what makes that absence real - EKS
# installs vpc-cni, coredns and kube-proxy at cluster creation otherwise (rules.md C-4).
#
# The _monolithic template left that flag at its default of true while installing only
# the coredns addon, so the cluster came up with a self-managed vpc-cni and kube-proxy
# that Terraform did not track. Nodes joined Ready on the VPC CNI, every pod got an
# address, and the project looked healthy while demonstrating none of what it is named
# after - and would have done so even if the Cilium install had run.
module "cilium" {
  source = "./modules/cilium"

  chart_version = var.cilium_chart_version
  # The operator makes EC2 calls and has no other source of a region. IRSA would normally
  # bring one through the pod identity webhook, but the chart declares AWS_DEFAULT_REGION
  # itself, which makes the webhook leave the region alone - see the module.
  region = data.aws_region.current.region
  # Without the scheme. With kube-proxy replacement on there is nothing translating the
  # in-cluster kubernetes Service address until Cilium itself is running, so the agent
  # has to be given the real endpoint (rules.md B-5).
  k8s_service_host             = module.eks_cluster.cluster_endpoint_host
  oidc_provider_arn            = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host             = module.eks_cluster.oidc_issuer_host
  ipam_mode                    = var.cilium_ipam_mode
  kube_proxy_replacement       = var.cilium_kube_proxy_replacement
  egress_masquerade_interfaces = var.cilium_egress_masquerade_interfaces

  # Before the node group, not after. A managed node group whose nodes have no CNI never
  # reports its instances as joined, and the create call fails with NodeCreationFailure -
  # so the CNI has to be in the cluster first, even though nothing can run it yet. That
  # is why this release does not wait (see the module's wait_for_release).
  depends_on = [module.network, module.eks_cluster]
}
module "eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name   = module.eks_cluster.cluster_name
  instance_types = var.node_group_instance_types
  desired_size   = var.node_group_desired_size
  min_size       = var.node_group_min_size
  max_size       = var.node_group_max_size
  subnet_ids     = module.network.private_subnet_ids

  # module.cilium is the load-bearing edge here, and it is also this project's only real
  # gate on Cilium working. The Helm release cannot wait for readiness - there are no
  # nodes to run on when it is installed - so nothing before this point proves the CNI
  # functions. Node group creation does: EKS waits for the instances to join, and a node
  # with no working CNI never becomes Ready.
  #
  # The _monolithic template expressed the same intent as
  # depends_on = [aws_instance.vs_code_ec2], which does not hold: that waits for the
  # instance to exist, not for the user data that was supposed to install Cilium to
  # finish - and on that template the install never ran at all (rules.md D-2/D-5).
  depends_on = [module.network, module.cilium]
}
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.eks_cluster.cluster_name

  # coredns is a Deployment and needs schedulable capacity to leave DEGRADED and become
  # ACTIVE (rules.md C-4). Here it needs more than capacity: its pods need addresses from
  # Cilium and its ClusterIP needs Cilium's Service implementation, so it is the first
  # thing in the apply that fails if either half of the CNI is not working.
  #
  # module.cilium is named even though module.eks_node_group already orders this after it
  # transitively, because that only holds while all three are being created. When the Cilium
  # release changes and this addon has to be replaced - which is exactly the shape of
  # recovering from a broken CNI - there is otherwise no edge between them, and the addon can
  # start its 20 minute wait for ACTIVE against the CNI that is still being fixed
  # (rules.md D-2).
  depends_on = [
  module.network, module.eks_node_group, module.cilium]
}
# The controller that reconciles the demo Ingress into the pre-created ALB. Its IRSA role
# and Helm release are one module, because the release has to annotate the service account
# with the role's ARN (rules.md C-2).
#
# The _monolithic template installed it from an SSM Association on the bastion and also
# downloaded the 2048 example manifest there without ever applying it - so the project
# ended with a controller, a manifest on disk, and nothing using either (rules.md E-1).
module "aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"

  cluster_name      = module.eks_cluster.cluster_name
  vpc_id            = module.network.vpc_id
  aws_region        = data.aws_region.current.region
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  chart_version     = var.aws_load_balancer_controller_chart_version
  # The demo Ingress does not set manage-backend-security-group-rules, so nothing asks
  # the controller to write node-side rules and this can stay false. The path from the
  # load balancer to the pods is declared below instead (rules.md G-2).
  enable_backend_security_group = false
  # Nothing here creates a Service of type LoadBalancer, so the webhook has nothing to
  # claim, while its failurePolicy: Fail applies to every Service creation in the cluster
  # (rules.md G-4).
  enable_service_mutator_webhook = var.enable_service_mutator_webhook

  # The controller is a Deployment with wait = true, so it needs schedulable capacity and
  # working cluster DNS before the release can report ready (rules.md D-2).
  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}
locals {
  # The stack tag the pre-created load balancer must carry to be adopted rather than
  # duplicated (rules.md G-3).
  #
  # Derived here rather than read from the workload module's output: the load balancer
  # needs this value before that module runs, and taking it from the module would make
  # the load balancer depend on the workload while the workload has to wait for the load
  # balancer. Both sides read the same root variables, so there is still one definition
  # (rules.md B-5).
  game_stack_tag = "${var.game_namespace}/${var.game_ingress_name}"
}
# Standalone rule resources rather than inline blocks, and revoke_rules_on_delete, because
# the controller adds its own rules to this group (rules.md F-2).
module "alb_security_group" {
  source = "./modules/load_balancer_security_group"

  vpc_id      = module.network.vpc_id
  name        = var.alb_security_group_name
  description = "Frontend security group for the pre-created ALB the controller adopts from the 2048 Ingress"
  ports = {
    http = var.alb_listener_port
  }
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere

  depends_on = [module.network]
}
# Created here and adopted by the controller rather than left for the controller to
# create, so its DNS name is known from state at apply time instead of only after a
# reconcile (rules.md G-3).
module "synced_alb" {
  source = "./modules/synced_load_balancer"

  cluster_name       = module.eks_cluster.cluster_name
  name               = var.synced_alb_name
  load_balancer_type = "application"
  internal           = false
  # internet-facing, so public subnets - this has to agree with the scheme the Ingress
  # annotates, or the controller builds a second load balancer instead of adopting this
  # one (rules.md G-3).
  subnet_ids         = module.network.public_subnet_ids
  security_group_ids = [module.alb_security_group.security_group_id]
  # ingress.k8s.aws/*, because this load balancer is provisioned from an Ingress rather
  # than a Service. The wrong prefix is not an error - the controller simply does not
  # adopt, and builds its own (rules.md G-3).
  resource_tag_prefix = "ingress"
  stack               = local.game_stack_tag

  depends_on = [module.network]
}
module "game_2048" {
  source = "./modules/game_2048"

  namespace     = var.game_namespace
  ingress_name  = var.game_ingress_name
  replica_count = var.game_replica_count
  # ClusterIP is enough with target-type ip: the load balancer talks to pod addresses, so
  # nothing needs a NodePort. It also means the only thing routing this Service inside the
  # cluster is Cilium, since there is no kube-proxy (rules.md G-1).
  service_type   = "ClusterIP"
  create_ingress = true
  ingress_annotations = {
    # Must agree with the pre-created load balancer's internal = false, or the controller
    # treats them as different load balancers and builds a second one (rules.md G-3).
    "alb.ingress.kubernetes.io/scheme" = "internet-facing"
    # ip, which is only reachable because Cilium is in ENI mode and pod addresses are
    # real VPC addresses. On an overlay IPAM mode the targets would never pass a health
    # check, with nothing reporting why (rules.md G-1).
    "alb.ingress.kubernetes.io/target-type"     = "ip"
    "alb.ingress.kubernetes.io/security-groups" = module.alb_security_group.security_group_id
    # Deliberately no manage-backend-security-group-rules annotation: with
    # enable_backend_security_group = false the controller rejects that combination, and
    # leaving it unset means node-side rules are Terraform's job (rules.md G-2).
  }

  # kubectl_manifest resources against the API server, and the Ingress is only fulfilled
  # once the controller is reconciling. Ordering the module after the controller, the
  # nodes and the pre-created load balancer also makes terraform destroy delete the
  # Ingress before any of them disappears (rules.md D-4/G-3).
  depends_on = [
    module.network,
    module.eks_node_group,
    module.eks_coredns_addon,
    module.aws_load_balancer_controller,
    module.synced_alb,
  ]
}
# With manage-backend-security-group-rules unset the controller writes no node-side rules
# at all, so the path from the load balancer to the pods has to be declared here or every
# target stays unhealthy with no error anywhere (rules.md G-2). target-type is ip, so
# traffic arrives at the pod's container port rather than a Service port.
#
# The cluster security group is the right group even though Cilium, not the VPC CNI, is
# attaching the interfaces these pods live on: in ENI mode Cilium copies the security
# groups from the instance's primary interface onto the ones it creates, and that primary
# interface carries the cluster security group.
#
# It modifies the cluster security group, which no module here owns outright, so it
# belongs in the root (rules.md C-1).
resource "aws_vpc_security_group_ingress_rule" "load_balancer_to_pods" {
  security_group_id            = module.eks_cluster.cluster_security_group_id
  description                  = "ALB to 2048 pods on the container port"
  ip_protocol                  = "tcp"
  from_port                    = var.game_container_port
  to_port                      = var.game_container_port
  referenced_security_group_id = module.alb_security_group.security_group_id
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
  # cluster and carries all five tools, plus the cilium CLI this project needs to inspect
  # the data plane (rules.md H-1). None of them creates anything: Cilium, the controller
  # and the demo workload the _monolithic template installed from here are Terraform
  # resources now (rules.md E-1).
  #
  # Two bugs from that template are fixed here rather than carried over. It ran
  # "exec bash" partway through, which replaces the shell and silently discarded every
  # remaining line - update-kubeconfig, eksctl, helm, the Cilium install and the cilium
  # CLI install were all after it, so none of them ever ran. And it pulled eksctl from
  # weaveworks; eksctl-io is the project's own org (rules.md H-1).
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
    # The cilium CLI, which is how the data plane is inspected - "cilium status" is the
    # one command that reports the IPAM mode and whether kube-proxy replacement is
    # actually in effect. Version comes from the project's own stable channel; the
    # checksum is verified rather than trusted.
    CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
    curl -sL --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/$CILIUM_CLI_VERSION/cilium-linux-amd64.tar.gz{,.sha256sum}
    sha256sum --check cilium-linux-amd64.tar.gz.sha256sum
    sudo tar xzf cilium-linux-amd64.tar.gz -C /usr/local/bin
    rm -f cilium-linux-amd64.tar.gz cilium-linux-amd64.tar.gz.sha256sum
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
      description = "Open the IDE here. The commands below are meant to be run from its terminal, which is where the cilium CLI is installed"
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
      description = "API server endpoint. Also what the Cilium agent is pointed at directly: with kube-proxy replaced there is nothing translating the in-cluster kubernetes Service address until Cilium is running"
      value       = module.eks_cluster.cluster_endpoint
    }
    data_plane = {
      order       = 4
      title       = "What is providing networking"
      description = "Cilium as both the CNI and the Service implementation. Neither the vpc-cni nor the kube-proxy addon is installed, and the cluster sets bootstrap_self_managed_addons = false so EKS does not install them either - that absence is what makes this real rather than two CNIs coexisting"
      value       = "cilium ${module.cilium.chart_version}, ipam=${module.cilium.ipam_mode}, kubeProxyReplacement=${module.cilium.kube_proxy_replacement}"
    }
    game_url = {
      order       = 5
      title       = "2048 URL"
      description = "The demo workload, reached through the pre-created ALB. Every hop in this path depends on Cilium: the pods have VPC addresses because Cilium is in ENI mode, and the load balancer sends traffic straight to them with target-type ip. The address is known from state because Terraform created the load balancer and the controller adopted it (rules.md G-3)"
      value       = module.synced_alb.url
    }
    cilium_status_command = {
      order       = 6
      title       = "1. Ask Cilium what it thinks it is doing"
      description = "Agent and operator counts, IPAM mode, and whether kube-proxy replacement is active. If this reports anything other than the values above, the rest of the checks will not make sense"
      value       = module.cilium.status_command
    }
    kube_proxy_absence_command = {
      order       = 7
      title       = "2. Confirm what is NOT there"
      description = "Both should report NotFound. This is the check the _monolithic template would have failed: it left bootstrap_self_managed_addons at its default, so EKS installed vpc-cni and kube-proxy at cluster creation and the cluster looked healthy while demonstrating nothing"
      value       = module.cilium.kube_proxy_absence_command
    }
    pod_address_command = {
      order       = 8
      title       = "3. Confirm pod addresses are VPC addresses"
      description = "Pod addresses should fall inside the VPC's own range, on interfaces Cilium attached rather than the VPC CNI. That is what makes target-type ip work at all - an overlay address would leave every load balancer target unhealthy"
      value       = "kubectl -n ${var.game_namespace} get pods -o wide"
    }
    interface_check_command = {
      order       = 9
      title       = "4. See the interfaces Cilium attached"
      description = "Interfaces described by Cilium rather than by the VPC CNI, which is the same fact as the pod addresses seen from the VPC's side. The operator is what creates these, using the IRSA role below"
      value       = "aws ec2 describe-network-interfaces --filters Name=vpc-id,Values=${module.network.vpc_id} --query 'NetworkInterfaces[].{ENI:NetworkInterfaceId,Subnet:SubnetId,IP:PrivateIpAddress,Desc:Description}' --output table"
    }
    operator_role_arn = {
      order       = 10
      title       = "Cilium operator IAM role"
      description = "The role the operator assumes through IRSA to attach interfaces. Its permissions are deliberately wider than AmazonEKS_CNI_Policy, which the VPC CNI needs and which lacks ec2:DescribeVpcs and ec2:DescribeSecurityGroups - without those the operator fails to allocate and pods simply stay without addresses, with no permissions error anywhere obvious"
      value       = module.cilium.operator_role_arn
    }
    service_routing_command = {
      order       = 11
      title       = "5. See Services being routed without kube-proxy"
      description = "The backends Cilium is load balancing, which is the work kube-proxy would otherwise be doing in iptables. An empty list while Services exist means kube-proxy replacement is not in effect"
      value       = module.cilium.service_routing_command
    }
    adopted_load_balancer_check_command = {
      order       = 12
      title       = "6. Confirm the load balancer was adopted, not duplicated"
      description = "Lists every load balancer tagged for this cluster. One is correct. Two means the controller did not adopt the pre-created one and built its own, which is a tag mismatch rather than an error (rules.md G-3)"
      value       = "aws resourcegroupstaggingapi get-resources --tag-filters Key=elbv2.k8s.aws/cluster,Values=${module.eks_cluster.cluster_name} --resource-type-filters elasticloadbalancing:loadbalancer --query 'ResourceTagMappingList[].ResourceARN' --output table"
    }
    ingress_hostname_command = {
      order       = 13
      title       = "7. Read the address the controller attached"
      description = "Compare this against the 2048 URL above. They should be the same load balancer"
      value       = module.game_2048.load_balancer_hostname_command
    }
    connectivity_test_command = {
      order       = 14
      title       = "8. Run Cilium's own test suite"
      description = "End-to-end connectivity checks, including Service routing and egress. It creates and deletes its own namespace, so it stays a command rather than a Terraform resource - those objects are meant to be temporary, and Terraform owning them would mean a permanent diff"
      value       = module.cilium.connectivity_test_command
    }
    update_kubeconfig_command = {
      order       = 15
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
