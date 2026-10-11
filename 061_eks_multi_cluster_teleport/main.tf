data "aws_region" "current" {}
locals {
  # One value produces the chart's clusterName, the certificate's subject, both DNS records
  # and the tsh login command. The _monolithic template set clusterName to the bare domain
  # while pointing its records at teleport.<domain>, so the certificate covered a name
  # nothing resolved to and the name that did resolve was only covered by the wildcard
  # (rules.md B-5).
  teleport_host = "${var.teleport_subdomain}.${var.teleport_domain_name}"
}
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
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not exist
  # until this addon creates it. As a DaemonSet it reaches ACTIVE with zero nodes, so it
  # comes before any capacity (rules.md C-4) - and nodes need it to join Ready. It is also
  # what makes target-type ip work, by giving pods addresses the VPC routes (rules.md G-1).
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
  # The node role carries only the four EKS managed policies. The _monolithic template
  # attached three inline policies here as well - DynamoDB, S3 and Route 53 - which handed
  # the ability to read Teleport's audit log, delete session recordings and rewrite the
  # cluster's DNS record to every pod on every node through IMDS. Those permissions are
  # IRSA roles in the cert_manager and teleport_cluster modules now.

  depends_on = [module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.eks_cluster.cluster_name

  # coredns is a Deployment and needs schedulable capacity to leave DEGRADED and become
  # ACTIVE (rules.md C-4). Everything after it needs cluster DNS: cert-manager's webhook is
  # reached by Service name, and Teleport's proxy finds its auth pods the same way.
  depends_on = [
  module.network, module.eks_node_group]
}
# The controller that adopts the pre-created NLB from Teleport's proxy Service. Its IRSA
# role and Helm release are one module, because the release has to annotate the service
# account with the role's ARN (rules.md C-2).
#
# The _monolithic template created this role and its policy and never installed the chart:
# the helm command was in the bastion's userdata, after an "exec bash" line that replaces
# the running shell. So the role existed, nothing used it, and the proxy Service was left
# to the in-tree cloud provider (rules.md E-1/H-1).
module "aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"

  cluster_name      = module.eks_cluster.cluster_name
  vpc_id            = module.network.vpc_id
  aws_region        = data.aws_region.current.region
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  chart_version     = var.aws_load_balancer_controller_chart_version
  # Teleport's proxy Service does not set manage-backend-security-group-rules, so nothing
  # asks the controller to write node-side rules and this can stay false. The path from the
  # load balancer to the proxy pods is declared below instead (rules.md G-2).
  enable_backend_security_group = false
  # Off: the proxy Service names the controller itself with the aws-load-balancer-type
  # annotation, so the webhook has nothing to mutate, and its failurePolicy: Fail would
  # otherwise gate every Service created by cert-manager and Teleport behind a controller
  # pod being Ready (rules.md G-4).
  enable_service_mutator_webhook = var.enable_service_mutator_webhook

  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}
# Standalone rule resources rather than inline blocks, and revoke_rules_on_delete, because
# the controller adds its own rules to this group (rules.md F-2).
module "nlb_security_group" {
  source = "./modules/load_balancer_security_group"

  vpc_id      = module.network.vpc_id
  name        = var.nlb_security_group_name
  description = "Frontend security group for the NLB fronting the Teleport proxy"
  # One port, because proxy listener mode is multiplex: SSH, Kubernetes and web traffic all
  # arrive on the same TLS port and Teleport separates them itself. Read from the same
  # variable the Service publishes, so the listener and the rule cannot disagree
  # (rules.md B-5/G-1).
  ports = {
    https = var.teleport_load_balancer_port
  }
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere

  depends_on = [module.network]
}
# Created here and adopted by the controller rather than left for the controller to create.
# Two reasons, and the second is what makes this project different from the _monolithic
# template: its DNS name and hosted zone ID are known from state, so the Route 53 records
# below can be Terraform resources instead of a shell script's change-batch. It is also the
# only way this NLB can carry a security group at all, since AWS refuses to add security
# groups to a network load balancer after creation (rules.md G-3).
module "synced_nlb" {
  source = "./modules/synced_load_balancer"

  cluster_name       = module.eks_cluster.cluster_name
  name               = var.synced_nlb_name
  load_balancer_type = "network"
  internal           = false
  # internet-facing, so public subnets - this has to agree with the scheme the proxy Service
  # annotates, or the controller builds a second load balancer instead of adopting this one
  # (rules.md G-3).
  subnet_ids         = module.network.public_subnet_ids
  security_group_ids = [module.nlb_security_group.security_group_id]
  # service.k8s.aws/*, not ingress.k8s.aws/*: this load balancer is provisioned from a
  # Service of type LoadBalancer. The wrong prefix is not an error - the controller simply
  # does not adopt, and builds its own (rules.md G-3).
  resource_tag_prefix = "service"
  # Taken from the workload module rather than restating "<namespace>/<release>", so the tag
  # cannot drift from the Service the controller is reconciling (rules.md B-5).
  stack = module.teleport_cluster.service_stack_tag

  depends_on = [module.network]
}
# cert-manager, and the one issuer Teleport's certificate is requested from.
#
# Its IRSA role is scoped to the single hosted zone below. The _monolithic template put the
# same Route 53 permissions on the node instance role and started the controller with
# --issuer-ambient-credentials, which together let any pod on the cluster - and any Issuer
# in any namespace - rewrite records in that zone.
module "cert_manager" {
  source = "./modules/cert_manager"

  chart_version          = var.cert_manager_chart_version
  oidc_provider_arn      = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host       = module.eks_cluster.oidc_issuer_host
  route53_hosted_zone_id = var.teleport_route53_hosted_zone_id
  issuer_email           = var.teleport_issuer_email
  acme_server            = var.acme_server
  # The zone the solver is selected for, which has to be a suffix of the certificate's own
  # names or no solver matches and the Certificate sits Pending with nothing on it to say
  # why.
  dns_zone   = var.teleport_domain_name
  aws_region = data.aws_region.current.region

  # The release waits for its own webhook to be serving, which needs schedulable capacity
  # and working cluster DNS (rules.md D-2).
  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}
module "teleport_cluster" {
  source = "./modules/teleport_cluster"

  cluster_host = local.teleport_host
  # What a user sees in "tsh kube ls". The EKS cluster's own name, so the two views of the
  # same cluster agree.
  kube_cluster_name            = module.eks_cluster.cluster_name
  chart_version                = var.teleport_chart_version
  aws_region                   = data.aws_region.current.region
  backend_table                = var.teleport_backend_table
  audit_log_table              = var.teleport_audit_log_table
  session_recording_bucket     = module.teleport_session_bucket.bucket
  session_recording_bucket_arn = module.teleport_session_bucket.bucket_arn
  oidc_provider_arn            = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host             = module.eks_cluster.oidc_issuer_host
  replica_count                = var.teleport_replica_count
  # Both taken from the cert_manager module rather than restated, so the chart cannot
  # reference an issuer that does not exist or get its kind wrong - either leaves the
  # Certificate Pending and the proxy never ready (rules.md B-5).
  issuer_name                 = module.cert_manager.issuer_name
  issuer_kind                 = module.cert_manager.issuer_kind
  load_balancer_port          = var.teleport_load_balancer_port
  proxy_target_port           = var.teleport_proxy_target_port
  scheme                      = "internet-facing"
  nlb_target_type             = "ip"
  frontend_security_group_ids = [module.nlb_security_group.security_group_id]
  # What a Teleport user can do once inside the cluster. The module binds a group to this
  # ClusterRole and puts the same group in the add-user command; a user without that group
  # can log in to Teleport and list the cluster, and is then refused by every kubectl call.
  kubernetes_cluster_role = var.teleport_kubernetes_cluster_role

  # cert_manager because the chart creates a Certificate, and that object cannot exist
  # before the CRD and the issuer do. The controller because the proxy Service needs
  # something to reconcile it, and the nodes and CoreDNS because the release waits for
  # readiness (rules.md D-2).
  #
  # Deliberately not module.synced_nlb, which would be a cycle: that load balancer's
  # adoption tag comes from this module's output. The ordering still holds in the direction
  # that matters, because the load balancer has no dependency on Teleport and is created as
  # soon as the network exists - well before the controller reconciles this Service.
  depends_on = [
    module.network,
    module.eks_node_group,
    module.eks_coredns_addon,
    module.aws_load_balancer_controller,
    module.cert_manager,
  ]
}
module "teleport_session_bucket" {
  source = "./modules/teleport_session_bucket"

  name                               = var.session_bucket_name
  noncurrent_version_expiration_days = var.session_recording_retention_days

  # No network dependency: an S3 bucket is a regional resource with nothing in the VPC, so
  # it is one of the few things here that genuinely does not need
  # depends_on = [module.network] (rules.md D-3).

  # module.network's value references only order this after the specific aws_subnet or
  # aws_vpc that produced them, not after the NAT gateway and route tables the network
  # module also owns. depends_on states "after the whole network" (rules.md D-3).
  depends_on = [module.network]
}
# The two records that make the cluster reachable by name.
#
# Terraform resources, where the _monolithic template built a change-batch document with jq
# in a shell script and posted it with the AWS CLI. That script could not have worked: it
# read the load balancer's address from "service/teleport-proxy", and the chart names that
# Service after the release - so the lookup returned NotFound and every line after it was
# skipped. Doing it here needs no lookup at all, because Terraform created the load balancer
# (rules.md G-3).
#
# for_each over a map with literal keys, so the addresses are the only unknown part
# (rules.md B-8).
resource "aws_route53_record" "teleport" {
  for_each = var.create_dns_records ? {
    # The proxy's own name, which is what tsh and a browser connect to.
    host = local.teleport_host
    # Teleport addresses applications and Kubernetes clusters as subdomains of its own
    # host, so the wildcard is not decoration - it is how "tsh kube login" and application
    # access resolve. It is also why the certificate needs a DNS-01 challenge: Let's
    # Encrypt only issues a wildcard against one.
    wildcard = "*.${local.teleport_host}"
  } : {}

  zone_id = var.teleport_route53_hosted_zone_id
  name    = each.value
  type    = "A"

  alias {
    name    = module.synced_nlb.dns_name
    zone_id = module.synced_nlb.zone_id
    # False because health is the load balancer's business, not Route 53's. With one record
    # per name there is nothing to fail over to, and an alias that evaluates target health
    # answers NXDOMAIN while the targets are unhealthy - which during a rollout means the
    # name disappears rather than returning an error.
    evaluate_target_health = false
  }
}
# With manage-backend-security-group-rules unset the controller writes no node-side rules at
# all, so the path from the load balancer to the proxy pods has to be declared here or every
# target stays unhealthy with no error anywhere (rules.md G-2). target-type is ip, so traffic
# arrives at the pod's own port rather than the Service port.
#
# It modifies the cluster security group, which no module here owns outright, so it belongs
# in the root (rules.md C-1).
resource "aws_vpc_security_group_ingress_rule" "nlb_to_proxy_pods" {
  security_group_id            = module.eks_cluster.cluster_security_group_id
  description                  = "Teleport proxy port from the NLB frontend security group"
  ip_protocol                  = "tcp"
  from_port                    = var.teleport_proxy_target_port
  to_port                      = var.teleport_proxy_target_port
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
  # cluster and carries all five tools, plus tsh - which is how the demo is actually
  # exercised (rules.md H-1). None of them creates anything: cert-manager, Teleport and the
  # DNS records the _monolithic template installed from here are Terraform resources now
  # (rules.md E-1).
  #
  # The one thing that template did here which cannot be a resource is create the first
  # Teleport user - its association ran "tctl users add test" as its last line. That is not
  # done from this instance at all any more. The operator runs add_user_command from the
  # terminal that ran terraform apply, so the invite link it prints never appears in this
  # IDE, whose code-server has no login of its own (see local.outputs below).
  #
  # Two bugs from that template are fixed here rather than carried over. It ran "exec bash"
  # partway through, which replaces the shell and silently discarded every remaining line -
  # update-kubeconfig, eksctl, helm and the load balancer controller install were all after
  # it. And it pulled eksctl from weaveworks; eksctl-io is the project's own org.
  additional_user_data = <<-EOT
    dnf install -yq docker jq
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
    # tsh, the Teleport client, at the same version as the cluster. A client more than one
    # major version from the proxy is refused, so this tracks the chart version rather
    # than fetching whatever is current.
    curl -sLO https://cdn.teleport.dev/teleport-v${var.teleport_chart_version}-linux-amd64-bin.tar.gz
    tar -xzf teleport-v${var.teleport_chart_version}-linux-amd64-bin.tar.gz -C /tmp
    sudo install -m 0755 /tmp/teleport/tsh /usr/local/bin/tsh
    rm -rf /tmp/teleport teleport-v${var.teleport_chart_version}-linux-amd64-bin.tar.gz
    aws configure set default.region ${data.aws_region.current.region}
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}
    EOF
  EOT

  depends_on = [module.network]
}
# Granting the bastion's instance role cluster access joins two modules that know nothing
# about each other, so it belongs in the root (rules.md C-1).
#
# Worth noting what this is for: it is how the bastion administers the cluster directly,
# which is the access path Teleport exists to replace. A user who logs in through Teleport
# needs neither an access entry nor an IAM principal here.
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
  # Points a terminal's kubectl at this cluster, as whatever AWS identity that terminal
  # holds. Used on its own as the IDE's bypass below, and in front of each command the
  # operator runs from the terminal that ran terraform apply. That terminal's kubectl is not
  # set up by the apply: the helm and kubectl providers carry their own host, CA and exec
  # settings and write no kubeconfig. Defined once so the two uses cannot name different
  # clusters or regions (rules.md B-5).
  update_kubeconfig_command = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
  # Every output this project exposes, defined once. outputs.tf projects these and the
  # README below renders them, so no value expression is written twice (rules.md B-5/H-2).
  # Adding an entry here is what makes an output possible, which is what keeps the README
  # from falling behind outputs.tf.
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here. The commands below are meant to be run from its terminal, which has kubectl, helm and tsh - except the three that create or change the Teleport account (step 1 and the last two sections), which belong to the operator's terminal, the one that ran terraform apply"
      value       = module.vscode_ec2.vscode_url
    }
    cluster_name = {
      order       = 2
      title       = "EKS cluster name"
      description = "Name of the EKS cluster, and the name it is registered under inside Teleport"
      value       = module.eks_cluster.cluster_name
    }
    cluster_endpoint = {
      order       = 3
      title       = "EKS cluster endpoint"
      description = "API server endpoint. This is the access path Teleport exists to replace: a user who authenticates through Teleport reaches the cluster without an IAM principal or an EKS access entry of their own"
      value       = module.eks_cluster.cluster_endpoint
    }
    teleport_url = {
      order       = 4
      title       = "Teleport web UI"
      description = "The front door. Answers once the DNS records point at the load balancer and cert-manager has issued the certificate - the first request after an apply can be a minute or two early"
      value       = module.teleport_cluster.web_url
    }
    teleport_version = {
      order       = 5
      title       = "Teleport version"
      description = "Chart version, which is also the Teleport version and the version its DynamoDB state format belongs to. Pinned, unlike the _monolithic template, which installed whatever the repository served that day"
      value       = module.teleport_cluster.chart_version
    }
    session_bucket = {
      order       = 6
      title       = "Session recording bucket"
      description = "Where keystroke-level recordings of every session are written. Versioned, encrypted and closed to public access here; the _monolithic template declared the bucket with an empty body and granted Teleport the permissions to configure it after the fact"
      value       = module.teleport_session_bucket.bucket
    }
    state_tables = {
      order       = 7
      title       = "DynamoDB tables"
      description = "Cluster state and the audit log. Created by Teleport rather than by Terraform - their schema and indexes belong to it and change between versions - which is why the IRSA policy grants dynamodb:CreateTable. That action was missing from the _monolithic template, so its auth pod failed on its first backend write"
      value       = "${var.teleport_backend_table}, ${var.teleport_audit_log_table}"
    }
    add_user_command = {
      order       = 8
      title       = "1. Create the first user - from the terminal that ran terraform apply"
      description = "Run it there, with the same AWS credentials, rather than in this IDE. Those credentials are the principal EKS made a cluster admin when it created the cluster - the one the helm and kubectl providers installed Teleport as - so they can exec into the auth pod with nothing else granted. The update-kubeconfig in front points that terminal's kubectl at this cluster, and also makes it the current context there. It prints a single-use invite link, valid for an hour, and whoever opens it first sets the password for an account with Teleport's access and editor roles and ${module.teleport_cluster.kubernetes_cluster_role} in this cluster - the last through --kubernetes-groups, which the preset access role takes its Kubernetes groups from. So the link belongs on the operator's screen, to be handed to whoever will sign in: code-server here has no login, and a link printed in this IDE's terminal can be read by anyone who reaches its URL. Deliberately a command rather than something the apply runs: an invite produced during an apply has usually expired by the time anyone reads it, and a Terraform output would write the credential to state. If tctl answers that the user already exists, see \"Issue a new invite link for an existing user\" at the end"
      value       = "${local.update_kubeconfig_command} && ${module.teleport_cluster.add_user_command}"
    }
    kube_login_command = {
      order       = 9
      title       = "2. Reach the cluster through Teleport"
      description = "The point of the project, and where this IDE comes in. Once the invite link from step 1 has been used, authenticate to Teleport as that account, list the Kubernetes clusters it knows about, and get a kubeconfig for one - with no IAM credential and no access entry for the person doing it. --user names the account; without it tsh signs in as ec2-user, the local login here. If kubectl then answers \"Your user's Teleport role does not allow Kubernetes access\", the user was created without a Kubernetes group; see \"Grant Kubernetes access to an existing user\" at the end"
      value       = module.teleport_cluster.kube_login_command
    }
    teleport_status_command = {
      order       = 10
      title       = "3. Ask Teleport about itself"
      description = "Cluster name, version and CA fingerprints, read from the auth pod. Reaching this at all proves the DynamoDB backend is readable, which is the first thing to check if the proxy is unhealthy"
      value       = module.teleport_cluster.status_command
    }
    certificate_command = {
      order       = 11
      title       = "4. Check the certificate"
      description = "Ready=False here is the usual reason the proxy never becomes ready. The reason itself is one level down, in the Challenge object - see the issuance chain command below"
      value       = module.teleport_cluster.certificate_command
    }
    issuance_chain_command = {
      order       = 12
      title       = "5. Follow the issuance chain"
      description = "cert-manager creates a Certificate, then a CertificateRequest, then an Order, then a Challenge. The last object present is where it stopped: a Challenge stuck Pending means the DNS-01 record could not be written, or has not propagated yet"
      value       = module.cert_manager.certificate_status_command
    }
    adopted_load_balancer_check_command = {
      order       = 13
      title       = "6. Confirm the load balancer was adopted, not duplicated"
      description = "Lists every load balancer tagged for this cluster. One is correct. Two means the controller did not adopt the pre-created one and built its own, which is a tag mismatch rather than an error - and the DNS records would then point at an empty load balancer (rules.md G-3)"
      value       = "aws resourcegroupstaggingapi get-resources --tag-filters Key=elbv2.k8s.aws/cluster,Values=${module.eks_cluster.cluster_name} --resource-type-filters elasticloadbalancing:loadbalancer --query 'ResourceTagMappingList[].ResourceARN' --output table"
    }
    proxy_hostname_command = {
      order       = 14
      title       = "7. Read the address the controller attached"
      description = "Compare it against the DNS records below. The Service is named after the release - the _monolithic template's script looked for service/teleport-proxy, which the chart does not create, and so skipped everything after that line"
      value       = module.teleport_cluster.load_balancer_hostname_command
    }
    dns_records = {
      order       = 15
      title       = "8. The DNS records"
      description = "Both point at the pre-created load balancer. The wildcard is not decoration: Teleport addresses Kubernetes clusters and applications as subdomains of its own host, which is also why the certificate needs a DNS-01 challenge - Let's Encrypt only issues wildcards against one"
      value       = var.create_dns_records ? join(", ", [for r in aws_route53_record.teleport : r.fqdn]) : "create_dns_records is false; nothing resolves to the proxy"
    }
    recording_list_command = {
      order       = 16
      title       = "9. Confirm sessions are being recorded"
      description = "Run it after joining a session through Teleport. Empty means recordings are going somewhere else, usually because the bucket value never reached the chart"
      value       = module.teleport_session_bucket.recording_list_command
    }
    update_kubeconfig_command = {
      order       = 17
      title       = "Re-point kubectl directly"
      description = "The bypass, for when Teleport itself is what is broken. User data already ran this, so kubectl on the instance works out of the box"
      value       = local.update_kubeconfig_command
    }
    grant_kubernetes_access_command = {
      order       = 18
      title       = "Grant Kubernetes access to an existing user - from the terminal that ran terraform apply"
      description = "Run it where step 1 runs, as the same operator: changing what the account may do is done with the cluster creator's credentials, like creating it, rather than from this IDE. For a user created without --kubernetes-groups, which Teleport lets log in and then refuses on every kubectl call. Sets the user's Kubernetes group to ${module.teleport_cluster.kubernetes_group}, the one bound to ${module.teleport_cluster.kubernetes_cluster_role}. The user then has to sign in again - tsh logout, then the login command in step 2 - because traits are copied into the certificate at login and the current one does not have it"
      value       = "${local.update_kubeconfig_command} && ${module.teleport_cluster.grant_kubernetes_access_command}"
    }
    reset_user_command = {
      order       = 19
      title       = "Issue a new invite link for an existing user - from the terminal that ran terraform apply"
      description = "For when step 1 answers that the user already exists. Either its link expired unused, or the account outlived an earlier deployment: the DynamoDB tables are created by Teleport rather than by Terraform, so terraform destroy leaves them - users included - and the next apply's Teleport reads them again. Run it where step 1 runs, for the same reason, since it prints the same kind of link, valid for eight hours this time. It discards the account's password and second factor devices and keeps its roles and Kubernetes group"
      value       = "${local.update_kubeconfig_command} && ${module.teleport_cluster.reset_user_command}"
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
