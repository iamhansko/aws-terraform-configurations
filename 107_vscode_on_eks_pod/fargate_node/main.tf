data "aws_region" "current" {}

locals {
  # The adoption tag, defined here rather than taken from the pod module's output. That is what lets
  # the load balancer be created first: reading it from an output would order the load balancer after
  # the Ingress, and the controller would then reconcile an Ingress whose load balancer does not
  # exist yet and build its own (rules.md B-5/G-3).
  vscode_stack_tag = "${var.vscode_pod_namespace}/${var.vscode_pod_name}"
}

module "network" {
  source = "./modules/network"

  region                         = data.aws_region.current.region
  vpc_cidr_block                 = var.vpc_cidr_block
  availability_zone_suffixes     = var.availability_zone_suffixes
  nat_availability_zone_suffixes = var.nat_availability_zone_suffixes
  vpc_name                       = "${var.project_name}-vpc"
  # The controller discovers subnets by tag, not by configuration, and a scheme that does not match
  # the tags fails with "couldn't auto-discover subnets". The _monolithic template tagged nothing,
  # which worked only because it pre-created the load balancer with explicit subnets - the moment
  # the controller had to place one itself, discovery had nothing to find (rules.md G-1).
  subnet_tags = {
    "kubernetes.io/role/elb"          = "1"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

module "key_pair" {
  source = "./modules/key_pair"

  key_name = "${var.project_name}-key"

  # Nothing here reads a network output, but the root orders every module after the network so the
  # whole VPC - NAT gateway and route tables included - is finished before anything starts in it
  # (rules.md D-3).
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

# vpc-cni and kube-proxy are DaemonSets, so they reach ACTIVE with zero nodes. They come before the
# node group because a node cannot join Ready without them, and with
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

# There is no eks_pod_identity_agent_addon here, and that absence is the point of this variant.
#
# Pod Identity is delivered by an agent DaemonSet, which needs a node to run on. This cluster has none,
# so every identity in it - the load balancer controller's and the code-server pod's - has to be bound
# through IRSA instead: the role trusts the cluster's OIDC provider, and the service account carries an
# annotation naming the role. Installing the addon anyway would succeed and then quietly never work.

# All the capacity this cluster has. A Fargate profile matches pods by namespace rather than providing
# machines, so a pod in a namespace no selector covers simply stays Pending.
module "eks_fargate_profile" {
  source = "./modules/eks_fargate_profile"

  cluster_name = module.eks_cluster.cluster_name
  profile_name = var.fargate_profile_name
  namespaces   = var.fargate_namespaces
  # Private subnets only. Fargate refuses a profile that names a subnet with a route to an internet
  # gateway, and the error says "cannot be created in public subnets" rather than naming the route
  # table.
  subnet_ids = module.network.private_subnet_ids

  # vpc-cni and kube-proxy first, for the same reason a node group waits for them: a Fargate pod gets
  # its address from the VPC CNI, and the profile is what makes the first pod schedulable
  # (rules.md C-4).
  depends_on = [module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}

# coredns is a Deployment, so unlike the DaemonSets it needs schedulable capacity to leave DEGRADED and
# become ACTIVE - here that capacity is the Fargate profile rather than a node group (rules.md C-4).
#
# compute_type is the part that is specific to a node-less cluster: EKS ships the CoreDNS Deployment
# annotated eks.amazonaws.com/compute-type: ec2, and with that annotation its pods never schedule here
# at all. Setting it declaratively is why this variant needs no rollout-restart step (rules.md E-4).
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name          = module.eks_cluster.cluster_name
  coredns_replica_count = var.coredns_replica_count
  compute_type          = var.coredns_compute_type

  depends_on = [
  module.network, module.eks_fargate_profile]
}

# The shared file system, which is the only storage a Fargate pod can have. EBS cannot be attached to
# one at all, and the EFS CSI node driver is part of the Fargate runtime - so there is no addon module
# here, only the file system and, further down, a statically provisioned volume.
module "efs_file_system" {
  source = "./modules/efs_file_system"

  name   = "${var.project_name}-efs"
  vpc_id = module.network.vpc_id
  # Keyed by zone suffix rather than passed as a list: the subnet ids are another module's output and
  # unknown at plan time, and for_each needs its keys known then (rules.md B-8).
  #
  # Every zone the profile can place a pod in needs a mount target, because a pod reaches the file
  # system only through the one in its own zone - and a Fargate pod's zone is not something the caller
  # picks.
  mount_target_subnet_ids = module.network.private_subnet_ids_by_zone
  performance_mode        = var.efs_performance_mode
  # The cluster security group, which is what Fargate pods carry. The _monolithic template opened NFS
  # to the whole VPC CIDR instead - broader, and it stops describing intent the moment the VPC gains
  # anything else (rules.md B-8).
  ingress_source_security_groups = {
    eks_cluster = module.eks_cluster.cluster_security_group_id
  }

  depends_on = [module.network]
}

# The PersistentVolume and claim for the EFS file system. Static provisioning only: the driver built
# into Fargate does not support the dynamic access-point workflow, so there is no StorageClass here and
# the volume names the file system directly.
module "static_csi_volumes" {
  source = "./modules/static_csi_volumes"

  namespace = var.vscode_pod_namespace

  efs_volumes = {
    "${var.vscode_pod_name}-project" = {
      file_system_id = module.efs_file_system.file_system_id
    }
  }

  # The mount targets have to exist before a pod can reach the file system, and the claim has to exist
  # before a pod referencing it is scheduled (rules.md D-4).
  depends_on = [
  module.network, module.efs_file_system, module.eks_fargate_profile]
}

# The controller that turns the pod's Ingress into an ALB. Its IAM role, its Pod Identity association
# and its Helm release stay in one module because they reference each other (rules.md C-2).
#
# This is the piece the _monolithic template never actually installed: its `helm install` sat after an
# `exec bash` in the workbench's user data, which replaces the shell and discards the rest of the
# script. Nothing reported that - the instance booted, the Ingress was created, and no load balancer
# ever appeared.
module "aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"

  cluster_name = module.eks_cluster.cluster_name
  vpc_id       = module.network.vpc_id
  aws_region   = data.aws_region.current.region
  # IRSA, not Pod Identity - there is no node here for the agent DaemonSet, so the role has to trust
  # the cluster's OIDC provider instead.
  oidc_provider_arn             = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host              = module.eks_cluster.oidc_issuer_host
  chart_version                 = var.load_balancer_controller_chart_version
  enable_backend_security_group = var.enable_backend_security_group

  depends_on = [
    module.network,
    module.eks_fargate_profile,
    module.eks_coredns_addon,
  ]
}

# The ALB's frontend security group, created here rather than left to the controller so its rules are
# reviewable in the plan (rules.md G-1). It is also the group the pre-created load balancer is built
# with, which is where the _monolithic template went wrong: it built the ALB with the VPC's default
# security group while the Ingress annotation named alb-sg, so the group the controller expected and
# the group the load balancer had were different.
module "alb_security_group" {
  source = "./modules/load_balancer_security_group"

  vpc_id      = module.network.vpc_id
  name        = var.alb_security_group_name
  description = "Frontend security group for the ALB in front of the code-server pod"
  ports = {
    listener = var.alb_listener_port
  }
  allow_inbound_from_anywhere = var.alb_allow_inbound_from_anywhere

  depends_on = [module.network]
}

# The pre-created ALB the controller adopts, rather than one the controller builds. The _monolithic
# template did the same thing, and this keeps it - the address is then known from state at apply time
# instead of only after the controller has reconciled the Ingress (rules.md G-3).
#
# What is not kept is its listener and target group. Those were Terraform resources in the original,
# which gives them two owners: the controller creates and rewires them as pods come and go, so every
# subsequent plan proposed to undo that. Only the load balancer itself belongs here.
module "synced_load_balancer" {
  source = "./modules/synced_load_balancer"

  cluster_name       = module.eks_cluster.cluster_name
  name               = var.alb_name
  load_balancer_type = "application"
  internal           = false
  # internet-facing, so public subnets. This has to agree with the scheme the Ingress annotates, or
  # the controller builds a second load balancer instead of adopting this one (rules.md G-3).
  subnet_ids         = module.network.public_subnet_ids
  security_group_ids = [module.alb_security_group.security_group_id]
  # ingress.k8s.aws/*, not service.k8s.aws/*: this fronts an Ingress. The wrong prefix is not an
  # error - the controller just does not adopt (rules.md G-3).
  resource_tag_prefix = "ingress"
  stack               = local.vscode_stack_tag

  depends_on = [module.network]
}

# The AWS identity the pod runs as. IRSA here, because Pod Identity's agent has no node to run on -
# passing the OIDC provider is what selects it, and it is the whole difference between this variant's
# pod and the node-based ones.
module "vscode_pod_role" {
  source = "./modules/vscode_pod_role"

  name                 = var.vscode_pod_name
  cluster_name         = module.eks_cluster.cluster_name
  namespace            = var.vscode_pod_namespace
  service_account_name = var.vscode_pod_name
  iam_policy_arns      = var.vscode_pod_iam_policy_arns
  # The mode is stated rather than inferred from the ARN below, because that ARN is unknown during plan
  # and a count derived from it stops the plan outright (rules.md B-8).
  identity_mode     = "irsa"
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host

  depends_on = [
  module.network, module.eks_cluster]
}

# code-server itself: the ConfigMaps, ServiceAccount, StatefulSet, Service and Ingress.
module "vscode_pod" {
  source = "./modules/vscode_pod"

  name           = var.vscode_pod_name
  namespace      = var.vscode_pod_namespace
  ingress_name   = var.vscode_pod_name
  image          = var.vscode_pod_image
  container_port = var.vscode_pod_port
  cpu_request    = var.vscode_pod_cpu_request
  memory_request = var.vscode_pod_memory_request
  # Nothing under Pod Identity, which is the point of using it - the binding is held by EKS rather
  # than written into the manifest (rules.md B-5).
  service_account_annotations = module.vscode_pod_role.service_account_annotations
  # Enough to build a working kubeconfig at apply time, so nothing inside the pod has to run
  # `aws eks update-kubeconfig` and lose it on the next restart.
  cluster_name               = module.eks_cluster.cluster_name
  cluster_endpoint           = module.eks_cluster.cluster_endpoint
  certificate_authority_data = module.eks_cluster.certificate_authority_data
  aws_region                 = data.aws_region.current.region
  install_tools              = var.vscode_pod_install_tools
  kubectl_download_version   = var.vscode_pod_kubectl_download_version

  # EFS and nothing else, and as a claim rather than a volumeClaimTemplate. A Fargate pod cannot have
  # an EBS volume attached, so there is no block storage to provision per replica - and the built-in
  # driver only does static provisioning, so the claim was created beforehand.
  persistent_volume_claims = [{
    name       = "project"
    claim_name = "${var.vscode_pod_name}-project"
    mount_path = var.efs_volume_mount_path
  }]

  # The image runs as uid 1000 and the file system root is owned by root, so without this the
  # container sees its own workspace directory and cannot write to it - which reads like a bug in
  # code-server rather than a volume permission.
  fs_group = 1000

  ingress_annotations = {
    "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
    "alb.ingress.kubernetes.io/target-type" = "ip"
    # Naming the frontend group is what stops the controller from building one of its own, and it is
    # half of what keeps the controller off the load balancer's security groups entirely. The other
    # half is the annotation that is missing below (rules.md G-2).
    "alb.ingress.kubernetes.io/security-groups" = module.alb_security_group.security_group_id
    # manage-backend-security-group-rules is deliberately absent, where the _monolithic template set
    # it to "true". With it the controller asks for its shared backend group and attaches that group
    # to the load balancer next to the one above, so the ALB would carry a security group nothing
    # here declares. Without it the controller writes no pod-side rule at all, which is why
    # load_balancer_to_pods below exists (rules.md G-2).
    "alb.ingress.kubernetes.io/listen-ports"     = jsonencode([{ HTTP = var.alb_listener_port }])
    "alb.ingress.kubernetes.io/healthcheck-path" = "/"
    "alb.ingress.kubernetes.io/healthcheck-port" = tostring(var.vscode_pod_port)
  }

  # The controller has to be running before the Ingress gets an address, the pre-created load
  # balancer has to exist before the controller reconciles it, and the pod needs capacity and DNS.
  # Ordering the module after these is also what makes `terraform destroy` remove the Ingress while
  # the controller is still alive, so the load balancer is cleaned up rather than orphaned
  # (rules.md D-4).
  depends_on = [
    module.network,
    module.synced_load_balancer,
    module.aws_load_balancer_controller,
    module.eks_coredns_addon,
    module.vscode_pod_role,
    module.eks_fargate_profile,
    # The claim has to exist before a pod referencing it is scheduled; otherwise the pod sits in
    # Pending with a FailedScheduling event naming a claim that is not there yet (rules.md D-4).
    module.static_csi_volumes,
  ]
}

# The rule from the load balancer to the pod, which the controller would otherwise have written.
#
# It is declared here because the Ingress above does not set manage-backend-security-group-rules, and
# that is not a free choice: asking the controller to manage these rules is what makes it attach its
# own shared group to the load balancer, and this variant requires every group on the ALB to be a
# Terraform resource. The cost is this resource. With the annotation gone the controller leaves the
# TargetGroupBinding without a networking spec, so it writes no pod-side rule whatsoever - and the
# result is not an error: the ALB is provisioned, the pod addresses are registered, and every target
# simply reports unhealthy with nothing logged to say why (rules.md G-2).
#
# The group being opened belongs to EKS rather than to this configuration, and on Fargate there is no
# alternative: a Fargate pod gets its own ENI and that ENI always carries the cluster security group,
# which is not configurable per pod and not reachable by a SecurityGroupPolicy either. One rule covers
# the health check as well, since healthcheck-port above is the container port.
resource "aws_vpc_security_group_ingress_rule" "load_balancer_to_pods" {
  security_group_id = module.eks_cluster.cluster_security_group_id
  description       = "ALB to the code-server pod on its container port"
  ip_protocol       = "tcp"
  # Read back from the pod module rather than from var.vscode_pod_port directly, so the port this
  # rule opens cannot drift from the port the container listens on (rules.md B-5).
  from_port                    = module.vscode_pod.container_port
  to_port                      = module.vscode_pod.container_port
  referenced_security_group_id = module.alb_security_group.security_group_id
}

# What the pod may do inside the cluster. The access entry maps its IAM role to a Kubernetes identity
# and the policy association decides what that identity can do - two resources, and the second one is
# the half people forget, which leaves a role that authenticates and is then denied everything.
#
# Joining two modules that know nothing about each other belongs in the root (rules.md C-1).
resource "aws_eks_access_entry" "vscode_pod_access_entry" {
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.vscode_pod_role.role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "vscode_pod_access_policy_association" {
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.vscode_pod_role.role_arn
  policy_arn    = var.vscode_pod_cluster_access_policy_arn
  access_scope {
    type = "cluster"
  }

  # EKS rejects a policy association for a principal with no access entry yet, and the two resources
  # share only literal argument values, so nothing orders them (rules.md D-1).
  depends_on = [aws_eks_access_entry.vscode_pod_access_entry]
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
  # Carrying the cluster security group is what lets kubectl on this instance reach the API server
  # without leaving the VPC. The module is handed an ID list and never learns what it belongs to
  # (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]
  # An EKS cluster and this instance share a root module, so this instance is the workbench for that
  # cluster and carries all five tools (rules.md H-1).
  #
  # The _monolithic template's script had three faults, and the first one hid the other two. It
  # called `exec bash` in the middle, which replaces the shell and silently drops every remaining
  # line - the eksctl and helm installs, `aws eks update-kubeconfig`, the `helm install` of the load
  # balancer controller, and the mkdir of the manifests directory the SSM Association then wrote
  # into. It also wrote the kubectl completion alias before sourcing the completion that defines
  # __start_kubectl, and it ended with `cfn-signal`, a CloudFormation helper with no stack to signal
  # (rules.md H-1).
  #
  # Nothing here creates cluster resources: the controller is a Helm release and the pod's manifests
  # are provider resources (rules.md E-1).
  additional_user_data = <<-EOT
    dnf install -yq docker git
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
    # Order matters: bash_completion has to be sourced before kubectl's own completion, which is what
    # defines __start_kubectl, and that function has to exist before complete references it
    # (rules.md H-1).
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
    # Without this - and without the access entry below - kubectl is installed but every command
    # answers "You must be logged in to the server" (rules.md H-1).
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

locals {
  # Every output this project exposes, defined once. outputs.tf projects these and the README below
  # renders them, so no value expression is written twice (rules.md B-5/H-2). Adding an entry here is
  # what makes an output possible, which is what keeps the README from falling behind outputs.tf.
  outputs = {
    vscode_ec2_url = {
      order       = 1
      title       = "code-server on EC2 (the workbench)"
      description = "The instance, not the pod. Open the IDE here and run every command below from its terminal"
      value       = module.vscode_ec2.vscode_url
    }
    vscode_pod_url = {
      order       = 2
      title       = "code-server in the pod"
      description = "The point of this project: the same IDE, running as a pod, reached through the ALB. The address is known from state because Terraform pre-created the load balancer rather than letting the controller build one (rules.md G-3)"
      value       = module.synced_load_balancer.url
    }
    security_warning = {
      order       = 3
      title       = "What this endpoint can do"
      description = "code-server in the pod runs with auth disabled, the pod's role holds AdministratorAccess and a cluster-admin access entry, and the load balancer accepts 0.0.0.0/0 by default. Anything that reaches the URL above has a root shell in this account - narrow alb_allow_inbound_from_anywhere and vscode_pod_iam_policy_arns before leaving it up"
      value       = "aws ec2 describe-security-group-rules --filters Name=group-id,Values=${module.alb_security_group.security_group_id} --query 'SecurityGroupRules[?!IsEgress].[IpProtocol,FromPort,ToPort,CidrIpv4]' --output table"
    }
    cluster_name = {
      order       = 4
      title       = "EKS cluster name"
      description = "Name of the EKS cluster, which is also the elbv2.k8s.aws/cluster tag on the pre-created load balancer"
      value       = module.eks_cluster.cluster_name
    }
    pod_rollout_command = {
      order       = 5
      title       = "1. The pod is running"
      description = "Init:0/1 means the tools init container is still downloading. Pending that never clears is the 3 CPU request against a node group that is too small, not a bad image"
      value       = module.vscode_pod.rollout_status_command
    }
    pod_tools_command = {
      order       = 6
      title       = "2. The tools are in the pod"
      description = "kubectl, helm, eksctl, terraform and the AWS CLI, installed by an init container into a volume. The original installed these with kubectl exec, so they were gone after every restart"
      value       = module.vscode_pod.tools_check_command
    }
    pod_cluster_access_command = {
      order       = 7
      title       = "3. kubectl works inside the pod"
      description = "Uses the kubeconfig mounted from a ConfigMap and the credentials from the pod's identity binding. \"You must be logged in to the server\" means the access entry is missing rather than the kubeconfig"
      value       = module.vscode_pod.cluster_access_check_command
    }
    pod_identity_command = {
      order       = 8
      title       = "4. The pod's identity binding"
      description = "IRSA on this variant, so the binding is an annotation on the service account. Pod Identity is not available: its agent is a DaemonSet and this cluster has no node to run one on"
      value       = module.vscode_pod_role.identity_check_command
    }
    fargate_placement_command = {
      order       = 9
      title       = "5. Everything is on Fargate"
      description = "Every node name starts with fargate-ip-, and there is one per pod - a Fargate pod is its own micro VM. CoreDNS appearing here at all is what compute_type Fargate bought: with the annotation EKS ships, its pods never schedule on a cluster like this"
      value       = "kubectl get nodes -o wide; kubectl get pods -A -o custom-columns='NS:.metadata.namespace,POD:.metadata.name,NODE:.spec.nodeName'"
    }
    volume_binding_command = {
      order       = 10
      title       = "6. The EFS volume is bound"
      description = "Statically provisioned, because the driver built into the Fargate runtime does not do the dynamic access-point workflow. A claim stuck in Pending is an accessModes or capacity mismatch rather than a missing driver"
      value       = module.static_csi_volumes.binding_check_command
    }
    volume_write_command = {
      order       = 11
      title       = "7. The pod can write to it"
      description = "The difference between this variant and the base one, which created the same file system and mounted nothing. A mount that hangs rather than fails is the EFS security group: NFS reaches it only from the cluster security group"
      value       = "kubectl -n ${var.vscode_pod_namespace} exec ${module.vscode_pod.pod_name} -- sh -c 'df -h ${var.efs_volume_mount_path}; echo ok > ${var.efs_volume_mount_path}/write-test && echo writable || echo NOT writable'"
    }
    ingress_status_command = {
      order       = 12
      title       = "8. The Ingress has an address"
      description = "An empty ADDRESS with a class set points at the controller log; an empty CLASS means no controller claimed it at all - which is exactly what the original produced, because its helm install never ran"
      value       = module.vscode_pod.ingress_status_command
    }
    adoption_check_command = {
      order       = 13
      title       = "9. The ALB was adopted, not duplicated"
      description = "One load balancer is correct. Two means the controller did not adopt the pre-created one and built its own, which is a tag mismatch rather than an error (rules.md G-3)"
      value       = "aws resourcegroupstaggingapi get-resources --tag-filters Key=elbv2.k8s.aws/cluster,Values=${module.eks_cluster.cluster_name} --resource-type-filters elasticloadbalancing:loadbalancer --query 'ResourceTagMappingList[].ResourceARN' --output table"
    }
    adopted_hostname_command = {
      order       = 14
      title       = "10. Compare the two addresses"
      description = "The hostname the controller attached to the Ingress should be the same load balancer as the URL above"
      value       = module.vscode_pod.load_balancer_hostname_command
    }
    target_health_command = {
      order       = 15
      title       = "11. The targets are healthy"
      description = "Pod IPs registered by the controller. All unhealthy with a healthy pod means the rule from the load balancer to the pod's port is missing - and on this variant that rule is load_balancer_to_pods in the configuration rather than something the controller writes, so it is a plan to read rather than a controller log (rules.md G-2)"
      value       = "aws elbv2 describe-target-groups --load-balancer-arn ${module.synced_load_balancer.arn} --query 'TargetGroups[0].TargetGroupArn' --output text | xargs -I {} aws elbv2 describe-target-health --target-group-arn {} --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State]' --output table"
    }
    load_balancer_security_groups_command = {
      order       = 16
      title       = "12. Every security group on the ALB is one Terraform made"
      description = "One group, the frontend group this configuration declares. A second group named k8s-traffic-<cluster>-<hash> is the controller's shared backend group, which it creates and attaches whenever enable_backend_security_group is on and an Ingress asks it to manage the pod-side rules - both of which this variant turns off, so anything beyond the one group here means one of them came back (rules.md G-2)"
      value       = "aws ec2 describe-security-groups --group-ids $(aws elbv2 describe-load-balancers --load-balancer-arns ${module.synced_load_balancer.arn} --query 'LoadBalancers[0].SecurityGroups' --output text) --query 'SecurityGroups[].[GroupId,GroupName]' --output table"
    }
    controller_log_command = {
      order       = 17
      title       = "Read the controller's log"
      description = "Where a rejected annotation combination explains itself. A backendSG message here means manage-backend-security-group-rules is being set somewhere while enable_backend_security_group is false, which is the pairing rules.md G-2 describes"
      value       = "kubectl -n kube-system logs deploy/aws-load-balancer-controller --tail 100"
    }
    update_kubeconfig_command = {
      order       = 18
      title       = "Re-point kubectl on the workbench"
      description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the order field and
  # taking values() sorts by that instead - values() returns a map's values ordered by key - so the
  # README reads in the order the demo is run.
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

# The work happens inside code-server in a browser, where "terraform output" does not exist, so every
# output above is also written to a README in the home directory the IDE opens (rules.md H-2). The
# _monolithic template wrote one line into that file - the project title - from inside the same SSM
# Association that applied the manifests.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on, is what orders this after the instance bootstrap - the marker is
    # written as the last line of user data. The original used `sleep 180`, which is the same bet
    # against a slower boot (rules.md D-5).
    #
    # SSM runs as root, hence the chown. The heredoc delimiter is quoted and deliberately unlikely to
    # appear in the body: Terraform has already substituted every value, so the shell has no reason to
    # touch a "$" or a backtick in the README - and the commands in it contain both.
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
