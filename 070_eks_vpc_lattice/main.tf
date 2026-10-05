data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
# The managed prefix lists VPC Lattice sends traffic from, which the cluster security group has to
# accept.
#
# The _monolithic template looked these up with a Lambda function: an inline Python handler, its own IAM
# role, an inline policy, an archive_file to package it and two aws_lambda_invocation resources to call
# it - all to turn a prefix list name into its ID. Terraform has a data source for exactly that.
#
# The Lambda could not have worked in any case. It imports cfnresponse, which exists only inside
# CloudFormation's inline Lambda runtime and is not in the deployment package, and it branches on
# event["RequestType"], which aws_lambda_invocation does not send - so the first line of the handler
# raises ImportError and the invocation fails. Its error handler then prints str(e) while the exception
# is bound to "error", so even the failure path raises NameError. Five resources and a source file, all
# replaced by these two blocks (rules.md E-1).
data "aws_ec2_managed_prefix_list" "vpc_lattice" {
  name = "com.amazonaws.${data.aws_region.current.region}.vpc-lattice"
}
data "aws_ec2_managed_prefix_list" "vpc_lattice_ipv6" {
  name = "com.amazonaws.${data.aws_region.current.region}.ipv6.vpc-lattice"
}
module "network" {
  source = "./modules/network"

  vpc_name                 = "${var.cluster_name}-vpc"
  internet_gateway_name    = "${var.cluster_name}-igw"
  public_subnet_name       = "${var.cluster_name}-public"
  private_subnet_name      = "${var.cluster_name}-private"
  public_route_table_name  = "${var.cluster_name}-public-rt"
  private_route_table_name = "${var.cluster_name}-private-rt"
  nat_gateway_name         = "${var.cluster_name}-natgw"
  # No subnet tags: nothing here creates an Elastic Load Balancer. That is the point of the project -
  # VPC Lattice fronts the services instead, and it needs no subnet discovery because it works through
  # a VPC association rather than by placing nodes in subnets (rules.md G-1).
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name = var.key_name

  # key_pair consumes no network output, so nothing would otherwise order it against the network
  # module's resources (rules.md D-3).
  depends_on = [module.network]
}
module "eks_cluster" {
  source = "./modules/eks_cluster"

  name                   = var.cluster_name
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  # Referencing module.network.*_subnet_ids only orders this after the specific aws_subnet resources
  # behind those outputs, not after the NAT gateways and route table associations that never surface as
  # outputs (rules.md D-3).
  depends_on = [module.network]
}
# What lets VPC Lattice reach the pods. Lattice sends traffic from addresses in its own managed prefix
# lists rather than from anything inside the VPC, so without these two rules the target groups are
# built, registered and permanently unhealthy - with nothing in Kubernetes reporting a reason.
#
# They modify the cluster security group, which no module here owns outright, so they belong in the root
# (rules.md C-1). Standalone rule resources rather than inline blocks, because EKS adds its own rules to
# that group (rules.md F-2).
resource "aws_vpc_security_group_ingress_rule" "vpc_lattice_ipv4" {
  security_group_id = module.eks_cluster.cluster_security_group_id
  description       = "All traffic from the VPC Lattice IPv4 managed prefix list"
  ip_protocol       = "-1"
  prefix_list_id    = data.aws_ec2_managed_prefix_list.vpc_lattice.id
}
resource "aws_vpc_security_group_ingress_rule" "vpc_lattice_ipv6" {
  security_group_id = module.eks_cluster.cluster_security_group_id
  description       = "All traffic from the VPC Lattice IPv6 managed prefix list"
  ip_protocol       = "-1"
  prefix_list_id    = data.aws_ec2_managed_prefix_list.vpc_lattice_ipv6.id
}
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not exist until this addon
  # creates it. As a DaemonSet it reaches ACTIVE with zero nodes, so it comes before any capacity - and
  # nodes need it to join Ready (rules.md C-4). It is also what makes the whole project possible: VPC
  # Lattice target groups hold pod addresses, which are only routable in the VPC because this addon puts
  # them there.
  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as eks_vpc_cni_addon (rules.md C-4).
  depends_on = [module.network, module.eks_vpc_cni_addon]
}
# The agent behind the Gateway API controller's and the EBS CSI driver's Pod Identity associations, as
# the _monolithic template had it. A DaemonSet, so it reaches ACTIVE with no nodes (rules.md C-4).
module "eks_pod_identity_agent_addon" {
  source = "./modules/eks_pod_identity_agent_addon"

  cluster_name = module.eks_cluster.cluster_name

  depends_on = [module.network, module.eks_cluster]
}
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
  # (rules.md C-4). It also resolves the Lattice-assigned domain names the demo curls, so nothing here
  # is reachable before it is up.
  depends_on = [
  module.network, module.eks_node_group]
}
module "eks_ebs_csi_driver_addon" {
  source = "./modules/eks_ebs_csi_driver_addon"

  cluster_name = module.eks_cluster.cluster_name

  # The controller half of this addon is a Deployment, so it needs node capacity to leave DEGRADED - and
  # the Pod Identity agent has to be running before its credentials work (rules.md C-4/D-2).
  depends_on = [
  module.network, module.eks_node_group, module.eks_pod_identity_agent_addon]
}
module "csi_storage_classes" {
  source = "./modules/csi_storage_classes"

  storage_class_name = var.storage_class_name
  # No snapshot-controller addon here, so no VolumeSnapshotClass - its kind would not exist and the
  # manifest would fail at apply after a clean plan (rules.md B-4).
  create_volume_snapshot_class = false

  # kubectl_manifest resources against the cluster's API server, so ordering the module after the nodes
  # is what makes terraform destroy remove them while there is still a controller to process the
  # deletion (rules.md D-4).
  depends_on = [
  module.network, module.eks_node_group, module.eks_ebs_csi_driver_addon]
}
# The Gateway API kinds everything below is an instance of. Fetched from the pinned upstream release at
# plan time and split into one resource per document, so the CRDs are in state rather than applied with
# kubectl from a shell (rules.md E-1).
# The Gateway API CRD bundle, fetched here rather than inside the module that applies it.
#
# It belongs here because the module below carries a depends_on, and a depends_on on a module block defers
# every data source declared inside that module until apply. The module keys a for_each by the documents in
# this bundle, so they have to be known at plan time - a deferred read makes them unknown and the plan fails
# on the for_each rather than on the ordering that caused it (rules.md B-8/D-6).
#
# This data source carries no depends_on, so it is read during plan and everything derived from it is known.
# terraform plan therefore needs to reach this URL. That is a real new dependency and the reason it is
# overridable: a network with no route to github.com should point at a mirror rather than lose the approach.
locals {
  gateway_api_crd_url = var.gateway_api_crd_url == null ? "https://github.com/kubernetes-sigs/gateway-api/releases/download/${var.gateway_api_version}/${var.gateway_api_channel}-install.yaml" : var.gateway_api_crd_url
}
data "http" "gateway_api_bundle" {
  url = local.gateway_api_crd_url

  lifecycle {
    # Without this a 404 from a mistyped version is a body of HTML that then fails to parse as YAML,
    # several steps away from the cause.
    postcondition {
      condition     = self.status_code == 200
      error_message = "Fetching the Gateway API CRD bundle returned HTTP ${self.status_code} rather than 200. Check that gateway_api_version and gateway_api_channel name an existing release asset."
    }
  }
}
module "gateway_api_crds" {
  source = "./modules/gateway_api_crds"

  bundle_yaml = data.http.gateway_api_bundle.response_body
  bundle_url  = local.gateway_api_crd_url
  version_tag = var.gateway_api_version

  # CRDs need only the cluster's API server, but the module waits for each to be established - and
  # ordering it after the nodes keeps terraform destroy removing the CRDs after the objects that use
  # them, rather than orphaning finalizers (rules.md D-4).
  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}
# What turns those objects into VPC Lattice resources. IAM role, Pod Identity association and Helm
# release in one module (rules.md C-2).
module "vpc_lattice_gateway_controller" {
  source = "./modules/vpc_lattice_gateway_controller"

  cluster_name   = module.eks_cluster.cluster_name
  cluster_vpc_id = module.network.vpc_id
  aws_region     = data.aws_region.current.region
  aws_account_id = data.aws_caller_identity.current.account_id
  chart_version  = var.gateway_api_controller_chart_version
  # The same name the Gateway below carries. The controller pairs a Gateway with the service network of
  # its own name, so one variable feeds both rather than the string being written twice (rules.md B-5).
  default_service_network = var.gateway_name

  # The controller's own CRDs come with its chart, but it starts by listing Gateways and HTTPRoutes -
  # kinds that only exist once the bundle above is installed. It also needs CoreDNS to reach the AWS
  # APIs and the Pod Identity agent for its credentials (rules.md D-2).
  depends_on = [
    module.network,
    module.gateway_api_crds,
    module.eks_pod_identity_agent_addon,
    module.eks_coredns_addon,
  ]
}
# The Gateway, which becomes the VPC Lattice service network.
module "lattice_gateway" {
  source = "./modules/lattice_gateway"

  name      = var.gateway_name
  namespace = var.workload_namespace

  # Applied after the controller so the object is reconciled as soon as it exists. Ordering it here also
  # makes terraform destroy remove the Gateway while the controller is still alive, which is what lets
  # the Lattice service network be deleted rather than left behind (rules.md D-4).
  depends_on = [
  module.network, module.gateway_api_crds, module.vpc_lattice_gateway_controller]
}
# The four backends. One module instantiated per Service, keyed by name so the keys are literal strings
# in configuration rather than anything computed (rules.md B-8).
module "backend_service" {
  source   = "./modules/http_echo_service"
  for_each = var.backend_services

  name           = each.key
  namespace      = var.workload_namespace
  replicas       = each.value.replicas
  image          = var.backend_image
  service_port   = var.backend_service_port
  container_port = var.backend_container_port

  # Ordinary Deployments and Services to create, so for apply these need only nodes. The controller is in
  # the list for the sake of destroy. Once a route names one of these Services as a backendRef the
  # controller owns a finalizer on it, and clearing that finalizer is what deletes the Lattice target
  # group - so the Services have to go while the controller is still running. Without this edge Terraform
  # is free to tear them down alongside or after the controller, and the target groups are orphaned
  # (rules.md D-4/D-7).
  #
  # This list previously claimed in a comment to order these after the controller without naming it, which
  # is how the target groups survived the destroy that prompted this.
  depends_on = [
    module.network,
    module.eks_node_group,
    module.eks_coredns_addon,
    module.vpc_lattice_gateway_controller,
  ]
}
# The two routes, which are what the controller turns into VPC Lattice services.
#
# They demonstrate different things, and that is why there are two rather than one with more rules:
# inventory is the canary shape (a single weighted backend, ready for a second), rates is the path shape
# (one backend per prefix).
module "inventory_route" {
  source = "./modules/lattice_http_route"

  name          = "inventory"
  namespace     = var.workload_namespace
  gateway_name  = module.lattice_gateway.name
  listener_name = module.lattice_gateway.listener_name
  rules = [{
    # No path prefix: everything on this route goes to the backend below. Adding inventory-ver2 here
    # with a weight of its own is the whole canary demo, and the weight on the first backend is already
    # in place for it.
    backends = [{
      name   = module.backend_service["inventory-ver1"].name
      port   = module.backend_service["inventory-ver1"].service_port
      weight = var.inventory_route_weight
    }]
  }]

  depends_on = [
  module.network, module.lattice_gateway, module.backend_service]
}
module "rates_route" {
  source = "./modules/lattice_http_route"

  name          = "rates"
  namespace     = var.workload_namespace
  gateway_name  = module.lattice_gateway.name
  listener_name = module.lattice_gateway.listener_name
  rules = [
    {
      path_prefix = "/parking"
      backends = [{
        name = module.backend_service["parking"].name
        port = module.backend_service["parking"].service_port
      }]
    },
    {
      path_prefix = "/review"
      backends = [{
        name = module.backend_service["review"].name
        port = module.backend_service["review"].service_port
      }]
    },
  ]

  depends_on = [
  module.network, module.lattice_gateway, module.backend_service]
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  marker_file_path            = var.marker_file_path
  # Joining the cluster security group is what lets this instance reach the API server. The module is
  # handed an ID list and never learns it belongs to an EKS cluster (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]

  # An EKS cluster and this instance share a root module, so it is the workbench for that cluster and
  # carries all five tools (rules.md H-1). None of them creates anything: the Gateway API CRDs, the
  # controller, the StorageClass and every Gateway, Service and HTTPRoute the _monolithic template
  # installed from here are Terraform resources now (rules.md E-1).
  #
  # Bugs from that template that are not carried over. It ran "exec bash" partway through, which
  # replaces the shell and silently discarded every remaining line - eksctl, helm, the AWS Load Balancer
  # Controller install, the StorageClass, the Gateway API CRDs, the controller chart and every manifest
  # were all after it, so on a real boot none of them ran. It pulled eksctl from weaveworks rather than
  # eksctl-io. And it wrote the "complete" line for the k alias into .bashrc before the line that
  # defines __start_kubectl, so every login printed a "function not found" error (rules.md H-1).
  #
  # The AWS Load Balancer Controller it installed is gone too, along with the IAM role granting it ec2:*
  # and elasticloadbalancing:* and the Pod Identity association for it: nothing in this project creates
  # a Service of type LoadBalancer or an Ingress, which is the point of using VPC Lattice
  # (rules.md A-5).
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
    # Order matters: kubectl's completion defines __start_kubectl, and that has to exist before complete
    # names it, or every login prints "function not found" (rules.md H-1).
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
    rm get_helm.sh
    aws configure set default.region ${data.aws_region.current.region}
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}
    EOF
  EOT

  depends_on = [module.network]
}
# Granting the bastion's instance role cluster access joins two modules that know nothing about each
# other, so it belongs in the root (rules.md C-1).
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
  # Every output this project exposes, defined once. outputs.tf projects these and the README below
  # renders them, so no value expression is written twice (rules.md B-5/H-2).
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here. Every command below is meant to be run from its terminal - and for the curl commands that is not a convenience: a VPC Lattice service is only reachable from a VPC associated with its service network, which is this cluster's VPC"
      value       = module.vscode_ec2.vscode_url
    }
    cluster_name = {
      order       = 2
      title       = "EKS cluster name"
      description = "Name of the EKS cluster. The controller also tags every Lattice resource it creates with it"
      value       = module.eks_cluster.cluster_name
    }
    cluster_endpoint = {
      order       = 3
      title       = "EKS cluster endpoint"
      description = "API server endpoint. Public so the helm and kubectl providers could reach it during apply - narrow public_access_cidrs to your own address"
      value       = module.eks_cluster.cluster_endpoint
    }
    gateway_api_install = {
      order       = 4
      title       = "What was installed"
      description = "The Gateway API release and the controller that implements it. Both pinned, where the _monolithic template applied a CRD bundle from a URL and a chart from a registry it had to log in to first - and the versions have to be a supported pair, because a controller older than the CRDs ignores fields it does not know rather than rejecting them"
      value       = "Gateway API ${module.gateway_api_crds.version_tag} (${module.gateway_api_crds.document_count} documents), controller chart ${module.vpc_lattice_gateway_controller.chart_version}"
    }
    lattice_prefix_lists = {
      order       = 5
      title       = "How Lattice reaches the pods"
      description = "The managed prefix lists the cluster security group accepts traffic from. Without these rules the target groups are built, registered and permanently unhealthy, with nothing in Kubernetes saying why. The _monolithic template found these IDs with a Lambda function that could not have worked - this is two data sources"
      value       = "${data.aws_ec2_managed_prefix_list.vpc_lattice.name} (${data.aws_ec2_managed_prefix_list.vpc_lattice.id}), ${data.aws_ec2_managed_prefix_list.vpc_lattice_ipv6.name} (${data.aws_ec2_managed_prefix_list.vpc_lattice_ipv6.id})"
    }
    service_network_check_command = {
      order       = 6
      title       = "1. Confirm the service network exists"
      description = "The first thing the controller creates on the AWS side. An empty list means it has not made a single successful call - check its log and its Pod Identity association before looking at any Kubernetes object"
      value       = module.vpc_lattice_gateway_controller.service_network_check_command
    }
    gateway_status_command = {
      order       = 7
      title       = "2. Confirm the Gateway was programmed"
      description = "An empty ADDRESS with PROGRAMMED False is the controller not having built the service network for it. The Gateway and the controller's defaultServiceNetwork are paired by name, and both come from one variable here so they cannot differ"
      value       = module.lattice_gateway.status_command
    }
    route_status_command = {
      order       = 8
      title       = "3. Confirm both routes attached"
      description = "A route with no parent listed is one the Gateway's listener did not allow, or one whose sectionName names a listener that does not exist. Both are reported only in the route's own status"
      value       = "kubectl -n ${var.workload_namespace} get httproute -o wide"
    }
    inventory_domain_command = {
      order       = 9
      title       = "4. Read the inventory route's Lattice address"
      description = "The controller writes it back as an annotation once the Lattice service is built, so it is empty until then - and it cannot be known at apply time, which is why this is a command rather than an output value"
      value       = module.inventory_route.domain_name_command
    }
    inventory_curl_command = {
      order       = 10
      title       = "5. Call the inventory route"
      description = "Run it several times. The response names the pod that answered, and with two replicas behind one weighted backend the names alternate - which is the Lattice target group holding both pod addresses rather than a Service load-balancing between them"
      value       = module.inventory_route.curl_command
    }
    rates_curl_command = {
      order       = 11
      title       = "6. Call the rates route on both paths"
      description = "The path shape rather than the canary shape: /parking and /review reach different Services through one Lattice service. Appending each path to the domain name shows the rules being matched in order"
      value       = "RATES=$(${replace(module.rates_route.domain_name_command, "'", "")}); echo \"http://$RATES/parking and http://$RATES/review\""
    }
    controller_logs_command = {
      order       = 12
      title       = "7. If anything above is empty"
      description = "The controller's log is where every reason lives. An AccessDenied is the Pod Identity association or the policy; a reconcile error names the object it could not build. Neither appears on the Kubernetes objects themselves"
      value       = module.vpc_lattice_gateway_controller.logs_command
    }
    target_group_check_command = {
      order       = 13
      title       = "8. Read the Lattice target groups"
      description = "What the controller registered, and whether the targets are healthy. Unhealthy targets with everything else green is the security group question above - Lattice traffic arrives from its managed prefix lists, not from inside the VPC"
      value       = "aws vpc-lattice list-target-groups --query 'items[].[name,type,status]' --output table"
    }
    update_kubeconfig_command = {
      order       = 14
      title       = "Re-point kubectl"
      description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the order field and
  # taking values() - which returns a map's values ordered by key - makes the README read top to bottom
  # while the order stays decided by configuration.
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
    # bootstrap (rules.md D-5). The marker path comes back out of the module it was passed into, so it is
    # defined once (rules.md B-5).
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
