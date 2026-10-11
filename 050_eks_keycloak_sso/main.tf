data "aws_region" "current" {}
# The zone has to already exist - this project cannot work without real DNS, because the ACM
# certificate is validated through it and the ALB is reached by name rather than by its own hostname.
data "aws_route53_zone" "zone" {
  name         = var.hosted_zone_name
  private_zone = false
}
locals {
  # The host used in three places that have to agree: the ACM certificate's domain name, the
  # Ingress rule's host, and the Route 53 record pointing at the load balancer. Derived once here so
  # they cannot drift (rules.md B-5). A certificate for one name and an Ingress matching another is
  # not an error - the browser just gets a certificate warning or a 404, depending which one is wrong.
  keycloak_hostname = "${var.keycloak_subdomain}.${trimsuffix(var.hosted_zone_name, ".")}"
  # The stack tag the pre-created ALB must carry to be adopted rather than duplicated (rules.md G-3).
  #
  # Derived here rather than read from the keycloak module's output: the load balancer needs this
  # value before that module runs, and reading it from the module would make the load balancer
  # depend on the workload while the workload has to wait for the load balancer. Both sides read the
  # same variables, so there is still one definition (rules.md B-5).
  keycloak_stack_tag = "${var.keycloak_namespace}/${var.keycloak_ingress_name}"
}
module "network" {
  source = "./modules/network"

  public_subnet_tags  = var.public_subnet_tags
  private_subnet_tags = var.private_subnet_tags
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
  # behind those outputs, not after the NAT gateways and route table associations that never surface
  # as outputs (rules.md D-3).
  depends_on = [module.network]
}
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not exist until this
  # addon creates it. As a DaemonSet it reaches ACTIVE with zero nodes, so it comes before any
  # capacity (rules.md C-4) - and nodes need it to join Ready. It is also what makes target-type ip
  # work, by putting pod addresses in the VPC (rules.md G-1).
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

  # coredns is a Deployment and needs schedulable capacity to leave DEGRADED and become ACTIVE
  # (rules.md C-4). Keycloak also reaches its database by Service DNS name and its cache peers by
  # the headless Service, so neither works until this is up.
  depends_on = [
  module.network, module.eks_node_group]
}
# The controller that turns Keycloak's Ingress into the ALB. Its IRSA role and Helm release are one
# module, because the release has to annotate the service account with the role's ARN
# (rules.md C-2). The _monolithic template declared the role and installed the controller from a
# helm command in userdata (rules.md E-1).
module "aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"

  cluster_name      = module.eks_cluster.cluster_name
  vpc_id            = module.network.vpc_id
  aws_region        = data.aws_region.current.region
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  chart_version     = var.aws_load_balancer_controller_chart_version
  # The Ingress sets its own frontend security group but does not set
  # manage-backend-security-group-rules, so nothing asks the controller to write node-side rules and
  # this can stay false. The path from the load balancer to the pods is declared below instead
  # (rules.md G-2).
  enable_backend_security_group = false
  # Off: no Service here is of type LoadBalancer, so the webhook has nothing to mutate, and its
  # failurePolicy: Fail would gate every Service creation in the cluster behind a controller pod
  # being Ready (rules.md G-4).
  enable_service_mutator_webhook = var.enable_service_mutator_webhook

  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}
# The certificate, its DNS validation records and the wait for ACM to issue it. The _monolithic
# template created the certificate and never validated it, so the https URL it advertised could not
# have worked - see the module for the detail.
module "acm_certificate" {
  source = "./modules/acm_certificate"

  domain_name = local.keycloak_hostname
  zone_id     = data.aws_route53_zone.zone.zone_id

  # module.network's value references only order this after the specific aws_subnet or
  # aws_vpc that produced them, not after the NAT gateway and route tables the network
  # module also owns. depends_on states "after the whole network" (rules.md D-3).
  depends_on = [module.network]
}
# Standalone rule resources rather than inline blocks, and revoke_rules_on_delete, because the
# controller adds its own rules to this group (rules.md F-2). The _monolithic template built the ALB
# with the VPC's default security group while its Ingress annotation asked for a separate "alb-sg" -
# so the two disagreed about which group the load balancer had.
module "alb_security_group" {
  source = "./modules/load_balancer_security_group"

  vpc_id      = module.network.vpc_id
  name        = var.alb_security_group_name
  description = "Frontend security group for the ALB fronting the Keycloak console"
  # Only 443. The ALB terminates TLS with the ACM certificate and the Ingress redirects http to it,
  # so http never has to be reachable from outside (rules.md G-1).
  ports = {
    https = var.load_balancer_port
  }
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere

  depends_on = [module.network]
}
# Created here and adopted by the controller rather than left for the controller to create. Here it
# matters twice over: the DNS name is needed at apply time for the Route 53 alias record below, and
# an ALB the controller created is not a Terraform resource to point a record at (rules.md G-3).
module "synced_load_balancer" {
  source = "./modules/synced_load_balancer"

  cluster_name       = module.eks_cluster.cluster_name
  name               = var.synced_load_balancer_name
  load_balancer_type = "application"
  internal           = false
  # internet-facing, so public subnets - this has to agree with the scheme the Ingress annotates, or
  # the controller builds a second load balancer instead of adopting this one (rules.md G-3).
  subnet_ids         = module.network.public_subnet_ids
  security_group_ids = [module.alb_security_group.security_group_id]
  # ingress.k8s.aws/*, not service.k8s.aws/*: this load balancer fronts an Ingress. The wrong prefix
  # is not an error - the controller simply does not adopt, and builds its own (rules.md G-3).
  resource_tag_prefix = "ingress"
  stack               = local.keycloak_stack_tag

  depends_on = [module.network]
}
# The name users actually visit. An alias record rather than a CNAME so the zone apex would also work,
# and because an alias to an ALB costs nothing to resolve.
#
# It joins the hosted zone data source with the load balancer module, neither of which knows about
# the other, so it belongs in the root (rules.md C-1).
resource "aws_route53_record" "keycloak" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = local.keycloak_hostname
  type    = "A"

  alias {
    name    = module.synced_load_balancer.dns_name
    zone_id = module.synced_load_balancer.zone_id
    # The ALB's own target health is not a useful signal here: it is healthy as soon as it exists,
    # long before Keycloak's startup probe finishes, and evaluating it would only add a failure mode.
    evaluate_target_health = false
  }
}
module "keycloak" {
  source = "./modules/keycloak"

  hostname          = local.keycloak_hostname
  namespace         = var.keycloak_namespace
  ingress_name      = var.keycloak_ingress_name
  admin_username    = var.keycloak_admin_username
  admin_password    = var.keycloak_admin_password
  database_password = var.keycloak_database_password
  keycloak_image    = var.keycloak_image
  replicas          = var.keycloak_replicas
  ingress_annotations = {
    "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
    "alb.ingress.kubernetes.io/target-type" = "ip"
    # The frontend group this project owns. Naming it here is what makes the controller keep it on
    # the load balancer (rules.md G-3).
    "alb.ingress.kubernetes.io/security-groups" = module.alb_security_group.security_group_id
    # Redirects http to https at the load balancer, so the security group only has to open 443.
    "alb.ingress.kubernetes.io/ssl-redirect" = tostring(var.load_balancer_port)
    # The validated ARN, taken from the validation resource rather than the certificate - which is
    # what orders this Ingress after ACM has actually issued it (rules.md D-1).
    "alb.ingress.kubernetes.io/certificate-arn" = module.acm_certificate.certificate_arn
  }

  # The ALB has to exist before the controller reconciles this Ingress, or the controller creates its
  # own and the pre-created one is orphaned (rules.md G-3). The controller has to be running at all,
  # otherwise nothing reconciles the Ingress and it never gets an address (rules.md G-1).
  #
  # Ordering the module after the node group also makes terraform destroy remove these manifests
  # while the nodes and the controller are still there, so the load balancer is cleaned up rather
  # than orphaned (rules.md D-4).
  depends_on = [
    module.network,
    module.synced_load_balancer,
    module.aws_load_balancer_controller,
    module.eks_node_group,
    module.eks_coredns_addon,
  ]
}
# With manage-backend-security-group-rules unset the controller writes no node-side rules at all, so
# the path from load balancer to pod has to be declared here or every target stays unhealthy with no
# error anywhere (rules.md G-2). target-type is ip, so traffic arrives at Keycloak's container port -
# not the Service port, and not 443 - and pods on this cluster use the cluster security group.
#
# It modifies the cluster security group, which no module here owns outright, so it belongs in the
# root (rules.md C-1).
resource "aws_vpc_security_group_ingress_rule" "load_balancer_to_pods" {
  security_group_id            = module.eks_cluster.cluster_security_group_id
  description                  = "Keycloak container port from the ALB frontend security group"
  ip_protocol                  = "tcp"
  from_port                    = module.keycloak.container_port
  to_port                      = module.keycloak.container_port
  referenced_security_group_id = module.alb_security_group.security_group_id
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
  # carries all five tools (rules.md H-1). None of them creates anything: the chart and the manifests
  # the _monolithic template installed from here are Terraform resources now (rules.md E-1).
  #
  # Two bugs from that template are fixed here rather than carried over. It ran "exec bash" partway
  # through, which replaces the shell and silently discarded every remaining line - update-kubeconfig,
  # eksctl and helm were all after it, so none of them ever ran. And it pulled eksctl from weaveworks;
  # eksctl-io is the project's own org (rules.md H-1).
  additional_user_data = <<-EOT
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server is already running and predates the docker group, so its terminals would not have
    # it without a restart.
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
  # renders them, so no value expression is written twice (rules.md B-5/H-2). Adding an entry here is
  # what makes an output possible, which is what keeps the README from falling behind outputs.tf.
  #
  # Neither password is here. The _monolithic template published USERNAME="admin", PASSWORD="admin"
  # as an output, which also wrote it into the instance README that an unauthenticated code-server
  # serves - a working administrator login for an internet-facing console (rules.md H-2).
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
    keycloak_url = {
      order       = 3
      title       = "Keycloak console"
      description = "https, terminated at the ALB with a validated ACM certificate. The _monolithic template created that certificate and never validated it, so this URL could not have served a usable certificate. Keycloak's startup probe allows ten minutes, so give it time after the apply returns"
      value       = module.keycloak.url
    }
    keycloak_admin_username = {
      order       = 4
      title       = "Keycloak admin login"
      description = "The login name only. The password is deliberately not here: this text is written into a README served by a code-server with no authentication, and the console above is internet-facing (rules.md H-2). It is the value passed in as keycloak_admin_password"
      value       = module.keycloak.admin_username
    }
    certificate_status = {
      order       = 5
      title       = "Certificate"
      description = "ISSUED means ACM saw the validation records this project created in the hosted zone. PENDING_VALIDATION after a successful apply would mean those records went into a zone nothing resolves - the usual cause is a hosted zone that is not the one actually serving the domain"
      value       = "${module.acm_certificate.domain_name} (${module.acm_certificate.status})"
    }
    keycloak_rollout_command = {
      order       = 6
      title       = "1. Confirm Keycloak finished starting"
      description = "This is the thing to watch rather than reloading the URL. The startup probe allows ten minutes, and Keycloak restarts until its database answers"
      value       = module.keycloak.rollout_command
    }
    keycloak_pods_command = {
      order       = 7
      title       = "2. Look at the pods if it stalls"
      description = "Keycloak and PostgreSQL. A replica stuck Pending means the node group could not fit it - each Keycloak pod requests 1700Mi, which is why this project uses t3.large rather than t3.medium"
      value       = module.keycloak.pods_command
    }
    keycloak_ingress_command = {
      order       = 8
      title       = "3. Check the Ingress got an address"
      description = "An empty ADDRESS means the controller is not reconciling it, which is normally a class mismatch. An address that is not the pre-created ALB means adoption failed"
      value       = module.keycloak.ingress_command
    }
    adopted_load_balancer_check_command = {
      order       = 9
      title       = "4. Confirm the load balancer was adopted, not duplicated"
      description = "Lists every load balancer tagged for this cluster. One is correct. Two means the controller did not adopt the pre-created one and built its own, which is a tag mismatch rather than an error (rules.md G-3)"
      value       = "aws resourcegroupstaggingapi get-resources --tag-filters Key=elbv2.k8s.aws/cluster,Values=${module.eks_cluster.cluster_name} --resource-type-filters elasticloadbalancing:loadbalancer --query 'ResourceTagMappingList[].ResourceARN' --output table"
    }
    certificate_status_command = {
      order       = 10
      title       = "5. Check the certificate if https fails"
      description = "Shows the certificate's status and each name's validation state. A browser warning with everything else healthy points here"
      value       = module.acm_certificate.status_command
    }
    keycloak_logs_command = {
      order       = 11
      title       = "6. Read Keycloak's log"
      description = "Where a database it cannot reach, or proxy headers it does not trust, explains itself. Redirects that land on http or the wrong host are the KC_PROXY_HEADERS setting rather than the load balancer"
      value       = module.keycloak.logs_command
    }
    update_kubeconfig_command = {
      order       = 12
      title       = "Re-point kubectl"
      description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the order field and
  # taking values() - which returns a map's values ordered by key - makes the README read top to
  # bottom while the order stays decided by configuration.
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
# Combining several modules' outputs is the root's job, so this lives here rather than inside the
# instance module.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is what orders this after
    # the bootstrap (rules.md D-5). The marker path comes back out of the module it was passed into,
    # so it is defined once (rules.md B-5).
    #
    # SSM runs as root, hence the chown. The heredoc delimiter is quoted and unlikely to appear in
    # the body: Terraform has already substituted every value, so the shell has no reason to touch a
    # "$" or a backtick.
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
