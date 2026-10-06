data "aws_region" "current" {}

module "network" {
  source = "./modules/network"

  region                         = data.aws_region.current.region
  vpc_cidr_block                 = var.vpc_cidr_block
  availability_zone_suffixes     = var.availability_zone_suffixes
  nat_availability_zone_suffixes = var.nat_availability_zone_suffixes
  vpc_name                       = "${var.project_name}-vpc"
  # The AWS Load Balancer Controller finds subnets by tag rather than by
  # configuration, and a scheme that does not match the tags fails with
  # "couldn't auto-discover subnets" (rules.md G-1). Tagging here means the
  # controller can place a load balancer the moment someone adds an Ingress,
  # without editing the network.
  subnet_tags = {
    "kubernetes.io/role/elb"          = "1"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

module "key_pair" {
  source = "./modules/key_pair"

  key_name = "${var.project_name}-key"

  # Nothing here reads a network output, but the root orders every module after
  # the network so the whole VPC - NAT gateway and route tables included - is
  # finished before anything starts in it (rules.md D-3).
  depends_on = [module.network]
}

module "eks_cluster" {
  source = "./modules/eks_cluster"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version
  # Every subnet, public and private. The control plane's cross-account ENIs go
  # into these, and Fargate pods get a narrower list of their own below.
  subnet_ids                = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_private_access   = var.endpoint_private_access
  endpoint_public_access    = var.endpoint_public_access
  public_access_cidrs       = var.public_access_cidrs
  enabled_cluster_log_types = var.enabled_cluster_log_types

  # public_subnet_ids/private_subnet_ids order this after the specific aws_subnet
  # resources that produced them and nothing else - not the NAT gateway, not the
  # route table associations (rules.md D-3).
  depends_on = [module.network]
}

# vpc-cni and kube-proxy are DaemonSets, so on a cluster with no nodes at all
# they settle at desired == ready == 0 and go ACTIVE immediately. They are still
# declared, and still created before any compute exists, for the reason
# rules.md C-4 gives: with bootstrap_self_managed_addons = false nothing installs
# them otherwise, and an addon EKS does not know about is an addon Terraform
# cannot version or configure.
#
# On this cluster they are close to inert - Fargate pods get their ENI from the
# Fargate control plane rather than from the CNI DaemonSet, and there is no
# kube-proxy to run without a node. Declaring them keeps the cluster's addon set
# complete, so adding a node group later needs no new plumbing.
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

# One profile carrying both selectors, as the _monolithic template had it. EKS
# serialises Fargate profile creation per cluster and rejects a concurrent second
# create with ResourceInUseException, so one profile with two selectors avoids a
# chain of depends_on between profiles.
#
# Private subnets only: Fargate refuses a profile pointed at a subnet that maps
# public IPs, and the pods reach the internet - and pull images - through the
# regional NAT gateway.
module "eks_fargate_profile" {
  source = "./modules/eks_fargate_profile"

  cluster_name = module.eks_cluster.cluster_name
  profile_name = var.fargate_profile_name
  namespaces   = var.fargate_namespaces
  subnet_ids   = module.network.private_subnet_ids

  # A pod cannot join the cluster Ready before vpc-cni and kube-proxy exist, and
  # nothing in the value references says so (rules.md C-4).
  depends_on = [module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}

# CoreDNS is a Deployment, so unlike the two DaemonSets above it needs
# schedulable capacity to leave DEGRADED and become ACTIVE. On this cluster that
# capacity is the Fargate profile (rules.md C-4).
#
# compute_type = "Fargate" is what makes DNS work here at all. EKS ships the
# CoreDNS Deployment annotated eks.amazonaws.com/compute-type: ec2, and with that
# annotation the pods stay Pending forever on a cluster with no nodes. The
# _monolithic template addressed this with `kubectl rollout restart deployment
# coredns` from user data, which only helps if the annotation is gone; setting it
# as addon configuration removes the annotation declaratively and needs no
# rollout trigger (contrast rules.md E-4).
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name          = module.eks_cluster.cluster_name
  coredns_replica_count = var.coredns_replica_count
  compute_type          = "Fargate"

  depends_on = [
  module.network, module.eks_fargate_profile]
}

# The IRSA role and the Helm release stay in one module: they reference each
# other, so splitting them would only move the coupling into the root
# (rules.md C-2).
#
# The controller is not used by anything this project creates - there is no
# Ingress and no Service of type LoadBalancer in the EFS demo. It is here because
# the _monolithic template installed it (its IRSA role was a template resource,
# not just a user data side effect), and because it is what makes the cluster
# usable for an Ingress demo from the workbench. The chart version is pinned,
# unlike the template's bare `helm install`.
module "aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"

  cluster_name      = module.eks_cluster.cluster_name
  vpc_id            = module.network.vpc_id
  aws_region        = data.aws_region.current.region
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  chart_version     = var.load_balancer_controller_chart_version
  replica_count     = var.load_balancer_controller_replica_count
  timeout_seconds   = var.load_balancer_controller_timeout_seconds

  # The release waits for the Deployment to become Available, so the controller
  # pods need somewhere to run first; kube-system is selected by the Fargate
  # profile. CoreDNS is in the list because a controller pod that cannot resolve
  # anything is a pod that will be restarted while Helm is still waiting
  # (rules.md D-2).
  depends_on = [module.network, module.eks_fargate_profile, module.eks_coredns_addon]
}

# The file system the demo mounts. Static provisioning means it has to exist
# before any volume references it, which is why it is an AWS resource here rather
# than something a StorageClass creates on demand - and why Fargate, which
# supports no dynamic provisioning, can use it at all.
module "efs_file_system" {
  source = "./modules/efs_file_system"

  name                = var.efs_name
  vpc_id              = module.network.vpc_id
  security_group_name = var.efs_security_group_name
  performance_mode    = var.efs_performance_mode
  # One mount target per private subnet. A pod can only reach the file system
  # through the mount target in its own zone, so a zone without one fails to
  # mount instead of falling back - and Fargate chooses the zone, not the caller.
  mount_target_subnet_ids = module.network.private_subnet_ids_by_zone
  # The _monolithic template opened NFS to the whole VPC CIDR. Kept, because the
  # client here is a Fargate pod whose ENI belongs to the cluster security group,
  # and narrowing this to that group would still admit every pod in the cluster
  # while making the rule harder to read.
  ingress_cidr_blocks = [module.network.vpc_cidr_block]

  depends_on = [module.network]
}

# The demo itself: a StorageClass, two PersistentVolume/PersistentVolumeClaim
# pairs onto the same file system, and a writer and a reader pod. The
# _monolithic template rendered these as five YAML files from user data and
# applied four of them with kubectl, so none of it was in state and the file
# system ID reached the cluster by shell substitution (rules.md E-1/E-2).
module "efs_static_volume_workload" {
  source = "./modules/efs_static_volume_workload"

  file_system_id      = module.efs_file_system.file_system_id
  namespace           = var.workload_namespace
  storage_capacity    = var.workload_storage_capacity
  register_csi_driver = var.register_csi_driver

  # These objects reach the cluster's API server directly, and the pods they
  # create only run because the Fargate profile selects their namespace. Ordering
  # the module after the profile is also what makes `terraform destroy` remove
  # the pods and claims before the profile that runs them disappears - without
  # it, destroy can strand a claim whose deletion waits on a kubelet that is
  # already gone (rules.md D-4).
  #
  # The mount targets are in the list for a different reason: a pod that starts
  # before the mount target in its zone exists fails to mount and stays in
  # ContainerCreating, and module.efs_file_system.file_system_id orders this after
  # the file system only, not after its mount targets (rules.md D-3 is the same
  # argument about the network module).
  depends_on = [
  module.network, module.efs_file_system, module.eks_fargate_profile, module.eks_coredns_addon]
}

module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name                        = "${var.project_name}-vscode"
  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_ids_by_zone[var.availability_zone_suffixes[0]]
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  code_server_version         = var.code_server_version
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  # Tells the README association below when the bootstrap has finished
  # (rules.md H-2). The module touches <path>/userdata as its very last step,
  # after everything in additional_user_data has run - touching it earlier would
  # start the association while kubectl and helm were still installing.
  marker_file_path = var.marker_file_path
  # Joining the cluster security group is what lets this instance reach the API
  # server on its private address. The module is handed an ID list and never
  # learns that it belongs to an EKS cluster (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]
  # An EKS cluster and this instance share a root module, so this instance is the
  # workbench for that cluster and carries all five tools: code-server (the
  # module's own job) plus kubectl, eksctl, helm and docker (rules.md H-1).
  #
  # None of them creates anything. The _monolithic template used this same script
  # to `helm install` the load balancer controller and `kubectl apply` five
  # manifests; those are provider resources now (rules.md E-1), and what is left
  # here is only what a person needs to look at the cluster.
  #
  # The tools go in as ec2-user so the binaries, the kubeconfig and the .bashrc
  # additions land in /home/ec2-user, which is the directory code-server opens
  # and the user it runs as. HOME is set explicitly: user data runs as root, and
  # whether sudo keeps root's HOME depends on the sudoers configuration, so "~"
  # cannot be relied on to mean /home/ec2-user.
  additional_user_data = <<-EOT
    # Building an image or pushing one to ECR needs a daemon on the host, which
    # is the one thing here that no provider resource can replace
    # (rules.md E-1/H-1).
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server is already running from the module's bootstrap, so its process
    # predates the docker group and its terminals inherit the groups that process
    # started with. Restarting is what makes docker usable from the IDE, rather
    # than opening /var/run/docker.sock up to 666 as the _monolithic template did.
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
    # exist before complete references it. The _monolithic template had the
    # complete line first, so every login printed "function not found"
    # (rules.md H-1).
    echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
    echo 'source <(kubectl completion bash)' >> ~/.bashrc
    echo 'alias k=kubectl' >> ~/.bashrc
    echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
    # No `exec bash` here. The _monolithic template ran one at this point, which
    # replaced the shell and silently discarded everything after it - eksctl,
    # helm, the kubeconfig and every kubectl apply never ran.
    #
    # eksctl-io is the project's own org; the old weaveworks URL still redirects
    # but the current name is what gets used (rules.md H-1).
    PLATFORM=$(uname -s)_amd64
    curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
    tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
    sudo install -m 0755 /tmp/eksctl /usr/local/bin && rm /tmp/eksctl
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm -f get_helm.sh
    aws configure set default.region ${data.aws_region.current.region}
    # Without this - and without the access entry below - kubectl is installed
    # but every command answers "You must be logged in to the server"
    # (rules.md H-1).
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}
    EOF
  EOT

  depends_on = [module.network]
}

# Granting the workbench's instance role cluster access joins two modules that
# know nothing about each other, so it belongs in the root rather than inside
# either one (rules.md C-1).
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

  # EKS rejects a policy association for a principal that has no access entry
  # yet, and the two resources share only literal argument values, so nothing
  # orders them (rules.md D-1). The _monolithic template had no ordering here at
  # all, which made the apply a race.
  depends_on = [aws_eks_access_entry.vscode_access_entry]
}

locals {
  # Every output this project exposes, defined once. outputs.tf projects these
  # and the README below renders them, so no value expression is written twice
  # (rules.md B-5/H-2). Adding an entry here is what makes an output possible,
  # which is what keeps the README from silently falling behind outputs.tf.
  #
  # The map's keys are the output names, and the order field decides the README's
  # section order.
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here and run every command below from its terminal. kubectl is already pointed at the cluster"
      value       = module.vscode_ec2.vscode_url
    }
    cluster_name = {
      order       = 2
      title       = "EKS cluster name"
      description = "Name of the EKS cluster. It has no node group at all - every pod in it runs on Fargate"
      value       = module.eks_cluster.cluster_name
    }
    cluster_endpoint = {
      order       = 3
      title       = "EKS cluster endpoint"
      description = "API server endpoint. Public and private are both on, which is what lets the kubectl and helm providers apply this project's Kubernetes objects from outside the VPC"
      value       = module.eks_cluster.cluster_endpoint
    }
    fargate_profile_name = {
      order       = 4
      title       = "Fargate profile"
      description = "One profile with two selectors: kube-system, which gives CoreDNS and the load balancer controller somewhere to run, and default, which is where the EFS pods go"
      value       = module.eks_fargate_profile.fargate_profile_name
    }
    efs_file_system_id = {
      order       = 5
      title       = "EFS file system"
      description = "The volumeHandle both PersistentVolumes name. It exists before they do, because Fargate supports static provisioning only"
      value       = module.efs_file_system.file_system_id
    }
    efs_dns_name = {
      order       = 6
      title       = "EFS DNS name"
      description = "Resolves to the mount target in the caller's zone. There is one mount target per private subnet, and a pod in a zone without one fails to mount rather than reaching another zone's"
      value       = module.efs_file_system.dns_name
    }
    fargate_nodes_command = {
      order       = 7
      title       = "1. The nodes are Fargate, not EC2"
      description = "Every entry should be named fargate-ip-... There is no node group in this project, so an ec2 compute type would mean something unexpected joined"
      value       = "kubectl get nodes -L eks.amazonaws.com/compute-type"
    }
    coredns_status_command = {
      order       = 8
      title       = "2. CoreDNS is running on Fargate"
      description = "Both replicas should be READY. Pending replicas mean the coredns addon's computeType is still ec2 and its pods have no node to land on - the state the _monolithic template left this cluster in until someone patched the Deployment by hand"
      value       = "kubectl -n kube-system get deployment coredns -o wide"
    }
    persistent_volume_claim_status_command = {
      order       = 9
      title       = "3. Both claims are Bound"
      description = "efs-pvc binds through the efs-sc StorageClass; read-pvc binds by volumeName with storageClassName set to the empty string. A claim stuck Pending means capacity, access mode or class did not match its volume"
      value       = module.efs_static_volume_workload.persistent_volume_claim_status_command
    }
    pod_status_command = {
      order       = 10
      title       = "4. Both pods are Running on Fargate"
      description = "The NODE column shows a fargate-ip-* name per pod. A pod stuck in ContainerCreating usually means there is no EFS mount target in the zone Fargate picked for it"
      value       = module.efs_static_volume_workload.pod_status_command
    }
    shared_file_read_command = {
      order       = 11
      title       = "5. The reader sees what the writer wrote"
      description = "This is the point of the project: two pods, two separate PersistentVolumes, one EFS file system. The writer appends a UTC timestamp every 30 seconds and the reader tails the same file"
      value       = module.efs_static_volume_workload.shared_file_read_command
    }
    write_pod_log_command = {
      order       = 12
      title       = "6. If the shared file is empty"
      description = "Check the writer's own output first - an empty file with a Running writer is a mount problem, an empty file with no writer is a scheduling problem"
      value       = module.efs_static_volume_workload.write_pod_log_command
    }
    load_balancer_controller_status_command = {
      order       = 13
      title       = "AWS Load Balancer Controller"
      description = "Installed and idle: this project creates no Ingress and no Service of type LoadBalancer. It is here because the _monolithic template installed it, and it is what an Ingress demo from this workbench would need"
      value       = "kubectl -n ${module.aws_load_balancer_controller.namespace} get deployment ${module.aws_load_balancer_controller.release_name}"
    }
    update_kubeconfig_command = {
      order       = 14
      title       = "Re-point kubectl"
      description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
  }
  # Iterating local.outputs directly would order sections by key, which puts
  # "2. CoreDNS" above "1. The nodes are Fargate". Re-keying by the order field
  # and taking values() sorts by that instead - values() returns a map's values
  # ordered by key - so the README reads in the order the demo is run, and the
  # order is still decided entirely by the configuration.
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  # Rendered from the same map, so an added output appears here without anyone
  # remembering to edit two places (rules.md H-2).
  readme_body = join("\n", concat(
    ["# ${var.project_name}", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}

# The work happens inside code-server in a browser, where "terraform output" does
# not exist, so every output above is also written to a README in the home
# directory the IDE opens (rules.md H-2). Combining several modules' outputs is
# the root's job, so this lives here rather than inside the instance module,
# which never learns what gets written into its home directory (rules.md C-1).
#
# The _monolithic template wrote this file too, with a single `echo '# EKS
# Fargate + EFS FileSystem'` - a title and nothing else, while the file system ID
# and every verification command stayed in the template.
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
