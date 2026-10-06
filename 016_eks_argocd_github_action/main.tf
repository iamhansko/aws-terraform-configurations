data "aws_region" "current" {}
# Resolves CloudFront's origin-facing address ranges for this region at plan
# time. Replaces the _monolithic template's AWSRegions2PrefixListId mapping,
# a hand-maintained region-to-prefix-list table that silently had no entry for
# newer regions.
data "aws_ec2_managed_prefix_list" "cloudfront_origin_facing" {
  count = var.enable_cloudfront ? 1 : 0
  name  = var.cloudfront_origin_facing_prefix_list_name
}
module "network" {
  source = "./modules/network"

  vpc_cidr_block           = var.vpc_cidr_block
  vpc_name                 = "${var.prefix}-vpc"
  internet_gateway_name    = "${var.prefix}-igw"
  public_subnet_name       = "${var.prefix}-public"
  private_subnet_name      = "${var.prefix}-private"
  public_route_table_name  = "${var.prefix}-public-rt"
  private_route_table_name = "${var.prefix}-private-rt"
  nat_gateway_name         = "${var.prefix}-natgw"
  # The kubernetes.io/role tags the AWS Load Balancer Controller auto-discovers subnets
  # with (rules.md G-1). Passed explicitly: the network module defaults both maps to {},
  # because it is shared with projects that have no cluster to discover them. The comment
  # that used to be here claimed the module's defaults already carried them, and they did
  # not - the subnets went out with a Name tag and nothing else, so the controller had no
  # subnet to place a load balancer in and neither the Argo CD NLB nor the Ingress ALB was
  # ever created. Nothing reported it, because neither is a Terraform resource.
  #
  # No Karpenter discovery tag here - this project has a managed node group and nothing
  # that launches nodes on demand.
  public_subnet_tags  = var.public_subnet_tags
  private_subnet_tags = var.private_subnet_tags
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name = var.key_name

  # key_pair consumes no network output, so nothing would otherwise order it
  # against the network module's resources. Every module in a root that has a
  # network module waits for all of it (rules.md D-3).
  depends_on = [module.network]
}
module "eks_cluster" {
  source = "./modules/eks_cluster"

  name                   = var.cluster_name
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  # Referencing module.network.*_subnet_ids only orders this module after the
  # specific aws_subnet resources behind those outputs, not after the NAT
  # gateways and route table associations that never surface as outputs
  # (rules.md D-3).
  depends_on = [module.network]
}
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not
  # exist until this addon creates it. As a DaemonSet it reaches ACTIVE with
  # zero nodes, so it is created before any node capacity - worker nodes need it
  # running to join the cluster Ready (rules.md C-4).
  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as eks_vpc_cni_addon: kube-proxy is a DaemonSet and must
  # exist before any node capacity (rules.md C-4).
  depends_on = [module.network, module.eks_cluster]
}
module "eks_pod_identity_agent_addon" {
  source = "./modules/eks_pod_identity_agent_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Also a DaemonSet, so it becomes ACTIVE with zero nodes (rules.md C-4).
  depends_on = [module.network, module.eks_cluster]
}
# Karpenter cannot provision the nodes its own controller runs on, so a small
# managed node group is a prerequisite for it, not a duplicate of it. Everything
# beyond this baseline is left to Karpenter.
module "eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name    = module.eks_cluster.cluster_name
  node_group_name = var.node_group_name
  instance_types  = var.node_group_instance_types
  desired_size    = var.node_group_desired_size
  min_size        = var.node_group_min_size
  max_size        = var.node_group_max_size
  subnet_ids      = module.network.private_subnet_ids
  key_name        = module.key_pair.key_name

  # Nodes need vpc-cni and kube-proxy running to join the cluster Ready
  # (rules.md C-4).
  depends_on = [module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.eks_cluster.cluster_name

  # coredns is a Deployment and needs schedulable node capacity to leave its
  # DEGRADED state and become ACTIVE, so it is created after the node group
  # rather than before it (rules.md C-4).
  depends_on = [
  module.network, module.eks_node_group]
}
module "eks_metrics_server_addon" {
  source = "./modules/eks_metrics_server_addon"

  cluster_name = module.eks_cluster.cluster_name

  # metrics-server is a Deployment, so like coredns it needs schedulable node
  # capacity to become ACTIVE rather than DEGRADED (rules.md C-4).
  depends_on = [
  module.network, module.eks_node_group]
}
# The AWS Load Balancer Controller. Installed with helm_release and its own IRSA
# role in one module (rules.md C-2), rather than by the 00_install_lbc.sh script the
# _monolithic template cloned from a GitHub repository and ran over SSM. It is what
# reconciles the TargetGroupBinding the workload declares, which is what actually
# puts pod IPs into the target group Terraform created.
module "aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"

  cluster_name      = module.eks_cluster.cluster_name
  vpc_id            = module.network.vpc_id
  aws_region        = data.aws_region.current.region
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  chart_version     = var.load_balancer_controller_chart_version
  # False, as in every project in this repository. No workload here sets the
  # manage-backend-security-group-rules annotation, so nothing asks the controller to
  # write rules onto the cluster security group and the shared k8s-traffic group it
  # would need as a source is never required (rules.md G-2). The load balancer this
  # project creates carries the cluster security group instead, which already reaches
  # pod IPs.
  enable_backend_security_group = var.enable_backend_security_group

  # The controller is a Deployment with wait = true, so it needs schedulable capacity
  # and working cluster DNS before the release can report ready (rules.md D-2).
  depends_on = [module.network, module.eks_coredns_addon]
}
# The registry the pipeline pushes to.
module "ecr_repository" {
  source = "./modules/ecr_repository"

  name = var.ecr_repository_name

  depends_on = [module.network]
}
# CodeBuild acting as a GitHub Actions self-hosted runner, with the webhook the
# CloudFormation conversion left as a TODO. Declared before the repository below
# because the workflow's runs-on label has to name this project, and that value comes
# from here (rules.md B-5).
module "github_actions_runner" {
  source = "./modules/github_actions_runner"

  project_name         = var.codebuild_project_name
  github_token         = var.github_token
  repository_clone_url = "https://github.com/${var.github_owner}/${var.github_repository_name}.git"
  default_branch       = var.github_default_branch
  workflow_name        = var.github_workflow_name
  # Scoped push permission instead of the AdministratorAccess the _monolithic template
  # attached to this role.
  ecr_repository_arn = module.ecr_repository.arn

  depends_on = [module.network]
}
# The repository, its workflow and the manifests Argo CD syncs. This is the module
# that replaces the most: an SSM association that wrote seven files onto the bastion,
# zipped them, uploaded the zip to S3, and an AWS::CodeStar::GitHubRepository resource
# the AWS provider cannot express - which is why the conversion left it commented out
# (rules.md E-1).
module "github_repository" {
  source = "./modules/github_repository"

  repository_name = var.github_repository_name
  default_branch  = var.github_default_branch
  workflow_name   = var.github_workflow_name
  # The label the workflow routes on, and the registry it pushes to. Both come from the
  # modules that own them rather than being restated (rules.md B-5).
  codebuild_project_name = module.github_actions_runner.project_name
  ecr_repository_name    = module.ecr_repository.name
  app_name               = var.app_name
  replica_count          = var.app_replica_count
  manifest_path          = var.manifest_path

  # module.network's value references only order this after the specific aws_subnet or
  # aws_vpc that produced them, not after the NAT gateway and route tables the network
  # module also owns. depends_on states "after the whole network" (rules.md D-3).
  depends_on = [module.network]
}
# Argo CD, and the Application that watches the repository above. helm_release instead
# of "kubectl apply -f stable/manifests/install.yaml" followed by a kubectl patch, and
# a declared Application instead of "argocd app create" run from a shell script after
# scraping the admin password out of a secret (rules.md E-1).
module "argocd" {
  source = "./modules/argocd"

  chart_version    = var.argocd_chart_version
  namespace        = var.argocd_namespace
  application_name = var.argocd_application_name
  # The clone URL from the module that created the repository, so the Application
  # cannot point somewhere that does not exist (rules.md B-5).
  repository_url  = module.github_repository.http_clone_url
  manifest_path   = module.github_repository.manifest_path
  target_revision = module.github_repository.default_branch

  # The Application is a kubectl_manifest against the cluster API, and argocd-server is
  # a LoadBalancer Service the AWS Load Balancer Controller has to reconcile. Ordering
  # the module after the controller and the node group also makes terraform destroy
  # remove the Application, and then the release, while the controllers that clean up
  # after them are still running (rules.md D-4).
  depends_on = [
    module.network,
    module.eks_node_group,
    module.aws_load_balancer_controller,
  ]
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  vpc_id        = module.network.vpc_id
  subnet_id     = module.network.public_subnet_a_id
  key_name      = module.key_pair.key_name
  instance_type = var.vscode_instance_type
  # With CloudFront in front, only CloudFront's origin-facing ranges may reach
  # code-server, so the editor is never directly exposed to the internet.
  ingress_prefix_list_ids     = var.enable_cloudfront ? [data.aws_ec2_managed_prefix_list.cloudfront_origin_facing[0].id] : []
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  # Lets the README association below know when the bootstrap has finished
  # (rules.md H-2). The module touches <path>/userdata as its last step.
  marker_file_path = var.marker_file_path
  # Joining the cluster security group is what lets this instance reach the
  # private API server endpoint (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]
  # An EKS cluster and this instance live in the same root module, so the
  # instance is the workbench for that cluster and carries all five tools:
  # code-server (the module itself), plus kubectl, eksctl, helm and docker
  # (rules.md H-1). None of them is behind a flag, and none of them is used to
  # create resources - that stays with the helm and kubectl providers.
  additional_user_data = <<-EOT
    dnf install -yq python3.13
    ln -sf /usr/bin/python3.13 /usr/bin/python
    python -m ensurepip --upgrade
    # Building container images needs a real daemon on the host, so unlike the
    # kubectl/helm steps this cannot become a provider resource (rules.md E-1).
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server is already running from the module's bootstrap, so its process
    # predates the docker group and its integrated terminals inherit the groups
    # that process started with. Restarting picks the group up, which is what
    # makes docker usable from the IDE without loosening the socket's
    # permissions (rules.md H-1).
    systemctl restart code-server
    su - ec2-user << 'EOF'
    export HOME=/home/ec2-user
    cd $HOME
    curl -sO https://s3.us-west-2.amazonaws.com/amazon-eks/${var.kubectl_download_version}/bin/linux/amd64/kubectl
    chmod +x ./kubectl
    mkdir -p $HOME/bin && mv ./kubectl $HOME/bin/kubectl && export PATH=$HOME/bin:$PATH
    echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc
    echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
    echo 'source <(kubectl completion bash)' >> ~/.bashrc
    echo 'alias k=kubectl' >> ~/.bashrc
    echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
    ARCH=amd64
    PLATFORM=$(uname -s)_$ARCH
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
module "vscode_cloudfront" {
  count  = var.enable_cloudfront ? 1 : 0
  source = "./modules/vscode_cloudfront"

  origin_domain_name = module.vscode_ec2.public_dns
  # Taken from the instance module rather than restating 8000, so the origin
  # port cannot drift from what code-server binds to (rules.md B-5).
  origin_http_port = module.vscode_ec2.code_server_port
  # The stem of a generated name, not the name. This project, 007_eks_karpenter and
  # 017_eks_argorollouts_bluegreen all built the same "${var.prefix}-vscode-code-server" string with the same
  # default prefix, and cache policy names are unique per account - so the second of them applied into an
  # account failed on CachePolicyAlreadyExists, partway through, with the VPC, the cluster and the instance
  # already built. This project happened to be the one that got there first.
  #
  # The next apply here renames the existing policy rather than replacing it: the resource has no ForceNew on
  # name and the provider sends it to UpdateCachePolicy, and the distribution references the policy by id,
  # which does not change (rules.md G-3).
  cache_policy_name_prefix = "${var.prefix}-vscode-code-server"
  comment                  = "code-server on ${var.prefix} bastion"

  depends_on = [module.network]
}
# Granting the instance role cluster access joins two modules that know nothing
# about each other, so it belongs in the root rather than inside either one
# (rules.md C-1).
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
  # Every output this project exposes, defined once. outputs.tf projects these
  # and the README below renders them, so no value is written twice (rules.md
  # #5/#35). Adding an entry here is what makes an output possible, which is
  # what keeps the README from silently falling behind outputs.tf.
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server (CloudFront)"
      description = "Open the IDE here. The kubectl commands below are meant to be run from its terminal. Falls back to the instance address when enable_cloudfront is false"
      value       = var.enable_cloudfront ? module.vscode_cloudfront[0].url : module.vscode_ec2.vscode_url
    }
    cluster_name = {
      order       = 2
      title       = "EKS cluster name"
      description = "Name of the EKS cluster"
      value       = module.eks_cluster.cluster_name
    }
    github_repository_url = {
      order       = 3
      title       = "GitHub repository"
      description = "Created by Terraform through the github provider, with its workflow and manifests committed. The _monolithic template could not do this - it zipped the files to S3 for a CodeStar resource the AWS provider has no equivalent for"
      value       = module.github_repository.html_url
    }
    ecr_repository_url = {
      order       = 4
      title       = "ECR repository"
      description = "Where the pipeline pushes images. The workflow reads the tag from the repository's version file"
      value       = module.ecr_repository.repository_url
    }
    argocd_url_command = {
      order       = 5
      title       = "1. Argo CD address"
      description = "The UI is a LoadBalancer Service, so the AWS Load Balancer Controller provisions an NLB for it - its address is not a Terraform value and has to be read from the cluster. The URL is http, not https: the server runs insecure and both Service ports map to its plain HTTP port, so https fails the TLS handshake. An empty result means the controller never built the load balancer - check that the public subnets carry kubernetes.io/role/elb"
      value       = module.argocd.server_url_command
    }
    argocd_password_command = {
      order       = 6
      title       = "2. Argo CD admin password"
      description = "Log in as admin. Kept as a command rather than an output on purpose: a password in an output ends up in state and in this README on disk (rules.md H-2)"
      value       = module.argocd.initial_password_command
    }
    argocd_application_command = {
      order       = 7
      title       = "3. The Application is synced"
      description = "Synced/Healthy means Argo CD has applied the manifests from the repository. OutOfSync means it has seen a commit it has not applied yet"
      value       = module.argocd.application_status_command
    }
    edit_index_url = {
      order       = 8
      title       = "4. Start the pipeline"
      description = "Edit index.html in the browser and commit. The workflow triggers on that path, CodeBuild builds and pushes an image, then commits the new tag into the manifest - and Argo CD picks that up"
      value       = module.github_repository.edit_index_url
    }
    codebuild_builds_command = {
      order       = 9
      title       = "5. Watch the build"
      description = "Empty after a commit means GitHub queued a job no runner claimed - check that the workflow name matches the webhook filter"
      value       = module.github_actions_runner.builds_command
    }
    codebuild_log_command = {
      order       = 10
      title       = "6. Read the build log"
      description = "Where a failing docker build or ECR push shows up"
      value       = module.github_actions_runner.build_log_command
    }
    ecr_images_command = {
      order       = 11
      title       = "7. The image arrived"
      description = "The tag here should match the version file in the repository after a successful run"
      value       = module.ecr_repository.list_images_command
    }
    app_ingress_command = {
      order       = 12
      title       = "8. Reach the app"
      description = "Argo CD applies an Ingress, and the AWS Load Balancer Controller turns it into an internet-facing ALB. The ADDRESS column fills in a minute or two after the sync"
      value       = "kubectl -n default get ingress ${var.app_name}-ingress"
    }
    update_kubeconfig_command = {
      order       = 13
      title       = "Re-point kubectl"
      description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
  }
  # Iterating local.outputs directly would order sections by key, which puts
  # "2. Watch nodes arrive" above "1. Scale the demo up". Re-keying by the order
  # field and taking values() sorts by that instead - values() returns a map's
  # values ordered by key - so the README reads in the order the demo is run,
  # and the order is still fully determined by the configuration rather than
  # shuffling between applies.
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  # Rendered from the same map, so an added output shows up here without anyone
  # remembering to edit two places (rules.md H-2).
  readme_body = join("\n", concat(
    ["# ${var.cluster_name}", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}
# The work happens inside code-server in a browser, where "terraform output" is
# not available, so every output above is also written to a README in the home
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
    # orders this after the instance bootstrap, and the marker this command
    # leaves behind is what a later association would wait on (rules.md D-5).
    # SSM runs as root, hence the chown - without it the file is not editable
    # from the IDE.
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
