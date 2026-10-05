data "aws_region" "current" {}

locals {
  # The hostname the certificate covers and the record points at. One expression, used by the
  # certificate, the record and the URL output (rules.md B-5).
  mcp_hostname = "${var.mcp_record_subdomain}.${var.mcp_server_domain}"
  # The ports the ALB listens on. Three things have to agree on this and previously did not: the
  # listener the controller creates, the frontend security group's inbound rules, and the URL in
  # the outputs.
  #
  # What was here before was
  #
  #     listener_port = var.create_custom_domain ? var.https_port : var.mcp_server_port
  #
  # on the reasoning that with no certificate the listener is "the MCP port itself". Nothing made
  # that true. The listener is created by the AWS Load Balancer Controller from the Ingress, and
  # with no alb.ingress.kubernetes.io/listen-ports annotation the controller uses its own default
  # of HTTP:80 - which is also what mcp_server_url and the status probe below assume, because
  # neither carries a port. So the listener was on 80, the security group opened 8000, and the
  # endpoint accepted nothing. Every Terraform resource reported success, the target group's only
  # target was healthy, and the URL in the output timed out (rules.md G-1: the frontend group has
  # to open the listener port, and the container port is a different rule in a different group).
  #
  # Now the annotation is set from these values, so the controller's listener is decided here
  # rather than by its default, and the security group and the URL are derived from the same place
  # (rules.md B-5).
  listener_port = var.create_custom_domain ? var.https_port : var.http_port
  # Every port the listener set needs opened. With a certificate there are two: 443 for the real
  # listener and 80 for the redirect that the ssl-redirect annotation installs - without 80 open,
  # a client arriving on http gets a timeout instead of a redirect.
  listener_ports = var.create_custom_domain ? {
    https = var.https_port
    http  = var.http_port
    } : {
    http = var.http_port
  }
  # The same set in the shape the controller's annotation takes.
  alb_listen_ports = jsonencode(var.create_custom_domain
    ? [{ HTTP = var.http_port }, { HTTPS = var.https_port }]
    : [{ HTTP = var.http_port }]
  )
  # Only non-default ports belong in a URL, so the common case reads http://<host>/mcp.
  listener_port_suffix = (
    (var.create_custom_domain && var.https_port == 443) || (!var.create_custom_domain && var.http_port == 80)
    ? "" : ":${local.listener_port}"
  )
  # The adoption tag, defined here so both the load balancer and the workload receive it and
  # the load balancer can be created first (rules.md B-5/G-3).
  mcp_stack_tag = "${var.mcp_namespace}/${var.mcp_ingress_name}"
  # The URL an IDE puts in its mcp.json. With no custom domain the load balancer's own name
  # is the only address there is, and it has no certificate - so http, and the value is only
  # known after the controller has attached the load balancer.
  mcp_server_url = var.create_custom_domain ? "https://${local.mcp_hostname}${local.listener_port_suffix}/mcp" : "http://${module.synced_load_balancer.dns_name}${local.listener_port_suffix}/mcp"
}

module "network" {
  source = "./modules/network"

  region                         = data.aws_region.current.region
  vpc_cidr_block                 = var.vpc_cidr_block
  availability_zone_suffixes     = var.availability_zone_suffixes
  nat_availability_zone_suffixes = var.nat_availability_zone_suffixes
  vpc_name                       = "${var.project_name}-vpc"
  # The AWS Load Balancer Controller discovers subnets by tag, not by configuration, and a
  # scheme that does not match the tags fails with "couldn't auto-discover subnets". The
  # _monolithic template tagged nothing, which worked only because it pre-created the load
  # balancer with explicit subnets - the moment the controller had to place one itself,
  # discovery had nothing to find (rules.md G-1).
  subnet_tags = {
    "kubernetes.io/role/elb"          = "1"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

module "key_pair" {
  source = "./modules/key_pair"

  key_name = "${var.project_name}-key"

  # Nothing here reads a network output, but the root orders every module after the network so
  # the whole VPC - NAT gateway and route tables included - is finished before anything starts
  # in it (rules.md D-3).
  depends_on = [module.network]
}

module "eks_cluster" {
  source = "./modules/eks_cluster"

  name                   = var.cluster_name
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  depends_on = [module.network]
}

# vpc-cni and kube-proxy are DaemonSets, so they reach ACTIVE with zero nodes. They come
# before the node group because a node cannot join Ready without them, and with
# bootstrap_self_managed_addons = false nothing installs them otherwise (rules.md C-4).
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

# The Pod Identity agent, which is how both the load balancer controller and the MCP server
# pod get their credentials. A DaemonSet, so it needs no node capacity to become ACTIVE - but
# it has to exist before any pod tries to exchange a token (rules.md C-4).
module "eks_pod_identity_agent_addon" {
  source = "./modules/eks_pod_identity_agent_addon"

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
  subnet_ids      = module.network.private_subnet_ids

  depends_on = [module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}

# coredns is a Deployment, so unlike the DaemonSets it needs schedulable node capacity to
# leave DEGRADED and become ACTIVE (rules.md C-4).
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name          = module.eks_cluster.cluster_name
  coredns_replica_count = var.coredns_replica_count

  depends_on = [
  module.network, module.eks_node_group]
}

# The controller that turns the MCP Ingress into an ALB. Its IAM role, its Pod Identity
# association and its Helm release stay in one module because they reference each other
# (rules.md C-2).
module "aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"

  cluster_name                  = module.eks_cluster.cluster_name
  vpc_id                        = module.network.vpc_id
  aws_region                    = data.aws_region.current.region
  chart_version                 = var.load_balancer_controller_chart_version
  enable_backend_security_group = var.enable_backend_security_group

  depends_on = [
    module.network,
    module.eks_node_group,
    module.eks_coredns_addon,
    module.eks_pod_identity_agent_addon,
  ]
}

# The ALB's frontend security group, created here rather than left to the controller so its
# rules are reviewable in the plan (rules.md G-1). It is also the group the pre-created load
# balancer is built with, which matters more than usual here - see synced_load_balancer.
module "alb_security_group" {
  source = "./modules/load_balancer_security_group"

  vpc_id      = module.network.vpc_id
  name        = var.alb_security_group_name
  description = "Frontend security group for the ALB in front of the EKS MCP server"
  # Exactly the ports the controller is told to listen on, from the same local the annotation is
  # built from, so a rule can no longer disagree with a listener (rules.md B-5). The _monolithic
  # template opened 443 unconditionally; this configuration then opened the container port, which
  # was wrong in the other direction - see the note on local.listener_ports.
  ports                       = local.listener_ports
  allow_inbound_from_anywhere = var.alb_allow_inbound_from_anywhere

  depends_on = [module.network]
}

# The path from the ALB to the pods, which nothing else creates. With the shared backend
# security group off, the controller does not write a reduced set of pod-side rules - it
# leaves the networking spec out of the TargetGroupBinding altogether, so not one rule is
# created and every target reports unhealthy while the ALB itself looks fine
# (rules.md G-2).
#
# It modifies the cluster security group, which no module here owns outright, so it belongs in
# the root (rules.md C-1). target-type ip sends traffic to the pod's container port, and the
# ALB health check uses traffic-port, so this one rule covers both.
resource "aws_vpc_security_group_ingress_rule" "load_balancer_to_pods" {
  security_group_id            = module.eks_cluster.cluster_security_group_id
  description                  = "MCP server port from the ALB frontend security group"
  ip_protocol                  = "tcp"
  from_port                    = var.mcp_server_port
  to_port                      = var.mcp_server_port
  referenced_security_group_id = module.alb_security_group.security_group_id
}

# The ECR repository and the CodeBuild project that fills it. The image is built from
# files/Dockerfile rather than from a heredoc inside the buildspec.
module "mcp_server_image" {
  source = "./modules/mcp_server_image"

  repository_name = var.ecr_repository_name
  project_name    = var.codebuild_project_name
  image_tag       = var.image_tag
  # Read from disk, so the Dockerfile is a real file. The build has no source repository, so
  # the contents still travel inside the buildspec - but they are edited in one place and can
  # be linted.
  dockerfile = file("${path.module}/files/Dockerfile")

  depends_on = [module.network]
}

# What actually runs a build. Terraform has no resource for "run this build once" - a project
# is infrastructure, a build is not - so it is started through a small function the AWS
# provider invokes at apply time.
#
# The _monolithic template had the same pair as a CloudFormation custom resource, and neither
# half could work: its code imported cfnresponse, a module CloudFormation provides only to
# inline Lambda code, so a zipped function fails while loading it.
module "image_build_trigger" {
  source = "./modules/codebuild_start_trigger"

  name                 = "${var.project_name}-image-build-trigger"
  source_dir           = "${path.module}/lambda_src/trigger_function"
  project_name         = module.mcp_server_image.project_name
  project_arn          = module.mcp_server_image.project_arn
  start_build_on_apply = var.start_build_on_apply
  # Ties "a build runs" to "the build definition changed". Without it the invocation fires once, on
  # first create, and a later change to files/Dockerfile updates the CodeBuild project and builds
  # nothing - which is indistinguishable from a successful apply until a pod pulls the old image, or
  # fails to pull one at all.
  build_revision = module.mcp_server_image.build_revision

  depends_on = [
  module.network, module.mcp_server_image]
}

# The pre-created ALB the controller adopts, rather than one the controller builds.
#
# Two reasons it is worth pre-creating here. The address is known from state at apply time, so
# a Route 53 alias record and an ACM certificate validation can be created in the same apply -
# which is the whole point of the custom domain. And the load balancer carries the frontend
# security group from creation, which the _monolithic template got wrong: it pre-created this
# ALB with the VPC's default security group while the Ingress annotation named mcp-server-alb-sg,
# so the group the controller expected and the group the load balancer had disagreed.
module "synced_load_balancer" {
  source = "./modules/synced_load_balancer"

  cluster_name       = module.eks_cluster.cluster_name
  name               = var.alb_name
  load_balancer_type = "application"
  internal           = false
  # internet-facing, so public subnets. This has to agree with the scheme the Ingress
  # annotates, or the controller builds a second load balancer instead of adopting this one
  # (rules.md G-3).
  subnet_ids = module.network.public_subnet_ids
  # Both groups, matching what the Ingress annotation names below: the frontend group that
  # admits the internet, and the cluster group the pods carry.
  security_group_ids = [
    module.alb_security_group.security_group_id,
    module.eks_cluster.cluster_security_group_id,
  ]
  # ingress.k8s.aws/*, not service.k8s.aws/*: this fronts an Ingress. The wrong prefix is not
  # an error - the controller just does not adopt (rules.md G-3).
  resource_tag_prefix = "ingress"
  stack               = local.mcp_stack_tag

  depends_on = [module.network]
}

# The MCP server itself: its IAM role, its Pod Identity association, and the four Kubernetes
# objects.
#
# The adoption tag comes from local.mcp_stack_tag, not from this module's output, and that is
# the whole reason this can be ordered after the load balancer: taking it from an output here
# would make the load balancer wait for the Ingress, and the controller would then reconcile an
# Ingress whose load balancer does not exist yet and build its own (rules.md G-3).
module "mcp_server_workload" {
  source = "./modules/mcp_server_workload"

  cluster_name    = module.eks_cluster.cluster_name
  image           = module.mcp_server_image.image_uri
  namespace       = var.mcp_namespace
  ingress_name    = var.mcp_ingress_name
  stack_tag       = local.mcp_stack_tag
  container_port  = var.mcp_server_port
  iam_policy_arns = var.mcp_server_iam_policy_arns

  ingress_annotations = merge(
    {
      "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
      "alb.ingress.kubernetes.io/target-type" = "ip"
      # Both groups, as the _monolithic template's annotation had them.
      "alb.ingress.kubernetes.io/security-groups" = join(",", [
        module.alb_security_group.security_group_id,
        module.eks_cluster.cluster_security_group_id,
      ])
      # /status, not /mcp. The MCP endpoint needs a session, so a health check against it
      # reports unhealthy on a perfectly healthy server - and the ALB then removes the only
      # target it has.
      "alb.ingress.kubernetes.io/healthcheck-path" = "/status"
      "alb.ingress.kubernetes.io/healthcheck-port" = tostring(var.mcp_server_port)
      # Without this the controller uses its own default of HTTP:80, which is a listener nothing
      # else in this configuration knows about - the frontend security group opens what
      # local.listener_ports says and the output URL carries what local.listener_port says. Setting
      # it makes the listener a decision this configuration makes rather than one it inherits, and
      # it is also what creates the HTTPS listener at all when there is a certificate: an unset
      # listen-ports leaves certificate-arn attached to nothing (rules.md G-1).
      "alb.ingress.kubernetes.io/listen-ports" = local.alb_listen_ports
    },
    # Only when there is a certificate to terminate TLS with. The _monolithic template set
    # both of these unconditionally against a certificate it never validated, so the listener
    # could not be created and the Ingress never got an address (rules.md B-4).
    var.create_custom_domain ? {
      "alb.ingress.kubernetes.io/certificate-arn" = aws_acm_certificate.mcp[0].arn
      "alb.ingress.kubernetes.io/ssl-redirect"    = tostring(var.https_port)
    } : {},
  )

  # The controller has to be running before the Ingress gets an address, the pre-created load
  # balancer has to exist before the controller reconciles it, and the image has to be in ECR
  # before a pod can pull it.
  #
  # Ordering the module after these is also what makes `terraform destroy` remove the Ingress
  # while the controller is still alive, so the load balancer is cleaned up rather than
  # orphaned (rules.md D-4).
  depends_on = [
    module.network,
    module.synced_load_balancer,
    module.aws_load_balancer_controller,
    module.eks_pod_identity_agent_addon,
    aws_ssm_association.wait_for_image,
  ]
}

# What the MCP server may do inside the cluster. The access entry maps the pod's role to a
# Kubernetes identity and the policy association decides what that identity can do - and the
# _monolithic template created the entry without the association, so the role was mapped and
# authorised for nothing.
#
# Joining two modules that know nothing about each other belongs in the root (rules.md C-1).
resource "aws_eks_access_entry" "mcp_server_access_entry" {
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.mcp_server_workload.pod_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "mcp_server_access_policy_association" {
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.mcp_server_workload.pod_role_arn
  policy_arn    = var.mcp_server_cluster_access_policy_arn
  access_scope {
    type = "cluster"
  }

  # EKS rejects a policy association for a principal with no access entry yet, and the two
  # resources share only literal argument values, so nothing orders them (rules.md D-1).
  depends_on = [aws_eks_access_entry.mcp_server_access_entry]
}

# The certificate for the custom domain, and the records that validate it.
#
# Conditional, and the validation is the part the _monolithic template left out entirely: it
# created an aws_acm_certificate with validation_method = "DNS" and no validation records, so
# the certificate stayed PENDING_VALIDATION forever and the ALB listener referencing it could
# never be created (rules.md B-4).
data "aws_route53_zone" "mcp" {
  count = var.create_custom_domain ? 1 : 0

  name         = "${var.mcp_server_domain}."
  private_zone = false
}

resource "aws_acm_certificate" "mcp" {
  count = var.create_custom_domain ? 1 : 0

  domain_name       = local.mcp_hostname
  key_algorithm     = "RSA_2048"
  validation_method = "DNS"

  lifecycle {
    # A certificate cannot be modified in place, and a listener referencing the old one blocks
    # its deletion - so the new one has to exist first.
    create_before_destroy = true
  }
}

resource "aws_route53_record" "mcp_certificate_validation" {
  # One record per validation option, keyed by domain name. The set is derived from the
  # certificate, so the keys are unknown until apply - which is exactly the situation
  # rules.md B-8 warns about, and the reason for for_each over a map built from a known-length
  # set rather than toset() of the values themselves. ACM issues one option per domain name,
  # and there is one domain name here.
  for_each = var.create_custom_domain ? {
    for option in aws_acm_certificate.mcp[0].domain_validation_options :
    option.domain_name => option
  } : {}

  zone_id         = data.aws_route53_zone.mcp[0].zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  records         = [each.value.resource_record_value]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "mcp" {
  count = var.create_custom_domain ? 1 : 0

  certificate_arn         = aws_acm_certificate.mcp[0].arn
  validation_record_fqdns = [for record in aws_route53_record.mcp_certificate_validation : record.fqdn]
}

# The record the IDE's mcp.json resolves. An alias to the pre-created load balancer, which is
# what makes this possible at all: an alias record needs a DNS name and a hosted zone ID at
# plan time, and a load balancer the controller creates has neither (rules.md G-3).
resource "aws_route53_record" "mcp" {
  count = var.create_custom_domain ? 1 : 0

  zone_id = data.aws_route53_zone.mcp[0].zone_id
  name    = local.mcp_hostname
  type    = "A"
  alias {
    name                   = module.synced_load_balancer.dns_name
    zone_id                = module.synced_load_balancer.zone_id
    evaluate_target_health = false
  }
}

module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name                        = "${var.project_name}-vscode"
  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_ids_by_zone[var.availability_zone_suffixes[0]]
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  code_server_version         = var.code_server_version
  security_group_name         = "${var.project_name}-vscode-sg"
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  marker_file_path            = var.marker_file_path
  # Carrying the cluster security group is what lets kubectl on this instance reach the API
  # server without leaving the VPC. The module is handed an ID list and never learns what it
  # belongs to (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]
  # An EKS cluster and this instance share a root module, so this instance is the workbench for
  # that cluster and carries all five tools (rules.md H-1).
  #
  # None of them creates anything. The _monolithic template used this script to install the
  # load balancer controller and apply the MCP manifests; both are provider resources now
  # (rules.md E-1). What is left is what a person needs to look at the cluster - and the
  # completion tab it also lacked: the original never installed bash completion or eksctl here.
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
    # Order matters: bash_completion has to be sourced before kubectl's own completion, which
    # is what defines __start_kubectl, and that function has to exist before complete
    # references it (rules.md H-1).
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
    rm -f get_helm.sh
    aws configure set default.region ${data.aws_region.current.region}
    # Without this - and without the access entry below - kubectl is installed but every
    # command answers "You must be logged in to the server" (rules.md H-1).
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}
    EOF
  EOT

  depends_on = [module.network]
}

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

# Waits for the image to actually be in ECR before the Deployment is created.
#
# The build trigger returns as soon as StartBuild is accepted, so "a build was started" is all
# the Terraform graph knows - and a Deployment created at that moment produces a pod in
# ImagePullBackOff that recovers minutes later, which reads like a broken image reference. This
# step closes that gap, and it runs on the workbench because that is where an AWS CLI with the
# right credentials already is.
#
# The until loop, not depends_on, is what orders this after the instance bootstrap
# (rules.md D-5).
resource "aws_ssm_association" "wait_for_image" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.build_wait_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    commands = <<-EOT
      set -euo pipefail
      # Bounded, like the image poll below it. An unbounded wait turns every reason the marker is
      # missing into one symptom - the command never returns, the association stays Pending, and
      # Terraform reports "last state: 'Pending'" against a UUID half an hour later. Giving up here
      # puts the reason in the invocation's standard error instead (rules.md D-5 keeps the marker;
      # this only adds a ceiling).
      deadline=$(( $(date +%s) + ${var.marker_wait_timeout_seconds} ))
      until [ -f ${module.vscode_ec2.marker_file_path}/userdata ]; do
        if [ "$(date +%s)" -ge "$deadline" ]; then
          echo "gave up after ${var.marker_wait_timeout_seconds}s waiting for ${module.vscode_ec2.marker_file_path}/userdata" >&2
          echo "the instance bootstrap never reached its end - read /var/log/cloud-init-output.log on this instance" >&2
          exit 1
        fi
        sleep 10
      done
      # Polls the image rather than the build, so a build started by hand counts too.
      attempt=0
      until aws ecr describe-images --repository-name ${var.ecr_repository_name} --image-ids imageTag=${var.image_tag} >/dev/null 2>&1; do
        attempt=$((attempt + 1))
        if [ "$attempt" -gt 100 ]; then
          echo "image ${var.image_tag} did not appear in ${var.ecr_repository_name}"
          aws codebuild list-builds-for-project --project-name ${var.codebuild_project_name} --max-items 1 --query 'ids' --output text
          exit 1
        fi
        echo "waiting for the image build to push ${var.ecr_repository_name}:${var.image_tag}"
        sleep 15
      done
      touch ${module.vscode_ec2.marker_file_path}/image
      EOT
  }

  depends_on = [module.image_build_trigger]
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
      description = "Open the IDE here and run every command below from its terminal"
      value       = module.vscode_ec2.vscode_url
    }
    mcp_server_url = {
      order       = 2
      title       = "MCP endpoint"
      description = "The URL an IDE puts in its mcp.json as a streamable-http server. With create_custom_domain false this is the load balancer's own name over plain HTTP - the certificate and the record only exist when that is turned on"
      value       = local.mcp_server_url
    }
    mcp_json = {
      order       = 3
      title       = "mcp.json"
      description = "Paste this into the IDE's MCP configuration. autoApprove on everything is what makes the demo frictionless, and also what makes it worth reading the warning below"
      value = jsonencode({
        mcpServers = {
          "eks-mcp-server-remote" = {
            url         = local.mcp_server_url
            type        = "streamable-http"
            autoApprove = ["*"]
            disabled    = false
          }
        }
      })
    }
    security_warning = {
      order       = 4
      title       = "What this endpoint can do"
      description = "The server runs with --allow-write and --allow-sensitive-data-access, and its pod holds a cluster-admin access entry. Anything that can reach the URL above has full control of this cluster, and there is no authentication in front of it - narrow alb_allow_inbound_from_anywhere and mcp_server_cluster_access_policy_arn before leaving it up"
      value       = "aws ec2 describe-security-group-rules --filters Name=group-id,Values=${module.alb_security_group.security_group_id} --query 'SecurityGroupRules[?!IsEgress].[IpProtocol,FromPort,ToPort,CidrIpv4]' --output table"
    }
    cluster_name = {
      order       = 5
      title       = "EKS cluster name"
      description = "Name of the EKS cluster, which is also the elbv2.k8s.aws/cluster tag on the pre-created load balancer"
      value       = module.eks_cluster.cluster_name
    }
    image_uri = {
      order       = 6
      title       = "Container image"
      description = "Built by CodeBuild from files/Dockerfile and pushed here. The tag is mutable, so a rebuild replaces it in place - which is why the Deployment pulls Always"
      value       = module.mcp_server_image.image_uri
    }
    build_status_command = {
      order       = 7
      title       = "1. The image build succeeded"
      description = "Terraform starts the build and an SSM step waits for the pushed image, so by the time apply finishes this should be SUCCEEDED. A FAILED build names the phase, and the build log group has the docker output"
      value       = module.mcp_server_image.build_status_command
    }
    images_check_command = {
      order       = 8
      title       = "2. The image is in ECR"
      description = "An empty list while the pod sits in ImagePullBackOff means the build never pushed, which the previous command explains"
      value       = module.mcp_server_image.images_check_command
    }
    deployment_status_command = {
      order       = 9
      title       = "3. The MCP server is running"
      description = "One replica, ready. mcp-proxy keeps per-session state, so this is deliberately not scaled - a second replica behind one load balancer would answer requests for sessions it does not hold"
      value       = module.mcp_server_workload.deployment_status_command
    }
    ingress_status_command = {
      order       = 10
      title       = "4. The Ingress has an address"
      description = "An empty ADDRESS with a class set points at the controller log; an empty CLASS means no controller claimed it at all"
      value       = module.mcp_server_workload.ingress_status_command
    }
    adoption_check_command = {
      order       = 11
      title       = "5. The ALB was adopted, not duplicated"
      description = "One load balancer is correct. Two means the controller did not adopt the pre-created one and built its own, which is a tag mismatch rather than an error (rules.md G-3)"
      value       = "aws resourcegroupstaggingapi get-resources --tag-filters Key=elbv2.k8s.aws/cluster,Values=${module.eks_cluster.cluster_name} --resource-type-filters elasticloadbalancing:loadbalancer --query 'ResourceTagMappingList[].ResourceARN' --output table"
    }
    status_probe_command = {
      order       = 12
      title       = "6. The endpoint answers"
      description = "mcp-proxy's own health path, which is what the ALB health check uses. The MCP path itself needs a session, so curling /mcp directly is not a useful liveness test"
      value       = "curl -sS -o /dev/null -w '%%{http_code}\\n' ${var.create_custom_domain ? "https://${local.mcp_hostname}" : "http://$(aws elbv2 describe-load-balancers --load-balancer-arns ${module.synced_load_balancer.arn} --query 'LoadBalancers[0].DNSName' --output text)"}/status"
    }
    pod_log_command = {
      order       = 13
      title       = "7. Read the server's log"
      description = "Where an AWS access denied from the MCP server appears. The pod's credentials come from a Pod Identity association, so a failure here reads as a denial from the AWS SDK rather than as a missing role"
      value       = module.mcp_server_workload.pod_log_command
    }
    update_kubeconfig_command = {
      order       = 14
      title       = "Re-point kubectl"
      description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the order field
  # and taking values() sorts by that instead - values() returns a map's values ordered by key -
  # so the README reads in the order the demo is run.
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

# The work happens inside code-server in a browser, where "terraform output" does not exist, so
# every output above is also written to a README in the home directory the IDE opens
# (rules.md H-2). The _monolithic template put its mcp.json snippet in the project README
# instead, where the domain was a CloudFormation placeholder nobody could substitute.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # Waits on the image marker, so the README is written after the build the demo depends on
    # has landed (rules.md D-5).
    #
    # SSM runs as root, hence the chown. The heredoc delimiter is quoted and deliberately
    # unlikely to appear in the body: Terraform has already substituted every value, so the
    # shell has no reason to touch a "$" or a backtick in the README - and the commands in it
    # contain both.
    commands = <<-EOT
      deadline=$(( $(date +%s) + ${var.marker_wait_timeout_seconds} ))
      until [ -f ${module.vscode_ec2.marker_file_path}/image ]; do
        if [ "$(date +%s)" -ge "$deadline" ]; then
          echo "gave up after ${var.marker_wait_timeout_seconds}s waiting for ${module.vscode_ec2.marker_file_path}/image" >&2
          echo "the image wait step never finished, so the build has not pushed ${var.ecr_repository_name}:${var.image_tag}" >&2
          echo "read the build with: aws codebuild batch-get-builds --ids \$(aws codebuild list-builds-for-project --project-name ${var.codebuild_project_name} --max-items 1 --query 'ids' --output text)" >&2
          exit 1
        fi
        sleep 10
      done
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_readme
      EOT
  }

  depends_on = [aws_ssm_association.wait_for_image]
}
