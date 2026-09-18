data "aws_region" "current" {}
module "network" {
  source = "./modules/network"
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

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version
  subnet_ids         = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  # Kept from the _monolithic template: the API server is private only. Nothing
  # in this root talks to the cluster at apply time (see providers.tf), so there
  # is no reason to expose the endpoint - the bastion reaches it from inside the
  # VPC through the cluster security group.

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
  # exist until this addon creates it. As a DaemonSet it reaches ACTIVE with zero
  # nodes, so it is created before any capacity exists (rules.md C-4).
  #
  # On this cluster it never runs a pod: Fargate pods get their ENI from the
  # Fargate control plane, not from the CNI DaemonSet. It is declared anyway so
  # the three EKS-managed addons are all Terraform-tracked rather than half
  # managed and half invisible, and so adding a node group later needs no change
  # here.
  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as eks_vpc_cni_addon: a DaemonSet that must exist before any
  # capacity, and that stays at zero pods while the cluster is Fargate-only
  # (rules.md C-4).
  depends_on = [module.network, module.eks_cluster]
}
# The two Fargate profiles are two instances of one module rather than a module
# each: they differ only in which namespace they select. That difference is the
# whole point of the project - kube-system carries the cluster's own add-ons,
# default carries the workload - and expressing it as an argument is what makes
# the two readable side by side.
module "eks_default_fargate_profile" {
  source = "./modules/eks_fargate_profile"

  cluster_name = module.eks_cluster.cluster_name
  profile_name = var.default_fargate_profile_name
  namespace    = "default"
  # Private subnets only. Fargate rejects public subnets outright, which is why
  # the module validates the IDs but the root chooses which list to pass.
  subnet_ids = module.network.private_subnet_ids

  depends_on = [module.network, module.eks_cluster]
}
module "eks_kubesystem_fargate_profile" {
  source = "./modules/eks_fargate_profile"

  cluster_name = module.eks_cluster.cluster_name
  profile_name = var.kubesystem_fargate_profile_name
  namespace    = "kube-system"
  subnet_ids   = module.network.private_subnet_ids

  # The _monolithic template ordered these two profiles one after the other, and
  # that ordering is kept: EKS allows one profile create at a time per cluster
  # and returns ResourceInUseException for a concurrent second one. Nothing in
  # the value references expresses that, so it is stated (rules.md D-2).
  depends_on = [module.network, module.eks_default_fargate_profile]
}
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name          = module.eks_cluster.cluster_name
  coredns_replica_count = var.coredns_replica_count
  # Fargate, not ec2: this cluster has no nodes. Without it the CoreDNS pods keep
  # the eks.amazonaws.com/compute-type: ec2 annotation EKS ships and stay Pending
  # forever, which is the state the _monolithic template left the cluster in - it
  # created the Fargate profiles but never addressed CoreDNS, so DNS did not work
  # until someone patched the Deployment by hand.
  compute_type = "Fargate"

  # coredns is a Deployment and needs schedulable capacity to leave DEGRADED and
  # become ACTIVE. Here that capacity is the kube-system Fargate profile, not a
  # node group, so this waits on the profile (rules.md C-4).
  depends_on = [module.eks_kubesystem_fargate_profile]
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  # Lets the README association below know when the bootstrap has finished
  # (rules.md H-2). The module touches <path>/userdata as its very last step,
  # after everything in additional_user_data has run.
  marker_file_path = var.marker_file_path
  # Joining the cluster security group is what lets this instance reach the API
  # server through the cluster's private endpoint - the only path there is, since
  # endpoint_public_access is false. The module is handed an ID list and never
  # learns that it belongs to an EKS cluster (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]
  # An EKS cluster and this instance live in the same root module, so the
  # instance is the workbench for that cluster and carries all five tools:
  # code-server (installed by the module itself), plus kubectl, eksctl, helm and
  # docker (rules.md H-1). None of them is used to create resources - this project
  # creates everything through the AWS provider (rules.md E-1).
  #
  # The tools go in as ec2-user rather than root, so the binaries, the kubeconfig
  # and the .bashrc additions all land in /home/ec2-user where the code-server
  # session (which also runs as ec2-user) will find them. HOME is set explicitly
  # inside the block: user data runs as root, and how sudo treats HOME for the
  # target user depends on the sudoers configuration, so "~" cannot be relied on
  # to mean /home/ec2-user here.
  additional_user_data = <<-EOT
    # Building an image or pushing one to ECR needs a daemon on the host, which
    # is why this one tool cannot be replaced by a provider resource the way
    # kubectl and helm were (rules.md E-1/H-1).
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server is already running from the module's bootstrap, so its process
    # predates the docker group and its integrated terminals inherit whatever
    # groups that process started with. Restarting is what makes docker usable
    # from the IDE, rather than opening /var/run/docker.sock up to 666.
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
    # exist before complete references it - otherwise every login prints
    # "function not found" (rules.md H-1).
    echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
    echo 'source <(kubectl completion bash)' >> ~/.bashrc
    echo 'alias k=kubectl' >> ~/.bashrc
    echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
    # eksctl-io is the project's own org. The old weaveworks URL the _monolithic
    # template used still redirects, but the current name is what gets used
    # (rules.md H-1).
    PLATFORM=$(uname -s)_amd64
    curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
    tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
    sudo install -m 0755 /tmp/eksctl /usr/local/bin && rm /tmp/eksctl
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    aws configure set default.region ${data.aws_region.current.region}
    # Without this - and without the access entry below - kubectl is installed
    # but every command fails with "You must be logged in to the server"
    # (rules.md H-1).
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}
    EOF
  EOT

  depends_on = [module.network]
}
# Granting the bastion's instance role cluster access joins two modules that know
# nothing about each other, so it belongs in the root rather than inside either
# one (rules.md C-1).
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
  # and the README below renders them, so no value expression is written twice
  # (rules.md B-5/H-2). Adding an entry here is what makes an output possible,
  # which is what keeps the README from silently falling behind outputs.tf.
  #
  # The map's keys are the output names, and order decides the README's section
  # order.
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here. Every kubectl command below is meant to be run from its terminal - the cluster endpoint is private, so this instance is the only place they work"
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
      description = "API server endpoint. Private only, so it resolves to a VPC address and is unreachable from outside the VPC"
      value       = module.eks_cluster.cluster_endpoint
    }
    default_fargate_profile_name = {
      order       = 4
      title       = "Fargate profile: default"
      description = "Profile selecting the default namespace. Any pod created there runs on Fargate"
      value       = module.eks_default_fargate_profile.fargate_profile_name
    }
    kubesystem_fargate_profile_name = {
      order       = 5
      title       = "Fargate profile: kube-system"
      description = "Profile selecting kube-system. This is what gives CoreDNS somewhere to run on a cluster with no nodes"
      value       = module.eks_kubesystem_fargate_profile.fargate_profile_name
    }
    coredns_status_command = {
      order       = 6
      title       = "1. CoreDNS is running on Fargate"
      description = "Both replicas should be READY. If they are Pending, the coredns addon's computeType is still ec2 and there is no node to place them on - which is the state this cluster would be in without that setting"
      value       = "kubectl -n kube-system get deployment coredns -o wide"
    }
    fargate_nodes_command = {
      order       = 7
      title       = "2. The nodes are Fargate, not EC2"
      description = "Every entry should be named fargate-ip-... and report a Fargate compute type. There is no managed node group in this project, so an ec2 entry would mean something unexpected joined"
      value       = "kubectl get nodes -L eks.amazonaws.com/compute-type"
    }
    demo_pod_command = {
      order       = 8
      title       = "3. Run a pod in the default namespace"
      description = "It lands on Fargate because the default-fargate profile selects that namespace. Watch a new fargate-ip- node appear for it"
      value       = "kubectl run demo --image=public.ecr.aws/docker/library/nginx:latest --restart=Never && kubectl wait --for=condition=Ready pod/demo --timeout=180s && kubectl get pod demo -o wide"
    }
    demo_pod_cleanup_command = {
      order       = 9
      title       = "4. Remove the demo pod"
      description = "Fargate bills per pod, so the pod is worth deleting when the demo is over. Its node disappears with it"
      value       = "kubectl delete pod demo --ignore-not-found"
    }
    update_kubeconfig_command = {
      order       = 10
      title       = "Re-point kubectl"
      description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
  }
  # Iterating local.outputs directly would order sections by key, which puts
  # "2. The nodes are Fargate" above "1. CoreDNS is running". Re-keying by the
  # order field and taking values() sorts by that instead - values() returns a
  # map's values ordered by key - so the README reads in the order the demo is
  # run, and the order is still fully determined by the configuration rather than
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
# directory the IDE opens (rules.md H-2). Combining several modules' outputs is
# the root's job, so this lives here rather than inside the instance module,
# which never learns what gets written into its home directory (rules.md C-1).
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
    # leaves behind is what a later association would wait on (rules.md D-5). The
    # marker path comes back out of the module it was passed into, so it is
    # defined in exactly one place (rules.md B-5).
    #
    # SSM runs as root, hence the chown - without it the file is not editable
    # from the IDE. The heredoc delimiter is quoted and deliberately unlikely to
    # appear in the body: Terraform has already substituted every value, so the
    # shell has no reason to touch a "$" or a backtick in the README.
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
