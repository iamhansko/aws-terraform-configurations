data "aws_region" "current" {}
locals {
  # Derived rather than offered as a variable: "clusters/<name>" is the layout the flux CLI's own
  # documentation and every Flux example assume, and it is what lets one repository serve several
  # clusters. A variable here could only disagree with cluster_name (rules.md B-1).
  github_gitops_path = "clusters/${var.cluster_name}"
  # The two manifests that make podinfo arrive, committed into the repository rather than applied
  # from here.
  #
  # This is the shape GOAL.md describes and the one the _monolithic template reached by hand:
  # "flux create source git ... --export" and "flux create kustomization ... --export" write these
  # two documents to files, and "git push" is what puts them in the cluster. Declaring them as
  # Terraform resources instead would be simpler and would put them in state - but then the
  # repository is not what decides podinfo exists, and the pipeline being demonstrated is not
  # there. They have exactly one owner either way, and here the owner is Git.
  #
  # Rendered from HCL objects with yamlencode rather than written as YAML strings, so a missing or
  # misspelled key is a plan error rather than something the kustomize controller reports later as
  # a field it ignored (rules.md E-3). The field names are the Flux API's, unchanged from what the
  # CLI emits.
  podinfo_source_manifest = {
    apiVersion = "source.toolkit.fluxcd.io/v1"
    kind       = "GitRepository"
    metadata = {
      name = var.gitops_name
      # Stated rather than left to the Kustomization that applies this file. Flux's custom
      # resources have to live in the namespace the controllers watch, and the Kustomization
      # below names this GitRepository without a namespace - so the two have to agree, and this
      # is where they do.
      namespace = var.flux_namespace
    }
    spec = {
      interval = var.gitops_source_interval
      url      = var.gitops_url
      ref = {
        branch = var.gitops_branch
      }
    }
  }
  podinfo_kustomization_manifest = {
    apiVersion = "kustomize.toolkit.fluxcd.io/v1"
    kind       = "Kustomization"
    metadata = {
      name      = var.gitops_name
      namespace = var.flux_namespace
    }
    spec = {
      interval      = var.gitops_kustomization_interval
      retryInterval = var.gitops_retry_interval
      timeout       = var.gitops_health_check_timeout
      path          = var.gitops_path
      prune         = true
      wait          = true
      # Here this is right: podinfo's own manifests carry no namespace, so they all land in one.
      targetNamespace = var.gitops_target_namespace
      sourceRef = {
        kind = "GitRepository"
        name = var.gitops_name
      }
    }
  }
  # Named as GOAL.md names them, so the files in the repository match the commands anybody
  # following along would have run.
  #
  # No kustomization.yaml listing them, for the same reason GOAL.md commits none: with no
  # kustomization.yaml in the directory the kustomize controller generates one covering every YAML
  # file it finds. An explicit index would be more precise about what gets applied, but it would
  # also be a file Terraform owns in a directory whose other files are deliberately left to Git -
  # and changing the set of manifests would then need that index rewritten, which is exactly the
  # update the seeded files refuse to take.
  github_gitops_manifests = {
    "podinfo-source.yaml"        = yamlencode(local.podinfo_source_manifest)
    "podinfo-kustomization.yaml" = yamlencode(local.podinfo_kustomization_manifest)
  }
  # The file the patch step edits. Built from the module's prefix rather than taken from its
  # edit_url, which points at whichever file sorts first - true today and silently wrong the day
  # another manifest is added ahead of it alphabetically (rules.md B-5).
  podinfo_kustomization_edit_url = "${module.github_gitops_repository.edit_url_prefix}/podinfo-kustomization.yaml"
  # Checks for the objects that arrive through Git. They are not Terraform resources and no module
  # owns them, so the commands are built where the manifests are rendered - which is the one place
  # that knows their names (rules.md B-5).
  podinfo_objects_check_command  = "kubectl -n ${var.flux_namespace} get gitrepository,kustomization ${var.gitops_name}"
  podinfo_workload_check_command = "kubectl -n ${var.gitops_target_namespace} get pods,svc,hpa"
  podinfo_drift_test_command     = "kubectl -n ${var.gitops_target_namespace} scale deployment ${var.gitops_name} --replicas 5 && kubectl -n ${var.flux_namespace} annotate --overwrite kustomization ${var.gitops_name} reconcile.fluxcd.io/requestedAt=\"$(date +%s)\""
  # The second half of GOAL.md: append this to podinfo-kustomization.yaml, commit, and the
  # HorizontalPodAutoscaler's floor rises. spec.patches is a Flux field rather than a kustomize
  # one - the controller applies it to what the source produced, so the upstream repository does
  # not have to be forked to change one value in it.
  #
  # Written out as text rather than rendered from an object, because what is being demonstrated is
  # an edit somebody makes in a text editor on GitHub. The indentation is load-bearing: it has to
  # sit under the spec: this file already has.
  podinfo_patch_snippet = join("\n", [
    "  patches:",
    "    - patch: |-",
    "        apiVersion: autoscaling/v2",
    "        kind: HorizontalPodAutoscaler",
    "        metadata:",
    "          name: ${var.gitops_name}",
    "        spec:",
    "          minReplicas: 4",
    "      target:",
    "        name: ${var.gitops_name}",
    "        kind: HorizontalPodAutoscaler",
  ])
}
module "network" {
  source = "./modules/network"

  vpc_name                 = "${var.cluster_name}-vpc"
  internet_gateway_name    = "${var.cluster_name}-igw"
  public_subnet_name       = "${var.cluster_name}-public"
  private_subnet_name      = "${var.cluster_name}-private"
  public_route_table_name  = "${var.cluster_name}-public-rt"
  private_route_table_name = "${var.cluster_name}-private-rt"
  nat_gateway_name         = "${var.cluster_name}-natgw"
  # No subnet tags: nothing here creates a load balancer, so there is nothing for the AWS Load
  # Balancer Controller to auto-discover subnets for (rules.md G-1).
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
  # Deliberately left at the addon's defaults. The _monolithic template set
  # ENABLE_MULTI_NIC: "true" here, which belongs to the projects about pods with several network
  # interfaces and does nothing for a GitOps demo - it was carried over from a sibling template
  # along with the update-kubeconfig alias "nvidia" further down. Both are dropped rather than
  # reproduced (rules.md E-5).

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not exist until this
  # addon creates it. As a DaemonSet it reaches ACTIVE with zero nodes, so it comes before any
  # capacity - and nodes need it to join Ready (rules.md C-4).
  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as eks_vpc_cni_addon (rules.md C-4).
  depends_on = [module.network, module.eks_vpc_cni_addon]
}
# The agent behind the EBS CSI driver's Pod Identity association, as the _monolithic template
# had it. A DaemonSet, so it reaches ACTIVE with no nodes, but the driver's credentials do not
# work until it is running (rules.md C-4).
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
  # (rules.md C-4). Flux's source controller also resolves github.com through it, so nothing
  # reconciles before this is up.
  depends_on = [
  module.network, module.eks_node_group]
}
# What makes podinfo's HorizontalPodAutoscaler able to autoscale. Without a metrics API it reports
# "cpu: <unknown>" and cannot compute a desired replica count, so nothing responds to load - while
# still enforcing its replica floor, which is why the GOAL.md commit that sets minReplicas: 4
# works with or without this and is not the thing that needs it.
module "eks_metrics_server_addon" {
  source = "./modules/eks_metrics_server_addon"

  cluster_name = module.eks_cluster.cluster_name

  # A Deployment, so it needs schedulable capacity to leave DEGRADED and become ACTIVE - the same
  # requirement as coredns and the opposite of vpc-cni's (rules.md C-4).
  #
  # Nothing downstream waits for it. The podinfo HorizontalPodAutoscaler arrives through Flux
  # whether or not this exists, and an HPA counts as Ready without its metrics - so ordering the
  # Flux modules after this would express a dependency Kubernetes does not have.
  depends_on = [
  module.network, module.eks_node_group]
}
module "eks_ebs_csi_driver_addon" {
  source = "./modules/eks_ebs_csi_driver_addon"

  cluster_name = module.eks_cluster.cluster_name

  # The controller half of this addon is a Deployment, so it needs node capacity to leave
  # DEGRADED - and the Pod Identity agent has to be running before its credentials work
  # (rules.md C-4/D-2).
  depends_on = [
  module.network, module.eks_node_group, module.eks_pod_identity_agent_addon]
}
# The cluster's default StorageClass, as the _monolithic template applied it with kubectl from
# the bastion. Nothing in this project claims a volume; it is the storage baseline, and a cluster
# whose only default class is EKS's gp2 is a surprise for whatever is added next.
module "csi_storage_classes" {
  source = "./modules/csi_storage_classes"

  storage_class_name = var.storage_class_name
  # No snapshot-controller addon here, so no VolumeSnapshotClass - its kind would not exist and
  # the manifest would fail at apply after a clean plan (rules.md B-4).
  create_volume_snapshot_class = false

  # kubectl_manifest resources against the cluster's API server, so ordering the module after
  # the nodes is what makes terraform destroy remove them while there is still a controller to
  # process the deletion (rules.md D-4).
  depends_on = [
  module.network, module.eks_node_group, module.eks_ebs_csi_driver_addon]
}
# The subject of this project.
module "flux" {
  source = "./modules/flux"

  namespace     = var.flux_namespace
  chart_version = var.flux_chart_version

  # The controllers talk to the API server and resolve github.com, so CoreDNS has to be
  # answering before any of them is useful (rules.md D-2).
  depends_on = [
  module.network, module.eks_node_group, module.eks_coredns_addon]
}
# The repository that decides what this cluster runs, in the caller's own GitHub account and
# created by Terraform rather than by hand.
#
# What is deliberately not in this configuration any more: a GitRepository and Kustomization for
# podinfo applied straight at the cluster. Those two objects are now files in this repository
# (local.github_gitops_manifests), and Flux applies them because the source below points at it.
# The difference is the whole point of GOAL.md - podinfo exists because a repository says so, and
# the way to change it is a commit.
#
# It is still not "flux bootstrap". Flux does not keep its own manifests here; the controllers are
# installed by the chart above. What this adds is the repository, the credential and the pipeline
# into it, which were previously a manual command in this project's README.
module "github_gitops_repository" {
  source = "./modules/github_gitops_repository"

  name        = var.github_gitops_repository
  description = "GitOps repository reconciled by Flux on ${var.cluster_name}"
  visibility  = var.github_gitops_visibility
  path        = local.github_gitops_path

  seed_manifests = local.github_gitops_manifests
  commit_message = var.github_gitops_commit_message
  # Archived rather than deleted when this project is destroyed, because it is the only thing here
  # that holds history somebody wrote by hand.
  archive_on_destroy = var.github_gitops_archive_on_destroy

  # Nothing to order it against: this module talks to GitHub and not to AWS or the cluster, so it
  # has no dependency on the network or the cluster at all. It is deliberately not given
  # depends_on = [module.network] for that reason, which is the one case in this root where
  # rules.md D-3 does not apply - there is no AWS resource here to race.
}
# Flux pointed at the repository above. This is the only GitRepository and Kustomization pair
# Terraform applies, and everything else arrives through it - the podinfo pair included.
module "github_gitops_source" {
  source = "./modules/flux_gitops_source"

  name      = var.github_gitops_name
  namespace = module.flux.namespace
  # Read off the repository resource rather than built from the account name and the repository
  # name, so the URL names the repository that actually exists (rules.md B-5).
  url    = module.github_gitops_repository.clone_url
  branch = module.github_gitops_repository.branch
  # The path conversion to Flux's "./" form happens in the module that owns the directory, not
  # here (rules.md B-5).
  path = module.github_gitops_repository.flux_path
  # Left null on purpose. The files in this repository are Flux custom resources that declare
  # namespace: flux-system themselves, and setting targetNamespace here would rewrite them into
  # another namespace - where the podinfo Kustomization would then look for its GitRepository in
  # the wrong place (rules.md B-4).
  target_namespace = null
  source_interval  = var.github_gitops_source_interval

  # The repository is private, so the source controller needs a credential to clone it. GitHub
  # ignores the username for token authentication but the Secret must carry both keys, and "git"
  # is the conventional filler.
  git_username = var.github_gitops_git_username
  git_password = var.github_token

  # The Flux release installs the CRDs these two objects need, and ordering the module after it
  # also means terraform destroy removes them while the controllers are still alive - so the
  # ConfigMap they reconciled is pruned rather than orphaned (rules.md D-2/D-4).
  #
  # module.github_gitops_repository is reached through url and branch, so the repository already
  # exists before the GitRepository points at it.
  depends_on = [
  module.network, module.flux]
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

  # An EKS cluster and this instance share a root module, so it is the workbench for that cluster
  # and carries all five tools (rules.md H-1), plus the flux CLI - which is a diagnostic tool
  # here. The controllers and the two GitOps objects the _monolithic template created from this
  # shell are Terraform resources now (rules.md E-1).
  #
  # Bugs from that template that are not carried over. It ran "exec bash" partway through, which
  # replaces the shell and silently discarded every remaining line - eksctl, helm, the AWS Load
  # Balancer Controller install, the StorageClass and the whole Flux bootstrap were all after it,
  # so on a real boot none of them ran. It pulled eksctl from weaveworks rather than eksctl-io.
  # It wrote the "complete" line for the k alias into .bashrc before the line that defines
  # __start_kubectl, so every login printed a "function not found" error (rules.md H-1). It
  # passed "--alias nvidia" to update-kubeconfig, which is a leftover from a sibling template
  # about GPUs. And it wrote the GitHub token into /home/ec2-user/README.md in clear text, on an
  # instance whose code-server has no authentication in front of it - this README carries the
  # commands without the token (rules.md H-2).
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
    # The flux CLI, pinned to the release the chart installs rather than piped from
    # fluxcd.io/install.sh. It is here to read the loop - flux get kustomizations - not to
    # create anything (rules.md H-1).
    curl -sLO "https://github.com/fluxcd/flux2/releases/download/v${var.flux_cli_version}/flux_${var.flux_cli_version}_linux_amd64.tar.gz"
    tar -xzf flux_${var.flux_cli_version}_linux_amd64.tar.gz -C /tmp && rm flux_${var.flux_cli_version}_linux_amd64.tar.gz
    sudo install -m 0755 /tmp/flux /usr/local/bin && rm /tmp/flux
    echo 'source <(flux completion bash)' >> ~/.bashrc
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
      description = "Open the IDE here. Every command below is meant to be run from its terminal, which has kubectl and the flux CLI already pointed at the cluster"
      value       = module.vscode_ec2.vscode_url
    }
    cluster_name = {
      order       = 2
      title       = "EKS cluster name"
      description = "Name of the EKS cluster"
      value       = module.eks_cluster.cluster_name
    }
    cluster_endpoint = {
      order       = 3
      title       = "EKS cluster endpoint"
      description = "API server endpoint. Public so the helm and kubectl providers could reach it during apply - narrow public_access_cidrs to your own address"
      value       = module.eks_cluster.cluster_endpoint
    }
    metrics_server = {
      order       = 4
      title       = "metrics-server"
      description = "Installed as an EKS addon rather than from its upstream chart, so its version is in state and follows the cluster. It is here for podinfo's HorizontalPodAutoscaler, whose TARGETS column reads \"cpu: <unknown>\" without a metrics API. Note what that does and does not break: the replica floor is still enforced, so the committed minReplicas in step 8 takes effect either way - what cannot happen is scaling on load, because the controller has no number to compute a desired count from. Nothing reports it, since an HPA counts as Ready without its metrics"
      value       = "metrics-server addon ${module.eks_metrics_server_addon.addon_version}, ${module.eks_metrics_server_addon.metrics_check_command}"
    }
    flux_version = {
      order       = 5
      title       = "Flux install"
      description = "The controllers, installed from a pinned chart rather than by piping fluxcd.io/install.sh into bash - so the Flux version is a value in this configuration rather than whatever was current on boot day"
      value       = "flux2 chart ${module.flux.chart_version} in namespace ${module.flux.namespace}"
    }
    gitops_repository = {
      order       = 6
      title       = "The repository this cluster follows"
      description = "Created by this configuration in your GitHub account, private, and holding the two manifests that make podinfo exist. This is the only thing Terraform points Flux at; everything else arrives through it. Committing here is how the cluster changes"
      value       = "${module.github_gitops_repository.html_url} (${module.github_gitops_source.branch}) ${module.github_gitops_source.path}, polled every ${module.github_gitops_source.source_interval}"
    }
    gitops_repository_files = {
      order       = 7
      title       = "What Terraform committed into it"
      description = "Seeded once and then left to Git. These are the files GOAL.md produces with \"flux create source git --export\" and \"flux create kustomization --export\": a GitRepository pointing at podinfo and a Kustomization applying its kustomize directory. Terraform stopped tracking their contents on purpose, so editing them in Git is not reverted by the next plan - and equally, changing the gitops_ variables afterwards does not rewrite them"
      value       = join("\n", module.github_gitops_repository.seeded_files)
    }
    gitops_chain = {
      order       = 8
      title       = "The chain, end to end"
      description = "Two loops, not one. Terraform applies the first pair; the first pair applies the second, which it found in Git; the second pair applies podinfo. Nothing about podinfo exists in this Terraform configuration as a cluster object - only as a file committed to a repository"
      value       = "Terraform -> GitRepository/Kustomization ${var.github_gitops_name} -> ${module.github_gitops_repository.full_name} -> GitRepository/Kustomization ${var.gitops_name} -> ${var.gitops_url} (${var.gitops_branch}) ${var.gitops_path} -> namespace ${var.gitops_target_namespace}"
    }
    # No entry for the credential Secret. Everything in this map is written into a README on an
    # instance whose code-server has no authentication in front of it (rules.md H-2), and the
    # Secret's only operational signal - whether the clone authenticated - is already reported by
    # the GitRepository in step 2.
    controllers_check_command = {
      order       = 9
      title       = "1. Confirm the controllers are up"
      description = "All of them Available is the precondition for everything else. A GitRepository with no source-controller sits with no status at all, which reads like a manifest that was never applied"
      value       = module.flux.controllers_check_command
    }
    git_source_check_command = {
      order       = 10
      title       = "2. Confirm your repository was fetched"
      description = "The commit Flux currently has in hand from your own repository. Ready=True here also means the Secret worked: an authentication failure is reported on this object rather than on the Secret, and it reads much like an unreachable URL"
      value       = module.github_gitops_source.git_source_check_command
    }
    kustomization_check_command = {
      order       = 11
      title       = "3. Confirm its files were applied"
      description = "What that Kustomization applied - which is the podinfo pair, not podinfo itself. With wait enabled, Ready=True means those two objects are themselves Ready, so this going green is also the second loop reporting success"
      value       = module.github_gitops_source.kustomization_check_command
    }
    podinfo_objects_check_command = {
      order       = 12
      title       = "4. Confirm the podinfo pair arrived through Git"
      description = "The GitRepository and Kustomization that came out of the repository. These are the objects GOAL.md commits, and they are not Terraform resources - terraform state list will not show them, and deleting them by hand brings them back on the next reconciliation"
      value       = local.podinfo_objects_check_command
    }
    podinfo_workload_check_command = {
      order       = 13
      title       = "5. Look at what podinfo brought"
      description = "A Deployment, a Service and a HorizontalPodAutoscaler, three hops from anything in this configuration. They exist because a file in your repository names a repository that contains them"
      value       = local.podinfo_workload_check_command
    }
    reconcile_watch_command = {
      order       = 14
      title       = "6. Watch both loops"
      description = "Every Kustomization in the cluster as it reconciles - yours and podinfo's together, which is where the two-stage shape becomes visible"
      value       = module.github_gitops_source.reconcile_watch_command
    }
    drift_test_command = {
      order       = 15
      title       = "7. Change the cluster by hand and watch it revert"
      description = "Scales podinfo and then asks its Kustomization to reconcile immediately rather than waiting out the interval. The replica count goes back to what the repository says, which is the difference between GitOps and a one-off apply"
      value       = local.podinfo_drift_test_command
    }
    podinfo_patch_demo = {
      order       = 16
      title       = "8. Change it through Git instead, and watch that stick"
      description = "The second half of GOAL.md, and the step that tells this apart from step 7. Open podinfo-kustomization.yaml on GitHub, append the block below under its spec, and commit. Flux patches the HorizontalPodAutoscaler the upstream repository produced - minReplicas rises to four and the pod count follows, without forking podinfo and without a terraform apply. Indentation matters: the block sits under the spec: already in the file"
      value       = "${local.podinfo_kustomization_edit_url}\n\n${local.podinfo_patch_snippet}"
    }
    podinfo_patch_verify_command = {
      order       = 17
      title       = "9. Confirm the patch took effect"
      description = "MINPODS on the HorizontalPodAutoscaler is 4 once the commit has been reconciled, and the Deployment follows it. Until then it is whatever podinfo's own manifests say, so this is also how to tell the commit has not arrived yet. TARGETS should read a percentage rather than \"cpu: <unknown>\" - that column is metrics-server's doing, not the commit's, and an unknown there means the floor is being held but nothing is scaling on load"
      value       = "kubectl -n ${var.gitops_target_namespace} get hpa ${var.gitops_name} && ${module.github_gitops_source.reconcile_now_command}"
    }
    update_kubeconfig_command = {
      order       = 18
      title       = "Re-point kubectl"
      description = "User data already ran this, so kubectl and the flux CLI work out of the box. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the order field
  # and taking values() - which returns a map's values ordered by key - makes the README read top
  # to bottom while the order stays decided by configuration.
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
# (rules.md H-2). The _monolithic template wrote its own README here and put the GitHub token in
# it; this one carries the commands and leaves the token to the shell.
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
