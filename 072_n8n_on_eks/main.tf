data "aws_region" "current" {}
module "network" {
  source = "./modules/network"

  vpc_name                 = "${var.cluster_name}-vpc"
  internet_gateway_name    = "${var.cluster_name}-igw"
  public_subnet_name       = "${var.cluster_name}-public"
  private_subnet_name      = "${var.cluster_name}-private"
  public_route_table_name  = "${var.cluster_name}-public-rt"
  private_route_table_name = "${var.cluster_name}-private-rt"
  nat_gateway_name         = "${var.cluster_name}-natgw"
  # The tags the AWS Load Balancer Controller discovers subnets by (rules.md G-1).
  public_subnet_tags  = var.public_subnet_tags
  private_subnet_tags = var.private_subnet_tags

  # A NAT gateway per zone, where the _monolithic template had one shared between both private
  # subnets - and allocated a second Elastic IP for a second gateway it never created, which sat
  # unassociated and billed. Per-zone egress costs the second gateway on purpose; the stray
  # address is simply gone.
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

  # Referencing module.network.*_subnet_ids only orders this after the specific aws_subnet
  # resources behind those outputs, not after the NAT gateways and route table associations that
  # never surface as outputs (rules.md D-3).
  depends_on = [module.network]
}
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name
  # Left at the addon's defaults. The _monolithic template set ENABLE_MULTI_NIC: "true" here,
  # which belongs to the projects about pods with several network interfaces and does nothing for
  # n8n - it was carried over from a sibling template along with the update-kubeconfig alias
  # "nvidia" in the user data (rules.md E-5).

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not exist until this
  # addon creates it. As a DaemonSet it reaches ACTIVE with zero nodes, so it comes before any
  # capacity - and nodes need it to join Ready (rules.md C-4). It is also what makes
  # nlb-target-type ip work, by making pod addresses routable in the VPC (rules.md G-1).
  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as eks_vpc_cni_addon (rules.md C-4).
  depends_on = [module.network, module.eks_vpc_cni_addon]
}
# The agent behind the EBS CSI driver's Pod Identity association, as the _monolithic template had
# it. A DaemonSet, so it reaches ACTIVE with no nodes (rules.md C-4).
module "eks_pod_identity_agent_addon" {
  source = "./modules/eks_pod_identity_agent_addon"

  cluster_name = module.eks_cluster.cluster_name

  depends_on = [module.network, module.eks_cluster]
}
module "eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name    = module.eks_cluster.cluster_name
  node_group_name = "core-nodegroup"
  instance_types  = var.node_group_instance_types
  desired_size    = var.node_group_desired_size
  min_size        = var.node_group_min_size
  max_size        = var.node_group_max_size
  subnet_ids      = module.network.private_subnet_ids
  key_name        = module.key_pair.key_name

  # Nodes need vpc-cni and kube-proxy running to join the cluster Ready (rules.md C-4).
  depends_on = [module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.eks_cluster.cluster_name

  # coredns is a Deployment and needs schedulable capacity to leave DEGRADED and become ACTIVE
  # (rules.md C-4). n8n reaches Postgres by Service name, so nothing works before this is up.
  depends_on = [
  module.network, module.eks_node_group]
}
# What answers the two PersistentVolumeClaims. Without it both stay Pending, neither pod is ever
# scheduled, and the Service has no endpoints - which from the load balancer's side looks like the
# controller failing rather than storage failing.
module "eks_ebs_csi_driver_addon" {
  source = "./modules/eks_ebs_csi_driver_addon"

  cluster_name = module.eks_cluster.cluster_name

  # The controller half of this addon is a Deployment, so it needs node capacity to leave
  # DEGRADED - and the Pod Identity agent has to be running before its credentials work
  # (rules.md C-4/D-2).
  depends_on = [
  module.network, module.eks_node_group, module.eks_pod_identity_agent_addon]
}
module "csi_storage_classes" {
  source = "./modules/csi_storage_classes"

  storage_class_name = var.storage_class_name
  # No snapshot-controller addon here, so no VolumeSnapshotClass - its kind would not exist and
  # the manifest would fail at apply after a clean plan (rules.md B-4).
  create_volume_snapshot_class = false

  # kubectl_manifest resources against the cluster's API server, so ordering the module after the
  # nodes is what makes terraform destroy remove them while there is still a controller to process
  # the deletion (rules.md D-4).
  depends_on = [
  module.network, module.eks_node_group, module.eks_ebs_csi_driver_addon]
}
# What turns n8n's Service into an NLB. Its IRSA role and Helm release are one module
# (rules.md C-2).
module "aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"

  cluster_name      = module.eks_cluster.cluster_name
  vpc_id            = module.network.vpc_id
  aws_region        = data.aws_region.current.region
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  chart_version     = var.aws_load_balancer_controller_chart_version
  # False, and the n8n Service deliberately does not set manage-backend-security-group-rules. The
  # _monolithic template set that annotation to "true" while leaving this at the controller's
  # default - the one combination that works - and this is the other one: the path from the load
  # balancer to the pod is a declared rule below, visible in plan (rules.md G-2).
  enable_backend_security_group = false
  # Off: the one Service of type LoadBalancer here names the controller itself with
  # aws-load-balancer-type, so the webhook has nothing to mutate, and its failurePolicy: Fail
  # would otherwise gate every Service creation in the cluster behind a controller pod being
  # Ready (rules.md G-4).
  enable_service_mutator_webhook = var.enable_service_mutator_webhook

  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}
locals {
  # The stack tag the pre-created load balancer must carry to be adopted rather than duplicated
  # (rules.md G-3). For an Ingress it is <namespace>/<ingress name>, and the n8n module names its
  # Ingress after the workload - so these are the same two values.
  #
  # Derived here rather than read from the n8n module's output: the load balancer needs the tag
  # before that module runs, and the n8n module needs the load balancer's address - so taking the
  # tag from the module would make the two depend on each other. Both sides read the same two
  # variables, and the module re-exposes what it used as ingress_stack_tag so a mismatch shows up
  # in terraform output (rules.md B-5).
  n8n_stack_tag = "${var.n8n_namespace}/${var.n8n_name}"
}
# Standalone rule resources rather than inline blocks, and revoke_rules_on_delete, because the
# controller may add its own rules to this group (rules.md F-2).
module "load_balancer_security_group" {
  source = "./modules/load_balancer_security_group"

  vpc_id      = module.network.vpc_id
  name        = var.load_balancer_security_group_name
  description = "Frontend security group for the ALB fronting the n8n editor"
  # The listener port, which with an ALB is not n8n's port: the Ingress asks for a plain http
  # listener on 80 and the load balancer forwards to the pods on n8n's container port. Opening
  # n8n's port here instead is the mistake that leaves a working load balancer nobody can reach -
  # which is what this project did while advertising an address with no port in it (rules.md G-1).
  ports = {
    http = var.ingress_listen_port
  }
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere

  depends_on = [module.network]
}
# Created here and adopted by the controller rather than left for the controller to create, which
# this project needs for one reason above the others: the address is known from state at apply
# time, so n8n can be told its own external URL - and that is what makes the webhook URLs it hands
# out reachable (rules.md G-3).
#
# That reason is now the only one. While this was an NLB there was a second: AWS refuses to add
# security groups to an NLB after creation, so a frontend group meant pre-creating the load
# balancer. An ALB takes security groups at any time, so pre-creating it is a choice here rather
# than a requirement - and the choice is still worth making, because an address that is only known
# after the controller has reconciled cannot be put in an environment variable on the pod that
# needs it.
module "synced_load_balancer" {
  source = "./modules/synced_load_balancer"

  cluster_name = module.eks_cluster.cluster_name
  # application, not network: an Ingress is fronted by an ALB. A type mismatch is not rejected -
  # the controller cannot adopt a load balancer of the wrong type and builds a second one
  # (rules.md G-3).
  load_balancer_type = "application"
  internal           = false
  # internet-facing, so public subnets - this has to agree with the scheme the Ingress annotates,
  # or the controller builds a second load balancer instead of adopting this one (rules.md G-3).
  subnet_ids         = module.network.public_subnet_ids
  security_group_ids = [module.load_balancer_security_group.security_group_id]
  # ingress.k8s.aws/*, not service.k8s.aws/*: this fronts an Ingress now. The wrong prefix is not
  # an error - the controller simply does not adopt, and quietly builds its own (rules.md G-3).
  resource_tag_prefix = "ingress"
  stack               = local.n8n_stack_tag

  depends_on = [module.network]
}
module "n8n" {
  source = "./modules/n8n"

  namespace             = var.n8n_namespace
  name                  = var.n8n_name
  image                 = var.n8n_image
  container_port        = var.n8n_port
  service_port          = var.n8n_port
  postgres_storage_size = var.postgres_storage_size
  # Taken from the module that created the class. A claim naming a class that does not exist stays
  # Pending and the pods never start (rules.md B-5).
  storage_class_name = module.csi_storage_classes.storage_class_name
  # The address users actually reach, known because Terraform created the load balancer
  # (rules.md G-3). Without it n8n builds webhook URLs from the pod's hostname and every webhook
  # it hands out is unreachable - which the _monolithic template never addressed.
  external_url = module.synced_load_balancer.url
  # ClusterIP: the ALB registers pod addresses directly, so the Service is only the name the
  # Ingress resolves and is never in the data path (rules.md G-1).
  service_type = var.n8n_service_type
  ingress_annotations = {
    # Has to agree with internal = false and the public subnets above, and with the
    # kubernetes.io/role/elb tag on those subnets - the controller finds where to put the load
    # balancer by that tag, and a scheme the tags do not match fails with "couldn't auto-discover
    # subnets" (rules.md G-1/G-3).
    "alb.ingress.kubernetes.io/scheme" = "internet-facing"
    # target-type, with no nlb- prefix: that prefix belongs to the Service spelling, and the wrong
    # one is ignored rather than rejected (rules.md G-1). ip works because the VPC CNI makes pod
    # addresses routable in the VPC, which is also why no NodePort is needed.
    "alb.ingress.kubernetes.io/target-type" = "ip"
    # The plain http listener, which is what makes the load balancer's own DNS name - with no port
    # in it - a working address. This is the gap the NLB shape left: its listener was on n8n's own
    # port while the advertised URL had none, so the published address reached nothing.
    "alb.ingress.kubernetes.io/listen-ports" = jsonencode([{ HTTP = var.ingress_listen_port }])
    # Only the frontend group, and no manage-backend-security-group-rules: the path to the pod is
    # the declared rule below rather than something the controller writes (rules.md G-2).
    "alb.ingress.kubernetes.io/security-groups" = module.load_balancer_security_group.security_group_id
    # n8n answers 200 here as soon as the process is serving http, and deliberately without
    # consulting Postgres. That is the behaviour wanted from a load balancer health check: a
    # database-gated check would pull the only target out of service whenever Postgres restarts,
    # and the editor would go from "slow" to "502" for the duration.
    "alb.ingress.kubernetes.io/healthcheck-path"        = var.ingress_healthcheck_path
    "alb.ingress.kubernetes.io/target-group-attributes" = var.load_balancer_stickiness_attributes
  }

  # The load balancer has to exist before the controller reconciles this Ingress, or the controller
  # creates its own and the pre-created one is orphaned (rules.md G-3). Ordering the module after
  # the controller also means terraform destroy removes the Ingress while the controller is still
  # alive, so the load balancer is cleaned up rather than left behind (rules.md D-4).
  depends_on = [
    module.network,
    module.eks_node_group,
    module.eks_coredns_addon,
    module.eks_ebs_csi_driver_addon,
    module.csi_storage_classes,
    module.aws_load_balancer_controller,
    module.synced_load_balancer,
  ]
}
# With manage-backend-security-group-rules unset the controller writes no node-side rules at all,
# so the path from load balancer to pod has to be declared here or the target stays unhealthy with
# no error anywhere (rules.md G-2). target-type is ip, so traffic arrives at n8n's container port -
# not at the listener port - and pods on this cluster use the cluster security group. The ALB's
# health check goes to the same port, so this one rule covers both.
#
# It modifies the cluster security group, which no module here owns outright, so it belongs in the
# root (rules.md C-1).
resource "aws_vpc_security_group_ingress_rule" "load_balancer_to_pods" {
  security_group_id            = module.eks_cluster.cluster_security_group_id
  description                  = "n8n container port from the ALB frontend security group"
  ip_protocol                  = "tcp"
  from_port                    = module.n8n.container_port
  to_port                      = module.n8n.container_port
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
  # Joining the cluster security group is what lets this instance reach the API server. The module
  # is handed an ID list and never learns it belongs to an EKS cluster (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]

  # An EKS cluster and this instance share a root module, so it is the workbench for that cluster
  # and carries all five tools (rules.md H-1). None of them creates anything: the controller, the
  # StorageClass and every n8n object the _monolithic template installed from here are Terraform
  # resources now, so there is no git clone of n8n-hosting either (rules.md E-1).
  #
  # Bugs from that template that are not carried over. It ran "exec bash" partway through, which
  # replaces the shell and silently discarded every remaining line - eksctl, helm, the AWS Load
  # Balancer Controller install, the StorageClass and the whole n8n deployment were all after it,
  # so on a real boot none of them ran. It pulled eksctl from weaveworks rather than eksctl-io. It
  # wrote the "complete" line for the k alias into .bashrc before the line that defines
  # __start_kubectl, so every login printed a "function not found" error (rules.md H-1). And it
  # passed "--alias nvidia" to update-kubeconfig, a leftover from a sibling template about GPUs.
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
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm get_helm.sh
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
  # below renders them, so no value expression is written twice (rules.md B-5/H-2).
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here. The kubectl commands below are meant to be run from its terminal"
      value       = module.vscode_ec2.vscode_url
    }
    n8n_url = {
      order       = 2
      title       = "n8n editor"
      description = "The editor, over plain http on port 80 - which is why this address needs no port in it. First visit asks you to create an owner account, and whoever reaches it first gets it, so treat the address as unauthenticated until you have. It is known from state because Terraform created the load balancer and the controller adopted it for the Ingress (rules.md G-3)"
      value       = module.synced_load_balancer.url
    }
    cluster_name = {
      order       = 3
      title       = "EKS cluster name"
      description = "Name of the EKS cluster"
      value       = module.eks_cluster.cluster_name
    }
    cluster_endpoint = {
      order       = 4
      title       = "EKS cluster endpoint"
      description = "API server endpoint. Public so the helm and kubectl providers could reach it during apply - narrow public_access_cidrs to your own address"
      value       = module.eks_cluster.cluster_endpoint
    }
    n8n_deployment = {
      order       = 5
      title       = "What was deployed"
      description = "The image and the external URL n8n was told about. The second is the part the _monolithic template had no way to set: it deployed n8n without N8N_HOST or WEBHOOK_URL, so every webhook the editor generated pointed at the pod's own hostname"
      value       = "${module.n8n.image} in namespace ${module.n8n.namespace}, N8N_HOST/WEBHOOK_URL=${module.n8n.external_url}"
    }
    postgres_rollout_command = {
      order       = 6
      title       = "1. Wait for Postgres"
      description = "Run this first. While Postgres is still initialising its data directory and creating n8n's role, n8n exits and restarts - which looks like a broken image rather than a database that is not up yet"
      value       = module.n8n.postgres_rollout_status_command
    }
    n8n_rollout_command = {
      order       = 7
      title       = "2. Wait for n8n"
      description = "Two EBS volumes are provisioned only once their pods are scheduled, so the first start is slower than it looks"
      value       = module.n8n.rollout_status_command
    }
    pods_command = {
      order       = 8
      title       = "3. Read both pods and both claims"
      description = "A pod Pending with a Pending claim is the storage class or the EBS CSI driver rather than anything in the application - and from the editor's side it is indistinguishable from the load balancer being wrong"
      value       = module.n8n.pods_command
    }
    adopted_load_balancer_check_command = {
      order       = 9
      title       = "4. Confirm the load balancer was adopted, not duplicated"
      description = "Lists every load balancer tagged for this cluster. One is correct. Two means the controller did not adopt the pre-created one and built its own, which is a tag mismatch rather than an error - and the editor URL above would then point at the one with no listeners. The three things that have to match are the ingress.k8s.aws prefix, the <namespace>/<name> stack tag and the application type (rules.md G-3)"
      value       = "aws resourcegroupstaggingapi get-resources --tag-filters Key=elbv2.k8s.aws/cluster,Values=${module.eks_cluster.cluster_name} --resource-type-filters elasticloadbalancing:loadbalancer --query 'ResourceTagMappingList[].ResourceARN' --output table"
    }
    ingress_address_command = {
      order       = 10
      title       = "5. Confirm the Ingress has an address"
      description = "The failure worth recognising here is an empty ADDRESS, which is not an error anywhere: it means no controller is reconciling this Ingress, and that is almost always a missing or misspelled ingressClassName. If the column is populated it should be the same name as the editor URL above - a different one means the controller built its own load balancer instead of adopting the pre-created one (rules.md G-1/G-3)"
      value       = module.n8n.ingress_address_command
    }
    ingress_events_command = {
      order       = 11
      title       = "6. Read what the controller did with the Ingress"
      description = "Where the controller explains itself. \"couldn't auto-discover subnets\" means the subnet role tags and the scheme annotation disagree; a target group with no healthy targets usually means the rule from the frontend security group to the pod port is missing, which this configuration declares rather than letting the controller write (rules.md G-1/G-2)"
      value       = module.n8n.ingress_events_command
    }
    http_check_command = {
      order       = 12
      title       = "7. Reach it over http"
      description = "The end-to-end check, and the only one that exercises the whole path: listener, target group, security group rule and n8n itself. 200 means the editor is being served. 502 or 504 means the load balancer is there but the target is not answering - read n8n's log below. A connection that hangs is the frontend security group rather than anything in the cluster"
      # %%{ escapes the template directive: a bare %{ would make Terraform read http_code as a
      # template control keyword and fail the parse. The \\n is a literal backslash-n, which is
      # what curl's -w format expects.
      value = "curl -sS -o /dev/null -w '%%{http_code}\\n' ${module.synced_load_balancer.url}"
    }
    db_init_command = {
      order       = 13
      title       = "8. Confirm the database role was reconciled"
      description = "The Job that makes Postgres's application role match this configuration. It runs on every apply that changes the role, the password or the script, and the apply waits for it - so a failure here fails the apply instead of surfacing later as n8n reporting \"password authentication failed\". Nothing listed means its TTL has already cleaned it up, which is the normal state some minutes after an apply"
      value       = "${module.n8n.db_init_status_command}\n${module.n8n.db_init_log_command}"
    }
    logs_command = {
      order       = 14
      title       = "9. Read n8n's log"
      description = "A database authentication failure here means Postgres's first-start script did not create n8n's role. That script runs only when the data directory is empty, so it happens once and leaves no trace anywhere else"
      value       = module.n8n.logs_command
    }
    credentials_command = {
      order       = 15
      title       = "10. Read the generated database credentials"
      description = "Terraform generates both Postgres passwords rather than shipping the upstream manifests' \"changePassword\", and they are deliberately not written here or exposed as outputs - this instance's code-server has no authentication in front of it, so a password on this disk is a password published (rules.md H-2)"
      value       = module.n8n.credentials_command
    }
    update_kubeconfig_command = {
      order       = 16
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
# The work happens inside code-server in a browser, where terraform output is not available, so
# every output above is also written to a README in the home directory the IDE opens
# (rules.md H-2). The _monolithic template wrote a one-line README here.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is what orders this after
    # the bootstrap (rules.md D-5). The marker path comes back out of the module it was passed
    # into, so it is defined once (rules.md B-5).
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
