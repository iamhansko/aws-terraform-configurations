data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
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

  # Referencing module.network.*_subnet_ids only orders this after the specific aws_subnet
  # resources behind those outputs, not after the NAT gateways and route table associations that
  # never surface as outputs (rules.md D-3).
  depends_on = [module.network]
}
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not exist until this
  # addon creates it. As a DaemonSet it reaches ACTIVE with zero nodes, so it comes before any
  # capacity (rules.md C-4) - and nodes need it to join Ready. It is also what makes target-type
  # ip work, by putting pod addresses in the VPC (rules.md G-1).
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
  # (rules.md C-4). Argo CD's repo-server also resolves Vault by Service DNS name, so nothing in
  # the plugin path works until this is up.
  depends_on = [
  module.network, module.eks_node_group]
}
# Vault's server gets a 10Gi PersistentVolumeClaim from its chart's defaults, and since
# Kubernetes 1.23 the in-tree EBS provisioner is gone - so without this addon vault-0 stays
# Pending and the Vault release waits for its whole timeout. Its own module like every other EKS
# addon (rules.md C-4), holding the IRSA role because the trust policy names the exact service
# account the addon creates (rules.md C-2).
module "eks_ebs_csi_driver_addon" {
  source = "./modules/eks_ebs_csi_driver_addon"

  cluster_name      = module.eks_cluster.cluster_name
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host

  # The driver's controller is a Deployment, so it needs schedulable capacity for the same reason
  # coredns does (rules.md C-4).
  depends_on = [
  module.network, module.eks_node_group]
}
# The gp3 StorageClass, without which the addon above provisions nothing.
#
# The addon registers the ebs.csi.aws.com driver and creates no StorageClass, and a fresh EKS cluster
# has no default class to fall back on: its only class is the built-in gp2, whose in-tree
# kubernetes.io/aws-ebs provisioner was removed in Kubernetes 1.23, and which on current versions
# carries no default annotation (measured at 1.33). Vault's claim therefore resolved to no class at
# all and vault-0 stayed Pending for hours with "pod has unbound immediate PersistentVolumeClaims",
# which is what made aws_ssm_association.vault_bootstrap fail - it was waiting on a pod that could
# never start.
#
# The _monolithic template did create this class, with a kubectl apply from the bastion right after
# it rolled out the driver (rules.md E-1/E-2). Losing it was a conversion regression, not an upstream
# change. This module's class adds encryption at rest and volume expansion, which the original left
# off.
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
# The controller that turns Vault's Ingress into the ALB and Argo CD's Service into the NLB. Its
# IRSA role and Helm release are one module, because the release has to annotate the service
# account with the role's ARN (rules.md C-2). The _monolithic template declared the role and
# installed the controller from a helm command in userdata (rules.md E-1).
module "aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"

  cluster_name      = module.eks_cluster.cluster_name
  vpc_id            = module.network.vpc_id
  aws_region        = data.aws_region.current.region
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  chart_version     = var.aws_load_balancer_controller_chart_version
  # Neither workload sets manage-backend-security-group-rules, so nothing asks the controller to
  # write node-side rules and this can stay false. Both paths from load balancer to pod are
  # declared below instead (rules.md G-2).
  enable_backend_security_group = false
  # Off: the one Service of type LoadBalancer here names the controller itself with the
  # aws-load-balancer-type annotation, so the webhook has nothing to mutate - while its
  # failurePolicy: Fail would gate every Service in the cluster, and Argo CD alone creates seven,
  # behind a controller pod being Ready (rules.md G-4).
  enable_service_mutator_webhook = var.enable_service_mutator_webhook

  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}
locals {
  # The two adoption stack tags (rules.md G-3).
  #
  # Derived here rather than read from the workload modules' outputs: each pre-created load
  # balancer needs its tag before the module that creates the object runs, and reading it from
  # the module would make the load balancer depend on the release while the release has to wait
  # for the load balancer. Both sides read the same variables, so there is still one definition
  # (rules.md B-5).
  #
  # Vault's Ingress is named after its release, Argo CD's Service is <release>-server - both are
  # the chart's own naming, confirmed against the rendered chart rather than guessed (rules.md G-3).
  vault_stack_tag  = "${var.vault_namespace}/${var.vault_release_name}"
  argocd_stack_tag = "${var.argocd_namespace}/${var.argocd_release_name}-server"
}
# Two frontend security groups, one per load balancer. Standalone rule resources rather than
# inline blocks, and revoke_rules_on_delete, because the controller adds its own rules to these
# groups (rules.md F-2). The _monolithic template built both load balancers with the VPC's
# default security group while its annotations asked for these separate groups - so the two
# disagreed about which group each load balancer actually had.
module "alb_security_group" {
  source = "./modules/load_balancer_security_group"

  vpc_id      = module.network.vpc_id
  name        = var.alb_security_group_name
  description = "Frontend security group for the ALB fronting the Vault UI"
  ports = {
    http = var.vault_load_balancer_port
  }
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere

  depends_on = [module.network]
}
module "nlb_security_group" {
  source = "./modules/load_balancer_security_group"

  vpc_id      = module.network.vpc_id
  name        = var.nlb_security_group_name
  description = "Frontend security group for the NLB fronting the Argo CD UI"
  ports = {
    http = var.argocd_load_balancer_port
  }
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere

  depends_on = [module.network]
}
# Both load balancers are created here and adopted by the controller, which is what makes their
# DNS names known at apply time - so the Vault and Argo CD URLs are real outputs instead of
# kubectl commands (rules.md G-3).
module "vault_load_balancer" {
  source = "./modules/synced_load_balancer"

  cluster_name       = module.eks_cluster.cluster_name
  name               = var.vault_load_balancer_name
  load_balancer_type = "application"
  internal           = false
  subnet_ids         = module.network.public_subnet_ids
  security_group_ids = [module.alb_security_group.security_group_id]
  # ingress.k8s.aws/*, because this load balancer fronts an Ingress rather than a Service of type
  # LoadBalancer. The wrong prefix is not an error - the controller simply does not adopt
  # (rules.md G-3).
  resource_tag_prefix = "ingress"
  stack               = local.vault_stack_tag

  depends_on = [module.network]
}
module "argocd_load_balancer" {
  source = "./modules/synced_load_balancer"

  cluster_name       = module.eks_cluster.cluster_name
  name               = var.argocd_load_balancer_name
  load_balancer_type = "network"
  internal           = false
  subnet_ids         = module.network.public_subnet_ids
  security_group_ids = [module.nlb_security_group.security_group_id]
  # service.k8s.aws/*, because this one fronts a Service of type LoadBalancer (rules.md G-3).
  resource_tag_prefix = "service"
  stack               = local.argocd_stack_tag

  depends_on = [module.network]
}
module "vault" {
  source = "./modules/vault"

  release_name  = var.vault_release_name
  namespace     = var.vault_namespace
  chart_version = var.vault_chart_version
  # server.ingress.*, which is where this chart actually reads them. The _monolithic template set
  # them at the top level, where helm accepted them and the chart ignored them - so no Ingress
  # existed and the pre-created ALB was never adopted (rules.md G-3).
  ingress_enabled    = true
  ingress_class_name = "alb"
  ingress_annotations = {
    "alb.ingress.kubernetes.io/scheme"          = "internet-facing"
    "alb.ingress.kubernetes.io/target-type"     = "ip"
    "alb.ingress.kubernetes.io/security-groups" = module.alb_security_group.security_group_id
  }
  # Named explicitly rather than left to the default annotation. Taken from the module that creates
  # the class so the name exists in one place (rules.md B-5).
  storage_class = module.csi_storage_classes.storage_class_name

  # The ALB has to exist before the controller reconciles this Ingress, or the controller creates
  # its own and the pre-created one is orphaned (rules.md G-3). The EBS CSI driver has to be able
  # to provision Vault's volume, and the controller has to be running at all (rules.md D-2).
  #
  # csi_storage_classes is in the list even though storage_class above reads its output, because
  # that output is a passthrough of the module's own variable (rules.md B-5) and is therefore known
  # at plan time. Terraform orders an output reference after whatever the output's expression
  # depends on, and this one depends on nothing - so without this the StorageClass manifest and
  # this release would be created concurrently, and the claim could be evaluated before the class
  # exists. A value reference is not always an ordering (rules.md D-2/D-3).
  depends_on = [
    module.network,
    module.vault_load_balancer,
    module.aws_load_balancer_controller,
    module.eks_ebs_csi_driver_addon,
    module.csi_storage_classes,
    module.eks_coredns_addon,
  ]
}
module "argocd" {
  source = "./modules/argocd"

  release_name     = var.argocd_release_name
  namespace        = var.argocd_namespace
  chart_version    = var.argocd_chart_version
  argocd_image_tag = var.argocd_image_tag
  avp_version      = var.avp_version
  # Plain HTTP, because the frontend security group below opens only the listener port. With TLS
  # left on, argocd-server answers that port with a 307 to https:// and the browser has nowhere to
  # go - which is exactly how the dashboard failed to open.
  server_insecure = var.argocd_server_insecure
  # The credential for cloning the seed repository. Without it Argo CD attempts an anonymous clone and
  # a private repository answers with a connection error that says nothing about authentication.
  #
  # Derived from the visibility variable rather than from whether the URL below is set, because this
  # decides a count inside the module and a count has to be decidable during plan - the URL is an
  # attribute of a repository this same apply creates (rules.md B-8). Reading it from the visibility
  # also states the actual reason: flip that variable to public and the token stops being written into
  # the cluster.
  create_repository_credentials = var.github_repo_visibility == "private"
  # The URL comes from the module that created the repository, because Argo CD matches the credential
  # to the Application by URL prefix and the two must agree exactly (rules.md B-5).
  repository_url      = module.github_seed_repository.clone_url
  repository_username = var.github_user
  repository_token    = var.github_token
  # Declared as chart values rather than applied afterwards with three kubectl annotate calls and
  # a kubectl patch, which is what the _monolithic template did (rules.md E-1).
  service_annotations = {
    # The switch that decides which controller handles this Service, and the one the _monolithic
    # template omitted. Without it the in-tree cloud provider claims the Service and builds a
    # Classic Load Balancer, ignoring every annotation below - so the pre-created NLB is never
    # adopted (rules.md G-1).
    "service.beta.kubernetes.io/aws-load-balancer-type" = "external"
    # nlb-target-type, not target-type: the Service spelling carries the nlb- prefix while the
    # Ingress spelling does not, and the wrong one is ignored rather than rejected (rules.md G-1).
    "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
    "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
    "service.beta.kubernetes.io/aws-load-balancer-security-groups" = module.nlb_security_group.security_group_id
  }

  # Same reasoning as the Vault module for the load balancer and the controller. Vault itself is
  # not a dependency of the install - the plugin only needs it when it generates manifests - but
  # ordering Argo CD after it keeps the bootstrap association below, which needs both namespaces
  # to exist, at the end of the chain (rules.md D-2).
  depends_on = [
    module.network,
    module.argocd_load_balancer,
    module.aws_load_balancer_controller,
    module.eks_coredns_addon,
    module.vault,
  ]
}
module "github_source" {
  source = "./modules/github_source"

  github_user  = var.github_user
  github_token = var.github_token
  # S3 bucket names are globally unique, so this is derived from the account and region rather
  # than hardcoded the way the _monolithic template derived it from a stack id.
  bucket_name = "argocd-vault-source-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}"

  # Nothing in this module touches the cluster or the network, so only the repository-wide rule
  # that everything waits for the network applies (rules.md D-3).
  depends_on = [module.network]
}
# The Git repository Argo CD syncs from, which nothing created before - so the application created
# by the command this project outputs pointed at a repository that did not exist. Confirmed against
# the API before adding this: GET /repos/<user>/<repo> answered 404.
#
# Separate from github_source rather than folded into it: that module owns the AWS side of the GitHub
# integration (the CodeStar connection, the CodeBuild credential, the source bucket) and no GitHub
# object, and this one owns a GitHub object and nothing in AWS. Splitting them keeps each module to
# one provider.
#
# The manifests come from the same local.seed_manifests the SSM association writes onto the instance,
# so the definitions exist once: this module commits them, and the association leaves an editable
# working copy in the directory code-server opens (rules.md B-5).
module "github_seed_repository" {
  source = "./modules/github_seed_repository"

  repository_name = var.github_repo
  visibility      = var.github_repo_visibility
  files           = { for filename, body in local.seed_manifests : "${var.github_manifest_path}/${filename}" => body }

  # Nothing in this module touches AWS at all, but the repository-wide rule that every module waits
  # for the network is unconditional (rules.md D-3).
  depends_on = [module.network]
}
# The two paths from load balancer to pod. With manage-backend-security-group-rules unset the
# controller writes no node-side rules at all, so each has to be declared here or every target
# stays unhealthy with no error anywhere (rules.md G-2). target-type is ip for both, so traffic
# arrives at the pod's container port rather than the Service port, and pods on this cluster use
# the cluster security group.
#
# They modify the cluster security group, which no module here owns outright, so they belong in
# the root (rules.md C-1).
resource "aws_vpc_security_group_ingress_rule" "alb_to_vault_pods" {
  security_group_id            = module.eks_cluster.cluster_security_group_id
  description                  = "Vault container port from the Vault ALB frontend security group"
  ip_protocol                  = "tcp"
  from_port                    = var.vault_container_port
  to_port                      = var.vault_container_port
  referenced_security_group_id = module.alb_security_group.security_group_id
}
resource "aws_vpc_security_group_ingress_rule" "nlb_to_argocd_pods" {
  security_group_id            = module.eks_cluster.cluster_security_group_id
  description                  = "Argo CD server container port from the Argo CD NLB frontend security group"
  ip_protocol                  = "tcp"
  from_port                    = var.argocd_container_port
  to_port                      = var.argocd_container_port
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
  # Joining the cluster security group is what lets this instance reach the API server. The module
  # is handed an ID list and never learns it belongs to an EKS cluster (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]

  # An EKS cluster and this instance share a root module, so it is the workbench for that cluster
  # and carries all five tools (rules.md H-1). The Argo CD CLI and jq are added because the
  # bootstrap association below needs them - jq to read the init output, argocd for the demo.
  #
  # Two bugs from the _monolithic template are fixed here rather than carried over. It ran
  # "exec bash" partway through, which replaces the shell and silently discarded every remaining
  # line - update-kubeconfig, eksctl and helm were all after it, so none of them ever ran. And it
  # pulled eksctl from weaveworks; eksctl-io is the project's own org (rules.md H-1).
  additional_user_data = <<-EOT
    dnf install -yq docker jq zip
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
    # Pinned to argocd_image_tag rather than /releases/latest, so the CLI cannot end up ahead of
    # the server it talks to (rules.md H-1).
    curl -sSL -o /home/ec2-user/bin/argocd https://github.com/argoproj/argo-cd/releases/download/${var.argocd_cli_version}/argocd-linux-amd64
    chmod +x /home/ec2-user/bin/argocd
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
# --- The one documented exception to rules.md E-1 in this project ---
#
# Everything else here is a Terraform resource. This is not, and cannot be:
#
#   "vault operator init" is a one-time imperative operation that mints the unseal key and the
#   root token. There is no Terraform resource for it, and the vault provider cannot stand in -
#   every vault provider resource needs an address and a token, and the token is what this step
#   produces. Driving it from Terraform is circular.
#
#   The Secret that carries that token to Argo CD's plugin has the same problem: its value does
#   not exist until this runs, so it cannot be a kubectl_manifest either. The Role and RoleBinding
#   that let the repo-server read it do not depend on the token, so those stay in
#   modules/argocd as resources.
#
# What the _monolithic template got wrong here, beyond the shell:
#   - it never unsealed. "vault operator init" leaves Vault sealed, so the "vault login" that
#     followed was talking to a sealed server and the kv commands after it were commented out -
#     the demo could not have worked.
#   - it wrote the root token into vault_token.json and manifests/vault.yaml in the home
#     directory that an unauthenticated code-server serves. This keeps the init output, because
#     the unseal key is needed again after any pod restart, but with umask 077 so it is not
#     world-readable, and it never echoes the token.
# The demo secret's value, held in Secrets Manager so the bootstrap script can fetch it instead of
# carrying it.
#
# The alternative is interpolating it into the association's commands. Terraform would still keep it
# out of plan output, because the variable is sensitive and that mark propagates - but the rendered
# parameters are stored in AWS, and "aws ssm describe-association" returns them in full. That is the
# same leak this project's 047 sibling was criticised for, so it is not repeated here.
#
# recovery_window_in_days = 0 because a demo that is destroyed and recreated should not collide with
# a 30-day scheduled deletion of the same name.
resource "aws_secretsmanager_secret" "vault_demo" {
  name                    = "${var.cluster_name}-vault-demo-secret"
  description             = "Value seeded into Vault's kv engine by the bootstrap association, fetched at runtime so it never lands in an SSM association parameter"
  recovery_window_in_days = 0
}
resource "aws_secretsmanager_secret_version" "vault_demo" {
  secret_id     = aws_secretsmanager_secret.vault_demo.id
  secret_string = var.vault_demo_secret_password
}
resource "aws_ssm_association" "vault_bootstrap" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.vault_bootstrap_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on, is what orders this after the instance bootstrap
    # (rules.md D-5). The marker path comes back out of the module it was passed into, so it is
    # defined once (rules.md B-5).
    #
    # Every step is written to be re-runnable: the association re-executes whenever these
    # parameters change, and "vault operator init" fails against an already-initialised Vault, so
    # the state is checked first.
    commands = <<-EOT
      set -euo pipefail
      until [ -f ${module.vscode_ec2.marker_file_path}/userdata ]; do sleep 10; done
      sudo -Eu ec2-user bash << 'STEP'
      set -euo pipefail
      export HOME=/home/ec2-user
      export PATH=/home/ec2-user/bin:$PATH
      cd /home/ec2-user
      # Keeps the init output out of other users' reach; it holds the unseal key and root token.
      umask 077

      # An ERR trap, because without one this script's only report is the association's "Failed".
      # set -e exits at the first failing command and says nothing about which, so every diagnosis
      # of this step has had to start by guessing from the source. This prints the line that failed
      # and the state of the three things the script touches, and SSM captures it as the
      # invocation's StandardErrorContent - where rules.md A-4's get-command-invocation will find it.
      #
      # Deliberately uses "|| true" throughout: a diagnostic that fails must not replace the error
      # it was meant to explain.
      bootstrap_failed() {
        code=$?
        echo "=== vault bootstrap failed: exit $code at line $1 ===" >&2
        echo "--- vault pod ---" >&2
        kubectl -n ${module.vault.namespace} get pod ${module.vault.pod_name} -o wide 2>&1 | tail -5 >&2 || true
        kubectl -n ${module.vault.namespace} logs ${module.vault.pod_name} --tail 30 2>&1 >&2 || true
        echo "--- vault status ---" >&2
        kubectl -n ${module.vault.namespace} exec ${module.vault.pod_name} -- vault status 2>&1 | tail -20 >&2 || true
        echo "--- init output present? ---" >&2
        ls -l /home/ec2-user/vault_init.json 2>&1 >&2 || true
        echo "--- argocd repo-server ---" >&2
        kubectl -n ${module.argocd.namespace} get deployment ${module.argocd.release_name}-repo-server 2>&1 | tail -5 >&2 || true
        kubectl -n ${module.argocd.namespace} get pods 2>&1 | tail -15 >&2 || true
        echo "--- recent warnings ---" >&2
        kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp 2>&1 | tail -15 >&2 || true
        exit $code
      }
      trap 'bootstrap_failed $LINENO' ERR

      # What has to be waited for is "vault status can be run inside the pod at all", and neither of
      # the obvious conditions expresses it.
      #
      # Ready is unreachable: the chart's readiness probe *is* the seal status, and unsealing is what
      # this script does. Initialized looks like the alternative but is not - it means the pod's init
      # containers finished, and this chart declares none, so it goes true before the image has even
      # been pulled. An exec at that moment fails with `container not found ("vault")`.
      #
      # That was the actual failure here, and it was made worse by a guard: the first exec swallowed
      # the error with `|| echo false`, so the script read "not initialised" and went straight into
      # `vault operator init`, which is not guarded and killed the association under set -e.
      #
      # So the loop below runs the real command and waits for it to produce output. vault status exits
      # 2 when sealed and 1 when uninitialised, which is why its exit code is ignored - but it prints
      # JSON in both cases, and prints nothing at all when kubectl cannot reach a running container.
      # Commands in an until condition are exempt from set -e, so the assignment is safe here.
      attempt=0
      until VAULT_STATUS=$(kubectl -n ${module.vault.namespace} exec ${module.vault.pod_name} -- vault status -format=json 2>/dev/null); [ -n "$VAULT_STATUS" ]; do
        attempt=$((attempt + 1))
        if [ "$attempt" -gt 60 ]; then
          echo "vault status never answered in ${module.vault.pod_name} after 10 minutes"
          kubectl -n ${module.vault.namespace} get pod ${module.vault.pod_name} -o wide || true
          kubectl -n ${module.vault.namespace} describe pod ${module.vault.pod_name} | tail -40 || true
          kubectl -n ${module.vault.namespace} logs ${module.vault.pod_name} --tail 50 || true
          exit 1
        fi
        echo "waiting for ${module.vault.pod_name} to run vault status"
        sleep 10
      done

      INITIALISED=$(printf '%s' "$VAULT_STATUS" | jq -r '.initialized')
      if [ "$INITIALISED" != "true" ]; then
        kubectl -n ${module.vault.namespace} exec ${module.vault.pod_name} -- \
          vault operator init -key-shares=1 -key-threshold=1 -format=json > /home/ec2-user/vault_init.json
      fi

      # Initialised but with no init output on disk means the keys were minted on an instance that no
      # longer exists, or the file was removed. There is no way to recover the unseal key from Vault,
      # so say so rather than failing inside jq with "Cannot index null".
      if [ ! -s /home/ec2-user/vault_init.json ]; then
        echo "vault reports initialised but /home/ec2-user/vault_init.json is missing, so the unseal key is gone."
        echo "Delete the release and its PVC to start from an uninitialised Vault:"
        echo "  helm uninstall ${module.vault.release_name} -n ${module.vault.namespace}"
        echo "  kubectl -n ${module.vault.namespace} delete pvc --all"
        exit 1
      fi

      ROOT_TOKEN=$(jq -r '.root_token' /home/ec2-user/vault_init.json)
      UNSEAL_KEY=$(jq -r '.unseal_keys_b64[0]' /home/ec2-user/vault_init.json)

      # Unsealing is what the _monolithic template left out. Vault is sealed straight after init, and
      # a sealed server rejects every command below. Read again rather than reusing VAULT_STATUS,
      # because the init above changed it.
      #
      # Captured in two steps rather than piped straight into jq with a "|| echo true" fallback.
      # vault status exits 2 when sealed, and with pipefail set that makes the whole pipeline count
      # as failed - so the fallback fired *in addition to* jq's own output and SEALED became the
      # two-line string "true\ntrue". That matches neither branch, so the unseal was skipped in
      # silence and Vault was left initialised and sealed. Guarding the command instead of the
      # pipeline keeps the exit code out of the captured value:
      #
      #   SEALED=[true
      #   true] -> SKIPPED-UNSEAL
      VAULT_STATUS=$(kubectl -n ${module.vault.namespace} exec ${module.vault.pod_name} -- vault status -format=json 2>/dev/null || true)
      SEALED=$(printf '%s' "$VAULT_STATUS" | jq -r '.sealed')
      if [ "$SEALED" = "true" ]; then
        kubectl -n ${module.vault.namespace} exec ${module.vault.pod_name} -- vault operator unseal "$UNSEAL_KEY" > /dev/null
      fi

      # No -i on this exec or the next one, and that matters far more than it looks.
      #
      # This block is the body of the `sudo -Eu ec2-user bash << 'STEP'` heredoc above, so the
      # shell's stdin *is* the remainder of this script. kubectl exec -i attaches that stdin to the
      # container and reads it to EOF, consuming every line below - the shell then has nothing left
      # to run and exits 0. The association reported Success in 3.3 seconds while the secrets engine,
      # the demo secret, the Argo CD Secret and the repo-server restart had all silently never
      # happened. Verified by putting `echo AFTER` after an `exec -i` in the same heredoc shape: it
      # never printed.
      #
      # Nothing here needs stdin. The token travels in the environment of the in-pod process, which
      # does place it in that pod's argv - the env prefix does not hide it, and an earlier comment
      # here claimed otherwise.
      kubectl -n ${module.vault.namespace} exec ${module.vault.pod_name} -- \
        env VAULT_TOKEN="$ROOT_TOKEN" vault secrets enable -path=${var.vault_secrets_engine_path} kv-v2 2>/dev/null || true
      # The demo password is fetched from Secrets Manager rather than interpolated into this script.
      # Terraform marks it sensitive so it never reaches plan output, but an SSM association stores
      # its parameters in AWS - and "aws ssm describe-association" would hand the value to anyone
      # with that permission. Only the secret's name travels in this command.
      DEMO_PASSWORD=$(aws secretsmanager get-secret-value \
        --secret-id ${aws_secretsmanager_secret.vault_demo.id} \
        --query SecretString --output text)
      kubectl -n ${module.vault.namespace} exec ${module.vault.pod_name} -- \
        env VAULT_TOKEN="$ROOT_TOKEN" vault kv put ${var.vault_secrets_engine_path}/${var.vault_demo_secret_name} \
        user='${var.vault_demo_secret_user}' password="$DEMO_PASSWORD" > /dev/null

      # The Secret the plugin reads. Applied from stdin so the token is never written to a file in
      # the home directory code-server serves.
      kubectl apply -f - << 'TFSECRET'
      apiVersion: v1
      kind: Secret
      metadata:
        name: ${module.argocd.vault_secret_name}
        namespace: ${module.argocd.namespace}
      type: Opaque
      stringData:
        VAULT_ADDR: ${module.vault.internal_address}
        VAULT_TOKEN: PLACEHOLDER
        AVP_AUTH_TYPE: token
        AVP_TYPE: vault
      TFSECRET
      kubectl -n ${module.argocd.namespace} patch secret ${module.argocd.vault_secret_name} \
        --type merge -p "{\"stringData\":{\"VAULT_TOKEN\":\"$ROOT_TOKEN\"}}" > /dev/null

      # The repo-server caches plugin state, so it has to be restarted to pick up a Secret that
      # did not exist when it started.
      kubectl -n ${module.argocd.namespace} rollout restart deployment ${module.argocd.release_name}-repo-server
      kubectl -n ${module.argocd.namespace} rollout status deployment ${module.argocd.release_name}-repo-server --timeout=600s
      STEP
      touch ${module.vscode_ec2.marker_file_path}/vault_bootstrap
      EOT
  }

  # Both releases have to be installed before this runs: it execs into Vault's pod and writes a
  # Secret into Argo CD's namespace, and neither exists earlier (rules.md D-2). The secret version
  # has to exist too - the script reads it, and referencing only the secret's id would order this
  # after the container but not after its contents (rules.md D-1).
  depends_on = [
    module.vault,
    module.argocd,
    aws_secretsmanager_secret_version.vault_demo,
  ]
}
locals {
  # The seed repository's manifests, defined as HCL objects and rendered with yamlencode rather
  # than pasted as YAML strings (rules.md E-3). They are files in a Git repository rather than
  # objects to apply, so they are written to disk instead of becoming kubectl_manifest resources -
  # Argo CD is what applies them, which is the whole point of the demo.
  #
  # The <path:...> placeholders are argocd-vault-plugin syntax, resolved by the plugin at sync
  # time from the kv engine the bootstrap step above populates. The path is built from the same
  # variables the bootstrap uses, so the manifest and the secret cannot disagree (rules.md B-5).
  seed_manifests = {
    "deployment.yaml" = yamlencode({
      apiVersion = "apps/v1"
      kind       = "Deployment"
      metadata = {
        name   = "nginx-deploy"
        labels = { app = "nginx" }
      }
      spec = {
        replicas = 3
        selector = { matchLabels = { app = "nginx" } }
        template = {
          metadata = { labels = { app = "nginx" } }
          spec = {
            containers = [{
              name  = "nginx"
              image = var.seed_workload_image
              env = [
                { name = "ADMIN_USER", value = "<path:${var.vault_secrets_engine_path}/data/${var.vault_demo_secret_name}#user>" },
                { name = "ADMIN_PASSWORD", value = "<path:${var.vault_secrets_engine_path}/data/${var.vault_demo_secret_name}#password>" },
              ]
            }]
          }
        }
      }
    })
    "service.yaml" = yamlencode({
      apiVersion = "v1"
      kind       = "Service"
      metadata   = { name = "nginx-service" }
      spec = {
        selector = { app = "nginx" }
        ports    = [{ protocol = "TCP", port = 80, targetPort = 80 }]
      }
    })
  }
  # Written with a quoted delimiter and cannot contain it: Terraform has already substituted every
  # value, so the shell has no reason to touch a "$" or a backtick. The dedent of <<-EOT is
  # computed from the template's own lines, so an interpolated multi-line value lands at column 0
  # and these terminators close where they look like they do (rules.md E-9).
  seed_file_commands = join("\n", [
    for filename, body in local.seed_manifests :
    "cat > /home/ec2-user/${var.github_repo}/${var.github_manifest_path}/${filename} << 'TFSEED'\n${body}\nTFSEED"
  ])
}
# Writes the seed repository onto the instance and uploads it to the bucket, as the _monolithic
# template's first association did. Kept because nothing consumes the bucket yet but the seed
# manifests are what Argo CD is pointed at, so they have to exist somewhere a human can push them
# from.
resource "aws_ssm_association" "github_seed" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.github_seed_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # Second in the marker chain: it waits for the bootstrap rather than only for userdata, so the
    # three associations run in a known order on one instance rather than concurrently
    # (rules.md D-5).
    commands = <<-EOT
      set -euo pipefail
      until [ -f ${module.vscode_ec2.marker_file_path}/vault_bootstrap ]; do sleep 10; done
      sudo -Eu ec2-user bash << 'STEP'
      set -euo pipefail
      export HOME=/home/ec2-user
      mkdir -p /home/ec2-user/${var.github_repo}/${var.github_manifest_path}
      cd /home/ec2-user/${var.github_repo}
      ${local.seed_file_commands}
      zip -qr /home/ec2-user/src.zip .
      aws s3 cp /home/ec2-user/src.zip s3://${module.github_source.bucket_name}/src.zip
      STEP
      touch ${module.vscode_ec2.marker_file_path}/github_seed
      EOT
  }

  # Both halves of rules.md D-5, and they do different jobs. The marker loop above proves the
  # previous step's remote command finished, which depends_on cannot observe. depends_on decides when
  # this resource is *created*, and that is what starts its wait_for_success_timeout_seconds clock -
  # without it Terraform creates all three associations at once, so this one spends its whole timeout
  # sitting in the until loop while the bootstrap step is still running, and fails with a timeout
  # that has nothing to do with its own work.
  depends_on = [
    module.github_source,
    module.vscode_ec2,
    aws_ssm_association.vault_bootstrap,
  ]
}
locals {
  # Every output this project exposes, defined once. outputs.tf projects these and the README below
  # renders them, so no value expression is written twice (rules.md B-5/H-2). Adding an entry here
  # is what makes an output possible, which is what keeps the README from falling behind
  # outputs.tf.
  #
  # Nothing here carries Vault's root token, Argo CD's admin password, the GitHub token or the demo
  # secret. Every entry is rendered into a README on an instance whose code-server has no
  # authentication, so a secret here would be readable by anyone who can reach it (rules.md H-2).
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here. The kubectl and argocd commands below are meant to be run from its terminal"
      value       = module.vscode_ec2.vscode_url
    }
    cluster_name = {
      order       = 2
      title       = "EKS cluster name"
      description = "Name of the EKS cluster. The AWS Load Balancer Controller also writes this into the elbv2.k8s.aws/cluster tag it uses to find load balancers it owns"
      value       = module.eks_cluster.cluster_name
    }
    argocd_url = {
      order       = 3
      title       = "Argo CD UI"
      description = "Served through the pre-created NLB the controller adopts from the server Service, so the address is known from state at apply time (rules.md G-3). Log in as admin with the password from the command below"
      value       = module.argocd_load_balancer.url
    }
    argocd_password_command = {
      order       = 4
      title       = "Argo CD admin password"
      description = "Generated by the chart and read back from its Secret. A command rather than a value, because this README is served by a code-server with no authentication in front of it (rules.md H-2)"
      value       = module.argocd.initial_password_command
    }
    vault_url = {
      order       = 5
      title       = "Vault UI"
      description = "Served through the pre-created ALB the controller adopts from Vault's Ingress. The _monolithic template set the chart's ingress values at the top level, where the chart ignored them - so this Ingress never existed and this load balancer was never adopted"
      value       = module.vault_load_balancer.url
    }
    vault_token_command = {
      order       = 6
      title       = "Vault root token and unseal key"
      description = "Both are in the init output the bootstrap step left on the instance with umask 077. Needed to log into the Vault UI, and to unseal again after any restart of the Vault pod - this demo uses a single key share, so a restart leaves Vault sealed"
      value       = "sudo -u ec2-user jq -r '{root_token, unseal_key: .unseal_keys_b64[0]}' /home/ec2-user/vault_init.json"
    }
    vault_status_command = {
      order       = 7
      title       = "1. Confirm Vault is initialised and unsealed"
      description = "Both have to be true before the plugin can read anything. Sealed after a pod restart is expected rather than a fault - unseal it with the key above"
      value       = module.vault.status_command
    }
    argocd_repo_server_command = {
      order       = 8
      title       = "2. Confirm the repo-server came up with the plugin"
      description = "The pod that carries the argocd-vault-plugin sidecar. Its init container pulls the plugin binary over the internet, so it is the slowest part of the install"
      value       = module.argocd.repo_server_rollout_command
    }
    argocd_plugin_logs_command = {
      order       = 9
      title       = "3. Read the plugin log if a sync fails"
      description = "Where a token that was never written, or a Secret the Role does not grant, explains itself. Neither is a Terraform error - every object applied successfully"
      value       = module.argocd.plugin_logs_command
    }
    adopted_load_balancer_check_command = {
      order       = 10
      title       = "4. Confirm both load balancers were adopted, not duplicated"
      description = "Lists every load balancer tagged for this cluster. Two is correct here - one ALB for Vault and one NLB for Argo CD. Three or four means a tag mismatch and the controller built its own, which raises no error (rules.md G-3)"
      value       = "aws resourcegroupstaggingapi get-resources --tag-filters Key=elbv2.k8s.aws/cluster,Values=${module.eks_cluster.cluster_name} --resource-type-filters elasticloadbalancing:loadbalancer --query 'ResourceTagMappingList[].ResourceARN' --output table"
    }
    argocd_app_create_command = {
      order       = 11
      title       = "5. Create the Application that uses the plugin"
      description = "Points Argo CD at the seed repository and asks for the plugin by name. The repository and its manifests are created by this configuration, so nothing has to be pushed by hand first - the URL comes from the module that created it rather than being rebuilt from the user and repo variables (rules.md B-5). Run \"argocd login\" first; the URL above works without --insecure because the server serves plain HTTP"
      value       = "argocd app create argo-app --sync-policy automated --self-heal --repo ${module.github_seed_repository.clone_url} --path ${var.github_manifest_path} --dest-server https://kubernetes.default.svc --dest-namespace default --config-management-plugin ${module.argocd.plugin_name}"
    }
    seed_repo_path = {
      order       = 12
      title       = "Seed manifests"
      description = "Written here by the seed step and uploaded to the bucket below. The deployment's ADMIN_USER and ADMIN_PASSWORD are argocd-vault-plugin placeholders resolved from Vault at sync time - which is what the demo shows"
      value       = "/home/ec2-user/${var.github_repo}/${var.github_manifest_path}"
    }
    source_bucket = {
      order       = 13
      title       = "Source bucket"
      description = "Where the seed repository zip is uploaded. Nothing consumes it yet: there is no CodeBuild project or pipeline in this project, so it is scaffolding for a CI half that was never built"
      value       = module.github_source.bucket_name
    }
    codestar_connection_status = {
      order       = 14
      title       = "CodeStar connection"
      description = "Created in PENDING and usable only after the GitHub handshake is completed in the console at https://console.aws.amazon.com/codesuite/settings/connections. Terraform reports the apply as successful either way, which is why this is surfaced"
      value       = "${module.github_source.connection_arn} (${module.github_source.connection_status})"
    }
    update_kubeconfig_command = {
      order       = 15
      title       = "Re-point kubectl"
      description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
    storage_class_name = {
      order       = 18
      title       = "StorageClass"
      description = "The class Vault's data volume is provisioned from. Named explicitly in the claim rather than resolved through the default annotation, because a fresh EKS cluster has no default class - its built-in gp2 uses the in-tree provisioner removed in Kubernetes 1.23"
      value       = module.csi_storage_classes.storage_class_name
    }
    storage_class_check_command = {
      order       = 19
      title       = "Verify the StorageClass"
      description = "Expect a gp3 line with provisioner ebs.csi.aws.com marked (default). The gp2 line above it is EKS's own, and its kubernetes.io/aws-ebs provisioner has provisioned nothing since Kubernetes 1.23"
      value       = module.csi_storage_classes.storage_class_check_command
    }
    seed_repository_url = {
      order       = 16
      title       = "Seed repository"
      description = "The Git repository Argo CD syncs from, created by this configuration. Nothing created it before, so the application created by the command above pointed at a repository that did not exist. Note that terraform destroy deletes it"
      value       = module.github_seed_repository.html_url
    }
    seed_repository_files = {
      order       = 17
      title       = "Committed manifests"
      description = "What was committed, and on which branch. An Argo CD application stuck on \"directory contains no manifests\" is usually its --path not matching these paths, or the application tracking a different branch"
      value       = "${module.github_seed_repository.default_branch}: ${join(", ", module.github_seed_repository.committed_files)}"
    }
    pending_claims_command = {
      order       = 20
      title       = "Check the volume bound"
      description = "data-vault-0 should be Bound to the gp3 class. Pending with an empty STORAGECLASS column means the claim resolved to no class at all, which leaves vault-0 unschedulable and fails the bootstrap step with nothing in its own log to explain it"
      value       = module.csi_storage_classes.pending_claims_command
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
# (rules.md H-2). Combining several modules' outputs is the root's job, so this lives here rather
# than inside the instance module.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # Last in the marker chain, so it waits for the seed step - which itself waited for the
    # bootstrap. Ordering on markers rather than depends_on is what makes that reliable
    # (rules.md D-5).
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/github_seed ]; do sleep 10; done
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_readme
      EOT
  }

  # Ordered after the step whose marker the loop above waits for, so this resource is not created -
  # and its timeout clock not started - until that step has already succeeded. Without it Terraform
  # creates every association concurrently and this one exhausts its whole timeout in the until loop,
  # reporting "timeout while waiting for state to become 'Success' (last state: 'Pending')" about a
  # command that never ran (rules.md D-5).
  depends_on = [aws_ssm_association.github_seed]
}
