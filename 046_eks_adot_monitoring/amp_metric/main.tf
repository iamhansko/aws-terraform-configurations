data "aws_region" "current" {}
module "network" {
  source = "./modules/network"
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
  # comes before any capacity (rules.md C-4) - and nodes need it to join Ready.
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
  # ACTIVE (rules.md C-4). It is also the first workload whose logs this project collects,
  # since nothing else runs on the cluster.
  depends_on = [
  module.network, module.eks_node_group]
}
# cert-manager, which the ADOT add-on needs rather than merely benefits from: the add-on
# installs the OpenTelemetry Operator, whose admission webhook serves TLS from a certificate
# cert-manager issues. Without it the add-on installs, the operator never becomes ready, and
# the collector object is never reconciled into anything.
#
# The _monolithic template installed it with an unpinned helm command from an SSM
# Association on the bastion (rules.md E-1).
module "cert_manager" {
  source = "./modules/cert_manager"

  chart_version = var.cert_manager_chart_version

  # The release waits for its own webhook to be serving, which needs schedulable capacity
  # and working cluster DNS (rules.md D-2).
  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}
# The RBAC that lets EKS install the add-on at all. Five cluster-scoped objects the
# _monolithic template fetched with "kubectl apply -f https://amazon-eks.s3.amazonaws.com/..."
# from the bastion, leaving them outside Terraform entirely (rules.md E-1/E-2).
module "adot_addon_permissions" {
  source = "./modules/adot_addon_permissions"

  # kubectl_manifest resources against the cluster's API server, so they need nodes for the
  # API server to be reachable through and CoreDNS for the provider's token exec to resolve.
  # Ordering the module after the nodes also makes terraform destroy remove this RBAC while
  # the cluster is still there (rules.md D-4).
  depends_on = [
  module.network, module.eks_node_group, module.eks_coredns_addon]
}
# The controller that adopts the pre-created NLB from the ingress controller's Service. Its
# IRSA role and Helm release are one module, because the release has to annotate the service
# account with the role's ARN (rules.md C-2).
module "aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"

  cluster_name      = module.eks_cluster.cluster_name
  vpc_id            = module.network.vpc_id
  aws_region        = data.aws_region.current.region
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  chart_version     = var.aws_load_balancer_controller_chart_version
  # The ingress controller's Service does not set manage-backend-security-group-rules, so
  # nothing asks the controller to write node-side rules and this can stay false. The paths
  # from the load balancer to the controller pods are declared below instead (rules.md G-2).
  enable_backend_security_group = false
  # Off: that Service names the controller itself with the aws-load-balancer-type annotation,
  # so the webhook has nothing to mutate, and its failurePolicy: Fail would otherwise gate
  # every Service created by the three charts installed after it (rules.md G-4).
  enable_service_mutator_webhook = var.enable_service_mutator_webhook

  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}
locals {
  # The stack tag the pre-created load balancer must carry to be adopted rather than
  # duplicated (rules.md G-3).
  #
  # The Service name is the release name with a -controller suffix, which holds only because
  # the ingress_nginx module pins fullnameOverride to the release name. Left unpinned the
  # chart picks between two spellings by testing whether the release name happens to contain
  # the chart name, and a wrong guess here is not an error - the controller builds a second
  # load balancer instead (rules.md G-3).
  #
  # Derived here rather than read from the module's output: the load balancer needs this
  # value before that module runs, and taking it from the module would make the load balancer
  # depend on the ingress controller while the controller has to wait for the load balancer.
  # Both sides read the same root variables, so there is still one definition (rules.md B-5).
  ingress_nginx_stack_tag = "${var.ingress_nginx_namespace}/${var.ingress_nginx_release_name}-controller"
}
# Standalone rule resources rather than inline blocks, and revoke_rules_on_delete, because
# the controller adds its own rules to this group (rules.md F-2). The _monolithic template
# created this group and then attached neither: its aws_lb was given the VPC's default
# security group while the Service annotation named this one, so Terraform and the controller
# disagreed about which groups the load balancer had.
module "nlb_security_group" {
  source = "./modules/load_balancer_security_group"

  vpc_id      = module.network.vpc_id
  name        = var.nlb_security_group_name
  description = "Frontend security group for the NLB fronting the ingress controller that serves Grafana"
  # Exactly the ports the Service publishes, from the same variable the Service reads. The
  # _monolithic template opened only 80 while the chart published 80 and 443, leaving a
  # listener that accepted nothing (rules.md B-5/G-1).
  ports                       = var.load_balancer_ports
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere

  depends_on = [module.network]
}
# Created here and adopted by the controller rather than left for the controller to create,
# so its DNS name is known from state at apply time instead of only after a reconcile - which
# is what makes the Grafana URL a real output (rules.md G-3).
module "synced_nlb" {
  source = "./modules/synced_load_balancer"

  cluster_name       = module.eks_cluster.cluster_name
  name               = var.synced_nlb_name
  load_balancer_type = "network"
  internal           = false
  # internet-facing, so public subnets - this has to agree with the scheme the Service
  # annotates, or the controller builds a second load balancer instead of adopting this one
  # (rules.md G-3).
  subnet_ids         = module.network.public_subnet_ids
  security_group_ids = [module.nlb_security_group.security_group_id]
  # service.k8s.aws/*, not ingress.k8s.aws/*: this load balancer is provisioned from a
  # Service of type LoadBalancer - the ingress controller's - rather than from an Ingress.
  # Grafana's Ingress is fulfilled by that controller, not by the AWS one (rules.md G-3).
  resource_tag_prefix = "service"
  stack               = local.ingress_nginx_stack_tag

  depends_on = [module.network]
}
module "ingress_nginx" {
  source = "./modules/ingress_nginx"

  release_name       = var.ingress_nginx_release_name
  namespace          = var.ingress_nginx_namespace
  create_namespace   = false
  chart_version      = var.ingress_nginx_chart_version
  ingress_class_name = var.ingress_nginx_class_name
  # Must agree with the pre-created load balancer's internal = false (rules.md G-3).
  scheme          = "internet-facing"
  nlb_target_type = "ip"
  # Named in the Service annotation so the controller keeps the group Terraform already
  # attached. An NLB can only be given security groups at creation, which is the other reason
  # the load balancer is pre-created (rules.md B-6/G-3).
  frontend_security_group_ids = [module.nlb_security_group.security_group_id]
  service_ports               = var.load_balancer_ports
  # The Service name the stack tag above was built from. Passed so the module can re-expose
  # it, and so a mismatch is visible in outputs rather than only as a second load balancer.
  service_name = "${var.ingress_nginx_release_name}-controller"
  stack_tag    = local.ingress_nginx_stack_tag

  # The load balancer has to exist before the controller reconciles this Service, or the AWS
  # controller creates its own and the pre-created one is orphaned (rules.md G-3). The AWS
  # controller must also be running, otherwise the in-tree cloud provider claims the Service
  # and builds a Classic Load Balancer, ignoring every annotation (rules.md G-1).
  depends_on = [
    module.network,
    module.eks_node_group,
    module.eks_coredns_addon,
    module.aws_load_balancer_controller,
    module.synced_nlb,
  ]
}
# The metrics destination. A workspace, and the two log groups AMP reports through - one of
# which the _monolithic template created and never connected to anything.
module "prometheus_workspace" {
  source = "./modules/prometheus_workspace"

  alias                = coalesce(var.amp_workspace_alias, var.cluster_name)
  enable_query_logging = var.amp_enable_query_logging
  log_retention_days   = var.amp_log_retention_days

  # No network dependency: an AMP workspace is a regional resource with nothing in the VPC,
  # so it is one of the few things here that genuinely does not need
  # depends_on = [module.network] (rules.md D-3).

  # module.network's value references only order this after the specific aws_subnet or
  # aws_vpc that produced them, not after the NAT gateway and route tables the network
  # module also owns. depends_on states "after the whole network" (rules.md D-3).
  depends_on = [module.network]
}
# The variant. One collector, scraping pod metrics and remote-writing them to the workspace,
# with a second pipeline sending the same scrape to CloudWatch as embedded metric format.
module "eks_adot_addon" {
  source = "./modules/eks_adot_addon"

  cluster_name      = module.eks_cluster.cluster_name
  addon_version     = var.adot_addon_version
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  prometheus_metrics = {
    # The remote write path, assembled by the workspace module rather than here: the base
    # endpoint ends in a slash and the concatenation is easy to get wrong, and an exporter
    # pointed at the base URL gets 404s that appear only in the collector's log
    # (rules.md B-5).
    remote_write_endpoint = module.prometheus_workspace.remote_write_endpoint
    enable_emf            = var.enable_emf
  }
  # container_logs and otlp_ingest are left null: those are what the cloudwatch_log and
  # xray_trace variants enable. Each variant owns its own copy of this module
  # (rules.md A-1), so they can diverge without affecting each other.

  # Both edges are load-bearing and neither is a value reference, so neither is implied
  # (rules.md D-2). module.adot_addon_permissions because EKS installs this add-on as the
  # eks:addon-manager user, which cannot create the operator without that RBAC.
  # module.cert_manager because the operator's webhook needs a certificate.
  depends_on = [
  module.network, module.adot_addon_permissions, module.cert_manager]
}
# What reads the metrics back. Grafana through its operator, querying the workspace with
# SigV4 under an IRSA role.
module "grafana" {
  source = "./modules/grafana"

  namespace              = var.grafana_namespace
  operator_chart_version = var.grafana_operator_chart_version
  admin_user             = var.grafana_admin_user
  admin_password         = var.grafana_admin_password
  secrets_manager_name   = var.grafana_secrets_manager_name
  # The base endpoint, not the remote write path. Grafana's data source takes the workspace
  # URL as-is; pointing it at api/v1/remote_write returns 405 on every query, which Grafana
  # reports as a generic data source error (rules.md B-5).
  prometheus_endpoint      = module.prometheus_workspace.endpoint
  prometheus_workspace_arn = module.prometheus_workspace.workspace_arn
  aws_region               = data.aws_region.current.region
  oidc_provider_arn        = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host         = module.eks_cluster.oidc_issuer_host
  # Taken from the ingress controller module rather than restated, so Grafana's Ingress cannot
  # name a class no controller claims - which produces no error and no address (rules.md B-5).
  ingress_class_name = module.ingress_nginx.ingress_class_name

  # module.ingress_nginx because Grafana's Ingress needs a controller to fulfil it, and the
  # IngressClass has to exist before the object referencing it. Ordering the module after the
  # nodes also makes terraform destroy remove these manifests while their controllers are
  # still running (rules.md D-2/D-4).
  depends_on = [
    module.network,
    module.eks_node_group,
    module.eks_coredns_addon,
    module.ingress_nginx,
  ]
}
# With manage-backend-security-group-rules unset the AWS controller writes no node-side rules
# at all, so the paths from the load balancer to the ingress controller pods have to be
# declared here or every target stays unhealthy with no error anywhere (rules.md G-2).
# target-type is ip, so traffic arrives at the controller pod's own port.
#
# These modify the cluster security group, which no module here owns outright, so they belong
# in the root (rules.md C-1).
resource "aws_vpc_security_group_ingress_rule" "nlb_to_ingress_pods" {
  # Keys come from configuration, so they are known during plan even though the two security
  # group IDs are not (rules.md B-8).
  for_each = var.load_balancer_ports

  security_group_id            = module.eks_cluster.cluster_security_group_id
  description                  = "Ingress controller ${each.key} port from the NLB frontend security group"
  ip_protocol                  = "tcp"
  from_port                    = each.value
  to_port                      = each.value
  referenced_security_group_id = module.nlb_security_group.security_group_id
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
  # cluster and carries all five tools (rules.md H-1). None of them creates anything:
  # cert-manager and the add-on's RBAC, which the _monolithic template applied from here, are
  # Terraform resources now (rules.md E-1).
  #
  # Two bugs from that template are fixed here rather than carried over. It ran "exec bash"
  # partway through, which replaces the shell and silently discarded every remaining line -
  # update-kubeconfig, eksctl and helm were all after it, so the instance came up with no
  # kubeconfig while the SSM Association that followed depended on kubectl working. And it
  # pulled eksctl from weaveworks; eksctl-io is the project's own org (rules.md H-1).
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
      description = "Name of the EKS cluster, which the AWS Load Balancer Controller also writes into the elbv2.k8s.aws/cluster tag on load balancers it owns"
      value       = module.eks_cluster.cluster_name
    }
    cluster_endpoint = {
      order       = 3
      title       = "EKS cluster endpoint"
      description = "API server endpoint. Public so the helm and kubectl providers could reach it during apply - narrow public_access_cidrs to your own address"
      value       = module.eks_cluster.cluster_endpoint
    }
    grafana_url = {
      order       = 4
      title       = "Grafana"
      description = "The console, served by the ingress controller behind the pre-created NLB. The address is known from state because Terraform created that load balancer and the AWS controller adopted it (rules.md G-3). The first request can be a minute or two early: Grafana installs the Amazon Prometheus plugin at startup"
      value       = module.synced_nlb.url
    }
    grafana_admin_user = {
      order       = 5
      title       = "Grafana login"
      description = "The administrator user name. The password is deliberately not an output - the _monolithic template printed it and defaulted it to the literal string \"grafana\"; use the command below instead (rules.md H-2)"
      value       = module.grafana.admin_user
    }
    grafana_admin_password_command = {
      order       = 6
      title       = "1. Retrieve the password"
      description = "A command rather than a value, because an output would write the credential into state's plaintext output section and into any log that prints outputs. It is generated unless grafana_admin_password was set"
      value       = module.grafana.admin_password_command
    }
    amp_workspace = {
      order       = 7
      title       = "Prometheus workspace"
      description = "The ws-<uuid> everything actually references, and the alias the console lists. Metrics arrive here by remote write from the collector and leave by SigV4-signed query from Grafana"
      value       = "${module.prometheus_workspace.workspace_id} (${module.prometheus_workspace.alias})"
    }
    amp_endpoints = {
      order       = 8
      title       = "Workspace endpoints"
      description = "Two different URLs from one base, which is worth keeping straight: the collector needs the remote write path appended, and Grafana's data source takes the base as-is. Swapping them produces 404s in the collector log or 405s in Grafana, and nothing else reports either"
      value       = "write: ${module.prometheus_workspace.remote_write_endpoint} | query: ${module.prometheus_workspace.endpoint}"
    }
    amp_log_groups = {
      order       = 9
      title       = "AMP log groups"
      description = "Rule evaluation errors and served queries. Both are under /aws/vendedlogs, which is what lets AMP write to them without a log group resource policy - and the query one is connected, which the _monolithic template's was not: its CloudFormation source configured query logging and cfn2tf could not map the property"
      value       = "rules: ${module.prometheus_workspace.rule_log_group} | queries: ${module.prometheus_workspace.query_log_group}"
    }
    addon_configuration = {
      order       = 10
      title       = "The add-on configuration"
      description = "The JSON the adot add-on received. Read it first when no metrics arrive: a key in the wrong place is valid JSON the add-on ignores, and nothing anywhere reports that (rules.md E-5)"
      value       = module.eks_adot_addon.configuration_values
    }
    collector_role = {
      order       = 11
      title       = "Collector IAM role"
      description = "The IRSA role the Prometheus collector assumes. It carries both a Prometheus and a CloudWatch policy because two pipelines read the same scrape - remote write to the workspace, and embedded metric format to CloudWatch"
      value       = module.eks_adot_addon.collector_role_arns["prometheus_metrics"]
    }
    grafana_role = {
      order       = 12
      title       = "Grafana IAM role"
      description = "The role Grafana assumes to query the workspace. Also carries an inline policy scoped to this one workspace, where AmazonPrometheusQueryAccess alone covers every workspace in the account"
      value       = module.grafana.iam_role_arn
    }
    permission_check_command = {
      order       = 13
      title       = "2. Confirm EKS could install the add-on"
      description = "The RBAC that lets the eks:addon-manager user create the operator. If the add-on reports a create failure, the message names the object it could not create and every one of them is covered here"
      value       = module.adot_addon_permissions.permission_check_command
    }
    collector_status_command = {
      order       = 14
      title       = "3. Confirm the collector was built"
      description = "An OpenTelemetryCollector with no matching workload means the operator has not reconciled it, which is almost always its webhook failing to serve - check cert-manager before anything else"
      value       = module.eks_adot_addon.collector_status_command
    }
    series_count_command = {
      order       = 15
      title       = "4. Confirm metrics are arriving"
      description = "Counts every series in the workspace, which is the shortest answer to whether remote write is working. Needs awscurl because the endpoint requires SigV4 - a plain curl gets a 403 that reads as a permissions problem rather than an unsigned request"
      value       = module.prometheus_workspace.series_count_command
    }
    adopted_load_balancer_check_command = {
      order       = 16
      title       = "5. Confirm the load balancer was adopted, not duplicated"
      description = "Lists every load balancer tagged for this cluster. One is correct. Two means the AWS controller did not adopt the pre-created one and built its own, which is a tag mismatch rather than an error (rules.md G-3)"
      value       = "aws resourcegroupstaggingapi get-resources --tag-filters Key=elbv2.k8s.aws/cluster,Values=${module.eks_cluster.cluster_name} --resource-type-filters elasticloadbalancing:loadbalancer --query 'ResourceTagMappingList[].ResourceARN' --output table"
    }
    ingress_hostname_command = {
      order       = 17
      title       = "6. Read the address the controller attached"
      description = "Compare this against the Grafana URL above. They should be the same load balancer"
      value       = module.ingress_nginx.load_balancer_hostname_command
    }
    grafana_rollout_command = {
      order       = 18
      title       = "7. Wait for Grafana itself"
      description = "The Helm release finishes once the operator is running, so the instance it builds trails it. The first boot is the slow one, because the Amazon Prometheus plugin is installed at startup"
      value       = module.grafana.rollout_status_command
    }
    datasource_status_command = {
      order       = 19
      title       = "8. Confirm the data source reached Grafana"
      description = "An empty status usually means the instanceSelector matched nothing, which is accepted by the API server and reconciled into nothing - so the data source never appears in the UI"
      value       = module.grafana.datasource_status_command
    }
    grafana_log_command = {
      order       = 20
      title       = "9. Read Grafana's log"
      description = "Where a SigV4 signature AMP rejected, or a failed plugin install, appears. The data source page reports only that the query failed"
      value       = module.grafana.grafana_log_command
    }
    grafana_admin_env_command = {
      order       = 21
      title       = "If the Grafana pod is in CreateContainerConfigError"
      description = "It means an env source could not be resolved, and here that is always the admin credential. Exactly one entry per variable is correct: the operator injects the pair itself, pointing at <instance>-admin-credentials, so anything that also declares it produces a duplicate - and kubelet resolves every source including duplicates"
      value       = module.grafana.admin_env_check_command
    }
    grafana_admin_secret_keys_command = {
      order       = 22
      title       = "...and check the Secret holds the keys it reads"
      description = "GF_SECURITY_ADMIN_USER and GF_SECURITY_ADMIN_PASSWORD, exactly. The operator hardcodes both the Secret name and these key names, so a Secret of the right name with different keys exists as far as Kubernetes is concerned and the pod still never starts"
      value       = module.grafana.admin_secret_keys_command
    }
    collector_log_command = {
      order       = 23
      title       = "10. Read the collector's log"
      description = "The other end of the same question. An AccessDenied from AMP or CloudWatch appears here and nowhere else - the collector stays Running either way"
      value       = module.eks_adot_addon.collector_log_command
    }
    update_kubeconfig_command = {
      order       = 24
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
