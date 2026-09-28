data "aws_region" "current" {}
module "network" {
  source = "./modules/network"

  public_subnet_tags  = var.public_subnet_tags
  private_subnet_tags = var.private_subnet_tags
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name = var.key_name

  # key_pair consumes no network output, so nothing would otherwise order it
  # against the network module's resources (rules.md D-3).
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
  # aws_subnet resources behind those outputs, not after the NAT gateways and
  # route table associations that never surface as outputs (rules.md D-3).
  depends_on = [module.network]
}
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not
  # exist until this addon creates it. As a DaemonSet it reaches ACTIVE with zero
  # nodes, so it comes before any capacity (rules.md C-4) - and nodes need it to
  # join Ready. It is also what makes target-type ip work, by making pod addresses
  # routable in the VPC (rules.md G-1).
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

  # coredns is a Deployment and needs schedulable capacity to leave DEGRADED and
  # become ACTIVE (rules.md C-4).
  depends_on = [
  module.network, module.eks_node_group]
}
# The controller that turns the ingress controller's Service into an NLB. Its IRSA
# role and Helm release are one module, because the release has to annotate the
# service account with the role's ARN (rules.md C-2).
module "aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"

  cluster_name      = module.eks_cluster.cluster_name
  vpc_id            = module.network.vpc_id
  aws_region        = data.aws_region.current.region
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host

  # The ingress controller sets its own frontend security group but does not set
  # manage-backend-security-group-rules, so the node-side rule is declared in
  # Terraform below and this can stay false (rules.md G-2).
  enable_backend_security_group = false
  # Off, because the only Service of type LoadBalancer here is the ingress controller's,
  # and it names this controller itself with the aws-load-balancer-type annotation, so
  # the webhook has nothing to mutate. Left on it would gate every Service creation in
  # the cluster behind a controller pod being Ready - which nothing trips over as the
  # modules are ordered today, but only because prometheus, grafana_operator and kyverno
  # all chain back to module.ingress_nginx and so to this module (rules.md G-4).
  enable_service_mutator_webhook = var.enable_service_mutator_webhook

  depends_on = [module.network, module.eks_node_group]
}
locals {
  # The Service the ingress-nginx chart creates, and the stack tag its load
  # balancer must carry to be adopted rather than duplicated (rules.md G-3).
  #
  # Derived here rather than taken from the ingress module's output: the
  # pre-created load balancer needs this value before that module runs, and
  # reading it from the module would make the load balancer depend on the release
  # while the release has to wait for the load balancer. One definition, handed to
  # both (rules.md B-5).
  ingress_service_name = "${var.ingress_release_name}-ingress-nginx-controller"
  ingress_stack_tag    = "${var.kyverno_namespace}/${local.ingress_service_name}"
}
# Standalone rule resources rather than inline blocks, and revoke_rules_on_delete,
# because the controller adds its own rules to this group (rules.md F-2).
module "load_balancer_security_group" {
  source = "./modules/load_balancer_security_group"

  vpc_id                      = module.network.vpc_id
  name                        = var.load_balancer_security_group_name
  description                 = "Frontend security group for the NLB fronting the Kyverno policy dashboards"
  port                        = var.load_balancer_port
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere

  depends_on = [module.network]
}
# Created here and adopted by the controller rather than left for the controller to
# create, which makes its DNS name known at apply time and is the only way this NLB
# can carry a security group at all - AWS refuses to add security groups to an NLB
# after creation (rules.md G-3).
module "synced_load_balancer" {
  source = "./modules/synced_load_balancer"

  cluster_name       = module.eks_cluster.cluster_name
  load_balancer_type = "network"
  internal           = false
  # internet-facing, so public subnets - this has to agree with the scheme the
  # ingress release annotates, or the controller builds a second load balancer
  # instead of adopting this one (rules.md G-3).
  subnet_ids         = module.network.public_subnet_ids
  security_group_ids = [module.load_balancer_security_group.security_group_id]
  # service.k8s.aws/*, not ingress.k8s.aws/*: this load balancer fronts a Service
  # of type LoadBalancer. The wrong prefix is not an error - the controller simply
  # does not adopt, and builds its own (rules.md G-3).
  resource_tag_prefix = "service"
  stack               = local.ingress_stack_tag

  depends_on = [module.network]
}
module "ingress_nginx" {
  source = "./modules/ingress_nginx"

  release_name = var.ingress_release_name
  namespace    = var.kyverno_namespace
  # This release owns the namespace: it is installed first and everything else goes
  # into the same one afterwards.
  create_namespace            = true
  service_name                = local.ingress_service_name
  stack_tag                   = local.ingress_stack_tag
  chart_version               = var.ingress_nginx_chart_version
  scheme                      = "internet-facing"
  nlb_target_type             = "ip"
  service_port                = var.load_balancer_port
  frontend_security_group_ids = [module.load_balancer_security_group.security_group_id]

  # The load balancer has to exist before the controller reconciles this Service,
  # or the controller creates its own and the pre-created one is orphaned. This
  # module waits for its release to become ready, so by the time it returns the
  # controller has already decided (rules.md G-3).
  #
  # The AWS Load Balancer Controller must also be running, otherwise the in-tree
  # cloud provider claims the Service and builds a Classic Load Balancer, ignoring
  # every annotation (rules.md G-1).
  depends_on = [
    module.network,
    module.synced_load_balancer,
    module.aws_load_balancer_controller,
    module.eks_coredns_addon,
  ]
}
# With manage-backend-security-group-rules unset the controller writes no
# node-side rules at all, so the path from load balancer to pod has to be declared
# here or every target stays unhealthy with no error anywhere (rules.md G-2).
# target-type is ip, so traffic arrives at the ingress controller pod's container
# port, and pods on this cluster use the cluster security group.
resource "aws_vpc_security_group_ingress_rule" "load_balancer_to_pods" {
  security_group_id            = module.eks_cluster.cluster_security_group_id
  description                  = "Listener port from the Kyverno dashboard NLB"
  ip_protocol                  = "tcp"
  from_port                    = var.load_balancer_port
  to_port                      = var.load_balancer_port
  referenced_security_group_id = module.load_balancer_security_group.security_group_id
}
# Where the dashboards get their data. The _monolithic template installed this by
# cloning kyverno/grafana-dashboard onto the bastion and running
# "kubectl apply -k examples/prometheus" against a directory inside it, so nothing
# recorded what was installed and a later apply would pick up whatever upstream had
# changed. A pinned chart instead (rules.md E-1).
module "prometheus" {
  source = "./modules/prometheus"

  namespace     = var.kyverno_namespace
  chart_version = var.prometheus_chart_version

  depends_on = [
  module.network, module.ingress_nginx]
}
# Grafana as a custom resource managed by an operator, which is how the original
# did it. The operator's chart, the Grafana instance and its datasource are one
# module: a Grafana custom resource is meaningless without the operator that
# reconciles it, and the CRDs it is written against come from that chart
# (rules.md C-2).
module "grafana_operator" {
  source = "./modules/grafana_operator"

  namespace     = var.kyverno_namespace
  chart_version = var.grafana_operator_chart_version
  admin_user    = var.grafana_admin_user
  # Reaches the Grafana custom resource's spec.config.security block, which is what
  # the _monolithic template's inline YAML set.
  admin_password = var.grafana_admin_password
  # From the module that owns the class, so the operator's Ingress cannot name a
  # class no controller reconciles (rules.md B-5).
  ingress_class_name = module.ingress_nginx.ingress_class_name
  # From the Prometheus module rather than rebuilt, so the datasource cannot point
  # at a service name the chart did not create (rules.md B-5).
  prometheus_url = module.prometheus.server_url

  depends_on = [
  module.network, module.prometheus, module.ingress_nginx]
}
# What the project is named after. Kyverno's dashboard ConfigMap is switched on so
# the Grafana instance above picks it up, which is why Grafana and Prometheus are
# ordered first.
module "kyverno" {
  source = "./modules/kyverno"

  namespace                 = var.kyverno_namespace
  chart_version             = var.kyverno_chart_version
  policies_chart_version    = var.kyverno_policies_chart_version
  pod_security_standard     = var.pod_security_standard
  validation_failure_action = var.validation_failure_action

  # Last of the releases on purpose. Kyverno registers admission webhooks in front
  # of every pod creation in the cluster, so anything installed after it has to pass
  # its policies - including the monitoring stack's own pods. Installing it last
  # keeps a restricted profile from blocking this project's own components.
  depends_on = [
  module.network, module.grafana_operator, module.prometheus]
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  marker_file_path            = var.marker_file_path
  # Joining the cluster security group is what lets this instance reach the API
  # server. The module is handed an ID list and never learns it belongs to an EKS
  # cluster (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]

  # An EKS cluster and this instance share a root module, so it is the workbench
  # for that cluster and carries all five tools (rules.md H-1). None of them
  # creates anything: the charts, the git clone and the Grafana manifests the
  # _monolithic template applied from here are Terraform resources now
  # (rules.md E-1) - git is no longer needed for a clone, only for ordinary work.
  additional_user_data = <<-EOT
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server is already running and predates the docker group, so its
    # terminals would not have it without a restart.
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
    # Order matters: kubectl's completion defines __start_kubectl, and that has to
    # exist before complete names it, or every login prints "function not found"
    # (rules.md H-1).
    echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
    echo 'source <(kubectl completion bash)' >> ~/.bashrc
    echo 'alias k=kubectl' >> ~/.bashrc
    echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
    # eksctl-io is the project's own org; the weaveworks URL the _monolithic
    # template used still redirects, but the current name is what gets used
    # (rules.md H-1).
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
# Granting the bastion's instance role cluster access joins two modules that know
# nothing about each other, so it belongs in the root (rules.md C-1).
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
  # Every output this project exposes, defined once. outputs.tf projects these and
  # the README below renders them, so no value expression is written twice
  # (rules.md B-5/H-2). Adding an entry here is what makes an output possible,
  # which is what keeps the README from falling behind outputs.tf.
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
    pod_security_standard = {
      order       = 4
      title       = "Pod Security Standard profile"
      description = "Which profile the installed policies check against. restricted additionally requires dropping capabilities and running as non-root, which rejects most off-the-shelf images"
      value       = module.kyverno.pod_security_standard
    }
    validation_failure_action = {
      order       = 5
      title       = "Policy action"
      description = "Audit records a violation in a PolicyReport and admits the pod; Enforce rejects it. Audit is the default here because Enforce plus the restricted profile would stop this cluster's own monitoring pods from being rescheduled"
      value       = module.kyverno.validation_failure_action
    }
    grafana_url = {
      order       = 6
      title       = "Grafana"
      description = "Address of the pre-created load balancer fronting Grafana. Known from state because Terraform created the load balancer rather than leaving it to the controller (rules.md G-3)"
      value       = module.synced_load_balancer.url
    }
    grafana_admin_user = {
      order       = 7
      title       = "Grafana username"
      description = "Log in with this and the password you passed in. The password is not written here, because an unauthenticated code-server serves this file (rules.md H-2)"
      value       = module.grafana_operator.admin_user
    }
    policies_check_command = {
      order       = 8
      title       = "1. List the installed policies"
      description = "The ACTION column shows Audit or Enforce and READY shows whether Kyverno accepted each ClusterPolicy"
      value       = module.kyverno.policies_check_command
    }
    policy_report_command = {
      order       = 9
      title       = "2. Read the policy reports"
      description = "The payoff: every namespace gets a report counting passes and failures against the Pod Security Standard. These are the metrics the Grafana dashboard graphs"
      value       = module.kyverno.policy_report_command
    }
    prometheus_check_command = {
      order       = 10
      title       = "3. Check Prometheus"
      description = "If Grafana shows no data, start here. A Pending pod usually means persistent_volume_enabled was turned on without a default StorageClass - this cluster has no EBS CSI driver"
      value       = module.prometheus.check_command
    }
    grafana_datasource_check_command = {
      order       = 11
      title       = "4. Check the Grafana datasource"
      description = "The operator matches a datasource to a Grafana instance by label. A datasource whose instanceSelector matches nothing is created without error and attached to no instance, which looks exactly like Grafana having no data"
      value       = module.grafana_operator.datasource_check_command
    }
    grafana_ingress_check_command = {
      order       = 12
      title       = "5. Check the Grafana Ingress"
      description = "An empty ADDRESS means the ingress controller is not reconciling the Ingress the operator created, usually a class name mismatch"
      value       = module.grafana_operator.ingress_check_command
    }
    adopted_load_balancer_check_command = {
      order       = 13
      title       = "6. Confirm the load balancer was adopted, not duplicated"
      description = "Lists every load balancer tagged for this cluster. One is correct. Two means the controller did not adopt the pre-created one and built its own, which is a tag mismatch rather than an error (rules.md G-3)"
      value       = "aws resourcegroupstaggingapi get-resources --tag-filters Key=elbv2.k8s.aws/cluster,Values=${module.eks_cluster.cluster_name} --resource-type-filters elasticloadbalancing:loadbalancer --query 'ResourceTagMappingList[].ResourceARN' --output table"
    }
    update_kubeconfig_command = {
      order       = 14
      title       = "Re-point kubectl"
      description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the
  # order field and taking values() - which returns a map's values ordered by key -
  # makes the README read top to bottom while the order stays decided by
  # configuration.
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
# available, so every output above is also written to a README in the home
# directory the IDE opens (rules.md H-2). Combining several modules' outputs is the
# root's job, so this lives here rather than inside the instance module.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is what
    # orders this after the bootstrap (rules.md D-5). The marker path comes back
    # out of the module it was passed into, so it is defined once (rules.md B-5).
    #
    # SSM runs as root, hence the chown. The heredoc delimiter is quoted and
    # unlikely to appear in the body: Terraform has already substituted every
    # value, so the shell has no reason to touch a "$" or a backtick.
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
