data "aws_region" "current" {}
module "network" {
  source = "./modules/network"
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name = var.key_name

  # key_pair consumes no network output, so nothing would otherwise order it
  # against the network module's resources. Every module in a root that has a
  # network module waits for all of it (rules.md D-3).
  depends_on = [module.network]
}
module "eks_cluster" {
  source = "./modules/eks_cluster"

  name                   = var.cluster_name
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  # Referencing module.network.*_subnet_ids only orders this module after the
  # specific aws_subnet resources behind those outputs, not after the NAT
  # gateways and route table associations that never surface as outputs
  # (rules.md D-3).
  depends_on = [module.network]
}
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not
  # exist until this addon creates it. As a DaemonSet it reaches ACTIVE with
  # zero nodes, so it is created before any node capacity - worker nodes need it
  # running to join the cluster Ready (rules.md C-4). It also has to be running
  # before the NLB can register pod IPs as targets, since nlb_target_type = ip
  # relies on the CNI making pod IPs routable in the VPC.
  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as eks_vpc_cni_addon: kube-proxy is a DaemonSet and must
  # exist before any node capacity (rules.md C-4).
  depends_on = [module.network, module.eks_cluster]
}
module "eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name    = module.eks_cluster.cluster_name
  node_group_name = var.node_group_name
  labels          = var.node_group_labels
  instance_types  = var.node_group_instance_types
  desired_size    = var.node_group_desired_size
  min_size        = var.node_group_min_size
  max_size        = var.node_group_max_size
  subnet_ids      = module.network.private_subnet_ids
  key_name        = module.key_pair.key_name

  # Nodes need vpc-cni and kube-proxy running to join the cluster Ready
  # (rules.md C-4).
  depends_on = [module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.eks_cluster.cluster_name

  # coredns is a Deployment and needs schedulable node capacity to leave its
  # DEGRADED state and become ACTIVE, so it is created after the node group
  # rather than before it (rules.md C-4).
  depends_on = [module.eks_node_group]
}
module "eks_metrics_server_addon" {
  source = "./modules/eks_metrics_server_addon"

  cluster_name = module.eks_cluster.cluster_name

  # metrics-server is a Deployment, so like coredns it needs schedulable node
  # capacity to become ACTIVE rather than DEGRADED (rules.md C-4).
  depends_on = [module.eks_node_group]
}
module "aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"

  cluster_name      = module.eks_cluster.cluster_name
  vpc_id            = module.network.vpc_id
  aws_region        = data.aws_region.current.region
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  chart_version     = var.load_balancer_controller_chart_version
  # False, as in every variant of this project. No workload here sets the
  # manage-backend-security-group-rules annotation, so nothing asks the
  # controller to write rules onto the cluster security group, and the shared
  # backend security group it would need to name as the source in those rules is
  # never required. The NLB therefore carries only the frontend group declared
  # below, and no k8s-traffic-<cluster> group is created.
  #
  # Turning this off while a workload does set that annotation is what the
  # controller rejects, with "backendSG feature is required to manage worker node
  # SG rules when frontendSG manually specified" - and it fails while building the
  # load balancer model, so nothing is provisioned and the reason appears only in
  # the controller's log (rules.md G-2).
  enable_backend_security_group = var.enable_backend_security_group

  # The controller is a Deployment with wait = true, so it needs schedulable
  # capacity and working cluster DNS before the release can report ready
  # (rules.md D-2).
  depends_on = [module.network, module.eks_coredns_addon]
}
# Like every variant in project 008, this one has the controller attach a
# caller-supplied frontend security group to the load balancer and manage no
# node-side rules at all, so no shared backend security group is created
# (rules.md G-2). What this variant adds is the validation that pins the target
# type to ip, which is the assumption the Terraform-declared node rule rests on;
# the other six leave that variable accepting instance as well.
#
# What makes it work here is the absence of that annotation, not the absence of a
# custom frontend group: the controller only needs the shared group when it has
# to name a traffic source in rules it writes onto nodes. With nothing asking it
# to write those rules, the load balancer carries exactly the group below and
# Terraform owns the path from it to the pods (see the ingress rule further
# down).
module "nlb_security_group" {
  source = "./modules/load_balancer_security_group"

  vpc_id = module.network.vpc_id
  name   = var.nlb_security_group_name
  # Left exactly as it was on purpose. A security group's description cannot be
  # updated in place - changing this string replaces the group (rules.md F-1) -
  # and AWS refuses to delete a group while a load balancer still references it,
  # so a reworded description would turn this into a DependencyViolation instead
  # of a no-op. The wording is stale (there is no pre-created load balancer in
  # this variant, unlike sync_nlb where it was copied from); the comment above is
  # the place to correct that, not the API value.
  description                 = "Frontend security group for the pre-created NLB"
  allow_inbound_from_anywhere = var.nlb_allow_inbound_from_anywhere
  ingress_cidr_blocks         = var.nlb_service_cidr_blocks

  depends_on = [module.network]
}
module "kube_ops_view" {
  source = "./modules/kube_ops_view"

  image_tag    = var.kube_ops_view_image_tag
  service_type = var.kube_ops_view_service_type
  service_annotations = {
    # Required before any of the annotations below mean anything. Without it the
    # in-tree cloud provider handles the Service and provisions a legacy Classic
    # Load Balancer, ignoring the frontend security group and target type
    # entirely - the AWS Load Balancer Controller never reconciles the Service at
    # all. This is the declarative form of the "kubectl patch svc kube-ops-view"
    # step in the _monolithic userdata.
    "service.beta.kubernetes.io/aws-load-balancer-type"            = "external"
    "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
    "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = var.nlb_target_type
    "service.beta.kubernetes.io/aws-load-balancer-security-groups" = module.nlb_security_group.security_group_id
    # Deliberately no manage-backend-security-group-rules annotation. Setting it
    # would make the controller write rules onto the cluster security group, and
    # to name a source in them it needs the shared backend security group - which
    # is exactly what enable_backend_security_group = false switches off, and the
    # controller errors out rather than doing one without the other. Leaving it
    # unset (its default is false) means the controller writes no node rules, so
    # the rule below is Terraform's job (rules.md G-2).
  }

  # The Service is only fulfilled once the controller is reconciling, and it also
  # needs schedulable capacity and working cluster DNS. Ordering the module after
  # the node group makes terraform destroy remove the Service - letting the
  # controller delete the NLB - before the nodes disappear (rules.md D-4).
  depends_on = [module.network, module.eks_node_group, module.aws_load_balancer_controller]
}
# The node-side half of the path, which the controller would normally write and
# here does not. With nlb-target-type = ip the NLB registers pod IPs directly, so
# the traffic arrives on the pod's container port rather than a node port, and
# pods use the EKS cluster security group. The health check uses the same port
# (traffic-port), so this one rule covers both.
#
# A standalone rule resource rather than an inline block, because the group
# belongs to EKS and Terraform only adds to it (rules.md F-2). The port comes
# from the module that owns it instead of being restated here (rules.md B-5).
resource "aws_vpc_security_group_ingress_rule" "load_balancer_to_pods" {
  count = var.kube_ops_view_service_type == "LoadBalancer" ? 1 : 0

  security_group_id            = module.eks_cluster.cluster_security_group_id
  description                  = "NLB to kube-ops-view pods on the container port"
  ip_protocol                  = "tcp"
  from_port                    = module.kube_ops_view.container_port
  to_port                      = module.kube_ops_view.container_port
  referenced_security_group_id = module.nlb_security_group.security_group_id
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  # Lets the README association below know when the bootstrap has finished
  # (rules.md H-2). The module touches <path>/userdata as its very last step,
  # after everything in additional_user_data has run.
  marker_file_path = var.marker_file_path
  # Joining the cluster security group is what lets this instance reach the API
  # server through the cluster's private endpoint, the only path left when
  # endpoint_public_access is turned off. The module is handed an ID list and
  # never learns that it belongs to an EKS cluster (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]
  # An EKS cluster and this instance live in the same root module, so the
  # instance is the workbench for that cluster and carries all five tools:
  # code-server (installed by the module itself), plus kubectl, eksctl, helm and
  # docker (rules.md H-1). None of them is behind a flag, and none of them is
  # used to create resources - that stays with the kubectl and helm providers
  # (rules.md E-1).
  #
  # The tools go in as ec2-user rather than root, so the binaries, the kubeconfig
  # and the .bashrc additions all land in /home/ec2-user where the code-server
  # session (which also runs as ec2-user) will find them. HOME is set explicitly
  # inside the block: user data runs as root, and how sudo treats HOME for the
  # target user depends on the sudoers configuration, so "~" cannot be relied on
  # to mean /home/ec2-user here.
  additional_user_data = <<-EOT
    # Building an image or pushing one to ECR needs a daemon on the host, which
    # is why this one tool cannot be replaced by a provider resource the way
    # kubectl and helm were (rules.md E-1/H-1).
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server is already running from the module's bootstrap, so its process
    # predates the docker group and its integrated terminals inherit whatever
    # groups that process started with. Restarting is what makes docker usable
    # from the IDE, rather than opening /var/run/docker.sock up to 666.
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
    # Order matters: bash_completion has to be sourced before kubectl's own
    # completion, which is what defines __start_kubectl, and that function has to
    # exist before complete references it - otherwise every login prints
    # "function not found" (rules.md H-1).
    echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
    echo 'source <(kubectl completion bash)' >> ~/.bashrc
    echo 'alias k=kubectl' >> ~/.bashrc
    echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
    # eksctl-io is the project's own org. The old weaveworks URL still
    # redirects, but the current name is what gets used (rules.md H-1).
    PLATFORM=$(uname -s)_amd64
    curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
    tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
    sudo install -m 0755 /tmp/eksctl /usr/local/bin && rm /tmp/eksctl
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    aws configure set default.region ${data.aws_region.current.region}
    # Without this - and without the access entry below - kubectl is installed
    # but every command fails with "You must be logged in to the server"
    # (rules.md H-1).
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}
    EOF
  EOT

  depends_on = [module.network]
}
# Granting the bastion's instance role cluster access joins two modules that
# know nothing about each other, so it belongs in the root rather than inside
# either one (rules.md C-1).
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
  # Every output this project exposes, defined once. outputs.tf projects these
  # and the README below renders them, so no value expression is written twice
  # (rules.md B-5/H-2). Adding an entry here is what makes an output possible,
  # which is what keeps the README from silently falling behind outputs.tf.
  #
  # The map's keys are the output names, and order decides the README's section
  # order.
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
      description = "Name of the EKS cluster"
      value       = module.eks_cluster.cluster_name
    }
    cluster_endpoint = {
      order       = 3
      title       = "EKS cluster endpoint"
      description = "API server endpoint of the EKS cluster"
      value       = module.eks_cluster.cluster_endpoint
    }
    load_balancer_controller_role_arn = {
      order       = 4
      title       = "Controller IAM role"
      description = "Role the AWS Load Balancer Controller assumes through IRSA, replacing the eksctl create iamserviceaccount step and the CloudFormation stack it used to leave behind"
      value       = module.aws_load_balancer_controller.controller_role_arn
    }
    kube_ops_view_namespace = {
      order       = 5
      title       = "Dashboard namespace"
      description = "Namespace kube-ops-view runs in. Whether a load balancer exists at all depends on kube_ops_view_service_type"
      value       = module.kube_ops_view.namespace
    }
    nlb_security_group_id = {
      order       = 6
      title       = "NLB frontend security group"
      description = "The only security group on the NLB. This variant runs the controller with --enable-backend-security-group=false, so no shared k8s-traffic-<cluster> group is created alongside it - the two commands below are how to confirm that"
      value       = module.nlb_security_group.security_group_id
    }
    load_balancer_security_groups_command = {
      order       = 7
      title       = "4. Check which groups the NLB carries"
      description = "Should list exactly one group, the frontend group above. A second k8s-traffic-<cluster>-<hash> group appearing here would mean the shared backend group is back, so enable_backend_security_group is not actually false"
      value       = "LB=$(${module.kube_ops_view.load_balancer_hostname_command}); aws elbv2 describe-load-balancers --query \"LoadBalancers[?DNSName=='$LB'].SecurityGroups\" --output json"
    }
    pod_ingress_rule_command = {
      order       = 8
      title       = "5. Check the node-side rule Terraform owns"
      description = "With no shared backend group the controller writes no rules onto the cluster security group, so this rule - from the frontend group to the pod container port - is what lets the NLB reach the pods. Terraform declares it, so unlike the controller-managed version it appears in the plan"
      value       = "aws ec2 describe-security-group-rules --filter Name=group-id,Values=${module.eks_cluster.cluster_security_group_id} --query \"SecurityGroupRules[?ReferencedGroupInfo.GroupId=='${module.nlb_security_group.security_group_id}']\" --output json"
    }
    kube_ops_view_service_type = {
      order       = 9
      title       = "Dashboard Service type"
      description = "Service type actually applied. With ClusterIP the dashboard is reached by port-forwarding and no load balancer or cluster security group rule is created; with LoadBalancer the controller provisions an NLB and the commands below apply"
      value       = module.kube_ops_view.service_type
    }
    kube_ops_view_service_command = {
      order       = 10
      title       = "1. Check the Service"
      description = "Shows the Service, including the load balancer address once the controller has reconciled it. An address that never appears means the controller declined the Service - check its log"
      value       = module.kube_ops_view.describe_command
    }
    kube_ops_view_endpoint_command = {
      order       = 11
      title       = "2. Read the load balancer DNS name"
      description = "Null unless kube_ops_view_service_type is LoadBalancer. The NLB is created by the controller rather than by Terraform, so its address is read from the cluster instead of being a Terraform output (rules.md H-2)"
      value       = module.kube_ops_view.load_balancer_hostname_command
    }
    kube_ops_view_fetch_command = {
      order       = 12
      title       = "3. Fetch the dashboard through the NLB"
      description = "Null unless kube_ops_view_service_type is LoadBalancer. This variant's NLB is internet-facing, so the same hostname also opens in a browser - subject to the frontend security group above"
      value       = module.kube_ops_view.load_balancer_fetch_command
    }
    kube_ops_view_port_forward_command = {
      order       = 13
      title       = "Open the dashboard without the NLB"
      description = "Port-forwards the Service to http://localhost:8080. The way to use the ClusterIP setting, and it works regardless of the Service type"
      value       = module.kube_ops_view.port_forward_command
    }
    update_kubeconfig_command = {
      order       = 14
      title       = "Re-point kubectl"
      description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
  }
  # Iterating local.outputs directly would order sections by key, which puts
  # "2. Open the dashboard" above "1. Check the Service". Re-keying by the order
  # field and taking values() sorts by that instead - values() returns a map's
  # values ordered by key - so the README reads in the order the demo is run, and
  # the order is still fully determined by the configuration rather than
  # shuffling between applies.
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  # Rendered from the same map, so an added output shows up here without anyone
  # remembering to edit two places (rules.md H-2).
  readme_body = join("\n", concat(
    ["# ${var.cluster_name}", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}
# The work happens inside code-server in a browser, where "terraform output" is
# not available, so every output above is also written to a README in the home
# directory the IDE opens (rules.md H-2). Combining several modules' outputs is
# the root's job, so this lives here rather than inside the instance module,
# which never learns what gets written into its home directory (rules.md C-1).
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is what
    # orders this after the instance bootstrap, and the marker this command
    # leaves behind is what a later association would wait on (rules.md D-5). The
    # marker path comes back out of the module it was passed into, so it is
    # defined in exactly one place (rules.md B-5).
    #
    # SSM runs as root, hence the chown - without it the file is not editable
    # from the IDE. The heredoc delimiter is quoted and deliberately unlikely to
    # appear in the body: Terraform has already substituted every value, so the
    # shell has no reason to touch a "$" or a backtick in the README.
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
