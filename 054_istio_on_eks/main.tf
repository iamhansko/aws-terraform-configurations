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
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not exist
  # until this addon creates it. As a DaemonSet it reaches ACTIVE with zero nodes, so it
  # comes before any capacity (rules.md C-4) - and nodes need it to join Ready. It is
  # also what makes target-type ip work, by making pod addresses routable in the VPC,
  # which is how both load balancers here reach their targets (rules.md G-1).
  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as eks_vpc_cni_addon (rules.md C-4).
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

  depends_on = [module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.eks_cluster.cluster_name

  # coredns is a Deployment and needs schedulable capacity to leave DEGRADED and become
  # ACTIVE (rules.md C-4). Everything downstream also needs it: injected sidecars find
  # istiod by Service name, and the VirtualService routes to a fully qualified Service
  # name, so a mesh without DNS reports itself as a mesh that cannot route.
  depends_on = [
  module.network, module.eks_node_group]
}
# The controller that turns the gateway Service into an NLB and the Kiali Ingress into
# an ALB. Its IRSA role and Helm release are one module, because the release has to
# annotate the service account with the role's ARN (rules.md C-2).
#
# The _monolithic template installed it with a helm command in userdata placed after an
# "exec bash" line, which replaces the running shell - so that command, and every one
# after it, never ran. The IAM role and its policy were created, the chart never was,
# and with no controller nothing reconciles either load balancer (rules.md E-1/H-1).
module "aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"

  cluster_name      = module.eks_cluster.cluster_name
  vpc_id            = module.network.vpc_id
  aws_region        = data.aws_region.current.region
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  chart_version     = var.aws_load_balancer_controller_chart_version
  # Neither the gateway Service nor the Kiali Ingress sets
  # manage-backend-security-group-rules, so nothing asks the controller to write
  # node-side rules and this can stay false. The paths from both load balancers to
  # their pods are declared below instead (rules.md G-2).
  enable_backend_security_group = false
  # Off: the one Service of type LoadBalancer here names the controller itself with the
  # aws-load-balancer-type annotation, so the webhook has nothing to mutate, and its
  # failurePolicy: Fail would otherwise gate every Service created by the four charts
  # installed after it behind a controller pod being Ready (rules.md G-4).
  enable_service_mutator_webhook = var.enable_service_mutator_webhook

  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}
locals {
  # The stack tags the two pre-created load balancers must carry to be adopted rather
  # than duplicated (rules.md G-3).
  #
  # Derived here rather than read from the workload modules' outputs: each load balancer
  # needs its tag before the module that defines the object runs, and taking the value
  # from that module would make the load balancer depend on the workload while the
  # workload has to wait for the load balancer. Both sides read the same root variables,
  # so there is still one definition (rules.md B-5).
  #
  # The prefixes differ and are not interchangeable. An NLB provisioned from a Service
  # is tagged service.k8s.aws/*; an ALB provisioned from an Ingress, ingress.k8s.aws/*.
  # The wrong prefix is not an error - the controller simply does not adopt, and builds
  # its own alongside (rules.md G-3).
  istio_gateway_stack_tag = "${var.istio_gateway_namespace}/${var.istio_gateway_release_name}"
  kiali_stack_tag         = "${var.istio_control_plane_namespace}/${var.kiali_name}"
}
# Standalone rule resources rather than inline blocks, and revoke_rules_on_delete,
# because the controller adds its own rules to these groups (rules.md F-2).
#
# The _monolithic template created both of these groups and then attached neither: both
# aws_lb resources were given the VPC's default security group instead, while the
# Service and Ingress annotations named these. So Terraform and the controller disagreed
# about which groups the load balancers had, and the rules reviewed here governed
# nothing.
module "nlb_security_group" {
  source = "./modules/load_balancer_security_group"

  vpc_id      = module.network.vpc_id
  name        = var.nlb_security_group_name
  description = "Frontend security group for the NLB fronting the Istio ingress gateway"
  # Exactly the ports the gateway Service publishes, from the same variable the Service
  # reads. A listener whose port is missing here accepts nothing, and every Terraform
  # resource still reports success (rules.md B-5/G-1).
  ports                       = var.istio_gateway_service_ports
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere

  depends_on = [module.network]
}
module "alb_security_group" {
  source = "./modules/load_balancer_security_group"

  vpc_id      = module.network.vpc_id
  name        = var.alb_security_group_name
  description = "Frontend security group for the ALB fronting the Kiali console"
  ports = {
    http = var.kiali_load_balancer_port
  }
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere

  depends_on = [module.network]
}
# Both load balancers are created here and adopted by the controller rather than left
# for the controller to create. That is what makes their DNS names known at apply time,
# so the gateway and Kiali URLs are real outputs instead of kubectl commands - and for
# the NLB it is the only way it can carry a security group at all, since AWS refuses to
# add security groups to a network load balancer after creation (rules.md G-3).
module "synced_nlb" {
  source = "./modules/synced_load_balancer"

  cluster_name       = module.eks_cluster.cluster_name
  name               = var.synced_nlb_name
  load_balancer_type = "network"
  internal           = false
  # internet-facing, so public subnets - this has to agree with the scheme the gateway
  # Service annotates, or the controller builds a second load balancer instead of
  # adopting this one (rules.md G-3).
  subnet_ids          = module.network.public_subnet_ids
  security_group_ids  = [module.nlb_security_group.security_group_id]
  resource_tag_prefix = "service"
  stack               = local.istio_gateway_stack_tag

  depends_on = [module.network]
}
module "synced_alb" {
  source = "./modules/synced_load_balancer"

  cluster_name        = module.eks_cluster.cluster_name
  name                = var.synced_alb_name
  load_balancer_type  = "application"
  internal            = false
  subnet_ids          = module.network.public_subnet_ids
  security_group_ids  = [module.alb_security_group.security_group_id]
  resource_tag_prefix = "ingress"
  stack               = local.kiali_stack_tag

  depends_on = [module.network]
}
module "istio" {
  source = "./modules/istio"

  chart_version           = var.istio_chart_version
  control_plane_namespace = var.istio_control_plane_namespace
  gateway_namespace       = var.istio_gateway_namespace
  gateway_release_name    = var.istio_gateway_release_name
  service_ports           = var.istio_gateway_service_ports
  health_check_port       = var.istio_gateway_health_check_port
  scheme                  = "internet-facing"
  nlb_target_type         = "ip"
  # Named in the Service annotation so the controller keeps the group Terraform already
  # attached to the pre-created load balancer. Omitting it would have the controller
  # reconcile the load balancer's groups towards a set of its own choosing, removing
  # this one (rules.md B-6/G-3).
  frontend_security_group_ids = [module.nlb_security_group.security_group_id]

  # The load balancer has to exist before the controller reconciles the gateway Service,
  # or the controller creates its own and the pre-created one is orphaned (rules.md G-3).
  # The controller must also be running, otherwise the in-tree cloud provider claims the
  # Service and builds a Classic Load Balancer, ignoring every annotation (rules.md G-1).
  #
  # On the way down this same edge is what lets the load balancer be cleaned up: the
  # gateway release is uninstalled - deleting the Service - while the controller is still
  # alive to act on it (rules.md D-4).
  depends_on = [
    module.network,
    module.eks_node_group,
    module.eks_coredns_addon,
    module.aws_load_balancer_controller,
    module.synced_nlb,
  ]
}
module "kiali" {
  source = "./modules/kiali"

  chart_version               = var.kiali_chart_version
  namespace                   = var.istio_control_plane_namespace
  istio_namespace             = var.istio_control_plane_namespace
  name                        = var.kiali_name
  auth_strategy               = var.kiali_auth_strategy
  web_root                    = var.kiali_web_root
  server_port                 = var.kiali_server_port
  scheme                      = "internet-facing"
  target_type                 = "ip"
  frontend_security_group_ids = [module.alb_security_group.security_group_id]

  # module.istio because Kiali installs into the namespace the base chart creates and
  # reads the mesh configuration istiod publishes there - and because a Kiali with no
  # mesh to look at is a console reporting errors rather than a demo.
  #
  # module.synced_alb and the controller for the same reasons as the gateway above, and
  # with the same effect on destroy: the Ingress is deleted while the controller can
  # still tear the load balancer down (rules.md D-4/G-3).
  depends_on = [
    module.network,
    module.eks_node_group,
    module.eks_coredns_addon,
    module.aws_load_balancer_controller,
    module.synced_alb,
    module.istio,
  ]
}
module "mesh_demo_workload" {
  source = "./modules/mesh_demo_workload"

  namespace = var.demo_namespace
  name      = var.demo_name
  # Both taken from the istio module rather than restated, so the Gateway cannot select
  # a proxy that does not exist and cannot declare a server on a port the Service does
  # not publish. Either mistake is accepted by the API server and produces a load
  # balancer that refuses connections (rules.md B-5).
  gateway_selector = module.istio.gateway_selector
  gateway_port     = var.demo_gateway_port
  route_traffic    = var.demo_route_traffic

  # The sidecar injection webhook and the Gateway/VirtualService CRDs both come from
  # module.istio, and neither is referenced as an attribute here (rules.md D-1/D-2).
  # Ordering the module after the nodes also makes terraform destroy remove these
  # manifests while their controllers are still running (rules.md D-4).
  depends_on = [
  module.network, module.eks_node_group, module.eks_coredns_addon, module.istio]
}
# With manage-backend-security-group-rules unset the controller writes no node-side
# rules at all, so the paths from both load balancers to their pods have to be declared
# here or the targets stay unhealthy with no error anywhere (rules.md G-2). target-type
# is ip for both, so traffic arrives at the pod's own port - not the Service port - and
# pods on this cluster use the cluster security group.
#
# These modify the cluster security group, which no module here owns outright, so they
# belong in the root (rules.md C-1).
resource "aws_vpc_security_group_ingress_rule" "nlb_to_gateway_pods" {
  # Keys come from configuration, so they are known during plan even though the two
  # security group IDs are not (rules.md B-8).
  for_each = var.istio_gateway_service_ports

  security_group_id            = module.eks_cluster.cluster_security_group_id
  description                  = "Istio gateway ${each.key} port from the NLB frontend security group"
  ip_protocol                  = "tcp"
  from_port                    = each.value
  to_port                      = each.value
  referenced_security_group_id = module.nlb_security_group.security_group_id
}
# Separate from the traffic ports above because the health check port is deliberately
# not a published one. Without this rule the load balancer cannot reach the proxy's
# readiness endpoint, so every target is unhealthy - and because the listener, the
# frontend rules and the pods are all correct, there is nothing to find until someone
# looks at the target group's health check port (rules.md G-2).
resource "aws_vpc_security_group_ingress_rule" "nlb_to_gateway_health_check" {
  security_group_id            = module.eks_cluster.cluster_security_group_id
  description                  = "Istio gateway status port from the NLB frontend security group, for the target group health check"
  ip_protocol                  = "tcp"
  from_port                    = var.istio_gateway_health_check_port
  to_port                      = var.istio_gateway_health_check_port
  referenced_security_group_id = module.nlb_security_group.security_group_id
}
resource "aws_vpc_security_group_ingress_rule" "alb_to_kiali_pods" {
  security_group_id = module.eks_cluster.cluster_security_group_id
  description       = "Kiali server port from the ALB frontend security group"
  ip_protocol       = "tcp"
  # The Kiali pod's own port, not the ALB's listener port. The health check uses the
  # traffic port by default, so this one rule covers both.
  from_port                    = var.kiali_server_port
  to_port                      = var.kiali_server_port
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
  # cluster and carries all five tools (rules.md H-1). None of them creates anything: the
  # controller, Istio, Kiali and the demo objects the _monolithic template installed from
  # here are Terraform resources now (rules.md E-1).
  #
  # Two bugs from that template are fixed here rather than carried over. It ran
  # "exec bash" partway through, which replaces the shell and silently discarded every
  # remaining line - update-kubeconfig, eksctl, helm and the load balancer controller
  # install were all after it, so none of them ever ran. And it pulled eksctl from
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
      description = "API server endpoint. Public so the helm and kubectl providers could reach it during apply - narrow public_access_cidrs to your own address"
      value       = module.eks_cluster.cluster_endpoint
    }
    istio_version = {
      order       = 4
      title       = "Istio version"
      description = "Version all three Istio charts were installed at. Pinned, unlike the _monolithic template, which ran helm upgrade --install with no version and so installed whatever the repository served that day"
      value       = module.istio.chart_version
    }
    gateway_url = {
      order       = 5
      title       = "Istio ingress gateway URL"
      description = "The mesh's front door, serving the demo application. The address is known from state because Terraform created the network load balancer and the controller adopted it (rules.md G-3). It answers only while demo_route_traffic is true - with no Gateway resource the proxy binds no port and the connection is refused"
      value       = module.synced_nlb.url
    }
    kiali_url = {
      order       = 6
      title       = "Kiali console"
      description = "The mesh console, with no login: auth strategy is anonymous. Its Services, Workloads and Istio Config pages read the Kubernetes API and work immediately. The Graph page is built from metrics instead, so it stays empty until there is a Prometheus for Kiali to query and traffic for it to have recorded - this project installs neither, which is why the traffic generator below only makes the mesh visible to Istio's own telemetry, not to the graph"
      value       = "${module.synced_alb.url}${module.kiali.web_root}"
    }
    gateway_stack_tag = {
      order       = 7
      title       = "Gateway adoption stack tag"
      description = "The <namespace>/<name> the network load balancer carries in its service.k8s.aws/stack tag. The controller adopts it only when this matches the Service it is reconciling - a mismatch makes it build a second load balancer instead, with no error (rules.md G-3)"
      value       = module.synced_nlb.stack
    }
    kiali_stack_tag = {
      order       = 8
      title       = "Kiali adoption stack tag"
      description = "The same thing for the ALB, under ingress.k8s.aws/stack because it is provisioned from an Ingress rather than a Service. The two prefixes are not interchangeable and using the wrong one is silently ignored (rules.md G-3)"
      value       = module.synced_alb.stack
    }
    sidecar_check_command = {
      order       = 9
      title       = "1. Confirm the demo application is in the mesh"
      description = "Two containers per pod - the application and istio-proxy - means injection worked. One container means the pod is not in the mesh, which no resource reports as a problem: it runs and serves traffic, and simply never appears in Kiali"
      value       = module.mesh_demo_workload.sidecar_check_command
    }
    routing_check_command = {
      order       = 10
      title       = "2. Confirm routing exists"
      description = "The Gateway and VirtualService that decide whether the gateway URL serves anything. Empty output means demo_route_traffic was false"
      value       = module.mesh_demo_workload.routing_check_command
    }
    proxy_listener_command = {
      order       = 11
      title       = "3. Ask the proxy what it is listening on"
      description = "The listeners istiod actually programmed. This is the check that separates the two ways a mesh looks broken from outside: healthy targets with no listener on the traffic port means no Gateway binds it, not that the load balancer is misconfigured"
      value       = module.istio.proxy_status_command
    }
    adopted_load_balancer_check_command = {
      order       = 12
      title       = "4. Confirm both load balancers were adopted, not duplicated"
      description = "Lists every load balancer tagged for this cluster. Two is correct here - one NLB for the gateway, one ALB for Kiali. Three or four means the controller did not adopt a pre-created one and built its own, which is a tag mismatch rather than an error (rules.md G-3)"
      value       = "aws resourcegroupstaggingapi get-resources --tag-filters Key=elbv2.k8s.aws/cluster,Values=${module.eks_cluster.cluster_name} --resource-type-filters elasticloadbalancing:loadbalancer --query 'ResourceTagMappingList[].ResourceARN' --output table"
    }
    gateway_hostname_command = {
      order       = 13
      title       = "5. Read the address attached to the gateway Service"
      description = "Compare this against the gateway URL above. They should be the same load balancer"
      value       = module.istio.gateway_hostname_command
    }
    kiali_hostname_command = {
      order       = 14
      title       = "6. Read the address attached to the Kiali Ingress"
      description = "Same comparison for the ALB. This one can take a few minutes longer: the Ingress is created before the operator has built Kiali's Service, so the controller's first reconcile fails and it retries once the Service appears"
      value       = module.kiali.load_balancer_hostname_command
    }
    kiali_status_command = {
      order       = 15
      title       = "7. Wait for Kiali itself"
      description = "What the operator made of the CR, then whether the server it built is up. The Helm release finishes once the operator is running, so the server trails it by a minute or two"
      value       = module.kiali.server_status_command
    }
    traffic_generator_command = {
      order       = 16
      title       = "8. Send traffic through the mesh"
      description = "Two hundred requests from inside the mesh, so the sidecars have something to report. Istio's own telemetry - and anything scraping it - sees this; Kiali's graph will not, for the reason given above"
      value       = module.mesh_demo_workload.traffic_generator_command
    }
    disable_routing_command = {
      order       = 17
      title       = "9. See the mesh with no routes"
      description = "Removes the Gateway and VirtualService and leaves everything else. The gateway pod stays Running, the load balancer's targets stay healthy - the health check is against the proxy's status port, not the traffic port - and the URL starts refusing connections. That is the state the _monolithic template stopped at, and it is worth reaching deliberately rather than by accident"
      value       = "terraform apply -var demo_route_traffic=false"
    }
    update_kubeconfig_command = {
      order       = 18
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
