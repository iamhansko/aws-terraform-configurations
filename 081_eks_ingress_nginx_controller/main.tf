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
  # The tags the AWS Load Balancer Controller discovers subnets by. Without them it
  # refuses both load balancers with "couldn't auto-discover subnets" (rules.md G-1).
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
  # resources behind those outputs, not after the NAT gateways and route table
  # associations that never surface as outputs (rules.md D-3).
  depends_on = [module.network]
}
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not exist until
  # this addon creates it. As a DaemonSet it reaches ACTIVE with zero nodes, so it comes
  # before any capacity - and nodes need it to join Ready (rules.md C-4). It is also what
  # makes nlb-target-type: ip work, by making pod addresses routable in the VPC
  # (rules.md G-1).
  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as eks_vpc_cni_addon (rules.md C-4).
  depends_on = [module.network, module.eks_vpc_cni_addon]
}
# The agent behind the EBS CSI driver's Pod Identity association. A DaemonSet, so it reaches
# ACTIVE with no nodes, but the driver's credentials do not work until it is running - hence
# its own module and its own place in the order (rules.md C-4).
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

  # coredns is a Deployment and needs schedulable capacity to leave DEGRADED and become
  # ACTIVE (rules.md C-4). The ingress controllers resolve their upstream Services by name,
  # so nothing works before this is up either.
  depends_on = [
  module.network, module.eks_node_group]
}
# What answers the demo's PersistentVolumeClaim. Its IAM role and the addon are one module
# because the role exists for exactly one service account and the addon is what binds it
# (rules.md C-2).
module "eks_ebs_csi_driver_addon" {
  source = "./modules/eks_ebs_csi_driver_addon"

  cluster_name = module.eks_cluster.cluster_name

  # The controller half of this addon is a Deployment, so it needs node capacity to leave
  # DEGRADED - and the Pod Identity agent has to be running before its credentials work
  # (rules.md C-4/D-2).
  depends_on = [
  module.network, module.eks_node_group, module.eks_pod_identity_agent_addon]
}
# What turns each ingress controller's Service into an NLB. Its IRSA role and Helm release
# are one module, because the release has to annotate the service account with the role's
# ARN (rules.md C-2).
#
# The _monolithic template installed this with a helm command in the instance's user data -
# placed after an "exec bash" line that replaces the shell and discards everything following
# it, so on a real boot the controller was never installed at all and neither ingress
# controller Service ever got a load balancer (rules.md E-1/H-1).
module "aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"

  cluster_name      = module.eks_cluster.cluster_name
  vpc_id            = module.network.vpc_id
  aws_region        = data.aws_region.current.region
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  chart_version     = var.aws_load_balancer_controller_chart_version
  # False, so the controller writes no node-side rules and does not create its shared
  # k8s-traffic-<cluster> group. The two ingress controller Services carry their own frontend
  # security group and deliberately do not set manage-backend-security-group-rules, so the
  # path from load balancer to pod is declared below instead - where it is visible in plan
  # (rules.md G-2). The _monolithic template set that annotation to "true" on both Services
  # while leaving this at the controller's default, which is the one combination that works;
  # this is the other one.
  enable_backend_security_group = false
  # Off: both Services of type LoadBalancer here name the controller themselves with
  # aws-load-balancer-type, so the webhook has nothing to mutate, and its failurePolicy: Fail
  # would otherwise gate every Service creation in the cluster behind a controller pod being
  # Ready (rules.md G-4).
  enable_service_mutator_webhook = var.enable_service_mutator_webhook

  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}
locals {
  # The Service each ingress-nginx release creates, and the stack tag its load balancer has
  # to carry to be adopted rather than duplicated (rules.md G-3).
  #
  # Derived here rather than read from the ingress modules' outputs: each load balancer needs
  # its tag before the release that creates the Service runs, and taking the value from the
  # release would make the load balancer depend on the release while the release has to wait
  # for the load balancer. One definition, handed to both sides (rules.md B-5).
  #
  # <release>-controller, because the ingress module pins the chart's fullname to the release
  # name with fullnameOverride. Left to itself the chart chooses between that and
  # <release>-ingress-nginx-controller by testing whether the release name happens to contain
  # the chart name, and a wrong guess here is not an error - the tag then matches no Service,
  # the controller adopts nothing, and the only symptom is a second load balancer.
  ingress_release_names = {
    for class in var.ingress_classes : class => "${var.ingress_release_name_prefix}-${class}"
  }
  ingress_service_names = {
    for class in var.ingress_classes : class => "${local.ingress_release_names[class]}-controller"
  }
  ingress_stack_tags = {
    for class in var.ingress_classes : class => "${var.ingress_namespace}/${local.ingress_service_names[class]}"
  }
  # Each class gets its own controllerValue. Two IngressClasses sharing one would make both
  # controllers reconcile both classes, which produces two load balancers serving the same
  # Ingress - derived from the class name so the pair cannot disagree (rules.md B-1).
  ingress_class_controller_values = {
    for class in var.ingress_classes : class => "ingress.nginx/${class}"
  }
  # The classes the demo Ingress is not currently using. Sorted so the suggested command below
  # is stable, and allowed to be empty because ingress_classes may hold a single class.
  other_ingress_classes = [
    for class in sort(tolist(var.ingress_classes)) : class if class != var.workload_ingress_class
  ]
}
# One group for both load balancers, as the _monolithic template shared one between them.
# Standalone rule resources rather than inline blocks, and revoke_rules_on_delete, because
# AWS refuses to delete a group while rules reference it and the controller may add its own
# (rules.md F-2).
module "load_balancer_security_group" {
  source = "./modules/load_balancer_security_group"

  vpc_id      = module.network.vpc_id
  name        = var.load_balancer_security_group_name
  description = "Frontend security group shared by the NLBs in front of both ingress-nginx controllers"
  # Both ports the chart's Service publishes. The same map goes to each release's Service and
  # to load_balancer_to_pods below, so the three cannot drift apart (rules.md B-5). The
  # original opened only 80, leaving each NLB with a 443 listener nothing could reach.
  ports                       = var.load_balancer_ports
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere

  depends_on = [module.network]
}
# One NLB per ingress class, created here and adopted by the controller rather than left for
# the controller to create. That makes both addresses known from state at apply time, which is
# what lets this project's outputs say which URL belongs to which class - and it is the only
# way these NLBs can carry a security group at all, since AWS refuses to add security groups
# to an NLB after creation (rules.md G-3).
module "synced_load_balancer" {
  source   = "./modules/synced_load_balancer"
  for_each = var.ingress_classes

  cluster_name       = module.eks_cluster.cluster_name
  load_balancer_type = "network"
  internal           = false
  # internet-facing, so public subnets - this has to agree with the scheme each release
  # annotates, or the controller builds a second load balancer instead of adopting this one
  # (rules.md G-3).
  subnet_ids         = module.network.public_subnet_ids
  security_group_ids = [module.load_balancer_security_group.security_group_id]
  # service.k8s.aws/*, not ingress.k8s.aws/*: these front Services of type LoadBalancer, not
  # Ingresses. The Ingress objects in this project are served by nginx, which is itself behind
  # one of these Services - so as far as the AWS controller is concerned there is no Ingress
  # here at all. The wrong prefix is not an error; the controller simply does not adopt
  # (rules.md G-3).
  resource_tag_prefix = "service"
  stack               = local.ingress_stack_tags[each.key]

  depends_on = [module.network]
}
# The subject of this project: one ingress-nginx release per class, each owning its own
# IngressClass and its own load balancer.
#
# The _monolithic template installed both with a shell script it wrote out of an SSM
# Association, so neither release was in state: no diff in plan, nothing uninstalled on
# destroy, and a failed release left behind for the next run to trip over (rules.md E-1/E-7).
module "ingress_nginx" {
  source   = "./modules/ingress_nginx"
  for_each = var.ingress_classes

  release_name = local.ingress_release_names[each.key]
  namespace    = var.ingress_namespace
  # kube-system already exists, so neither release may try to create it.
  create_namespace               = false
  service_name                   = local.ingress_service_names[each.key]
  stack_tag                      = local.ingress_stack_tags[each.key]
  chart_version                  = var.ingress_nginx_chart_version
  ingress_class_name             = each.key
  ingress_class_controller_value = local.ingress_class_controller_values[each.key]
  # False on both. With two releases, each marking its own class the cluster default would
  # leave an Ingress that names no class ambiguous.
  set_as_default_ingress_class = false
  scheme                       = "internet-facing"
  nlb_target_type              = "ip"
  service_ports                = var.load_balancer_ports
  frontend_security_group_ids  = [module.load_balancer_security_group.security_group_id]

  # The load balancer has to exist before the controller reconciles this Service, or the
  # controller creates its own and the pre-created one is orphaned (rules.md G-3). The AWS
  # Load Balancer Controller must also be running, otherwise the in-tree cloud provider claims
  # the Service and builds a Classic Load Balancer, ignoring every annotation - which is what
  # the _monolithic template's Services would have done, since none of them set
  # aws-load-balancer-type (rules.md G-1).
  depends_on = [
    module.network,
    module.synced_load_balancer,
    module.aws_load_balancer_controller,
    module.eks_coredns_addon,
  ]
}
# With manage-backend-security-group-rules unset the controller writes no node-side rules at
# all, so the path from load balancer to ingress controller pod has to be declared here or
# every target stays unhealthy with no error anywhere (rules.md G-2). nlb-target-type is ip,
# so traffic arrives at the nginx pod's container port rather than a NodePort, and pods on
# this cluster use the cluster security group.
#
# One rule per published port, covering both load balancers because they share one frontend
# group. It modifies the cluster security group, which no module here owns outright, so it
# belongs in the root (rules.md C-1).
resource "aws_vpc_security_group_ingress_rule" "load_balancer_to_pods" {
  for_each                     = var.load_balancer_ports
  security_group_id            = module.eks_cluster.cluster_security_group_id
  description                  = "Ingress controller ${each.key} port from the shared NLB frontend security group"
  ip_protocol                  = "tcp"
  from_port                    = each.value
  to_port                      = each.value
  referenced_security_group_id = module.load_balancer_security_group.security_group_id
}
# The gp3 StorageClass the demo's claim asks for.
module "csi_storage_classes" {
  source = "./modules/csi_storage_classes"

  storage_class_name = var.storage_class_name
  # No snapshot-controller addon here, so no VolumeSnapshotClass - its kind would not exist
  # and the manifest would fail at apply after a clean plan (rules.md B-4).
  create_volume_snapshot_class = false

  # kubectl_manifest resources against the cluster's API server, so ordering the module after
  # the nodes is what makes terraform destroy remove them while there is still a controller to
  # process the deletion (rules.md D-4).
  depends_on = [
  module.network, module.eks_node_group, module.eks_ebs_csi_driver_addon]
}
module "todo_workload" {
  source = "./modules/todo_workload"

  name        = var.workload_name
  namespace   = var.workload_namespace
  path_prefix = var.workload_path_prefix
  # Taken from the class the controllers actually own rather than restated, and checked
  # against ingress_classes by a validation - an Ingress naming an unowned class never gets an
  # address and reports nothing (rules.md B-1/B-5).
  ingress_class_name = var.workload_ingress_class
  # Taken from the module that created the class. A claim naming a class that does not exist
  # stays Pending and the pod never starts (rules.md B-5).
  storage_class_name = module.csi_storage_classes.storage_class_name

  # The ingress controller that serves this Ingress has to be running, or the Ingress sits
  # without an address. Ordering the module after the releases also means terraform destroy
  # removes the Ingress while its controller is still alive, so the load balancer's listener
  # rules are cleaned up rather than orphaned (rules.md D-4).
  depends_on = [
    module.network,
    module.eks_node_group,
    module.eks_coredns_addon,
    module.eks_ebs_csi_driver_addon,
    module.csi_storage_classes,
    module.ingress_nginx,
  ]
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
  # cluster and carries all five tools (rules.md H-1). None of them creates anything: the two
  # Helm releases and every manifest the _monolithic template applied from here are Terraform
  # resources now (rules.md E-1).
  #
  # Three bugs from that template are fixed here rather than carried over. It ran "exec bash"
  # partway through, which replaces the shell and silently discarded every remaining line -
  # update-kubeconfig, eksctl, helm and the AWS Load Balancer Controller install were all
  # after it, so on a real boot none of them ran. It pulled eksctl from weaveworks rather than
  # eksctl-io. And it wrote the "complete" line for the k alias into .bashrc before the line
  # that defines __start_kubectl, so every login printed a "function not found" error
  # (rules.md H-1).
  additional_user_data = <<-EOT
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server is already running and predates the docker group, so its terminals would
    # not have it without a restart.
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
    # before complete names it, or every login prints "function not found" (rules.md H-1).
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
    cluster_name = {
      order       = 2
      title       = "EKS cluster name"
      description = "Name of the EKS cluster. The AWS Load Balancer Controller also writes this into the elbv2.k8s.aws/cluster tag it uses to find load balancers it owns"
      value       = module.eks_cluster.cluster_name
    }
    cluster_endpoint = {
      order       = 3
      title       = "EKS cluster endpoint"
      description = "API server endpoint. Public, unlike the _monolithic template's private one, so the helm and kubectl providers could reach it during apply - narrow public_access_cidrs to your own address"
      value       = module.eks_cluster.cluster_endpoint
    }
    ingress_classes = {
      order       = 4
      title       = "Ingress classes and their controllers"
      description = "One ingress-nginx release per class, each with its own controllerValue. That value is what each controller pod matches on, and giving two classes the same one would make both controllers serve both - producing two load balancers for one Ingress and no error anywhere"
      value       = join("\n", [for class in sort(tolist(var.ingress_classes)) : "${class}: controllerValue=${local.ingress_class_controller_values[class]}, service=${local.ingress_service_names[class]}"])
    }
    load_balancer_urls = {
      order       = 5
      title       = "One load balancer per class"
      description = "Terraform created these and the controller adopted them, which is why their addresses are known from state rather than only after the controller has reconciled (rules.md G-3). Only the class the demo Ingress names serves the app; the other answers with nginx's default backend, and that is the point rather than a fault"
      value       = join("\n", [for class in sort(tolist(var.ingress_classes)) : "${class}: ${module.synced_load_balancer[class].url}"])
    }
    app_url = {
      order       = 6
      title       = "Demo app URL"
      description = "The app, through the class it currently names. One prefix reaches uvicorn's --root-path, the Ingress path regex and the rewrite annotation, so this URL is built from the same value all three read"
      value       = "${module.synced_load_balancer[var.workload_ingress_class].url}${module.todo_workload.docs_path}"
    }
    adopted_load_balancer_check_command = {
      order       = 7
      title       = "1. Confirm both load balancers were adopted, not duplicated"
      description = "Lists every load balancer tagged for this cluster. Two is correct here, one per class. Four means the controller adopted neither of the pre-created ones and built its own pair, which is a tag mismatch rather than an error (rules.md G-3)"
      value       = "aws resourcegroupstaggingapi get-resources --tag-filters Key=elbv2.k8s.aws/cluster,Values=${module.eks_cluster.cluster_name} --resource-type-filters elasticloadbalancing:loadbalancer --query 'ResourceTagMappingList[].ResourceARN' --output table"
    }
    ingress_class_list_command = {
      order       = 8
      title       = "2. Read the IngressClasses the cluster has"
      description = "Both classes with their controller values. Neither should be marked default: with two controllers a default class makes an Ingress that names no class ambiguous"
      value       = "kubectl get ingressclass -o custom-columns=NAME:.metadata.name,CONTROLLER:.spec.controller,DEFAULT:.metadata.annotations.ingressclass\\.kubernetes\\.io/is-default-class"
    }
    workload_rollout_command = {
      order       = 9
      title       = "3. Wait for the app"
      description = "Longer than it looks: the claim provisions an EBS volume only once the pod is scheduled, MySQL initialises its data directory on first start, and the app container restarts until that finishes"
      value       = module.todo_workload.rollout_status_command
    }
    claim_status_command = {
      order       = 10
      title       = "4. Confirm the volume was provisioned"
      description = "A claim stuck Pending after the pod is scheduled means no provisioner answered, which points at the EBS CSI driver addon rather than at the app - and from the Ingress's side it looks like the controller is broken"
      value       = module.todo_workload.claim_status_command
    }
    ingress_status_command = {
      order       = 11
      title       = "5. Read the Ingress and the address its controller attached"
      description = "Compare the ADDRESS against the URL for that class above. An empty ADDRESS means no controller claimed the Ingress, which is almost always the class name"
      value       = module.todo_workload.ingress_status_command
    }
    switch_class_command = {
      order       = 12
      title       = "6. Move the app to the other class"
      description = "The demo. Nothing about the app, the Service or the load balancers changes - only which class the Ingress names - and the app then answers on the other load balancer's address while the first falls back to nginx's default backend"
      value = (length(local.other_ingress_classes) > 0
        ? "terraform apply -var workload_ingress_class=${local.other_ingress_classes[0]}"
      : "Only one class is configured, so there is nowhere to move the Ingress. Add a second entry to ingress_classes first.")
    }
    other_class_check_command = {
      order       = 13
      title       = "7. Confirm the unused class serves nothing"
      description = "Requesting the app's path on the class the Ingress does not name should return nginx's 404 default backend rather than the app. That is the isolation the two controllers give: an Ingress is reconciled only by the controller whose class it names"
      value       = join("\n", [for class in sort(tolist(var.ingress_classes)) : "curl -sS -o /dev/null -w '${class}: %%{http_code}\\n' ${module.synced_load_balancer[class].url}${module.todo_workload.docs_path}"])
    }
    controller_logs_command = {
      order       = 14
      title       = "8. Read a controller's log"
      description = "Each release has its own controller pod. Whether it picked up the Ingress is in here, and an Ingress naming the other class leaves no trace at all in this one - which is how to tell 'not mine' from 'mine and broken'"
      value       = "kubectl -n ${var.ingress_namespace} logs deploy/${local.ingress_service_names[var.workload_ingress_class]} --tail 50"
    }
    update_kubeconfig_command = {
      order       = 15
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
