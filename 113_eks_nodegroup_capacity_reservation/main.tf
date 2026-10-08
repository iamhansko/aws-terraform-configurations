data "aws_region" "current" {}
# The EKS-optimized NVIDIA AMI for the GPU node group.
#
# The path is built from kubernetes_version rather than hardcoded, which is what the _monolithic template did:
# it wrote 1.36 into the SSM parameter path while taking the cluster version as a parameter, so selecting 1.34
# produced a 1.34 cluster with a 1.36 kubelet. A kubelet newer than its API server is not a supported skew - it
# is the direction EKS refuses outright.
#
# The nvidia variant carries the driver, the CUDA user mode driver and the container toolkit. It does not
# carry the NVIDIA device plugin DaemonSet, which is the thing that advertises nvidia.com/gpu to the
# scheduler: "The EKS-optimized AL2023 NVIDIA AMIs do not include the NVIDIA Kubernetes device plugin or the
# NVIDIA DRA driver, and these must be installed separately"
# (https://docs.aws.amazon.com/eks/latest/userguide/ml-eks-optimized-ami.html). The Bottlerocket NVIDIA
# variant does include it, which is the source of the belief that the AMI covers this. So the plugin is a
# module below rather than something to check for after the fact.
data "aws_ssm_parameter" "gpu_node_ami_id" {
  name = "/aws/service/eks/optimized-ami/${var.kubernetes_version}/amazon-linux-2023/x86_64/nvidia/recommended/image_id"
}
locals {
  key_name = var.key_name == null ? "${var.cluster_name}-key" : var.key_name
  # The one zone that ties the reservation, the subnet and the node together. A capacity reservation is zonal,
  # so all three have to name it - derived once here rather than repeated (rules.md B-5).
  gpu_availability_zone = "${data.aws_region.current.region}${var.gpu_availability_zone_suffix}"
  # The labels the GPU node actually carries, which is var.gpu_node_labels plus the one the device plugin's
  # chart requires.
  #
  # nvidia.com/gpu.present is the third of three alternative node affinity terms the nvidia-device-plugin
  # chart gives its DaemonSet; the other two are set by node-feature-discovery, which this project does not
  # install. A node matching none of them gets no plugin pod, so it advertises no nvidia.com/gpu and every pod
  # requesting a GPU stays Pending - while the DaemonSet, wanting zero pods, reports ready and the Helm
  # release reports success. Merged here rather than written into the variable's default so the label sits
  # next to the reason it exists, and merged in this order so a caller cannot remove it by accident.
  gpu_node_labels = merge(var.gpu_node_labels, { "nvidia.com/gpu.present" = "true" })
  # The same map as a kubelet --node-labels argument, because on this node group the labels have to be
  # delivered twice over.
  #
  # aws_eks_node_group.labels is how EKS is told what the nodes are labelled, and EKS delivers that to the
  # kubelet by merging its own NodeConfig into the launch template's user data. It does not do that here:
  # "If a custom AMI ID is specified in a launch template, Amazon EKS doesn't merge user data"
  # (https://docs.aws.amazon.com/eks/latest/userguide/launch-templates.html), and this node group names the
  # EKS-optimized NVIDIA AMI explicitly so it can pin it to the cluster's Kubernetes version. So the node
  # group records the labels in its API object and the node never receives them.
  #
  # That failure is quiet in both directions: describe-nodegroup shows the labels, and "kubectl get nodes
  # --show-labels" does not. It is why the GPU workload below carries a nodeSelector that would have matched
  # nothing. Both consumers read this one map (rules.md B-5).
  gpu_node_labels_kubelet_flag = "--node-labels=${join(",", [for key, value in local.gpu_node_labels : "${key}=${value}"])}"
}
module "network" {
  source = "./modules/network"

  region                     = data.aws_region.current.region
  vpc_cidr_block             = var.vpc_cidr_block
  availability_zone_suffixes = var.availability_zone_suffixes
  # The same two zones, so the regional NAT gateway has an address in each - the GPU node is in a private
  # subnet and pulls its container images through it.
  nat_availability_zone_suffixes = var.availability_zone_suffixes
  vpc_name                       = "${var.cluster_name}-vpc"
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name = local.key_name

  # key_pair consumes no network output, so nothing would otherwise order it against the network module's
  # resources (rules.md D-3).
  depends_on = [module.network]
}
module "eks_cluster" {
  source = "./modules/eks_cluster"

  name                   = var.cluster_name
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  # Referencing module.network.*_subnet_ids only orders this after the specific aws_subnet resources behind
  # those outputs, not after the NAT gateway and route table associations that never surface as outputs
  # (rules.md D-3).
  depends_on = [module.network]
}
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not exist until this addon creates
  # it. As a DaemonSet it reaches ACTIVE with zero nodes, so it comes before any capacity - and nodes need it to
  # join Ready (rules.md C-4). The _monolithic template declared its four addons with no ordering at all and no
  # bootstrap flag, so EKS installed three of them as unmanaged addons first.
  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  depends_on = [module.network, module.eks_vpc_cni_addon]
}
# Required by the load balancer controller's Pod Identity association: the agent is what delivers credentials
# to the pod. Without it the association exists, the controller starts, and every AWS call it makes fails
# with no credentials.
module "eks_pod_identity_agent_addon" {
  source = "./modules/eks_pod_identity_agent_addon"

  cluster_name = module.eks_cluster.cluster_name

  # A DaemonSet, so it reaches ACTIVE with no nodes (rules.md C-4).
  depends_on = [module.network, module.eks_vpc_cni_addon]
}
# The reservation, created before the node group that launches into it.
module "gpu_capacity_reservation" {
  source = "./modules/gpu_capacity_reservation"

  instance_type     = var.gpu_instance_type
  availability_zone = local.gpu_availability_zone
  instance_count    = var.gpu_reserved_instance_count
  end_date          = var.gpu_reservation_end_date
  tags = {
    Name = "${var.cluster_name}-gpu-reservation"
  }

  # A reservation needs nothing from the network, but every module in a root with a network module waits for
  # all of it (rules.md D-3).
  depends_on = [module.network]
}
module "eks_gpu_node_group" {
  source = "./modules/eks_node_group"

  cluster_name    = module.eks_cluster.cluster_name
  node_group_name = "${var.cluster_name}-gpu"
  # Empty, because the launch template names the type instead - which it has to, since the reservation covers
  # one exact type and EKS rejects both places naming one. The module validates that exactly one of the two is
  # set.
  instance_types                = []
  launch_template_instance_type = module.gpu_capacity_reservation.instance_type
  # capacity-reservations-only: the node launches into the reservation or not at all. That is the behaviour
  # being demonstrated - falling back to ordinary On-Demand capacity would hide whether the reservation worked.
  capacity_reservation_id = module.gpu_capacity_reservation.id
  desired_size            = var.gpu_node_desired_size
  min_size                = var.gpu_node_desired_size
  # Capped at what is reserved. A larger maximum is not an error, but with capacity-reservations-only the extra
  # instances cannot launch - so the node group would sit degraded rather than scaling.
  max_size = var.gpu_reserved_instance_count
  labels   = local.gpu_node_labels
  # MINIMAL, because this group is pinned to a reservation holding exactly as many instances as it runs. The
  # DEFAULT strategy launches a replacement node before draining the one it replaces, and with
  # capacity-reservations-only there is no free slot for it and no ordinary capacity to fall back on - so a
  # launch template change would wait on capacity that cannot appear. The module validates the combination.
  update_strategy        = var.gpu_node_update_strategy
  update_max_unavailable = var.gpu_node_update_max_unavailable
  # The one private subnet in the reservation's zone. A reservation is zonal, so any other subnet leaves it
  # unused and the node group unable to launch.
  subnet_ids    = [module.network.private_subnet_ids_by_zone[var.gpu_availability_zone_suffix]]
  key_name      = module.key_pair.key_name
  custom_ami_id = data.aws_ssm_parameter.gpu_node_ami_id.insecure_value
  # A custom AMI means EKS does not inject its own bootstrap, so the node has to be told how to join. MIME
  # multipart with a NodeConfig document, which is the only form EKS accepts here - a bare shell script or a
  # bare NodeConfig is silently ignored and the node never registers.
  #
  # The kubelet flags carry the node labels, and they have to: the same rule that means EKS does not inject a
  # bootstrap also means it does not merge its own NodeConfig in, so the labels field above never reaches the
  # kubelet on its own. local.gpu_node_labels_kubelet_flag derives the flag from the same map, and the
  # comment on it explains the rest. Nothing is commented inside the document itself, because every line of
  # it is base64-encoded into the launch template's user data.
  custom_user_data = <<-EOT
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary="BOUNDARY"

    --BOUNDARY
    Content-Type: application/node.eks.aws

    apiVersion: node.eks.aws/v1alpha1
    kind: NodeConfig
    spec:
      cluster:
        name: ${module.eks_cluster.cluster_name}
        apiServerEndpoint: ${module.eks_cluster.cluster_endpoint}
        certificateAuthority: ${module.eks_cluster.certificate_authority_data}
        cidr: ${var.service_ipv4_cidr}
      kubelet:
        config:
          clusterDNS:
          - ${cidrhost(var.service_ipv4_cidr, 10)}
        flags:
        - ${local.gpu_node_labels_kubelet_flag}

    --BOUNDARY--
  EOT
  instance_tags = {
    Name = "${var.cluster_name}-gpu-node"
  }

  # Nodes need vpc-cni and kube-proxy running to join the cluster Ready, and the reservation has to exist
  # before an instance can launch into it (rules.md C-4/D-2).
  depends_on = [module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon, module.gpu_capacity_reservation]
}
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.eks_cluster.cluster_name

  # coredns is a Deployment and needs schedulable capacity to leave DEGRADED and become ACTIVE (rules.md C-4).
  # With one GPU node as the only capacity in this cluster, that node is where CoreDNS lands.
  depends_on = [
  module.network, module.eks_gpu_node_group]
}
# What turns the node's GPU into a schedulable resource. The AL2023 NVIDIA AMI carries the driver and the
# container toolkit but not this plugin, so without it the node is Ready, nvidia-smi works on the host, and
# nvidia.com/gpu does not exist as far as the scheduler is concerned.
#
# Not in the _monolithic template either, which is why its own GPU test pod could not have been scheduled.
module "nvidia_device_plugin" {
  source = "./modules/nvidia_device_plugin"

  chart_version   = var.nvidia_device_plugin_chart_version
  timeout_seconds = var.nvidia_device_plugin_timeout_seconds
  # False, so no node-feature-discovery comes along. The DaemonSet's node affinity is satisfied by the
  # nvidia.com/gpu.present label local.gpu_node_labels puts on the node instead, which is the cheaper of the
  # two routes and the only one that does not add a controller to a single-node cluster.
  enable_gpu_feature_discovery = var.enable_gpu_feature_discovery

  # The DaemonSet has to have a GPU node to land on, and wait = true inside the module would otherwise hold
  # the apply open against a cluster with no capacity. CoreDNS is in the list because the plugin's pod
  # resolves nothing itself but the release's readiness check runs against a cluster that has to be
  # functioning - and because ordering every Kubernetes-side module after it keeps destroy in the reverse of
  # apply (rules.md D-2/D-4).
  depends_on = [module.network, module.eks_gpu_node_group, module.eks_coredns_addon]
}
# The load balancer controller, with a Pod Identity association rather than IRSA.
#
# The _monolithic template created the role and the association and then installed the chart from the
# workbench's user data - below an "exec bash" line that replaced the shell, so the install never ran and the
# role and association sat unused (rules.md E-1/H-1).
module "aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"

  cluster_name  = module.eks_cluster.cluster_name
  vpc_id        = module.network.vpc_id
  aws_region    = data.aws_region.current.region
  chart_version = var.aws_load_balancer_controller_chart_version
  # One replica: there is one node in this cluster, so a second would stay Pending.
  replica_count = 1

  # The Pod Identity agent has to be running before the controller pod starts, and CoreDNS has to be answering
  # before it can reach the EKS API - neither is implied by the arguments above (rules.md D-2).
  depends_on = [module.network, module.eks_pod_identity_agent_addon, module.eks_gpu_node_group, module.eks_coredns_addon]
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name                        = "vscode"
  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_ids[0]
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  security_group_name         = "${var.cluster_name}-vscode-sg"
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  marker_file_path            = var.marker_file_path
  # The cluster security group, so kubectl reaches the API server without leaving the VPC. Injected as an ID
  # list so the module never learns what it belongs to (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]

  # An EKS cluster and this instance share a root module, so it carries the workbench tooling (rules.md H-1).
  #
  # Bugs from the _monolithic template that are not carried over. It ran "exec bash" partway through user
  # data, which replaces the shell and silently discarded everything after it - eksctl, helm, the kubeconfig
  # and the load balancer controller install were all below that line. It pulled eksctl from weaveworks rather
  # than eksctl-io. And it wrote the "complete" line for the k alias into .bashrc before the line that defines
  # __start_kubectl, so every login printed a "function not found" error (rules.md H-1).
  additional_user_data = <<-EOT
    sudo -Eu ec2-user bash << 'EOF'
    set -euo pipefail
    export HOME=/home/ec2-user
    cd /home/ec2-user
    mkdir -p /home/ec2-user/bin
    curl -sO https://s3.us-west-2.amazonaws.com/amazon-eks/${var.kubectl_download_version}/bin/linux/amd64/kubectl
    chmod +x kubectl
    mv kubectl /home/ec2-user/bin/kubectl
    export PATH=/home/ec2-user/bin:$PATH
    echo 'export PATH=/home/ec2-user/bin:$PATH' >> ~/.bashrc
    # Order matters: kubectl's completion defines __start_kubectl, and that has to exist before complete names
    # it, or every login prints "function not found" (rules.md H-1).
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
resource "aws_eks_access_entry" "vscode" {
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.vscode_ec2.iam_role_arn
  type          = "STANDARD"
}
resource "aws_eks_access_policy_association" "vscode" {
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.vscode_ec2.iam_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }

  # The _monolithic template declared the association and the entry as unrelated resources, so nothing ordered
  # the association after the entry it depends on (rules.md D-1).
  depends_on = [aws_eks_access_entry.vscode]
}
locals {
  # Every output this project exposes, defined once. outputs.tf projects these and the README below renders
  # them, so no value expression is written twice (rules.md B-5/H-2).
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here. kubectl is already pointed at the cluster, and the commands below are meant to be run in its terminal"
      value       = module.vscode_ec2.vscode_url
    }
    cost_note = {
      order       = 2
      title       = "What this costs while idle"
      description = "The one thing about this project that is easy to leave running by accident. Reserved capacity is billed from creation until the reservation is deleted, whether or not an instance occupies it - so scaling the node group to zero does not stop the charge. Only terraform destroy, or an end date on the reservation, does"
      value       = module.gpu_capacity_reservation.billing_note
    }
    cluster_name = {
      order       = 3
      title       = "EKS cluster name"
      description = "Name of the EKS cluster"
      value       = module.eks_cluster.cluster_name
    }
    reservation = {
      order       = 4
      title       = "The capacity reservation"
      description = "One instance type in one zone, which is what makes it useful for scarce GPU capacity and what constrains everything downstream: the node group gets the single private subnet in this zone, and its maximum size is capped at what is reserved"
      value       = "${module.gpu_capacity_reservation.id}: ${module.gpu_capacity_reservation.instance_count} x ${module.gpu_capacity_reservation.instance_type} in ${module.gpu_capacity_reservation.availability_zone} (open-ended=${module.gpu_capacity_reservation.is_open_ended})"
    }
    reservation_usage_command = {
      order       = 5
      title       = "1. Is the reservation actually being used"
      description = "AvailableInstanceCount below TotalInstanceCount means the node is occupying it. Equal counts with the node group up means the instances launched outside the reservation, which points at the launch template's capacity_reservation_target"
      value       = module.gpu_capacity_reservation.usage_command
    }
    node_command = {
      order       = 6
      title       = "2. Did the GPU node join"
      description = "With capacity-reservations-only a node that cannot get reserved capacity does not launch at all - so no node here means the reservation is full or in the wrong zone, not that the AMI or the bootstrap failed"
      value       = "kubectl get nodes -L nodegroup,node.kubernetes.io/instance-type,topology.kubernetes.io/zone"
    }
    gpu_capacity_command = {
      order       = 7
      title       = "3. Does the node advertise a GPU"
      description = "Should read 1. The AMI carries the driver and the container toolkit but not the device plugin, so this number comes from the nvidia_device_plugin module rather than from the AMI. An empty column with the node Ready means the plugin's DaemonSet matched no node - check its DESIRED count next, not the driver"
      value       = "kubectl get nodes -o custom-columns='NODE:.metadata.name,GPU:.status.allocatable.nvidia\\.com/gpu'"
    }
    device_plugin_daemon_set_command = {
      order       = 8
      title       = "4. Is the device plugin running"
      description = "DESIRED 1 and READY 1. DESIRED 0 is the failure worth knowing the shape of: the chart requires one of three node labels on a GPU node, this project supplies nvidia.com/gpu.present through the node group's kubelet flags, and a DaemonSet wanting zero pods still counts as ready - so the Helm release succeeds and no GPU is ever advertised"
      value       = module.nvidia_device_plugin.daemon_set_check_command
    }
    gpu_node_labels_note = {
      order       = 9
      title       = "The labels the GPU node carries"
      description = "Both of these are delivered as kubelet --node-labels flags in the node group's NodeConfig, not by the node group's labels field. EKS does not merge its NodeConfig into the user data of a launch template that names an AMI, and this one names the NVIDIA AMI - so the labels field alone records them in the EKS API and never reaches the node. nodegroup is what the GPU workload below selects on; nvidia.com/gpu.present is what the device plugin's DaemonSet requires"
      value       = join(" ", [for key, value in local.gpu_node_labels : "${key}=${value}"])
    }
    gpu_workload_snippet = {
      order       = 10
      title       = "5. Run something on the GPU"
      description = "A pod that requests one GPU and lands on the reserved node. It needs both halves of this project to be in place: the nodeSelector matches a label the node group delivers through its kubelet flags, and the resource limit matches what the device plugin advertises. If it stays Pending, read its events - \"Insufficient nvidia.com/gpu\" points at the plugin and \"didn't match Pod's node affinity/selector\" at the labels"
      value       = "kubectl run gpu-check --rm -it --restart=Never --image=nvidia/cuda:12.4.1-base-ubuntu22.04 --overrides='{\"spec\":{\"nodeSelector\":{\"nodegroup\":\"gpu\"},\"containers\":[{\"name\":\"gpu-check\",\"image\":\"nvidia/cuda:12.4.1-base-ubuntu22.04\",\"command\":[\"nvidia-smi\"],\"resources\":{\"limits\":{\"nvidia.com/gpu\":1}}}]}}'"
    }
    node_group_ami = {
      order       = 11
      title       = "The AMI the node launched from"
      description = "The EKS-optimized NVIDIA image for this cluster's Kubernetes version. The _monolithic template hardcoded 1.36 into this parameter path while taking the cluster version as a parameter, so a 1.34 cluster got a 1.36 kubelet - which EKS does not support in that direction"
      value       = data.aws_ssm_parameter.gpu_node_ami_id.insecure_value
    }
    node_group_update_strategy_note = {
      order       = 12
      title       = "Why the node group can be changed at all"
      description = "EKS's DEFAULT update strategy launches a replacement node before draining the one it replaces, which needs a free instance slot. This reservation holds exactly as many instances as the group runs and capacity-reservations-only gives it nothing to fall back on, so any launch template change would wait on capacity that cannot appear. MINIMAL drains first and the replacement takes the freed slot - at the cost of the group having no capacity meanwhile"
      value       = module.eks_gpu_node_group.update_strategy
    }
    load_balancer_controller_command = {
      order       = 13
      title       = "6. Is the load balancer controller running"
      description = "It authenticates with Pod Identity rather than IRSA, so its service account carries no role-arn annotation - the binding is the association resource instead. A controller reporting AccessDenied with the association in place usually means the pod identity agent addon is missing"
      value       = "kubectl -n ${module.aws_load_balancer_controller.namespace} get pods -l app.kubernetes.io/name=aws-load-balancer-controller -o wide"
    }
    pod_identity_command = {
      order       = 14
      title       = "7. Read the Pod Identity association"
      description = "What replaces IRSA's service account annotation. This is the whole binding between the controller's service account and its IAM role, and it is a resource rather than a string - so it appears in plan and is removable without editing IAM"
      value       = "aws eks list-pod-identity-associations --cluster-name ${module.eks_cluster.cluster_name} --query 'associations[].[namespace,serviceAccount,associationId]' --output table"
    }
    update_kubeconfig_command = {
      order       = 15
      title       = "Re-point kubectl"
      description = "User data already ran this. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
    private_key_command = {
      order       = 16
      title       = "The workbench's SSH private key"
      description = "Written to SSM Parameter Store as a SecureString, which is where CloudFormation puts a generated key pair's private half"
      value       = "aws ssm get-parameter --name /ec2/keypair/${module.key_pair.key_pair_id} --with-decryption --query Parameter.Value --output text"
    }
  }
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
# The work happens inside code-server in a browser, where terraform output is not available, so every output
# above is also written to a README in the home directory the IDE opens (rules.md H-2). The _monolithic
# template wrote "# EKS Cluster" and nothing else.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is what orders this after the
    # bootstrap (rules.md D-5). The marker path comes back out of the module it was passed into
    # (rules.md B-5).
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/userdata ]; do sleep 10; done
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_readme
      EOT
  }

  depends_on = [module.vscode_ec2]
}
