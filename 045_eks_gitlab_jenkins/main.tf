data "aws_region" "current" {}

locals {
  # The object names the adoption tags are built from, defined once here.
  #
  # Each Service name has to be known before the release that creates it runs,
  # because the pre-created load balancer is tagged with it first - so the value
  # cannot come out of the release. Defining it here and passing it into both the
  # load balancer and the release is what keeps the two from drifting
  # (rules.md B-5/G-3).
  #
  # GitLab's bundled nginx-ingress subchart names its Service
  # <release>-nginx-ingress-controller, which is the name the _monolithic template
  # annotated by hand.
  gitlab_ingress_service_name = "${var.gitlab_release_name}-nginx-ingress-controller"
  gitlab_stack_tag            = "${var.gitlab_namespace}/${local.gitlab_ingress_service_name}"
  # The Jenkins side uses the standalone ingress-nginx chart, and the module pins
  # fullnameOverride to the release name, so its Service is <release>-controller.
  # The _monolithic template relied on the chart's conditional naming instead and
  # tagged its load balancer jenkins/jenkins-nginx-ingress-nginx-controller -
  # correct for that release name, and silently wrong for any other.
  jenkins_ingress_service_name = "${var.jenkins_ingress_release_name}-controller"
  jenkins_stack_tag            = "${var.jenkins_namespace}/${local.jenkins_ingress_service_name}"
}

module "network" {
  source = "./modules/network"

  vpc_cidr_block           = var.vpc_cidr_block
  vpc_name                 = "${var.project_name}-vpc"
  internet_gateway_name    = "${var.project_name}-igw"
  public_subnet_name       = "${var.project_name}-public"
  private_subnet_name      = "${var.project_name}-private"
  public_route_table_name  = "${var.project_name}-public-rt"
  private_route_table_name = "${var.project_name}-private-rt"
  nat_gateway_name         = "${var.project_name}-natgw"
  # The AWS Load Balancer Controller discovers subnets by tag, not by
  # configuration, and a scheme that does not match the tags fails with
  # "couldn't auto-discover subnets". The _monolithic template tagged nothing,
  # which worked only because it pre-created both load balancers and named their
  # subnets explicitly - the moment anything asked the controller to build one,
  # discovery had nothing to find (rules.md G-1).
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

module "key_pair" {
  source = "./modules/key_pair"

  key_name = "${var.project_name}-key"

  # Nothing here reads a network output, but the root orders every module after
  # the network so the whole VPC - NAT gateways and route tables included - is
  # finished before anything starts in it (rules.md D-3).
  depends_on = [module.network]
}

module "eks_cluster" {
  source = "./modules/eks_cluster"

  name                      = var.cluster_name
  kubernetes_version        = var.kubernetes_version
  subnet_ids                = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_private_access   = var.endpoint_private_access
  endpoint_public_access    = var.endpoint_public_access
  public_access_cidrs       = var.public_access_cidrs
  enabled_cluster_log_types = var.enabled_cluster_log_types

  # public_subnet_ids/private_subnet_ids order this after the specific aws_subnet
  # resources that produced them and nothing else - not the NAT gateways, not the
  # route table associations (rules.md D-3).
  depends_on = [module.network]
}

# vpc-cni and kube-proxy are DaemonSets, so they reach ACTIVE with zero nodes.
# They are created before the node group because a node cannot join Ready without
# them, and with bootstrap_self_managed_addons = false nothing installs them
# otherwise (rules.md C-4). The _monolithic template declared all three addons
# with no ordering at all and left the cluster bootstrapping its own unmanaged
# copies alongside them.
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  depends_on = [module.network, module.eks_cluster]
}

module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  depends_on = [module.network, module.eks_cluster]
}

module "eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name    = module.eks_cluster.cluster_name
  node_group_name = var.node_group_name
  instance_types  = var.node_instance_types
  desired_size    = var.node_desired_size
  min_size        = var.node_min_size
  max_size        = var.node_max_size
  key_name        = module.key_pair.key_name
  # Private subnets: the nodes reach the internet through the NAT gateways, and
  # nothing outside the VPC has a reason to reach them.
  subnet_ids = module.network.private_subnet_ids

  # Nodes need vpc-cni and kube-proxy running to join the cluster Ready
  # (rules.md C-4).
  depends_on = [module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}

# coredns is a Deployment, so unlike the two DaemonSets it needs schedulable node
# capacity to leave DEGRADED and become ACTIVE (rules.md C-4).
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name          = module.eks_cluster.cluster_name
  coredns_replica_count = var.coredns_replica_count

  depends_on = [
  module.network, module.eks_node_group]
}

# The Pod Identity agent, which is how the EBS CSI driver below gets its
# credentials. Its own module like every other addon (rules.md C-4), and it has to
# exist before any role is exchanged through it.
#
# The _monolithic template had no such addon: it built an IRSA role for the driver
# and relied on the addon annotating its service account. Pod Identity is used
# instead because its trust policy names no OIDC issuer, so nothing in the role has
# to be rebuilt when the cluster is replaced.
module "eks_pod_identity_agent_addon" {
  source = "./modules/eks_pod_identity_agent_addon"

  cluster_name = module.eks_cluster.cluster_name

  depends_on = [module.network, module.eks_cluster]
}

# The EBS CSI driver, with its own IAM role. Both GitLab and Jenkins claim
# persistent volumes, so without this every claim stays Pending, neither
# application starts, and the symptom shows up three layers away as an ingress
# returning 503.
module "eks_ebs_csi_driver_addon" {
  source = "./modules/eks_ebs_csi_driver_addon"

  cluster_name = module.eks_cluster.cluster_name

  # The controller half of this addon is a Deployment, so it needs node capacity to
  # leave DEGRADED - and the Pod Identity agent has to be running before its
  # credentials work (rules.md C-4/D-2).
  depends_on = [
  module.network, module.eks_node_group, module.eks_pod_identity_agent_addon]
}

# The gp3 StorageClass both applications' volume claims land on, and the
# annotation that stops EKS's built-in gp2 class from also claiming to be the
# default. The _monolithic template applied this with kubectl from a shell on the
# workbench, so it was in no state file (rules.md E-1/E-2).
module "csi_storage_classes" {
  source = "./modules/csi_storage_classes"

  storage_class_name = var.storage_class_name
  # No snapshot-controller addon in this project, so no VolumeSnapshotClass - its
  # kind would not exist and the manifest would fail at apply rather than at plan
  # (rules.md B-4).
  create_volume_snapshot_class = false

  # The class names ebs.csi.aws.com as its provisioner, so the driver has to be
  # installed first; the name is a literal string, which creates no dependency
  # (rules.md D-2).
  depends_on = [
  module.network, module.eks_ebs_csi_driver_addon]
}

# The controller that turns both ingress Services into network load balancers. Its
# IRSA role and its Helm release stay in one module because they reference each
# other (rules.md C-2).
module "aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"

  cluster_name                  = module.eks_cluster.cluster_name
  vpc_id                        = module.network.vpc_id
  aws_region                    = data.aws_region.current.region
  oidc_provider_arn             = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host              = module.eks_cluster.oidc_issuer_host
  chart_version                 = var.load_balancer_controller_chart_version
  enable_backend_security_group = var.enable_backend_security_group

  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}

# One frontend security group shared by both load balancers, as the _monolithic
# template's nlb-sg was.
module "load_balancer_security_group" {
  source = "./modules/load_balancer_security_group"

  vpc_id      = module.network.vpc_id
  name        = var.load_balancer_security_group_name
  description = "Frontend security group shared by the NLBs in front of GitLab and Jenkins"
  # The same map reaches both Services, both load balancers and the node-side
  # rules below, so the three cannot drift apart (rules.md B-5).
  ports                       = var.load_balancer_ports
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere

  depends_on = [module.network]
}

# The two network load balancers, created here and adopted by the controller
# rather than left for the controller to create. That is what makes both
# addresses known from state at apply time - and it is the only way these NLBs can
# carry a security group at all, since AWS refuses to add security groups to an
# NLB after creation (rules.md G-3).
#
# The _monolithic template pre-created both too, but gave them the VPC's default
# security group. That group opens nothing the ingress Services need, and because
# the Services also named nlb-sg in their annotations the controller's own model
# disagreed with what existed.
module "synced_gitlab_load_balancer" {
  source = "./modules/synced_load_balancer"

  cluster_name       = module.eks_cluster.cluster_name
  name               = var.gitlab_load_balancer_name
  load_balancer_type = "network"
  internal           = false
  # internet-facing, so public subnets. This has to agree with the scheme the
  # release annotates, or the controller builds a second load balancer instead of
  # adopting this one (rules.md G-3).
  subnet_ids         = module.network.public_subnet_ids
  security_group_ids = [module.load_balancer_security_group.security_group_id]
  # service.k8s.aws/*, not ingress.k8s.aws/*: this fronts a Service of type
  # LoadBalancer. GitLab's own Ingress objects are served by the nginx controller
  # behind that Service, so as far as the AWS controller is concerned there is no
  # Ingress here. The wrong prefix is not an error - the controller just does not
  # adopt (rules.md G-3).
  resource_tag_prefix = "service"
  stack               = local.gitlab_stack_tag

  depends_on = [module.network]
}

module "synced_jenkins_load_balancer" {
  source = "./modules/synced_load_balancer"

  cluster_name        = module.eks_cluster.cluster_name
  name                = var.jenkins_load_balancer_name
  load_balancer_type  = "network"
  internal            = false
  subnet_ids          = module.network.public_subnet_ids
  security_group_ids  = [module.load_balancer_security_group.security_group_id]
  resource_tag_prefix = "service"
  stack               = local.jenkins_stack_tag

  depends_on = [module.network]
}

# GitLab, as a Helm release rather than as a shell script an SSM Association ran
# (rules.md E-1).
module "gitlab" {
  source = "./modules/gitlab"

  release_name     = var.gitlab_release_name
  namespace        = var.gitlab_namespace
  create_namespace = true
  domain           = var.gitlab_domain
  issuer_email     = var.admin_email
  chart_version    = var.gitlab_chart_version
  wait             = var.gitlab_wait
  # Both names come from the root locals, which is also where the load balancer's
  # tag comes from (rules.md B-5).
  ingress_service_name        = local.gitlab_ingress_service_name
  stack_tag                   = local.gitlab_stack_tag
  scheme                      = "internet-facing"
  nlb_target_type             = "ip"
  frontend_security_group_ids = [module.load_balancer_security_group.security_group_id]

  # The load balancer has to exist before the controller reconciles this Service,
  # or the controller creates its own and the pre-created one is orphaned
  # (rules.md G-3). The AWS Load Balancer Controller has to be running too,
  # otherwise the in-tree cloud provider claims the Service and builds a Classic
  # Load Balancer, ignoring every annotation (rules.md G-1). The StorageClass is
  # in the list because the chart's Gitaly and PostgreSQL volumes are claimed
  # without naming a class, so they get the default.
  #
  # The DNS record is in the list because the runner and the HTTP-01 self check
  # start looking the hostnames up as soon as their pods run. A lookup that comes
  # first is answered NXDOMAIN, and the VPC resolver keeps that answer for the
  # zone's negative-caching TTL - 15 minutes with Route 53's default SOA - so both
  # would go on failing that long after the record exists. Nothing in this module
  # references the record, so only depends_on orders it; the _monolithic template
  # installed GitLab after its record for the same reason (rules.md D-2). With
  # create_dns_record false the list entry has no instances and orders nothing.
  depends_on = [
    module.network,
    module.synced_gitlab_load_balancer,
    module.aws_load_balancer_controller,
    module.csi_storage_classes,
    module.eks_coredns_addon,
    aws_route53_record.gitlab_wildcard,
  ]
}

# The ingress-nginx controller in front of Jenkins. A second, independent
# controller with its own IngressClass, which is why neither class is marked the
# cluster default - GitLab brings its own, and a shared default would let either
# claim the other's Ingress.
module "jenkins_ingress_nginx" {
  source = "./modules/ingress_nginx"

  release_name     = var.jenkins_ingress_release_name
  namespace        = var.jenkins_namespace
  create_namespace = true
  service_name     = local.jenkins_ingress_service_name
  stack_tag        = local.jenkins_stack_tag
  chart_version    = var.jenkins_ingress_nginx_chart_version
  # The class name and controller value the _monolithic script used.
  ingress_class_name             = var.jenkins_ingress_class_name
  ingress_class_controller_value = "ingress.nginx/jenkins"
  set_as_default_ingress_class   = false
  scheme                         = "internet-facing"
  nlb_target_type                = "ip"
  service_ports                  = var.load_balancer_ports
  frontend_security_group_ids    = [module.load_balancer_security_group.security_group_id]

  depends_on = [
    module.network,
    module.synced_jenkins_load_balancer,
    module.aws_load_balancer_controller,
    module.eks_coredns_addon,
  ]
}

# Jenkins itself, behind the controller above.
module "jenkins" {
  source = "./modules/jenkins"

  release_name   = var.jenkins_release_name
  namespace      = var.jenkins_namespace
  admin_username = var.jenkins_admin_username
  admin_password = var.jenkins_admin_password
  admin_email    = var.admin_email
  chart_version  = var.jenkins_chart_version
  # Taken from the controller module's output rather than from the variable, so
  # the class the Ingress asks for is the class that was actually created
  # (rules.md B-5). The _monolithic script set this with a kubectl patch after the
  # install, which left the Ingress unclaimed in between and untracked afterwards.
  ingress_class_name = module.jenkins_ingress_nginx.ingress_class_name
  # Null: the controller's default backend is this Ingress, and there is no second
  # application sharing it (rules.md B-4).
  ingress_hostname = null
  # Null too - the claim takes the cluster default, which is the gp3 class
  # module.csi_storage_classes installs.
  persistence_storage_class = null

  # The controller has to exist first, so the class this Ingress names is real,
  # and the StorageClass has to exist before the controller's volume is claimed
  # (rules.md D-2).
  depends_on = [
  module.network, module.jenkins_ingress_nginx, module.csi_storage_classes]
}

# The node-side rules. Both Services name their own frontend security group and
# neither sets manage-backend-security-group-rules, so the controller writes no
# rules toward the pods at all - with backendSGIDToken empty it omits the
# TargetGroupBinding networking spec entirely. These rules are what make the data
# path exist (rules.md G-2).
#
# One rule per published port, covering both load balancers because they share one
# frontend group. target-type ip means traffic arrives at the pods' container
# ports, and the pods use the cluster security group - which no module here owns
# outright, so this belongs in the root (rules.md C-1).
resource "aws_vpc_security_group_ingress_rule" "load_balancer_to_pods" {
  for_each                     = var.load_balancer_ports
  security_group_id            = module.eks_cluster.cluster_security_group_id
  description                  = "Ingress controller ${each.key} port from the shared NLB frontend security group"
  ip_protocol                  = "tcp"
  from_port                    = each.value
  to_port                      = each.value
  referenced_security_group_id = module.load_balancer_security_group.security_group_id
}

# The wildcard record that makes gitlab.<domain>, registry.<domain>,
# minio.<domain> and kas.<domain> resolve to the GitLab load balancer.
#
# The release needs it as much as a browser does. The bundled runner registers
# against https://gitlab.<domain>, and cert-manager self-checks every HTTP-01
# challenge at http://<host>/.well-known/acme-challenge/ before it asks Let's
# Encrypt to validate. Both look the names up through CoreDNS and the VPC
# resolver, which means public DNS. Without this record the runner PANICs with
# "no such host" on every attempt and every hostname keeps cert-manager's
# temporary certificate, while helm reports the release deployed.
#
# On by default, as in the _monolithic template, and still switchable for a zone
# held elsewhere. It used to be off by default so that a plan in an account
# without the zone would not stop at this lookup - a data source resolves during
# plan. That stop is the better failure: the alternative was the silent one above,
# which is how this project's first apply ended (rules.md B-1/B-4).
data "aws_route53_zone" "gitlab_zone" {
  count = var.create_dns_record ? 1 : 0

  name         = "${var.gitlab_domain}."
  private_zone = false
}

resource "aws_route53_record" "gitlab_wildcard" {
  count = var.create_dns_record ? 1 : 0

  zone_id = data.aws_route53_zone.gitlab_zone[0].zone_id
  name    = coalesce(var.dns_record_name, "*.${var.gitlab_domain}")
  type    = "A"
  alias {
    # The pre-created load balancer, which is exactly why this project pre-creates
    # it: an alias record needs a DNS name and a hosted zone ID at plan time, and a
    # load balancer the controller creates has neither until long after
    # (rules.md G-3).
    name                   = module.synced_gitlab_load_balancer.dns_name
    zone_id                = module.synced_gitlab_load_balancer.zone_id
    evaluate_target_health = false
  }
}

module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name                        = "${var.project_name}-vscode"
  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  code_server_version         = var.code_server_version
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  # Lets the README association below know when the bootstrap has finished
  # (rules.md H-2). The module touches <path>/userdata as its very last step.
  marker_file_path = var.marker_file_path
  # Joining the cluster security group is what lets this instance reach the API
  # server on its private address. The module is handed an ID list and never
  # learns that it belongs to an EKS cluster (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]
  # An EKS cluster and this instance share a root module, so this instance is the
  # workbench for that cluster and carries all five tools: code-server (the
  # module's own job) plus kubectl, eksctl, helm and docker (rules.md H-1).
  #
  # None of them creates anything. The _monolithic template used this script to
  # `helm install` the load balancer controller and then had an SSM Association
  # run two more scripts that installed GitLab, ingress-nginx and Jenkins; all
  # five are Helm releases and Kubernetes objects now (rules.md E-1).
  additional_user_data = <<-EOT
    # Building an image or pushing one to ECR needs a daemon on the host, which is
    # the one thing here no provider resource can replace (rules.md E-1/H-1).
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server is already running from the module's bootstrap, so its process
    # predates the docker group and its terminals inherit the groups that process
    # started with. Restarting is what makes docker usable from the IDE, rather
    # than opening /var/run/docker.sock up to 666.
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
    # exist before complete references it. The _monolithic template had the
    # complete line first, so every login printed "function not found"
    # (rules.md H-1).
    echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
    echo 'source <(kubectl completion bash)' >> ~/.bashrc
    echo 'alias k=kubectl' >> ~/.bashrc
    echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
    # No `exec bash` here. The _monolithic template ran one at this point, which
    # replaced the shell and silently discarded everything after it - the
    # kubeconfig, eksctl, helm and the load balancer controller install all never
    # ran.
    #
    # eksctl-io is the project's own org; the old weaveworks URL still redirects
    # but the current name is what gets used (rules.md H-1).
    PLATFORM=$(uname -s)_amd64
    curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
    tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
    sudo install -m 0755 /tmp/eksctl /usr/local/bin && rm /tmp/eksctl
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm -f get_helm.sh
    aws configure set default.region ${data.aws_region.current.region}
    # Without this - and without the access entry below - kubectl is installed but
    # every command answers "You must be logged in to the server" (rules.md H-1).
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}
    EOF
  EOT

  depends_on = [module.network]
}

# Granting the workbench's instance role cluster access joins two modules that
# know nothing about each other, so it belongs in the root (rules.md C-1).
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

  # EKS rejects a policy association for a principal with no access entry yet, and
  # the two resources share only literal argument values, so nothing orders them
  # (rules.md D-1). The _monolithic template had no ordering here at all.
  depends_on = [aws_eks_access_entry.vscode_access_entry]
}

locals {
  # Every output this project exposes, defined once. outputs.tf projects these and
  # the README below renders them, so no value expression is written twice
  # (rules.md B-5/H-2). Adding an entry here is what makes an output possible,
  # which is what keeps the README from silently falling behind outputs.tf.
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here and run every command below from its terminal. kubectl is already pointed at the cluster"
      value       = module.vscode_ec2.vscode_url
    }
    cluster_name = {
      order       = 2
      title       = "EKS cluster name"
      description = "Name of the EKS cluster. Also the elbv2.k8s.aws/cluster tag on both pre-created load balancers"
      value       = module.eks_cluster.cluster_name
    }
    gitlab_url = {
      order       = 3
      title       = "GitLab"
      description = "GitLab web URL, username root. It resolves through the wildcard record this project creates in the domain's hosted zone. With create_dns_record set to false, add that record by hand wherever the domain is hosted - until it resolves, the bundled runner cannot register and no hostname gets a Let's Encrypt certificate"
      value       = module.gitlab.url
    }
    gitlab_initial_root_password_command = {
      order       = 4
      title       = "1. GitLab root password"
      description = "The chart generates it and stores it in a Secret, so it is read from the cluster rather than exposed as a Terraform output"
      value       = module.gitlab.initial_root_password_command
    }
    gitlab_load_balancer_url = {
      order       = 5
      title       = "GitLab load balancer"
      description = "Address of the NLB Terraform pre-created for GitLab. Known from state at apply time, which is what makes the alias record above possible"
      value       = module.synced_gitlab_load_balancer.url
    }
    gitlab_adoption_check_command = {
      order       = 6
      title       = "2. Did the controller adopt the GitLab NLB?"
      description = "Compare the address this prints against the pre-created load balancer above. Two different names mean the adoption tags did not match and a second load balancer was built - which is the failure mode of this pattern, and it produces no error (rules.md G-3)"
      value       = module.gitlab.load_balancer_hostname_command
    }
    jenkins_url = {
      order       = 7
      title       = "Jenkins"
      description = "Jenkins web URL, served through the pre-created NLB and the jenkins-nginx ingress controller. No DNS record needed - this is the load balancer's own name"
      value       = module.synced_jenkins_load_balancer.url
    }
    jenkins_admin_username = {
      order       = 8
      title       = "Jenkins administrator"
      description = "Login name for the Jenkins UI"
      value       = module.jenkins.admin_username
    }
    jenkins_admin_password_command = {
      order       = 9
      title       = "3. Jenkins password"
      description = "Read back out of the chart's Secret. The password is never a Terraform output: this README sits on a code-server instance that serves with authentication disabled (rules.md H-2)"
      value       = module.jenkins.admin_password_command
    }
    jenkins_ingress_status_command = {
      order       = 10
      title       = "4. The Jenkins Ingress has a class"
      description = "The CLASS column should read jenkins-nginx. Empty means no controller will claim it, which is the state the _monolithic template left it in until its kubectl patch ran"
      value       = module.jenkins.ingress_status_command
    }
    jenkins_adoption_check_command = {
      order       = 11
      title       = "5. Did the controller adopt the Jenkins NLB?"
      description = "Same comparison as for GitLab, against the Jenkins load balancer address"
      value       = module.jenkins_ingress_nginx.load_balancer_hostname_command
    }
    storage_class_check_command = {
      order       = 12
      title       = "6. One default StorageClass"
      description = "gp3 should be the only class marked (default). Two defaults leave a claim that names no class bound to whichever one the API server happens to pick, and both applications here claim without naming one"
      value       = module.csi_storage_classes.storage_class_check_command
    }
    load_balancer_count_command = {
      order       = 13
      title       = "7. Exactly two load balancers"
      description = "Lists every load balancer tagged for this cluster. Two is correct - GitLab and Jenkins. Three or four means adoption failed and the controller built its own alongside the pre-created ones"
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
  # order field and taking values() sorts by that instead - values() returns a
  # map's values ordered by key - so the README reads in the order the demo is run.
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  readme_body = join("\n", concat(
    ["# ${var.project_name}", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}

# The work happens inside code-server in a browser, where "terraform output" does
# not exist, so every output above is also written to a README in the home
# directory the IDE opens (rules.md H-2).
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is what
    # orders this after the instance bootstrap, and the marker this command leaves
    # behind is what a later association would wait on (rules.md D-5). The marker
    # path comes back out of the module it was passed into, so it is defined in
    # exactly one place (rules.md B-5).
    #
    # SSM runs as root, hence the chown. The heredoc delimiter is quoted and
    # deliberately unlikely to appear in the body: Terraform has already
    # substituted every value, so the shell has no reason to touch a "$" or a
    # backtick in the README. The _monolithic template built this file with echo
    # instead, and its commands contained both.
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
