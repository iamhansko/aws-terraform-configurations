data "aws_region" "current" {}
module "network" {
  source = "./modules/network"

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
  # before any capacity (rules.md C-4) - and nodes need it to join Ready. It is also what
  # makes target-type ip work, by putting pod addresses in the VPC (rules.md G-1).
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
  # ACTIVE (rules.md C-4). Sentry's subcharts also find each other by Service DNS name, so
  # nothing settles until this is up.
  depends_on = [
  module.network, module.eks_node_group]
}
# Half of what makes the Sentry chart possible at all - the driver. Its PostgreSQL, Redis, Kafka,
# ZooKeeper, RabbitMQ and ClickHouse subcharts want eight PersistentVolumeClaims between them, and
# since Kubernetes 1.23 the in-tree EBS provisioner is gone, so nothing provisions them without
# this addon.
#
# The other half is the StorageClass below, which this addon does not create. Both are needed;
# neither is sufficient.
#
# Its own module like every other EKS addon (rules.md C-4), holding the IRSA role too because
# the trust policy names the exact service account the addon creates (rules.md C-2).
module "eks_ebs_csi_driver_addon" {
  source = "./modules/eks_ebs_csi_driver_addon"

  cluster_name      = module.eks_cluster.cluster_name
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host

  # The driver's controller is a Deployment, so it needs schedulable capacity for the same
  # reason coredns does (rules.md C-4).
  depends_on = [
  module.network, module.eks_node_group]
}
# The default gp3 StorageClass, without which the addon above provisions nothing.
#
# A fresh EKS cluster has no default StorageClass to fall back on: its only class is the built-in
# gp2, whose in-tree kubernetes.io/aws-ebs provisioner was removed in Kubernetes 1.23, and which on
# current versions carries no default annotation (measured at 1.33). None of the chart's eight
# claims names a storageClassName, so all eight resolved to no class and stayed Pending.
#
# That is what the release's timeout was really about. sentry-sentry-postgresql never started, so
# the chart's db-check hook at weight -1 waited on a database that would never answer - and helm
# waits for hook groups in order regardless of --wait, so neither a longer timeout nor
# wait_for_release = false gets past it. The failure reported only:
#
#   Error: context deadline exceeded
#
# The _monolithic template did create this class, with a kubectl apply from the bastion right after
# it rolled out the driver (rules.md E-1/E-2). Losing it was a conversion regression.
module "csi_storage_classes" {
  source = "./modules/csi_storage_classes"

  storage_class_name = var.storage_class_name

  # kubectl_manifest resources against the cluster's API server, so ordering the module after the
  # nodes is what makes terraform destroy remove them while there is still something to process the
  # deletion (rules.md D-4). After the addon too: the class names a provisioner, and a class whose
  # driver is not registered yet accepts claims and provisions none.
  depends_on = [
  module.network, module.eks_node_group, module.eks_ebs_csi_driver_addon]
}
# The controller that turns the ingress controller's Service into an NLB. Its IRSA role and
# Helm release are one module, because the release has to annotate the service account with
# the role's ARN (rules.md C-2). The _monolithic template installed it with a helm command in
# userdata (rules.md E-1).
module "aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"

  cluster_name      = module.eks_cluster.cluster_name
  vpc_id            = module.network.vpc_id
  aws_region        = data.aws_region.current.region
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  chart_version     = var.aws_load_balancer_controller_chart_version
  # The ingress controller sets its own frontend security group but does not set
  # manage-backend-security-group-rules, so nothing asks the controller to write node-side
  # rules and this can stay false. The path from the load balancer to the pods is declared
  # below instead (rules.md G-2).
  enable_backend_security_group = false
  # Off: the one Service of type LoadBalancer here names the controller itself with the
  # aws-load-balancer-type annotation, so the webhook has nothing to mutate - while its
  # failurePolicy: Fail would gate every Service in the cluster, and the Sentry chart creates
  # a dozen of them, behind a controller pod being Ready (rules.md G-4).
  enable_service_mutator_webhook = var.enable_service_mutator_webhook

  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}
locals {
  # The Service the ingress-nginx chart creates, and the stack tag its load balancer must
  # carry to be adopted rather than duplicated (rules.md G-3).
  #
  # <release>-controller, because the ingress module pins the chart's fullname to the release
  # name with fullnameOverride. Left to itself the chart chooses between that and
  # <release>-ingress-nginx-controller by testing whether the release name contains the chart
  # name, and guessing wrong produces a stack tag no Service ever carries - the controller
  # then builds its own load balancer and the pre-created one never gets a listener
  # (rules.md G-3).
  #
  # Derived here rather than taken from the ingress module's output: the pre-created load
  # balancer needs this value before that module runs, and reading it from the module would
  # make the load balancer depend on the release while the release has to wait for the load
  # balancer. One definition here, handed to both (rules.md B-5).
  ingress_service_name = "${var.ingress_release_name}-controller"
  ingress_stack_tag    = "${var.ingress_namespace}/${local.ingress_service_name}"
}
# Standalone rule resources rather than inline blocks, and revoke_rules_on_delete, because the
# controller adds its own rules to this group (rules.md F-2). The _monolithic template built
# the NLB with the VPC's default security group while its Service annotation asked for a
# separate "nlb-sg" that nothing attached - so the two disagreed about which group the load
# balancer had.
module "load_balancer_security_group" {
  source = "./modules/load_balancer_security_group"

  vpc_id      = module.network.vpc_id
  name        = var.load_balancer_security_group_name
  description = "Frontend security group for the NLB fronting the Sentry dashboard"
  # Both ports the ingress controller's Service publishes. The _monolithic template opened
  # only 80 here while the chart published 80 and 443, so the https listener existed and
  # accepted nothing (rules.md G-1).
  ports                       = var.load_balancer_ports
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere

  depends_on = [module.network]
}
# Created here and adopted by the controller rather than left for the controller to create.
# That is what makes its DNS name known at apply time, so the Sentry URL is a real output
# instead of a kubectl command - and it is the only way this NLB can carry a security group at
# all, since AWS refuses to add security groups to an NLB after creation (rules.md G-3).
module "synced_load_balancer" {
  source = "./modules/synced_load_balancer"

  cluster_name       = module.eks_cluster.cluster_name
  name               = var.synced_load_balancer_name
  load_balancer_type = "network"
  internal           = false
  # internet-facing, so public subnets - this has to agree with the scheme the ingress release
  # annotates, or the controller builds a second load balancer instead of adopting this one
  # (rules.md G-3).
  subnet_ids         = module.network.public_subnet_ids
  security_group_ids = [module.load_balancer_security_group.security_group_id]
  # service.k8s.aws/*, not ingress.k8s.aws/*: this load balancer fronts a Service of type
  # LoadBalancer. The wrong prefix is not an error - the controller simply does not adopt, and
  # builds its own (rules.md G-3).
  resource_tag_prefix = "service"
  stack               = local.ingress_stack_tag

  depends_on = [module.network]
}
module "ingress_nginx" {
  source = "./modules/ingress_nginx"

  release_name = var.ingress_release_name
  namespace    = var.ingress_namespace
  # kube-system already exists, so this release must not try to create it.
  create_namespace            = false
  service_name                = local.ingress_service_name
  stack_tag                   = local.ingress_stack_tag
  chart_version               = var.ingress_nginx_chart_version
  scheme                      = "internet-facing"
  nlb_target_type             = "ip"
  service_ports               = var.load_balancer_ports
  frontend_security_group_ids = [module.load_balancer_security_group.security_group_id]

  # The load balancer has to exist before the controller reconciles this Service, or the
  # controller creates its own and the pre-created one is orphaned. This module waits for its
  # release to become ready, so by the time it returns the controller has already decided
  # (rules.md G-3).
  #
  # The AWS Load Balancer Controller must also be running, otherwise the in-tree cloud
  # provider claims the Service and builds a Classic Load Balancer, ignoring every annotation
  # (rules.md G-1).
  depends_on = [
    module.network,
    module.synced_load_balancer,
    module.aws_load_balancer_controller,
    module.eks_coredns_addon,
  ]
}
# The variant. Sentry itself, reached through the ingress controller above.
module "sentry" {
  source = "./modules/sentry"

  admin_email     = var.sentry_admin_email
  admin_password  = var.sentry_admin_password
  namespace       = var.sentry_namespace
  chart_version   = var.sentry_chart_version
  timeout_seconds = var.sentry_timeout_seconds
  # The subchart images come from Bitnami's legacy namespace, because the tags this chart pins were
  # moved out of docker.io/bitnami and now answer NotFound there. Without this the install fails in
  # the db-check hook with DeadlineExceeded, which names neither images nor the registry.
  bitnami_image_namespace = var.bitnami_image_namespace
  # From the module that owns the class, so Sentry's Ingress cannot name a class no controller
  # reconciles (rules.md B-5).
  ingress_class_name = module.ingress_nginx.ingress_class_name

  # Three different reasons, all real: the EBS CSI driver has to be able to provision volumes, a
  # default StorageClass has to exist for the subcharts' claims to resolve to anything at all, and
  # the ingress controller has to be reconciling before Sentry's Ingress gets an address. None of
  # them is visible to Terraform's graph from the values above (rules.md D-2).
  #
  # csi_storage_classes especially: this module reads none of its outputs, and even if it did, that
  # module's outputs are passthroughs of its own variables (rules.md B-5) and therefore known at
  # plan time - so a value reference would not have ordered anything either.
  depends_on = [
    module.network,
    module.eks_ebs_csi_driver_addon,
    module.csi_storage_classes,
    module.ingress_nginx,
  ]
}
# With manage-backend-security-group-rules unset the controller writes no node-side rules at
# all, so the path from load balancer to pod has to be declared here or every target stays
# unhealthy with no error anywhere (rules.md G-2). target-type is ip, so traffic arrives at the
# ingress controller pod's container port, and pods on this cluster use the cluster security
# group.
#
# One rule per published port: https is the port the dashboard is actually reached on once
# Sentry redirects, so leaving it out closes the path even though the listener exists.
#
# It modifies the cluster security group, which no module here owns outright, so it belongs in
# the root (rules.md C-1).
resource "aws_vpc_security_group_ingress_rule" "load_balancer_to_pods" {
  for_each                     = var.load_balancer_ports
  security_group_id            = module.eks_cluster.cluster_security_group_id
  description                  = "Ingress controller ${each.key} port from the Sentry NLB"
  ip_protocol                  = "tcp"
  from_port                    = each.value
  to_port                      = each.value
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
  # cluster and carries all five tools (rules.md H-1). None of them creates anything: the two
  # charts the _monolithic template installed from here are Terraform resources now
  # (rules.md E-1). sentry-cli stays, because it is a tool for talking to the running Sentry
  # rather than something that creates it.
  #
  # Two bugs from that template are fixed here rather than carried over. It ran "exec bash"
  # partway through, which replaces the shell and silently discarded every remaining line -
  # update-kubeconfig, eksctl and helm were all after it, so none of them ever ran. And it
  # pulled eksctl from weaveworks; eksctl-io is the project's own org (rules.md H-1).
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
    # The Sentry CLI, as the _monolithic template installed it. INSTALL_DIR keeps it in the
    # user's own bin rather than needing sudo, and pinning the version stops a later boot from
    # picking up an incompatible one.
    curl -sL https://sentry.io/get-cli/ | INSTALL_DIR=/home/ec2-user/bin SENTRY_CLI_VERSION=${var.sentry_cli_version} bash
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
  #
  # Nothing here carries the admin password. The _monolithic template put it and the email into
  # one plaintext output, and every output is rendered into a README on an instance whose
  # code-server has no authentication - so that output handed the dashboard to anyone who could
  # reach the instance (rules.md H-2).
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
      description = "API server endpoint. Public so the helm provider could reach it during apply - narrow public_access_cidrs to your own address"
      value       = module.eks_cluster.cluster_endpoint
    }
    sentry_url = {
      order       = 4
      title       = "Sentry dashboard"
      description = "Served through the pre-created NLB the ingress controller adopts, so the address is known from state at apply time rather than only after reconciliation (rules.md G-3). Sentry takes several minutes after the apply returns before it answers"
      value       = module.synced_load_balancer.url
    }
    sentry_admin_login = {
      order       = 5
      title       = "Sentry admin login"
      description = "The login name only. The password is deliberately not here: this text is written into a README served by a code-server with no authentication in front of it, and the dashboard above is internet-facing (rules.md H-2). Read the password with the command below"
      value       = module.sentry.admin_email
    }
    sentry_admin_password_command = {
      order       = 6
      title       = "Read the admin password"
      description = "Out of the release's own Secret, for whoever already has cluster access. A command rather than the value, for the reason above"
      value       = module.sentry.admin_password_check_command
    }
    sentry_rollout_command = {
      order       = 7
      title       = "1. Confirm Sentry finished rolling out"
      description = "This is the thing to watch rather than reloading the URL. The chart brings PostgreSQL, Redis, Kafka, ZooKeeper and ClickHouse, so the first install routinely takes tens of minutes"
      value       = module.sentry.rollout_command
    }
    sentry_main_workloads_command = {
      order       = 8
      title       = "1b. Wait for web and snuba-api"
      description = "The apply deliberately does not wait for these two. Their readiness probes need the database schema that the chart's post-install hooks create, so requiring them during install would deadlock - they come up shortly after the hooks finish, and this is where to confirm it"
      value       = module.sentry.main_workloads_command
    }
    sentry_pods_command = {
      order       = 9
      title       = "2. Look at the pods if it stalls"
      description = "Every pod the chart brings. Pods stuck Pending here are almost always waiting on a volume rather than on Sentry - check the claims with the command below"
      value       = module.sentry.pods_command
    }
    sentry_install_progress_command = {
      order       = 10
      title       = "If the apply failed with \"context deadline exceeded\""
      description = "That is the helm timeout, and it reports nothing else. The chart installs through 12 serialized hook weights - db-check, snuba-db-init, snuba-migrate, db-init, user-create, then five waves of Deployments - so the last completed Job names the wave it was still on, and the pods after it are what it was waiting for"
      value       = module.sentry.install_progress_command
    }
    sentry_migration_log_command = {
      order       = 11
      title       = "...and read the migration Jobs"
      description = "snuba-migrate runs the ClickHouse migrations and is the slowest link in the chain, so it is where a timeout is usually spent. Both Jobs carry hook-delete-policy hook-succeeded, so \"not found\" means the Job passed and was cleaned up"
      value       = module.sentry.migration_log_command
    }
    sentry_pending_reason_command = {
      order       = 12
      title       = "...and why anything is still Pending"
      description = "\"Too many pods\" is the node group's per-node pod limit rather than its CPU or memory - see node_group_instance_types. A Pending claim or FailedAttachVolume is the EBS CSI driver"
      value       = module.sentry.pending_reason_command
    }
    volume_check_command = {
      order       = 13
      title       = "3. Check volume provisioning"
      description = "Claims and then the EBS CSI controller's log. Read the STORAGECLASS column first: empty means the claim resolved to no class and the driver was never asked to provision anything, so check the StorageClass below instead of this log. A class named but the claim still Pending is the driver failing, usually its IAM role missing AmazonEBSCSIDriverPolicy"
      value       = module.eks_ebs_csi_driver_addon.volume_check_command
    }
    sentry_ingress_command = {
      order       = 14
      title       = "4. Check the Ingress got an address"
      description = "An empty ADDRESS means the ingress controller is not reconciling Sentry's Ingress, which is normally a class mismatch rather than anything wrong with Sentry"
      value       = module.sentry.ingress_command
    }
    adopted_load_balancer_check_command = {
      order       = 15
      title       = "5. Confirm the load balancer was adopted, not duplicated"
      description = "Lists every load balancer tagged for this cluster. One is correct. Two means the controller did not adopt the pre-created one and built its own, which is a tag mismatch rather than an error (rules.md G-3)"
      value       = "aws resourcegroupstaggingapi get-resources --tag-filters Key=elbv2.k8s.aws/cluster,Values=${module.eks_cluster.cluster_name} --resource-type-filters elasticloadbalancing:loadbalancer --query 'ResourceTagMappingList[].ResourceARN' --output table"
    }
    ingress_hostname_command = {
      order       = 16
      title       = "6. Read the address the controller attached"
      description = "Compare this against the dashboard URL above. They should be the same load balancer"
      value       = module.ingress_nginx.load_balancer_hostname_command
    }
    sentry_cli_login_command = {
      order       = 17
      title       = "Sentry CLI"
      description = "The CLI is already installed on the instance. This points it at this deployment and prompts for a token from the dashboard"
      value       = "sentry-cli --url ${module.synced_load_balancer.url} login"
    }
    storage_class_name = {
      order       = 18
      title       = "StorageClass"
      description = "The default class all eight of Sentry's volume claims resolve through. None of them names a storageClassName, so the default annotation on this class is the only thing connecting them to the EBS CSI driver - a cluster without it leaves every claim Pending and the release times out in its hook chain with no mention of storage"
      value       = module.csi_storage_classes.storage_class_name
    }
    storage_class_check_command = {
      order       = 19
      title       = "Verify the default StorageClass"
      description = "Exactly one line should read (default), and it should be the gp3 one with provisioner ebs.csi.aws.com. The gp2 line is EKS's own and its kubernetes.io/aws-ebs provisioner has provisioned nothing since Kubernetes 1.23"
      value       = module.csi_storage_classes.storage_class_check_command
    }
    sentry_image_namespace = {
      order       = 20
      title       = "Bitnami image namespace"
      description = "Where the chart's PostgreSQL, Redis, Kafka, ZooKeeper, RabbitMQ and nginx images come from. bitnamilegacy because Bitnami moved its versioned tags out of docker.io/bitnami, where they now answer NotFound. That archive receives no updates, so mirroring these images is the better long-term answer"
      value       = module.sentry.bitnami_image_namespace
    }
    sentry_image_pull_check_command = {
      order       = 21
      title       = "Check for image pull failures"
      description = "Run this first when the release fails inside a hook. A hook that waits for a dependency reports only its own DeadlineExceeded, so an image that cannot be pulled appears here and nowhere in Terraform's error. \"not found\" means the tag is gone from the registry, not that the pull was unauthorised"
      value       = module.sentry.image_pull_check_command
    }
    update_kubeconfig_command = {
      order       = 22
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
# The work happens inside code-server in a browser, where terraform output is not available, so
# every output above is also written to a README in the home directory the IDE opens
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
    # SSM runs as root, hence the chown. The heredoc delimiter is quoted and unlikely to appear
    # in the body: Terraform has already substituted every value, so the shell has no reason to
    # touch a "$" or a backtick.
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
