module "network" {
  source = "./modules/network"
}

module "key_pair" {
  source = "./modules/key_pair"

  key_name = var.key_name

  # key_pair doesn't reference any network output, so without this the
  # network module's own resources (NAT gateways, routes, etc.) would have
  # no ordering relationship with it at all (rules.md D-2).
  depends_on = [module.network]
}

module "eks_cluster" {
  source = "./modules/eks_cluster"

  name                   = var.cluster_name
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  # Referencing module.network.*_subnet_ids only orders this module after
  # the specific subnet resources that produce those outputs, not after
  # every resource in the network module (e.g. NAT gateways, route table
  # associations). depends_on makes "all of network before this" explicit.
  depends_on = [module.network]
}

module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name                      = module.eks_cluster.cluster_name
  enable_pod_eni                    = var.enable_pod_eni
  pod_security_group_enforcing_mode = var.pod_security_group_enforcing_mode

  # bootstrap_self_managed_addons = false (modules/eks_cluster) means
  # vpc-cni does not exist until this aws_eks_addon resource creates it. As
  # a DaemonSet it becomes ACTIVE with zero nodes, so it's created before
  # the node group instead of after it (rules.md C-4) - worker nodes need
  # it running to join the cluster in a Ready state.
  depends_on = [module.network, module.eks_cluster]
}

module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as eks_vpc_cni_addon above: kube-proxy is a DaemonSet
  # and must exist before the node group (rules.md C-4).
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

  # Nodes need vpc-cni/kube-proxy running to join the cluster Ready
  # (rules.md C-4).
  depends_on = [module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}

module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.eks_cluster.cluster_name

  # coredns is a Deployment and needs schedulable node capacity to leave
  # its DEGRADED state and become ACTIVE, so it's created after the node
  # group instead of before it (rules.md C-4).
  depends_on = [
  module.network, module.eks_node_group]
}

module "pod_security_group_policy" {
  source = "./modules/pod_security_group_policy"

  vpc_id          = module.network.vpc_id
  create_demo_pod = var.create_demo_pod

  # default_sgp/demo_pod (kubectl_manifest) need a live vpc-resource-
  # controller pod, which runs on the node group; ordering the module
  # itself after the node group (not after an unrelated module like
  # eks_coredns_addon) makes `terraform destroy` remove these manifests
  # before the node group disappears (rules.md D-4).
  depends_on = [module.network, module.eks_node_group]
}

module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  extra_security_group_ids    = [module.eks_cluster.cluster_security_group_id]
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

module "web_ec2" {
  source = "./modules/web_ec2"

  vpc_id        = module.network.vpc_id
  subnet_id     = module.network.private_subnet_b_id
  key_name      = module.key_pair.key_name
  instance_type = var.web_instance_type
  # Keyed by a label rather than passed as a list: the ID is unknown until the
  # pod security group is created, and the module's for_each needs keys that are
  # known during plan (rules.md B-8).
  ingress_source_security_groups = {
    pod = module.pod_security_group_policy.pod_security_group_id
  }

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
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here and run every command below from its terminal. kubectl is already installed and the kubeconfig already points at the cluster"
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
      description = "API server endpoint of the EKS cluster"
      value       = module.eks_cluster.cluster_endpoint
    }
    pod_security_group_id = {
      order       = 4
      title       = "Pod security group"
      description = "The security group the SecurityGroupPolicy assigns to pods. This is the point of the project: a pod gets a branch ENI carrying this group instead of inheriting the node's"
      value       = module.pod_security_group_policy.pod_security_group_id
    }
    web_ec2_private_ip = {
      order       = 5
      title       = "Demo web instance"
      description = "An nginx instance in a private subnet whose security group admits only the pod security group above. Reaching it from a pod is what proves the branch ENI is in effect"
      value       = module.web_ec2.private_ip
    }
    pod_eni_setting_command = {
      order       = 6
      title       = "1. The CNI has pod ENI enabled"
      description = "ENABLE_POD_ENI comes from the vpc-cni addon's configuration_values rather than from a kubectl set env on the DaemonSet, so it survives an addon upgrade (rules.md E-5)"
      value       = "kubectl -n kube-system get daemonset aws-node -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{\"\\n\"}{end}' | grep -E 'POD_ENI|ENFORCING'"
    }
    security_group_policy_command = {
      order       = 7
      title       = "2. The SecurityGroupPolicy exists"
      description = "A CRD the vpc-resource-controller reconciles. It is a Terraform resource here rather than something applied by hand, which is what lets destroy remove it while that controller is still running (rules.md D-4)"
      value       = "kubectl get securitygrouppolicy -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,GROUPS:.spec.securityGroups.groupIds'"
    }
    branch_eni_command = {
      order       = 8
      title       = "3. The pod got a branch ENI"
      description = "The pod's address is on an ENI of its own, and the interface carries the pod security group rather than the node's. An empty result with a Running pod means the policy did not match its labels"
      value       = "aws ec2 describe-network-interfaces --filters Name=interface-type,Values=branch Name=group-id,Values=${module.pod_security_group_policy.pod_security_group_id} --query 'NetworkInterfaces[].[NetworkInterfaceId,PrivateIpAddress,Status]' --output table"
    }
    pod_reachability_command = {
      order       = 9
      title       = "4. The pod can reach the instance and nothing else can"
      description = "curl from inside the pod succeeds because the instance admits the pod security group. The same curl from a node fails, which is the whole demonstration"
      value       = "kubectl exec demo-pod -- curl -sS -o /dev/null -w '%%{http_code}\\n' http://${module.web_ec2.private_ip}"
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
    ["# ${var.cluster_name}", ""],
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
