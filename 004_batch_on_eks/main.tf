data "aws_ssm_parameter" "amazon_linux2023_ami_id" {
  name = var.amazon_linux2023_ami_id
}

module "network" {
  source = "./modules/network"
}

module "key_pair" {
  source   = "./modules/key_pair"
  key_name = "${var.prefix}-key"

  # module.network's value references only order this after the specific aws_subnet or
  # aws_vpc that produced them, not after the NAT gateway and route tables the network
  # module also owns. depends_on states "after the whole network" (rules.md D-3).
  depends_on = [module.network]
}

module "eks_cluster" {
  source = "./modules/eks_cluster"

  name               = "${var.prefix}-eks-cluster"
  kubernetes_version = var.kubernetes_version
  subnet_ids = concat(
    [module.network.public_subnet_a_id, module.network.public_subnet_b_id],
    module.network.private_subnet_ids,
  )

  depends_on = [module.network]
}

module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  # vpc-cni is a DaemonSet and becomes ACTIVE with zero nodes, so it only
  # needs the cluster (rules.md C-4) and is created before any node
  # capacity (eks_fargate_profile/karpenter) exists.
  depends_on = [
  module.network, module.eks_cluster]
}

module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # kube-proxy is a DaemonSet and becomes ACTIVE with zero nodes, so it
  # only needs the cluster (rules.md C-4) and is created before any node
  # capacity (eks_fargate_profile/karpenter) exists.
  depends_on = [
  module.network, module.eks_cluster]
}

module "eks_fargate_profile" {
  source = "./modules/eks_fargate_profile"

  cluster_name = module.eks_cluster.cluster_name
  profile_name = "${var.prefix}-kubesystem-fargate-profile"
  subnet_ids   = module.network.private_subnet_ids
  namespace    = "kube-system"

  # vpc-cni/kube-proxy must be running before workloads (including
  # coredns, once it's scheduled onto this profile) can rely on pod
  # networking (rules.md C-4).
  depends_on = [
  module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}

module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.eks_cluster.cluster_name

  # coredns is a Deployment and needs schedulable capacity to leave
  # DEGRADED and become ACTIVE; that capacity is the kube-system Fargate
  # profile, which must exist first (rules.md C-4).
  depends_on = [
  module.network, module.eks_fargate_profile]
}

module "karpenter" {
  source = "./modules/karpenter"

  cluster_name      = module.eks_cluster.cluster_name
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host

  # The Karpenter controller pod needs coredns ACTIVE to resolve DNS and
  # reach the EKS API (rules.md D-2, #28).
  depends_on = [
  module.network, module.eks_coredns_addon]
}

module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name          = "vscode"
  instance_type = var.vscode_instance_type
  ami_id        = data.aws_ssm_parameter.amazon_linux2023_ami_id.insecure_value
  key_name      = module.key_pair.key_name

  vpc_id    = module.network.vpc_id
  subnet_id = module.network.public_subnet_a_id
  # The marker the README association below waits on, written as the last line of user data
  # (rules.md B-4/D-5).
  marker_file_path = var.marker_file_path

  additional_user_data = <<-EOT
    su - ec2-user << 'EOF'
    export HOME=/home/ec2-user
    cd $HOME
    curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.36.2/2026-07-05/bin/linux/amd64/kubectl
    chmod +x ./kubectl
    mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$HOME/bin:$PATH
    echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc
    echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
    echo 'source <(kubectl completion bash)' >> ~/.bashrc
    echo 'alias k=kubectl' >>~/.bashrc
    echo 'complete -o default -F __start_kubectl k' >>~/.bashrc

    ARCH=amd64
    PLATFORM=$(uname -s)_$ARCH
    curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
    tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
    sudo install -m 0755 /tmp/eksctl /usr/local/bin && rm /tmp/eksctl

    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh

    aws eks update-kubeconfig --name ${module.eks_cluster.cluster_name}
    EOF
  EOT

  depends_on = [module.network]
}

resource "aws_vpc_security_group_ingress_rule" "vscode_ec2_security_group_ingress" {
  security_group_id            = module.eks_cluster.cluster_security_group_id
  ip_protocol                  = "-1"
  referenced_security_group_id = module.vscode_ec2.security_group_id
}

resource "aws_eks_access_entry" "vscode_ec2_iam_access_entry" {
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.vscode_ec2.iam_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "vscode_ec2_iam_access_policy_association" {
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.vscode_ec2.iam_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.vscode_ec2_iam_access_entry]
}

module "batch" {
  source = "./modules/batch"

  cluster_name                     = module.eks_cluster.cluster_name
  cluster_arn                      = module.eks_cluster.cluster_arn
  kubernetes_namespace             = "batch-default"
  additional_kubernetes_namespaces = ["batch-app"]
  subnet_ids                       = module.network.private_subnet_ids
  security_group_ids               = [module.eks_cluster.cluster_security_group_id]
  key_name                         = module.key_pair.key_name
  name_prefix                      = var.prefix

  # module.network's value references only order this after the specific aws_subnet or
  # aws_vpc that produced them, not after the NAT gateway and route tables the network
  # module also owns. depends_on states "after the whole network" (rules.md D-3).
  depends_on = [module.network]
}

locals {
  # Every output this project exposes, defined once. outputs.tf projects these and the README below
  # renders them, so no value expression is written twice (rules.md B-5/H-2). Adding an entry here is
  # what makes an output possible, which is what keeps the README from falling behind outputs.tf.
  outputs = {
    vscode = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here and run every command below from its terminal. kubectl, eksctl and helm are already installed and the kubeconfig already points at the cluster"
      value       = "http://${module.vscode_ec2.public_ip}:8000"
    }
    eks_cluster_name = {
      order       = 2
      title       = "EKS cluster name"
      description = "Name of the EKS cluster AWS Batch submits jobs into"
      value       = module.eks_cluster.cluster_name
    }
    eks_cluster_endpoint = {
      order       = 3
      title       = "EKS cluster endpoint"
      description = "API server endpoint of the EKS cluster"
      value       = module.eks_cluster.cluster_endpoint
    }
    batch_job_queue_arn = {
      order       = 4
      title       = "Batch job queue"
      description = "The queue a submitted job lands in. Its compute environment is the EKS cluster, so a job here becomes a pod rather than an EC2 instance"
      value       = module.batch.job_queue_arn
    }
    batch_job_definition_arn = {
      order       = 5
      title       = "Batch job definition"
      description = "What a submitted job runs. The namespace it targets has to exist and carry the RBAC the Batch service-linked role is mapped to, which is what the batch module creates"
      value       = module.batch.job_definition_arn
    }
    submit_job_command = {
      order       = 6
      title       = "1. Submit a job"
      description = "Names the queue and definition above. A job stuck in RUNNABLE usually means the namespace mapping is missing rather than that there is no capacity"
      value       = "aws batch submit-job --job-name batch-on-eks-demo --job-queue ${module.batch.job_queue_arn} --job-definition ${module.batch.job_definition_arn}"
    }
    job_status_command = {
      order       = 7
      title       = "2. Watch the job"
      description = "SUBMITTED to RUNNABLE to STARTING to RUNNING to SUCCEEDED. Anything that stops at RUNNABLE is a placement problem, and the reason is in the queue's status reason rather than in the pod"
      value       = "aws batch list-jobs --job-queue ${module.batch.job_queue_arn} --query 'jobSummaryList[].[jobName,status,statusReason]' --output table"
    }
    job_pod_command = {
      order       = 8
      title       = "3. Find the pod it became"
      description = "AWS Batch creates the pod itself, so it is not declared anywhere in this configuration. It appears in the namespace the job definition names"
      value       = "kubectl -n ${module.batch.namespaces[0]} get pods -o wide"
    }
    namespace_rbac_command = {
      order       = 9
      title       = "The namespace mapping Batch needs"
      description = "AWS Batch reaches the cluster as AWSServiceRoleForBatch, a service-linked role. Access entries do not accept those, so the mapping is in the aws-auth ConfigMap instead (rules.md E-6) - and the ARN in it has its path stripped, which the IAM authenticator requires"
      value       = "kubectl -n kube-system get configmap aws-auth -o jsonpath='{.data.mapRoles}{\"\\n\"}'"
    }
    update_kubeconfig_command = {
      order       = 10
      title       = "Re-point kubectl"
      description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks_cluster.cluster_name}"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the order field and
  # taking values() sorts by that instead - values() returns a map's values ordered by key - so the
  # README reads in the order the demo is run.
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  readme_body = join("\n", concat(
    ["# ${var.prefix}", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}

# The work happens inside code-server in a browser, where "terraform output" does not exist, so every
# output above is also written to a README in the home directory the IDE opens (rules.md H-2).
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on, is what orders this after the instance bootstrap - the marker is
    # written as the last line of user data (rules.md D-5).
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
