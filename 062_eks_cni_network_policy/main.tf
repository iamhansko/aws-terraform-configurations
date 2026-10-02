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
# The variant. Everything else in this root exists to give this addon something to
# enforce policies on.
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name
  # What this project is for: the network policy agent the addon runs alongside
  # aws-node. The _monolithic template set it through the same configuration_values
  # key, which is the one part of that template this variant already had right - the
  # conversion keeps it as a typed bool instead of a heredoc string (rules.md E-5).
  enable_network_policy = var.enable_network_policy

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not exist
  # until this addon creates it. As a DaemonSet it reaches ACTIVE with zero nodes, so it
  # comes before any capacity (rules.md C-4) - and nodes need it to join Ready. It is
  # also what makes target-type ip work, by making pod addresses routable in the VPC
  # (rules.md G-1).
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
  # ACTIVE (rules.md C-4). The probes also address each other by Service DNS name, so
  # nothing in the demo reports green until this is up.
  depends_on = [
  module.network, module.eks_node_group]
}
# The controller that turns the management UI's Service into an NLB. Its IRSA role and
# Helm release are one module, because the release has to annotate the service account
# with the role's ARN (rules.md C-2). The _monolithic template installed it with a helm
# command in userdata, after an eksctl call that built a CloudFormation stack Terraform
# knew nothing about (rules.md E-1).
module "aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"

  cluster_name      = module.eks_cluster.cluster_name
  vpc_id            = module.network.vpc_id
  aws_region        = data.aws_region.current.region
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  chart_version     = var.aws_load_balancer_controller_chart_version
  # The management UI Service does not set manage-backend-security-group-rules, so
  # nothing asks the controller to write node-side rules and this can stay false. The
  # path from the load balancer to the pod is declared below instead (rules.md G-2).
  enable_backend_security_group = false
  # Off: the one Service of type LoadBalancer here names the controller itself with the
  # aws-load-balancer-type annotation, so the webhook has nothing to mutate, and its
  # failurePolicy: Fail would otherwise gate all six of this project's Services behind a
  # controller pod being Ready (rules.md G-4).
  enable_service_mutator_webhook = var.enable_service_mutator_webhook

  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}
locals {
  # The stack tag the pre-created load balancer must carry to be adopted rather than
  # duplicated (rules.md G-3).
  #
  # Derived here rather than read from the workload module's output: the load balancer
  # needs this value before that module runs, and taking it from the module would make
  # the load balancer depend on the workload while the workload has to wait for the load
  # balancer. Both sides read var.management_ui_namespace/name, so there is still one
  # definition (rules.md B-5).
  management_ui_stack_tag = "${var.management_ui_namespace}/${var.management_ui_name}"
}
# Standalone rule resources rather than inline blocks, and revoke_rules_on_delete,
# because the controller adds its own rules to this group (rules.md F-2). The
# _monolithic template built the NLB with the VPC's default security group while its
# Service annotation asked for a separate "nlb-sg" - so the two disagreed about which
# group the load balancer actually had.
module "load_balancer_security_group" {
  source = "./modules/load_balancer_security_group"

  vpc_id      = module.network.vpc_id
  name        = var.load_balancer_security_group_name
  description = "Frontend security group for the NLB fronting the Calico stars management UI"
  # Only the Service port. Unlike an ingress controller, this Service publishes a single
  # port, so there is one listener and one rule (rules.md G-1).
  ports = {
    http = var.management_ui_service_port
  }
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere

  depends_on = [module.network]
}
# Created here and adopted by the controller rather than left for the controller to
# create. That is what makes its DNS name known at apply time, so the management UI URL
# is a real output instead of a kubectl command - and it is the only way this NLB can
# carry a security group at all, since AWS refuses to add security groups to an NLB after
# creation (rules.md G-3).
module "synced_load_balancer" {
  source = "./modules/synced_load_balancer"

  cluster_name       = module.eks_cluster.cluster_name
  name               = var.synced_load_balancer_name
  load_balancer_type = "network"
  internal           = false
  # internet-facing, so public subnets - this has to agree with the scheme the Service
  # annotates, or the controller builds a second load balancer instead of adopting this
  # one (rules.md G-3).
  subnet_ids         = module.network.public_subnet_ids
  security_group_ids = [module.load_balancer_security_group.security_group_id]
  # service.k8s.aws/*, not ingress.k8s.aws/*: this load balancer fronts a Service of type
  # LoadBalancer. The wrong prefix is not an error - the controller simply does not adopt,
  # and builds its own (rules.md G-3).
  resource_tag_prefix = "service"
  stack               = local.management_ui_stack_tag

  depends_on = [module.network]
}
module "stars_policy_workload" {
  source = "./modules/stars_policy_workload"

  management_ui_namespace = var.management_ui_namespace
  management_ui_name      = var.management_ui_name
  # Both ports, from the same variables the security group and the pod-side rule read, so
  # the Service, the listener and the two rules cannot disagree (rules.md B-5/G-1).
  management_ui_service_port   = var.management_ui_service_port
  management_ui_container_port = var.management_ui_container_port
  scheme                       = "internet-facing"
  nlb_target_type              = "ip"
  frontend_security_group_ids  = [module.load_balancer_security_group.security_group_id]
  # The demo's policies are Terraform resources like everything else, so they are in
  # state, appear in plan and are destroyed in order (rules.md E-1/E-2). Set false to see
  # the unrestricted graph rather than deleting them with kubectl, which the next apply
  # would undo (rules.md B-4).
  apply_network_policies = var.apply_network_policies

  # The load balancer has to exist before the controller reconciles this Service, or the
  # controller creates its own and the pre-created one is orphaned (rules.md G-3). The
  # controller must also be running, otherwise the in-tree cloud provider claims the
  # Service and builds a Classic Load Balancer, ignoring every annotation (rules.md G-1).
  #
  # The node group and CoreDNS are here because these are kubectl_manifest resources
  # against the cluster's API server: ordering the module after the nodes makes
  # terraform destroy remove the manifests while the controller is still alive, so the
  # load balancer is cleaned up rather than orphaned, and a Service deleted after the
  # controller is gone does not hang (rules.md D-4).
  depends_on = [
    module.network,
    module.eks_node_group,
    module.eks_coredns_addon,
    module.aws_load_balancer_controller,
    module.synced_load_balancer,
  ]
}
# With manage-backend-security-group-rules unset the controller writes no node-side rules
# at all, so the path from load balancer to pod has to be declared here or the target
# stays unhealthy with no error anywhere (rules.md G-2). target-type is ip, so traffic
# arrives at the management UI pod's container port - not the Service port - and pods on
# this cluster use the cluster security group.
#
# It modifies the cluster security group, which no module here owns outright, so it
# belongs in the root (rules.md C-1).
resource "aws_vpc_security_group_ingress_rule" "load_balancer_to_pods" {
  security_group_id            = module.eks_cluster.cluster_security_group_id
  description                  = "Management UI container port from the NLB frontend security group"
  ip_protocol                  = "tcp"
  from_port                    = var.management_ui_container_port
  to_port                      = var.management_ui_container_port
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
  # Joining the cluster security group is what lets this instance reach the API server.
  # The module is handed an ID list and never learns it belongs to an EKS cluster
  # (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]

  # An EKS cluster and this instance share a root module, so it is the workbench for that
  # cluster and carries all five tools (rules.md H-1). None of them creates anything: the
  # controller and the demo objects the _monolithic template installed from here are
  # Terraform resources now (rules.md E-1).
  #
  # Two bugs from that template are fixed here rather than carried over. It ran
  # "exec bash" partway through, which replaces the shell and silently discarded every
  # remaining line - update-kubeconfig, eksctl and helm were all after it, so none of
  # them ever ran. And it pulled eksctl from weaveworks; eksctl-io is the project's own
  # org (rules.md H-1).
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
      description = "API server endpoint. Public so the kubectl and helm providers could reach it during apply - narrow public_access_cidrs to your own address"
      value       = module.eks_cluster.cluster_endpoint
    }
    management_ui_url = {
      order       = 4
      title       = "Stars management UI"
      description = "The graph. Every arrow is green to begin with, which is the starting state of the demo rather than a sign that policies are missing. The address is known from state because Terraform created the load balancer and the controller adopted it (rules.md G-3)"
      value       = module.synced_load_balancer.url
    }
    network_policy_enforcement = {
      order       = 5
      title       = "Network policy enforcement"
      description = "Whether the VPC CNI is enforcing NetworkPolicy objects. This is the switch the whole demo depends on: with it off every policy below is accepted by the API server and quietly ignored, so the graph never changes"
      value       = "enableNetworkPolicy=${module.eks_vpc_cni_addon.network_policy_enabled} on the vpc-cni addon"
    }
    graph_check_command = {
      order       = 6
      title       = "1. Confirm every probe is running"
      description = "The graph shows nothing until all four pods are Running, and a pod still pulling its image looks the same as one being denied. Run this before reading anything into the UI"
      value       = module.stars_policy_workload.graph_check_command
    }
    adopted_load_balancer_check_command = {
      order       = 7
      title       = "2. Confirm the load balancer was adopted, not duplicated"
      description = "Lists every load balancer tagged for this cluster. One is correct. Two means the controller did not adopt the pre-created one and built its own, which is a tag mismatch rather than an error (rules.md G-3)"
      value       = "aws resourcegroupstaggingapi get-resources --tag-filters Key=elbv2.k8s.aws/cluster,Values=${module.eks_cluster.cluster_name} --resource-type-filters elasticloadbalancing:loadbalancer --query 'ResourceTagMappingList[].ResourceARN' --output table"
    }
    ingress_hostname_command = {
      order       = 8
      title       = "3. Read the address the controller attached"
      description = "Compare this against the management UI URL above. They should be the same load balancer"
      value       = module.stars_policy_workload.load_balancer_hostname_command
    }
    expected_graph = {
      order       = 9
      title       = "4. What the graph should show"
      description = "The apply already created the policies, so this is the finished state rather than a starting point. Exactly three connections survive: the UI reaches all three probes, the frontend reaches the backend, and the client reaches the frontend. Every other arrow is red, and that is the demo working rather than something broken"
      value       = "policies applied: ${module.stars_policy_workload.network_policies_applied} (${join(", ", module.stars_policy_workload.network_policy_names)})"
    }
    policy_list_command = {
      order       = 10
      title       = "5. List what is in force"
      description = "Every policy Terraform created. If the graph does not match what these say, check the enforcement switch above before suspecting the policies - an unenforced policy is accepted silently"
      value       = module.stars_policy_workload.policy_list_command
    }
    policy_describe_command = {
      order       = 11
      title       = "6. Read how they combine"
      description = "Policies are additive: a pod's effective rules are the union of every policy selecting it, which is why default-deny and allow-ui coexist rather than one overriding the other. This is where that union is visible"
      value       = module.stars_policy_workload.policy_describe_command
    }
    unrestricted_graph_command = {
      order       = 12
      title       = "7. See the unrestricted graph"
      description = "Walk the demo backwards without fighting Terraform. Removing the policies with kubectl also works, but the next apply puts them straight back, which looks like them reappearing on their own. Re-run without the flag to restore them"
      value       = "terraform apply -var apply_network_policies=false"
    }
    update_kubeconfig_command = {
      order       = 13
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
    # SSM runs as root, hence the chown over both the README and the manifests directory.
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
