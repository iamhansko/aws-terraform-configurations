data "aws_region" "current" {}
# One VPC for both clusters, as the _monolithic template had it. That is deliberate rather than
# incidental: the two clusters differ in exactly one setting, so sharing the network removes it as a
# variable - and it halves the NAT gateway bill for a project that is already running four GPU
# instances.
module "network" {
  source = "./modules/network"

  vpc_name                 = "musicgen-vpc"
  internet_gateway_name    = "musicgen-igw"
  public_subnet_name       = "musicgen-public"
  private_subnet_name      = "musicgen-private"
  public_route_table_name  = "musicgen-public-rt"
  private_route_table_name = "musicgen-private-rt"
  nat_gateway_name         = "musicgen-natgw"
  # No subnet tags: nothing here creates a load balancer (rules.md G-1).
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name = var.key_name

  # key_pair consumes no network output, so nothing would otherwise order it against the network
  # module's resources (rules.md D-3).
  depends_on = [module.network]
}
# ---------------------------------------------------------------------------------------------------
# The control cluster: one GPU, advertised once.
# ---------------------------------------------------------------------------------------------------
module "nvidia_eks_cluster" {
  source = "./modules/eks_cluster"

  name                   = var.nvidia_cluster_name
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  # Referencing module.network.*_subnet_ids only orders this after the specific aws_subnet resources
  # behind those outputs, not after the NAT gateways and route table associations that never surface as
  # outputs (rules.md D-3).
  depends_on = [module.network]
}
module "nvidia_eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.nvidia_eks_cluster.cluster_name

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not exist until this addon
  # creates it. As a DaemonSet it reaches ACTIVE with zero nodes, so it comes before any capacity - and
  # nodes need it to join Ready (rules.md C-4).
  depends_on = [module.network, module.nvidia_eks_cluster]
}
module "nvidia_eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.nvidia_eks_cluster.cluster_name

  # Same reasoning as the vpc-cni addon (rules.md C-4).
  depends_on = [module.network, module.nvidia_eks_vpc_cni_addon]
}
module "nvidia_eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name    = module.nvidia_eks_cluster.cluster_name
  node_group_name = var.gpu_node_group_name
  # The GPU AMI, which is what puts the driver and the container runtime hook on the node. A standard
  # AMI on the same instance type produces a node whose GPU Kubernetes cannot see.
  ami_type       = var.gpu_ami_type
  instance_types = var.gpu_instance_types
  desired_size   = var.gpu_node_group_desired_size
  min_size       = var.gpu_node_group_min_size
  max_size       = var.gpu_node_group_max_size
  subnet_ids     = module.network.private_subnet_ids
  key_name       = module.key_pair.key_name

  # Nodes need vpc-cni and kube-proxy running to join the cluster Ready (rules.md C-4).
  depends_on = [module.network, module.nvidia_eks_vpc_cni_addon, module.nvidia_eks_kube_proxy_addon]
}
module "nvidia_eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.nvidia_eks_cluster.cluster_name

  # coredns is a Deployment and needs schedulable capacity to leave DEGRADED and become ACTIVE
  # (rules.md C-4).
  depends_on = [
  module.network, module.nvidia_eks_node_group]
}
# No time_slicing_replicas, so the plugin is installed with no sharing configuration and no config map.
# One card, one nvidia.com/gpu.
module "nvidia_device_plugin" {
  source = "./modules/nvidia_device_plugin"
  providers = {
    helm    = helm.nvidia
    kubectl = kubectl.nvidia
  }

  chart_version = var.device_plugin_chart_version

  # The plugin runs on the GPU nodes, so they have to exist before its DaemonSet can become ready - and
  # its readiness is what the workload below waits on (rules.md D-2).
  depends_on = [
  module.network, module.nvidia_eks_node_group, module.nvidia_eks_coredns_addon]
}
module "nvidia_gpu_workload" {
  source = "./modules/gpu_workload"
  providers = {
    kubectl = kubectl.nvidia
  }

  namespace    = var.workload_namespace
  app_image    = var.app_image
  app_replicas = var.app_replicas_without_time_slicing

  # The plugin has to have advertised a GPU before these pods can be scheduled. Ordering the module after
  # it also makes terraform destroy remove the pods while the nodes are still there to delete them
  # (rules.md D-2/D-4).
  depends_on = [
  module.network, module.nvidia_device_plugin]
}
# ---------------------------------------------------------------------------------------------------
# The time-slicing cluster: the same card, advertised several times.
# ---------------------------------------------------------------------------------------------------
module "time_slicing_eks_cluster" {
  source = "./modules/eks_cluster"

  name                   = var.time_slicing_cluster_name
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  depends_on = [module.network]
}
module "time_slicing_eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.time_slicing_eks_cluster.cluster_name

  depends_on = [module.network, module.time_slicing_eks_cluster]
}
module "time_slicing_eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.time_slicing_eks_cluster.cluster_name

  depends_on = [module.network, module.time_slicing_eks_vpc_cni_addon]
}
module "time_slicing_eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name    = module.time_slicing_eks_cluster.cluster_name
  node_group_name = var.gpu_node_group_name
  ami_type        = var.gpu_ami_type
  instance_types  = var.gpu_instance_types
  desired_size    = var.gpu_node_group_desired_size
  min_size        = var.gpu_node_group_min_size
  max_size        = var.gpu_node_group_max_size
  subnet_ids      = module.network.private_subnet_ids
  key_name        = module.key_pair.key_name

  depends_on = [module.network, module.time_slicing_eks_vpc_cni_addon, module.time_slicing_eks_kube_proxy_addon]
}
module "time_slicing_eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.time_slicing_eks_cluster.cluster_name

  depends_on = [
  module.network, module.time_slicing_eks_node_group]
}
# The one difference between the two clusters. The module creates the config map first and the release
# depends on it - the _monolithic template applied the config map *after* the chart that was told to read
# it, so the plugin came up without a sharing configuration and the time-slicing cluster behaved exactly
# like the other one (rules.md D-1).
module "time_slicing_device_plugin" {
  source = "./modules/nvidia_device_plugin"
  providers = {
    helm    = helm.time_slicing
    kubectl = kubectl.time_slicing
  }

  chart_version         = var.device_plugin_chart_version
  time_slicing_replicas = var.time_slicing_replicas

  depends_on = [
  module.network, module.time_slicing_eks_node_group, module.time_slicing_eks_coredns_addon]
}
module "time_slicing_gpu_workload" {
  source = "./modules/gpu_workload"
  providers = {
    kubectl = kubectl.time_slicing
  }

  namespace = var.workload_namespace
  app_image = var.app_image
  # More pods than there are physical GPUs per node, which is what the slicing makes possible.
  app_replicas = var.app_replicas_with_time_slicing

  depends_on = [
  module.network, module.time_slicing_device_plugin]
}
# ---------------------------------------------------------------------------------------------------
# The workbench, which reaches both clusters.
# ---------------------------------------------------------------------------------------------------
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  marker_file_path            = var.marker_file_path
  # Both clusters' security groups, so this instance can reach either API server. The module is handed an
  # ID list and never learns what they belong to (rules.md B-6).
  extra_security_group_ids = [
    module.nvidia_eks_cluster.cluster_security_group_id,
    module.time_slicing_eks_cluster.cluster_security_group_id,
  ]

  # Two EKS clusters and this instance share a root module, so it is the workbench for both and carries
  # all five tools (rules.md H-1). None of them creates anything: the device plugin releases and the pod
  # manifests the _monolithic template installed from here are Terraform resources now (rules.md E-1).
  #
  # Bugs from that template that are not carried over. It ran "exec bash" partway through, which replaces
  # the shell and silently discarded every remaining line - eksctl, helm, both update-kubeconfig calls,
  # both AWS Load Balancer Controller installs, both device plugin installs and every manifest were all
  # after it, so on a real boot nothing in either cluster was configured. It pulled eksctl from
  # weaveworks rather than eksctl-io. It wrote the "complete" line for the k alias into .bashrc before the
  # line that defines __start_kubectl, so every login printed a "function not found" error
  # (rules.md H-1). And it gave both clusters the kubeconfig alias "nvidia", so the second call
  # overwrote the first and there was no way to address the control cluster at all - the two contexts
  # below are named after the clusters.
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
    # One context per cluster, each named after it. The whole demo is running the same command against
    # both, so the names have to differ.
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.nvidia_eks_cluster.cluster_name} --alias ${module.nvidia_eks_cluster.cluster_name}
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.time_slicing_eks_cluster.cluster_name} --alias ${module.time_slicing_eks_cluster.cluster_name}
    EOF
  EOT

  depends_on = [module.network]
}
# Granting the bastion's instance role access to both clusters joins modules that know nothing about each
# other, so it belongs in the root (rules.md C-1). One entry and one association per cluster: access is
# granted on a cluster, not on a principal.
resource "aws_eks_access_entry" "nvidia_vscode" {
  cluster_name  = module.nvidia_eks_cluster.cluster_name
  principal_arn = module.vscode_ec2.iam_role_arn
  type          = "STANDARD"
}
resource "aws_eks_access_policy_association" "nvidia_vscode" {
  cluster_name  = module.nvidia_eks_cluster.cluster_name
  principal_arn = module.vscode_ec2.iam_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.nvidia_vscode]
}
resource "aws_eks_access_entry" "time_slicing_vscode" {
  cluster_name  = module.time_slicing_eks_cluster.cluster_name
  principal_arn = module.vscode_ec2.iam_role_arn
  type          = "STANDARD"
}
resource "aws_eks_access_policy_association" "time_slicing_vscode" {
  cluster_name  = module.time_slicing_eks_cluster.cluster_name
  principal_arn = module.vscode_ec2.iam_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.time_slicing_vscode]
}
locals {
  # Every output this project exposes, defined once. outputs.tf projects these and the README below
  # renders them, so no value expression is written twice (rules.md B-5/H-2).
  outputs = {
    # Order 0 so it heads the README without renumbering every entry below it.
    vscode_port_forward_command = {
      order       = 0
      title       = "Connect to code-server through SSM"
      description = "Run this on your own machine rather than here: it needs the AWS CLI and the Session Manager plugin installed locally, and it keeps running until you stop it. While it runs, http://localhost:${module.vscode_ec2.code_server_port} is this IDE. The tunnel rides the SSM agent's own outbound connection, so the security group needs no inbound rule for it - which is what lets allow_inbound_from_anywhere stay false. Changing both port numbers reaches anything else listening on the instance, such as the application port-forward below. SessionManagerPlugin is not found means the plugin is missing locally, not a permissions problem; TargetNotConnected means the agent on the instance has not registered with Systems Manager"
      # --region because the instance lives where this configuration was applied, which need not be the
      # CLI's default region on the machine running the command.
      value = "aws ssm start-session --region ${data.aws_region.current.region} --target ${module.vscode_ec2.instance_id} --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"${module.vscode_ec2.code_server_port}\"],\"localPortNumber\":[\"${module.vscode_ec2.code_server_port}\"]}'"
    }
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here, once the port forward above is running. Its kubeconfig has one context per cluster, named after the cluster - run the same command against both with \"kubectl --context <name>\", which is the whole demo"
      # The public address only when the security group admits it; otherwise a URL that would time out.
      value = var.allow_inbound_from_anywhere ? module.vscode_ec2.vscode_url : "http://localhost:${module.vscode_ec2.code_server_port}"
    }
    clusters = {
      order       = 2
      title       = "The two clusters"
      description = "Identical in every respect except the device plugin's configuration. Same VPC, same Kubernetes version, same AMI type, same instance type, same node count"
      value       = "${module.nvidia_eks_cluster.cluster_name} (no time slicing)\n${module.time_slicing_eks_cluster.cluster_name} (time slicing, ${module.time_slicing_device_plugin.time_slicing_replicas} slices per GPU)"
    }
    gpu_capacity = {
      order       = 3
      title       = "What each cluster advertises and what it was asked for"
      description = "The numbers the comparison comes down to. Each node has one physical GPU; what differs is how many nvidia.com/gpu the plugin says that is, and therefore how many pods can be scheduled"
      value       = "${module.nvidia_eks_cluster.cluster_name}: ${module.nvidia_gpu_workload.gpu_request_total} GPU(s) requested by the workload\n${module.time_slicing_eks_cluster.cluster_name}: ${module.time_slicing_gpu_workload.gpu_request_total} GPU(s) requested by the workload, against ${module.time_slicing_device_plugin.time_slicing_replicas} advertised per card"
    }
    advertised_gpu_command = {
      order       = 4
      title       = "1. Read the advertised GPU count on both clusters"
      description = "The one command that shows the difference. Without slicing each node reports 1; with it, each reports the slice count - on identical hardware"
      value       = "kubectl --context ${module.nvidia_eks_cluster.cluster_name} ${trimprefix(module.nvidia_device_plugin.advertised_gpu_command, "kubectl ")}\nkubectl --context ${module.time_slicing_eks_cluster.cluster_name} ${trimprefix(module.time_slicing_device_plugin.advertised_gpu_command, "kubectl ")}"
    }
    smi_output_command = {
      order       = 5
      title       = "2. Confirm a container really got a GPU"
      description = "nvidia-smi from inside a bare Amazon Linux image that contains no NVIDIA tooling. It works because the runtime injects the host's driver into any container that requested nvidia.com/gpu - so a GPU table here means the AMI, the plugin and the runtime are all doing their part"
      value       = "kubectl --context ${module.nvidia_eks_cluster.cluster_name} ${trimprefix(module.nvidia_gpu_workload.smi_output_command, "kubectl ")}"
    }
    pod_status_command = {
      order       = 6
      title       = "3. Compare where the pods ended up"
      description = "On the time-slicing cluster more application pods are Running than there are physical GPUs on their node. On the other cluster the same thing would leave the surplus pods Pending, which is worth producing on purpose - see the next command"
      value       = "kubectl --context ${module.nvidia_eks_cluster.cluster_name} ${trimprefix(module.nvidia_gpu_workload.pod_status_command, "kubectl ")}\nkubectl --context ${module.time_slicing_eks_cluster.cluster_name} ${trimprefix(module.time_slicing_gpu_workload.pod_status_command, "kubectl ")}"
    }
    oversubscribe_command = {
      order       = 7
      title       = "4. Ask the control cluster for more GPUs than it has"
      description = "Raises the replica count on the cluster without slicing. The surplus pods stay Pending with \"Insufficient nvidia.com/gpu\" - which is the wall the other cluster does not hit, and the reason time slicing exists"
      value       = "terraform apply -var app_replicas_without_time_slicing=${var.gpu_node_group_desired_size * 2 + 1}"
    }
    pending_reason_command = {
      order       = 8
      title       = "5. Read why a pod is Pending"
      description = "\"Insufficient nvidia.com/gpu\" is the scheduler saying the advertised count is exhausted - not that the node has no GPU. That distinction is the whole point of the advertised count"
      value       = "kubectl --context ${module.nvidia_eks_cluster.cluster_name} ${trimprefix(module.nvidia_gpu_workload.pending_reason_command, "kubectl ")}"
    }
    time_slicing_config_command = {
      order       = 9
      title       = "6. Read the slicing configuration from the cluster"
      description = "What the plugin loaded, as the cluster holds it. The _monolithic template applied this config map after the chart that reads it, so the plugin started with none - and a time-slicing cluster with no configuration is indistinguishable from the cluster it is being compared against"
      value       = module.time_slicing_device_plugin.config_map_check_command
    }
    plugin_log_command = {
      order       = 10
      title       = "7. If the counts are not what they should be"
      description = "The plugin states the sharing configuration it loaded in its own log. This is the only place that tells \"time slicing is off\" apart from \"the config map was not found\""
      value       = "kubectl --context ${module.time_slicing_eks_cluster.cluster_name} ${trimprefix(module.time_slicing_device_plugin.plugin_log_command, "kubectl ")}"
    }
    port_forward_command = {
      order       = 11
      title       = "8. Open the application's interface"
      description = "Nothing publishes it: there is no Service and no load balancer here, which the _monolithic template also did not have despite passing --ui-expose. Forward the port on the workbench and open it from the IDE"
      value       = "kubectl --context ${module.time_slicing_eks_cluster.cluster_name} ${trimprefix(module.time_slicing_gpu_workload.port_forward_command, "kubectl ")}"
    }
    app_rollout_command = {
      order       = 12
      title       = "Waiting for the application"
      description = "The image is about 2.1 GB of CUDA and cuDNN runtime, so the first pull on each node is the slowest part of the whole apply - minutes rather than seconds. It holds no model weights: the application downloads those after it starts, so a Running pod is not yet an interface that answers"
      value       = "kubectl --context ${module.time_slicing_eks_cluster.cluster_name} ${trimprefix(module.time_slicing_gpu_workload.app_rollout_command, "kubectl ")}"
    }
    update_kubeconfig_commands = {
      order       = 13
      title       = "Re-point kubectl"
      description = "User data already ran both, with one context per cluster. Re-run them if the kubeconfig is ever lost - and keep the aliases distinct, which the original did not"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.nvidia_eks_cluster.cluster_name} --alias ${module.nvidia_eks_cluster.cluster_name}\naws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.time_slicing_eks_cluster.cluster_name} --alias ${module.time_slicing_eks_cluster.cluster_name}"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the order field and taking
  # values() - which returns a map's values ordered by key - makes the README read top to bottom while the
  # order stays decided by configuration.
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  readme_body = join("\n", concat(
    ["# ${var.nvidia_cluster_name} and ${var.time_slicing_cluster_name}", ""],
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
