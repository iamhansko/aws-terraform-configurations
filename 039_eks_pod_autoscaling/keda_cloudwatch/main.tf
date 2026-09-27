data "aws_region" "current" {}
module "network" {
  source = "./modules/network"
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
  # aws_subnet resources behind those outputs, not after the NAT gateways and route
  # table associations that never surface as outputs (rules.md D-3).
  depends_on = [module.network]
}
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not exist
  # until this addon creates it. As a DaemonSet it reaches ACTIVE with zero nodes, so
  # it comes before any capacity (rules.md C-4) - and nodes need it to join Ready.
  # target-type ip also depends on it: pod addresses are only routable from the ALB
  # because the CNI puts them in the VPC (rules.md G-1).
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
  depends_on = [module.eks_node_group]
}
# Not what drives scaling here - the signal is a CloudWatch metric from outside the
# cluster - but it is what makes "kubectl top" work, so the pods' actual load can be
# compared against the request count KEDA is scaling on.
module "eks_metrics_server_addon" {
  source = "./modules/eks_metrics_server_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Also a Deployment, so it needs node capacity for the same reason as coredns
  # (rules.md C-4).
  depends_on = [module.eks_node_group]
}
# The variant. KEDA plus the IAM role its operator assumes to read CloudWatch, in one
# module because IRSA is one component: the trust policy names a service account the
# chart creates, and the chart annotates that service account with the role's ARN
# (rules.md C-2).
module "keda" {
  source = "./modules/keda"

  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  chart_version     = var.keda_chart_version
  namespace         = var.keda_namespace
  role_name         = var.keda_operator_role_name

  # The release has wait = true, so the apply blocks until the operator, metrics
  # server and webhook are Available - all of which needs node capacity and working
  # DNS, since the operator resolves the CloudWatch and STS endpoints.
  depends_on = [module.eks_node_group, module.eks_coredns_addon]
}
module "aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"

  cluster_name      = module.eks_cluster.cluster_name
  vpc_id            = module.network.vpc_id
  aws_region        = data.aws_region.current.region
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  chart_version     = var.aws_load_balancer_controller_chart_version
  # The workload's Ingress sets manage-backend-security-group-rules, so this has to be
  # true - the controller refuses that combination otherwise, and only says so in its
  # own log (rules.md G-2).
  enable_backend_security_group = var.enable_backend_security_group
  # Off, because no Service in this project is of type LoadBalancer - the workload is
  # fronted by an Ingress and its Service is ClusterIP. Left on, the webhook it
  # installs gates every Service creation in the cluster behind a controller pod being
  # Ready, which is what made this root's apply fail: module.keda and this module share
  # no ordering, so KEDA's three Services were created in the window between the
  # webhook being registered and this release's Deployment becoming Available
  # (rules.md G-4).
  enable_service_mutator_webhook = var.enable_service_mutator_webhook

  # The _monolithic template declared this controller's IAM role and never installed
  # the controller, so the Ingress it wrote had nothing to reconcile it and the
  # pre-created load balancer was never adopted. Installing it is what makes the ALB
  # exist, and the ALB is where the scaler's metric comes from - so without this the
  # ScaledObject would have nothing to read either.
  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}
# Standalone rule resources rather than inline blocks, and revoke_rules_on_delete,
# because the controller adds its own rules to this group (rules.md F-2). The
# _monolithic template built the pre-created ALB with the VPC's default security group
# while its Ingress annotation asked for a separate "alb-sg" that nothing attached -
# so the two disagreed about which group the load balancer had.
module "alb_security_group" {
  source = "./modules/load_balancer_security_group"

  vpc_id                      = module.network.vpc_id
  name                        = var.alb_security_group_name
  description                 = "Frontend security group for the ALB the controller adopts from the nginx Ingress"
  port                        = var.alb_port
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  # The load generator runs as a pod, so the request reaches the ALB from a pod
  # address in the cluster security group. A map rather than a list because this ID is
  # another module's output and is unknown until apply, and for_each needs statically
  # known keys (rules.md B-8).
  ingress_source_security_groups = {
    cluster = module.eks_cluster.cluster_security_group_id
  }

  depends_on = [module.network]
}
# The path from the load balancer to the pods, which nothing else creates now. With
# its backend security group turned off the controller does not write a reduced set of
# pod-side rules - it leaves the networking spec out of the TargetGroupBinding
# altogether, so not one rule is created and every target reports unhealthy while the
# load balancer itself looks fine (rules.md G-2).
#
# It modifies the cluster security group, which no module here owns outright, so it
# belongs in the root (rules.md C-1). Pods share their node's ENIs under the default
# CNI, and those carry the cluster security group, so that is where traffic addressed
# to a pod IP arrives.
resource "aws_vpc_security_group_ingress_rule" "load_balancer_to_pods" {
  # Exactly one owner. When the annotation is on, the controller writes these rules
  # and this must not (rules.md F-2).
  count = var.manage_backend_security_group_rules ? 0 : 1

  security_group_id = module.eks_cluster.cluster_security_group_id
  description       = "Container port from the ALB frontend security group"
  ip_protocol       = "tcp"
  # target-type ip sends traffic to the container port on the pod, and the ALB health
  # check uses traffic-port, so this one rule covers both.
  from_port                    = var.workload_container_port
  to_port                      = var.workload_container_port
  referenced_security_group_id = module.alb_security_group.security_group_id
}
# The workload. Declared before the load balancer module so the ALB can take its
# adoption stack tag from this module's output rather than the root restating
# "<namespace>/<name>" (rules.md B-5/G-3).
module "nginx_workload" {
  source = "./modules/nginx_workload"

  name           = var.workload_name
  namespace      = var.workload_namespace
  image          = var.workload_image
  container_port = var.workload_container_port
  # One replica to start with. Every replica after this is one KEDA added, and the
  # module excludes spec.replicas from its diff so the autoscaler keeps ownership.
  replicas                            = var.scaler_min_replica_count
  scheme                              = "internet-facing"
  target_type                         = var.alb_target_type
  frontend_security_group_id          = module.alb_security_group.security_group_id
  manage_backend_security_group_rules = var.manage_backend_security_group_rules

  # The controller has to be reconciling before the Ingress appears, or nothing picks
  # it up (rules.md G-1). Ordering the module after the node group also makes
  # terraform destroy remove these manifests while the nodes and the controller are
  # still there, so the load balancer is cleaned up rather than orphaned
  # (rules.md D-4).
  depends_on = [
    module.eks_node_group,
    module.eks_coredns_addon,
    module.aws_load_balancer_controller,
  ]
}
# Created here and adopted by the controller, so the ALB's arn_suffix is known from
# state at apply time (rules.md G-3). That is what makes this variant work at all: the
# scaler's CloudWatch query has to name the load balancer, and a load balancer the
# controller created is not a Terraform resource to ask.
module "synced_load_balancer" {
  source = "./modules/synced_load_balancer"

  cluster_name       = module.eks_cluster.cluster_name
  name               = var.synced_load_balancer_name
  load_balancer_type = "application"
  internal           = false
  # internet-facing, so public subnets. This has to agree with the Ingress's scheme
  # annotation or the controller builds a second load balancer instead of adopting
  # this one - and the scaler would then be reading the metric of an ALB that serves
  # no traffic (rules.md G-3).
  subnet_ids         = module.network.public_subnet_ids
  security_group_ids = [module.alb_security_group.security_group_id]
  # ingress.k8s.aws/*, not service.k8s.aws/*: this load balancer fronts an Ingress.
  # The wrong prefix is not an error - the controller just builds its own
  # (rules.md G-3).
  resource_tag_prefix = "ingress"
  stack               = module.nginx_workload.stack_tag

  depends_on = [module.network]
}
# What ties the two halves together: the scaler reads the request count of the load
# balancer above and resizes the Deployment below it.
module "keda_scaled_object" {
  source = "./modules/keda_scaled_object"

  name              = var.scaled_object_name
  namespace         = module.nginx_workload.namespace
  scale_target_name = module.nginx_workload.name
  scale_target_kind = "Deployment"
  # The operator's own role, because the TriggerAuthentication uses identityOwner keda.
  # Reading it off the module removes the _monolithic template's actual failure here:
  # it passed the literal string "{KedaOperatorRole.Arn}", an unconverted
  # CloudFormation reference, so the service account was annotated with a role that
  # does not exist and every metric query failed to authenticate.
  operator_role_arn = module.keda.operator_role_arn
  aws_region        = data.aws_region.current.region
  # arn_suffix, not arn: this is the string CloudWatch uses in the LoadBalancer
  # dimension, and a query built from the ARN matches nothing at all.
  load_balancer_arn_suffix = module.synced_load_balancer.arn_suffix
  target_metric_value      = var.scaler_target_metric_value
  metric_stat_period       = var.scaler_metric_stat_period
  polling_interval         = var.scaler_polling_interval
  cooldown_period          = var.scaler_cooldown_period
  min_replica_count        = var.scaler_min_replica_count
  max_replica_count        = var.scaler_max_replica_count

  # The CRDs for both objects arrive with the KEDA release, so they have to be
  # registered first. Ordering the module after the release also makes terraform
  # destroy remove these objects while the operator is still running, so its
  # finalizers can complete - a ScaledObject deleted after the operator is gone waits
  # forever (rules.md D-4).
  depends_on = [module.keda, module.nginx_workload]
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

  # An EKS cluster and this instance share a root module, so it is the workbench for
  # that cluster and carries all five tools (rules.md H-1). None of them creates
  # anything: the charts and the manifests the _monolithic template installed from
  # here are Terraform resources now (rules.md E-1).
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
    # Order matters: kubectl's completion defines __start_kubectl, and that has to
    # exist before complete names it, or every login prints "function not found"
    # (rules.md H-1).
    echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
    echo 'source <(kubectl completion bash)' >> ~/.bashrc
    echo 'alias k=kubectl' >> ~/.bashrc
    echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
    # eksctl-io is the project's own org; the weaveworks URL the _monolithic template
    # used still redirects, but the current name is what gets used (rules.md H-1).
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
  # (rules.md B-5/H-2). Adding an entry here is what makes an output possible, which
  # is what keeps the README from falling behind outputs.tf.
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
      description = "API server endpoint. Public here because the helm and kubectl providers install KEDA, the controller and the workload from wherever terraform runs"
      value       = module.eks_cluster.cluster_endpoint
    }
    application_url = {
      order       = 4
      title       = "Application URL"
      description = "The pre-created ALB, whose address is known from state rather than only after the controller has reconciled the Ingress (rules.md G-3). The page names the pod that served it, so refreshing shows requests spreading as replicas are added"
      value       = module.synced_load_balancer.url
    }
    keda_release = {
      order       = 5
      title       = "KEDA release"
      description = "The chart and pinned version, and the IAM role its operator assumes to read CloudWatch. The role ARN being real is the whole fix here: the _monolithic template passed an unconverted CloudFormation placeholder, so authentication failed silently on every poll"
      value       = "${module.keda.release_name} ${module.keda.chart_version} in ${module.keda.namespace}, as ${module.keda.operator_role_arn}"
    }
    scaler_target = {
      order       = 6
      title       = "What the scaler holds"
      description = "Requests per period each replica is expected to absorb. KEDA divides the load balancer's observed request count by this, so the two figures are read together"
      value       = "${module.keda_scaled_object.target_metric_value} requests per ${module.keda_scaled_object.metric_stat_period}s per replica, ${module.keda_scaled_object.replica_range} replicas"
    }
    scaler_expression = {
      order       = 7
      title       = "The CloudWatch query"
      description = "SUM, not COUNT: COUNT returns how many observations matched, which for one load balancer at one-minute granularity is 1 - the _monolithic template used it and so could never reach a target of 100. The identifier is the load balancer's arn_suffix, and a query matching nothing is reported as no load rather than as an error"
      value       = module.keda_scaled_object.metric_expression
    }
    adoption_stack_tag = {
      order       = 8
      title       = "Adoption stack tag"
      description = "The <namespace>/<name> value the ALB carries in its ingress.k8s.aws/stack tag. The controller adopts the pre-created load balancer only when this matches the Ingress it is reconciling; a mismatch makes it build a second one, and the scaler would then be watching the idle one (rules.md G-3)"
      value       = module.synced_load_balancer.stack
    }
    load_balancer_count_command = {
      order       = 9
      title       = "1. Confirm there is only one load balancer"
      description = "Two results means adoption failed - no error is raised for it. That matters more here than in a plain ALB demo, because the scaler reads the metric of the one Terraform created"
      value       = "aws resourcegroupstaggingapi get-resources --tag-filters Key=elbv2.k8s.aws/cluster,Values=${module.eks_cluster.cluster_name} --resource-type-filters elasticloadbalancing:loadbalancer --query 'ResourceTagMappingList[].ResourceARN' --output table"
    }
    scaled_object_command = {
      order       = 10
      title       = "2. Check the ScaledObject is ready"
      description = "READY true means KEDA accepted the object and authenticated. READY false is almost always authentication rather than a low metric, and the reason is in the operator's log"
      value       = module.keda_scaled_object.scaled_object_command
    }
    metric_value_command = {
      order       = 11
      title       = "3. Read the metric KEDA is publishing"
      description = "Straight from the external metrics API - the most direct answer to whether the CloudWatch query returns anything. Zero here with traffic flowing means the query matches nothing, most likely the wrong load balancer identifier or region. The labelSelector is part of the request rather than decoration: KEDA's metrics apiserver resolves the metric by the scaledobject.keda.sh/name label, and without it the answer is NotFound, which reads like the metric is missing when the scaler is in fact working"
      value       = module.keda_scaled_object.metric_value_command
    }
    hpa_command = {
      order       = 12
      title       = "4. Watch the replica count"
      description = "KEDA does not resize the workload itself: it publishes an external metric and creates this HorizontalPodAutoscaler to act on it. So the replica count moves on the HPA's schedule, not on pollingInterval"
      value       = module.keda_scaled_object.hpa_command
    }
    load_generator_command = {
      order       = 13
      title       = "5. Generate load through the ALB"
      description = "The requests have to go through the load balancer, not to the Service: the metric is the ALB's request count, so in-cluster traffic straight to the pods is invisible to the scaler. Expect a delay of a minute or two - CloudWatch publishes per minute and is eventually consistent"
      value       = "kubectl -n ${module.nginx_workload.namespace} run load-generator --image=busybox --restart=Never -- /bin/sh -c 'while true; do wget -q -O - http://${module.synced_load_balancer.dns_name}:${var.alb_port}; done'"
    }
    pods_command = {
      order       = 14
      title       = "6. See the replicas KEDA added"
      description = "Pods and the nodes they landed on. Cleaning up afterwards is 'kubectl -n default delete pod load-generator', after which the scaler returns to its floor once the cooldown period has passed"
      value       = module.nginx_workload.pods_command
    }
    keda_operator_logs_command = {
      order       = 15
      title       = "7. Read the operator's log if anything is off"
      description = "Where a scaler's authentication and metric queries either succeed or explain themselves. The first place to look when the ScaledObject has no metric value"
      value       = module.keda.operator_logs_command
    }
    update_kubeconfig_command = {
      order       = 16
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
# available, so every output above is also written to a README in the home directory
# the IDE opens (rules.md H-2). Combining several modules' outputs is the root's job,
# so this lives here rather than inside the instance module.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is what
    # orders this after the bootstrap (rules.md D-5). The marker path comes back out
    # of the module it was passed into, so it is defined once (rules.md B-5).
    #
    # SSM runs as root, hence the chown. The heredoc delimiter is quoted and unlikely
    # to appear in the body: Terraform has already substituted every value, so the
    # shell has no reason to touch a "$" or a backtick.
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
