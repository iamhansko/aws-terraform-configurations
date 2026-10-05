data "aws_region" "current" {}
locals {
  # Three names from one prefix, so the set cannot be named inconsistently (rules.md B-1).
  imds_cluster_name         = "${var.cluster_name_prefix}-imds"
  irsa_cluster_name         = "${var.cluster_name_prefix}-irsa"
  pod_identity_cluster_name = "${var.cluster_name_prefix}-pod-identity"
  # The policy all three mechanisms are measured against: read one bucket, nothing else. The _monolithic
  # template attached AmazonS3FullAccess to the IRSA and Pod Identity roles, which is access to every
  # bucket in the account for a demo that reads one (rules.md A-5).
  bucket_read_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # ListBucket is granted on the bucket itself, while GetObject is granted on its contents. The two
        # take different ARN forms, and swapping them produces a role that can read an object it cannot
        # find or find one it cannot read - neither of which says what went wrong.
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = module.demo_bucket.bucket_arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = module.demo_bucket.object_arn_pattern
      },
      {
        # s3:ListAllMyBuckets is what a bare "aws s3 ls" with no bucket needs, and it is account-wide by
        # definition - there is no narrower form. Granted so the demo command can be the simple one; the
        # listing it produces is names only.
        Effect   = "Allow"
        Action   = ["s3:ListAllMyBuckets"]
        Resource = "*"
      },
    ]
  })
}
# One VPC for all three clusters, as the _monolithic template had it - which removes the network as a
# variable in a comparison meant to have one, and pays for one set of NAT gateways rather than three.
module "network" {
  source = "./modules/network"

  vpc_name                 = "${var.cluster_name_prefix}-vpc"
  internet_gateway_name    = "${var.cluster_name_prefix}-igw"
  public_subnet_name       = "${var.cluster_name_prefix}-public"
  private_subnet_name      = "${var.cluster_name_prefix}-private"
  public_route_table_name  = "${var.cluster_name_prefix}-public-rt"
  private_route_table_name = "${var.cluster_name_prefix}-private-rt"
  nat_gateway_name         = "${var.cluster_name_prefix}-natgw"
  # No subnet tags: nothing here creates a load balancer (rules.md G-1).
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name = var.key_name

  # key_pair consumes no network output, so nothing would otherwise order it against the network module's
  # resources (rules.md D-3).
  depends_on = [module.network]
}
# What every identity is measured against: one bucket with one object in it.
module "demo_bucket" {
  source = "./modules/demo_bucket"

  bucket_name = var.bucket_name

  depends_on = [module.network]
}
# ---------------------------------------------------------------------------------------------------
# Cluster one: credentials from the instance metadata service.
#
# Nothing is configured for this. The pod's service account carries no annotation, there is no
# association, and the AWS SDK inside the pod falls through to 169.254.169.254 and gets the node's
# instance role. The only thing that has to be true is the node's IMDS hop limit being at least two,
# because a pod is one hop further away than the node itself.
# ---------------------------------------------------------------------------------------------------
module "imds_eks_cluster" {
  source = "./modules/eks_cluster"

  name                   = local.imds_cluster_name
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  # Referencing module.network.*_subnet_ids only orders this after the specific aws_subnet resources
  # behind those outputs, not after the NAT gateways and route table associations that never surface as
  # outputs (rules.md D-3).
  depends_on = [module.network]
}
module "imds_eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.imds_eks_cluster.cluster_name

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not exist until this addon
  # creates it. As a DaemonSet it reaches ACTIVE with zero nodes, so it comes before any capacity - and
  # nodes need it to join Ready (rules.md C-4).
  depends_on = [module.network, module.imds_eks_cluster]
}
module "imds_eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.imds_eks_cluster.cluster_name

  depends_on = [module.network, module.imds_eks_vpc_cni_addon]
}
module "imds_eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name    = module.imds_eks_cluster.cluster_name
  node_group_name = var.node_group_name
  instance_types  = var.node_group_instance_types
  desired_size    = var.node_group_size
  min_size        = var.node_group_size
  max_size        = var.node_group_size
  subnet_ids      = module.network.private_subnet_ids
  key_name        = module.key_pair.key_name
  # The setting the whole IMDS demonstration rests on. At one, a pod's request to the metadata service is
  # dropped before it leaves the node and the mechanism does not work at all.
  instance_metadata_http_put_response_hop_limit = var.imds_hop_limit

  depends_on = [module.network, module.imds_eks_vpc_cni_addon, module.imds_eks_kube_proxy_addon]
}
module "imds_eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.imds_eks_cluster.cluster_name

  # coredns is a Deployment and needs schedulable capacity to leave DEGRADED and become ACTIVE
  # (rules.md C-4). The pod also resolves the STS and S3 endpoints through it.
  depends_on = [
  module.network, module.imds_eks_node_group]
}
module "imds_cli_pod" {
  source = "./modules/aws_cli_pod"
  providers = {
    kubectl = kubectl.imds
  }

  name      = var.pod_name
  namespace = var.pod_namespace
  # No role annotation and no association. The pod is meant to fall through to the node's credentials,
  # and the absence of both is what makes that happen (rules.md B-4).
  service_account_name = var.service_account_name
  image                = var.pod_image
  credential_mechanism = "imds"

  depends_on = [
  module.network, module.imds_eks_node_group, module.imds_eks_coredns_addon]
}
# ---------------------------------------------------------------------------------------------------
# Cluster two: IAM Roles for Service Accounts.
#
# The role's trust policy names this cluster's OIDC issuer and one service account inside it, and the
# service account carries the role's ARN as an annotation. The pod's SDK exchanges a projected token for
# the role's credentials.
#
# Because the trust policy names the issuer, the role belongs to this cluster and cannot be reused by
# another - which is the difference from Pod Identity below, and the reason a cluster rebuild means a new
# role.
# ---------------------------------------------------------------------------------------------------
module "irsa_eks_cluster" {
  source = "./modules/eks_cluster"

  name                   = local.irsa_cluster_name
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  depends_on = [module.network]
}
module "irsa_eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.irsa_eks_cluster.cluster_name

  depends_on = [module.network, module.irsa_eks_cluster]
}
module "irsa_eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.irsa_eks_cluster.cluster_name

  depends_on = [module.network, module.irsa_eks_vpc_cni_addon]
}
module "irsa_eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name    = module.irsa_eks_cluster.cluster_name
  node_group_name = var.node_group_name
  instance_types  = var.node_group_instance_types
  desired_size    = var.node_group_size
  min_size        = var.node_group_size
  max_size        = var.node_group_size
  subnet_ids      = module.network.private_subnet_ids
  key_name        = module.key_pair.key_name
  # The same hop limit as the IMDS cluster, deliberately. Leaving IRSA's nodes at one would make this
  # cluster differ in two ways rather than one, and the fallback that hides a broken IRSA setup would be
  # closed here and open there.
  instance_metadata_http_put_response_hop_limit = var.imds_hop_limit

  depends_on = [module.network, module.irsa_eks_vpc_cni_addon, module.irsa_eks_kube_proxy_addon]
}
module "irsa_eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.irsa_eks_cluster.cluster_name

  depends_on = [
  module.network, module.irsa_eks_node_group]
}
# The role IRSA hands out. Created in the root because it joins two modules that know nothing about each
# other: the cluster's OIDC issuer and the bucket's ARN (rules.md C-1).
resource "aws_iam_role" "irsa" {
  name_prefix = "${var.cluster_name_prefix}-irsa-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = module.irsa_eks_cluster.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          # Both conditions matter. Without sub, any service account in the cluster could assume the role;
          # without aud, a token minted for a different audience would be accepted. The issuer host in the
          # key names this cluster, which is what ties the role to it.
          "${module.irsa_eks_cluster.oidc_issuer_host}:sub" = "system:serviceaccount:${var.pod_namespace}:${var.service_account_name}"
          "${module.irsa_eks_cluster.oidc_issuer_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}
resource "aws_iam_role_policy" "irsa" {
  name   = "demo-bucket-read"
  role   = aws_iam_role.irsa.name
  policy = local.bucket_read_policy
}
module "irsa_cli_pod" {
  source = "./modules/aws_cli_pod"
  providers = {
    kubectl = kubectl.irsa
  }

  name                 = var.pod_name
  namespace            = var.pod_namespace
  service_account_name = var.service_account_name
  image                = var.pod_image
  credential_mechanism = "irsa"
  # The one line that makes this cluster different from the IMDS one on the Kubernetes side. The
  # _monolithic template added it with a separate kubectl annotate call after applying the account
  # (rules.md E-5).
  role_arn_annotation = aws_iam_role.irsa.arn

  # The role has to carry its policy before the pod uses it, and the annotation referencing the ARN does
  # not order this after the policy (rules.md D-1). A pod that assumes the role too early gets credentials
  # with no permissions, which looks like the wrong role rather than a race.
  depends_on = [
    module.network,
    module.irsa_eks_node_group,
    module.irsa_eks_coredns_addon,
    aws_iam_role_policy.irsa,
  ]
}
# ---------------------------------------------------------------------------------------------------
# Cluster three: EKS Pod Identity.
#
# The role's trust policy names no cluster and no issuer - just the Pod Identity service - and which
# service account may use it is an AWS-side association instead. So the same role works on any cluster,
# and there is nothing to annotate on the Kubernetes side.
#
# It needs the eks-pod-identity-agent addon, which is the only component any of these three clusters has
# that the others do not. That is not an inconsistency in the comparison: the agent is this mechanism.
# ---------------------------------------------------------------------------------------------------
module "pod_identity_eks_cluster" {
  source = "./modules/eks_cluster"

  name                   = local.pod_identity_cluster_name
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  depends_on = [module.network]
}
module "pod_identity_eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.pod_identity_eks_cluster.cluster_name

  depends_on = [module.network, module.pod_identity_eks_cluster]
}
module "pod_identity_eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.pod_identity_eks_cluster.cluster_name

  depends_on = [module.network, module.pod_identity_eks_vpc_cni_addon]
}
# The mechanism itself. A DaemonSet, so it reaches ACTIVE with no nodes - but no pod gets Pod Identity
# credentials until it is actually running on that pod's node (rules.md C-4).
module "pod_identity_agent_addon" {
  source = "./modules/eks_pod_identity_agent_addon"

  cluster_name = module.pod_identity_eks_cluster.cluster_name

  depends_on = [module.network, module.pod_identity_eks_cluster]
}
module "pod_identity_eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name    = module.pod_identity_eks_cluster.cluster_name
  node_group_name = var.node_group_name
  instance_types  = var.node_group_instance_types
  desired_size    = var.node_group_size
  min_size        = var.node_group_size
  max_size        = var.node_group_size
  subnet_ids      = module.network.private_subnet_ids
  key_name        = module.key_pair.key_name
  # Same as the other two, for the same reason.
  instance_metadata_http_put_response_hop_limit = var.imds_hop_limit

  depends_on = [module.network, module.pod_identity_eks_vpc_cni_addon, module.pod_identity_eks_kube_proxy_addon]
}
module "pod_identity_eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.pod_identity_eks_cluster.cluster_name

  depends_on = [
  module.network, module.pod_identity_eks_node_group]
}
# The role Pod Identity hands out. Note what is not in the trust policy: no issuer, no cluster, no
# namespace and no service account. All of that lives in the association below, which is why this role
# would work unchanged on a cluster rebuilt tomorrow.
resource "aws_iam_role" "pod_identity" {
  name_prefix = "${var.cluster_name_prefix}-pod-identity-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      # TagSession as well as AssumeRole. Pod Identity attaches session tags naming the cluster, namespace
      # and service account, and without this action the exchange fails with an error about tagging rather
      # than about trust - which is not where anyone looks first.
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}
resource "aws_iam_role_policy" "pod_identity" {
  name   = "demo-bucket-read"
  role   = aws_iam_role.pod_identity.name
  policy = local.bucket_read_policy
}
# What the IRSA cluster expresses as a service account annotation, expressed on the AWS side instead.
resource "aws_eks_pod_identity_association" "cli" {
  cluster_name    = module.pod_identity_eks_cluster.cluster_name
  namespace       = var.pod_namespace
  service_account = var.service_account_name
  role_arn        = aws_iam_role.pod_identity.arn

  # The policy has to be attached before a pod uses the role, and nothing else orders that
  # (rules.md D-1).
  depends_on = [aws_iam_role_policy.pod_identity]
}
module "pod_identity_cli_pod" {
  source = "./modules/aws_cli_pod"
  providers = {
    kubectl = kubectl.pod_identity
  }

  name      = var.pod_name
  namespace = var.pod_namespace
  # No annotation, deliberately: this cluster's binding is the association above. An annotated account
  # here would work too - IRSA and Pod Identity can coexist, with Pod Identity taking precedence - and
  # leaving it off is what makes the comparison honest.
  service_account_name = var.service_account_name
  image                = var.pod_image
  credential_mechanism = "pod_identity"

  # The agent has to be running on the node before the pod can get credentials from it, and the
  # association has to exist (rules.md D-2).
  depends_on = [
    module.network,
    module.pod_identity_eks_node_group,
    module.pod_identity_eks_coredns_addon,
    module.pod_identity_agent_addon,
    aws_eks_pod_identity_association.cli,
  ]
}
# ---------------------------------------------------------------------------------------------------
# Optionally, the same bucket access on the node role.
#
# Off by default, and the off state is the lesson: the IMDS pod gets the node's identity, which has no S3
# permissions, so its listing is denied while the other two succeed. Turning it on makes all three
# succeed - and grants the access to every pod on every node of all three clusters at once, because they
# share one node role. That is the argument for the other two mechanisms, made concrete.
# ---------------------------------------------------------------------------------------------------
resource "aws_iam_role_policy" "imds_node_bucket_read" {
  count = var.grant_node_role_bucket_access ? 1 : 0

  name   = "demo-bucket-read"
  role   = module.imds_eks_node_group.node_role_name
  policy = local.bucket_read_policy
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  marker_file_path            = var.marker_file_path
  # All three clusters' security groups, so this instance can reach every API server. The module is handed
  # an ID list and never learns what they belong to (rules.md B-6).
  extra_security_group_ids = [
    module.imds_eks_cluster.cluster_security_group_id,
    module.irsa_eks_cluster.cluster_security_group_id,
    module.pod_identity_eks_cluster.cluster_security_group_id,
  ]

  # Three EKS clusters and this instance share a root module, so it is the workbench for all of them and
  # carries all five tools (rules.md H-1). None of them creates anything: the service accounts, the pods
  # and the IRSA annotation the _monolithic template applied from here are Terraform resources now
  # (rules.md E-1).
  #
  # Bugs from that template that are not carried over. It ran "exec bash" partway through, which replaces
  # the shell and silently discarded every remaining line - eksctl, helm, all three update-kubeconfig
  # calls and every manifest were after it, so on a real boot none of the three clusters had a pod in it.
  # It pulled eksctl from weaveworks rather than eksctl-io, and get-helm-3 rather than the current script.
  # And it wrote the "complete" line for the k alias into .bashrc before the line that defines
  # __start_kubectl, so every login printed a "function not found" error (rules.md H-1).
  additional_user_data = <<-EOT
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server is already running and predates the docker group, so its terminals would not have it
    # without a restart.
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
    # Order matters: kubectl's completion defines __start_kubectl, and that has to exist before complete
    # names it, or every login prints "function not found" (rules.md H-1).
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
    # One context per cluster, each named after it. Running the same command against all three is the
    # whole demo, so the names have to differ.
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.imds_eks_cluster.cluster_name} --alias ${module.imds_eks_cluster.cluster_name}
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.irsa_eks_cluster.cluster_name} --alias ${module.irsa_eks_cluster.cluster_name}
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.pod_identity_eks_cluster.cluster_name} --alias ${module.pod_identity_eks_cluster.cluster_name}
    EOF
  EOT

  depends_on = [module.network]
}
# Granting the bastion's instance role access to each cluster joins modules that know nothing about each
# other, so it belongs in the root (rules.md C-1). One entry and one association per cluster: access is
# granted on a cluster, not on a principal.
resource "aws_eks_access_entry" "imds_vscode" {
  cluster_name  = module.imds_eks_cluster.cluster_name
  principal_arn = module.vscode_ec2.iam_role_arn
  type          = "STANDARD"
}
resource "aws_eks_access_policy_association" "imds_vscode" {
  cluster_name  = module.imds_eks_cluster.cluster_name
  principal_arn = module.vscode_ec2.iam_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.imds_vscode]
}
resource "aws_eks_access_entry" "irsa_vscode" {
  cluster_name  = module.irsa_eks_cluster.cluster_name
  principal_arn = module.vscode_ec2.iam_role_arn
  type          = "STANDARD"
}
resource "aws_eks_access_policy_association" "irsa_vscode" {
  cluster_name  = module.irsa_eks_cluster.cluster_name
  principal_arn = module.vscode_ec2.iam_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.irsa_vscode]
}
resource "aws_eks_access_entry" "pod_identity_vscode" {
  cluster_name  = module.pod_identity_eks_cluster.cluster_name
  principal_arn = module.vscode_ec2.iam_role_arn
  type          = "STANDARD"
}
resource "aws_eks_access_policy_association" "pod_identity_vscode" {
  cluster_name  = module.pod_identity_eks_cluster.cluster_name
  principal_arn = module.vscode_ec2.iam_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.pod_identity_vscode]
}
locals {
  # Every output this project exposes, defined once. outputs.tf projects these and the README below
  # renders them, so no value expression is written twice (rules.md B-5/H-2).
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here. Its kubeconfig has one context per cluster, named after the cluster - the demo is running the same command against all three with \"kubectl --context <name>\""
      value       = module.vscode_ec2.vscode_url
    }
    clusters = {
      order       = 2
      title       = "The three clusters"
      description = "Identical except for how the pod gets its credentials. Same VPC, same Kubernetes version, same node type and count, same pod - even the same IMDS hop limit, so nothing is closed on one cluster that is open on another"
      value       = "${module.imds_eks_cluster.cluster_name}: nothing configured, the SDK falls through to the node's instance role\n${module.irsa_eks_cluster.cluster_name}: the service account carries a role ARN annotation, the SDK exchanges a projected token\n${module.pod_identity_eks_cluster.cluster_name}: an AWS-side association names the service account, the agent supplies credentials"
    }
    roles = {
      order       = 3
      title       = "The roles each mechanism hands out"
      description = "Both scoped to reading one bucket, where the _monolithic template attached AmazonS3FullAccess - access to every bucket in the account for a demo that reads one. The IMDS cluster has no role of its own at all: its pod gets the node's, which is the point"
      value       = "IRSA: ${aws_iam_role.irsa.arn}\nPod Identity: ${aws_iam_role.pod_identity.arn}\nIMDS: none - the pod uses the node role ${module.imds_eks_node_group.node_role_arn}"
    }
    demo_bucket = {
      order       = 4
      title       = "The bucket every identity is measured against"
      description = "One bucket with one object in it. The object matters: an empty bucket makes a successful listing print nothing, which is indistinguishable from a denial the CLI swallowed"
      value       = "${module.demo_bucket.bucket_name} containing ${join(", ", module.demo_bucket.object_keys)}"
    }
    identity_commands = {
      order       = 5
      title       = "1. Ask each pod who it is"
      description = "The demo, in three commands. The IMDS pod prints the node's instance role; the other two print roles named after their mechanism. All three pods are byte-for-byte identical manifests, which is what makes this worth doing"
      value       = "kubectl --context ${module.imds_eks_cluster.cluster_name} ${trimprefix(module.imds_cli_pod.identity_command, "kubectl ")}\nkubectl --context ${module.irsa_eks_cluster.cluster_name} ${trimprefix(module.irsa_cli_pod.identity_command, "kubectl ")}\nkubectl --context ${module.pod_identity_eks_cluster.cluster_name} ${trimprefix(module.pod_identity_cli_pod.identity_command, "kubectl ")}"
    }
    credential_source_commands = {
      order       = 6
      title       = "2. Ask each pod how it got there"
      description = "How the credentials arrive rather than which ones. IRSA shows AWS_ROLE_ARN and AWS_WEB_IDENTITY_TOKEN_FILE, injected by the cluster's webhook; Pod Identity shows AWS_CONTAINER_CREDENTIALS_FULL_URI, injected by EKS; the IMDS pod shows nothing at all, because nothing was injected and the SDK simply fell through"
      value       = "kubectl --context ${module.imds_eks_cluster.cluster_name} ${trimprefix(module.imds_cli_pod.credential_source_command, "kubectl ")}\nkubectl --context ${module.irsa_eks_cluster.cluster_name} ${trimprefix(module.irsa_cli_pod.credential_source_command, "kubectl ")}\nkubectl --context ${module.pod_identity_eks_cluster.cluster_name} ${trimprefix(module.pod_identity_cli_pod.credential_source_command, "kubectl ")}"
    }
    bucket_access_commands = {
      order       = 7
      title       = "3. See which identity can actually do something"
      description = "Two of the three list the bucket. The IMDS pod is denied, because the node role has no S3 permissions - which is not a fault but the security argument: those credentials belong to the node and are shared by every pod on it"
      value       = "kubectl --context ${module.imds_eks_cluster.cluster_name} ${trimprefix(module.imds_cli_pod.bucket_access_command, "kubectl ")}\nkubectl --context ${module.irsa_eks_cluster.cluster_name} ${trimprefix(module.irsa_cli_pod.bucket_access_command, "kubectl ")}\nkubectl --context ${module.pod_identity_eks_cluster.cluster_name} ${trimprefix(module.pod_identity_cli_pod.bucket_access_command, "kubectl ")}"
    }
    node_role_grant_command = {
      order       = 8
      title       = "4. Make the IMDS pod succeed, and notice what that costs"
      description = "Grants the same bucket access to the node role, so the IMDS pod's listing works too. The three clusters share one node role, so this grants it to every pod on every node of all of them at once - which is the whole argument for the other two mechanisms, and worth producing rather than just reading. Re-apply without the flag to take it away"
      value       = "terraform apply -var grant_node_role_bucket_access=true"
    }
    imds_hop_limit_note = {
      order       = 9
      title       = "5. What the IMDS case actually depends on"
      description = "A pod is one network hop further from the metadata service than its node. At a hop limit of 1 - the EC2 default for a new launch template - the pod's request never arrives and the mechanism does not work at all, which looks like a pod with no credentials rather than a network setting. Set it to 1 to watch that happen"
      value       = "current hop limit: ${var.imds_hop_limit}; to break it deliberately: terraform apply -var imds_hop_limit=1"
    }
    pod_status_commands = {
      order       = 10
      title       = "6. If a pod is not running"
      description = "Each pod is a bare Pod rather than a Deployment, so a failed image pull shows up here and nowhere else - and the image is pulled three times, once per cluster"
      value       = "kubectl --context ${module.imds_eks_cluster.cluster_name} -n ${var.pod_namespace} get pods\nkubectl --context ${module.irsa_eks_cluster.cluster_name} -n ${var.pod_namespace} get pods\nkubectl --context ${module.pod_identity_eks_cluster.cluster_name} -n ${var.pod_namespace} get pods"
    }
    shell_command = {
      order       = 11
      title       = "7. A shell in any of the pods"
      description = "The image is the AWS CLI, so every AWS command is available with whatever identity that pod was given. Swap the context to move between mechanisms"
      value       = "kubectl --context ${module.pod_identity_eks_cluster.cluster_name} ${trimprefix(module.pod_identity_cli_pod.shell_command, "kubectl ")}"
    }
    update_kubeconfig_commands = {
      order       = 12
      title       = "Re-point kubectl"
      description = "User data already ran all three, with one context per cluster. Re-run them if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.imds_eks_cluster.cluster_name} --alias ${module.imds_eks_cluster.cluster_name}\naws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.irsa_eks_cluster.cluster_name} --alias ${module.irsa_eks_cluster.cluster_name}\naws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.pod_identity_eks_cluster.cluster_name} --alias ${module.pod_identity_eks_cluster.cluster_name}"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the order field and taking
  # values() - which returns a map's values ordered by key - makes the README read top to bottom while the
  # order stays decided by configuration.
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  readme_body = join("\n", concat(
    ["# ${var.cluster_name_prefix}: three ways a pod gets AWS credentials", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}
# The work happens inside code-server in a browser, where terraform output is not available, so every
# output above is also written to a README in the home directory the IDE opens (rules.md H-2).
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is what orders this after the
    # bootstrap (rules.md D-5). The marker path comes back out of the module it was passed into, so it is
    # defined once (rules.md B-5).
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
