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
  # running to join the cluster Ready (rules.md C-4). It also has to be running
  # before the NLB can register pod IPs as targets, since nlb_target_type = ip
  # relies on the CNI making pod IPs routable in the VPC.
  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as eks_vpc_cni_addon: kube-proxy is a DaemonSet and must
  # exist before any node capacity (rules.md C-4).
  depends_on = [module.network, module.eks_cluster]
}
module "eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name    = module.eks_cluster.cluster_name
  node_group_name = var.node_group_name
  labels          = var.node_group_labels
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
  depends_on = [module.eks_node_group]
}
module "aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"

  cluster_name      = module.eks_cluster.cluster_name
  vpc_id            = module.network.vpc_id
  aws_region        = data.aws_region.current.region
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  chart_version     = var.load_balancer_controller_chart_version
  # False, as in every variant of this project. The workload hands the controller
  # its own frontend security group but deliberately sets no
  # manage-backend-security-group-rules annotation, so nothing asks the
  # controller to write rules onto the cluster security group - and the shared
  # k8s-traffic-<cluster>-<hash> group it would have to name as the source in
  # those rules is never needed. The load balancer carries only the frontend
  # group declared below, and the path from it to the pods is the
  # Terraform-declared load_balancer_to_pods rule.
  #
  # Turning this off while a workload does set that annotation is the
  # combination the controller rejects:
  #
  #   backendSG feature is required to manage worker node SG rules when
  #   frontendSG manually specified
  #
  # It fails while building the load balancer model, so nothing is provisioned at
  # all - the Ingress or Service simply never gets an address, and the reason
  # appears only in the controller's own log (rules.md G-2).
  enable_backend_security_group = var.enable_backend_security_group

  # The controller is a Deployment with wait = true, so it needs schedulable
  # capacity and working cluster DNS before the release can report ready
  # (rules.md D-2).
  depends_on = [module.network, module.eks_coredns_addon]
}
# The NLB's frontend security group. Network load balancers only accept security
# groups assigned at creation time, so handing the controller a group it did not
# create is the only way to review these rules in a plan.
module "nlb_security_group" {
  source = "./modules/load_balancer_security_group"

  vpc_id                      = module.network.vpc_id
  name                        = var.nlb_security_group_name
  description                 = "Frontend security group for the internet-facing NLB the controller provisions from the kube-ops-view Service"
  allow_inbound_from_anywhere = var.nlb_allow_inbound_from_anywhere
  ingress_cidr_blocks         = var.nlb_ingress_cidr_blocks

  depends_on = [module.network]
}
# kube-ops-view behind a Service of type LoadBalancer. Unlike the ALB variants
# there is no Ingress: the controller provisions an NLB straight from the
# Service, driven entirely by the annotations below.
#
# Note that kube-ops-view has no authentication, so an internet-facing scheme
# publishes a live view of the cluster's nodes and pods to anyone who can reach
# the NLB. Narrow nlb_ingress_cidr_blocks accordingly.
# The node-side half of the path, which the controller would normally write and
# here does not: with enable_backend_security_group = false and no
# manage-backend-security-group-rules annotation on the workload, the controller
# writes no rules onto the cluster security group at all (rules.md G-2).
#
# The port named here is the container port, which is where a target-type = ip
# load balancer sends both traffic and health checks - the health check defaults
# to the same traffic-port. It does not cover target-type = instance, whose
# NodePort is assigned at random from 30000-32767 and so cannot be named in
# Terraform; the target type variable in this configuration still accepts that
# value, and only the kube-ops-view variant pins it to ip with a validation.
resource "aws_vpc_security_group_ingress_rule" "load_balancer_to_pods" {
  security_group_id            = module.eks_cluster.cluster_security_group_id
  description                  = "NLB to pods on the container port"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = module.nlb_security_group.security_group_id
}
module "kube_ops_view" {
  source = "./modules/kube_ops_view"

  image_tag    = var.kube_ops_view_image_tag
  service_type = "LoadBalancer"
  service_annotations = {
    # Without this the in-tree cloud provider would create a legacy Classic Load
    # Balancer instead of handing the Service to the AWS Load Balancer
    # Controller.
    "service.beta.kubernetes.io/aws-load-balancer-type"            = "external"
    "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
    "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = var.nlb_target_type
    "service.beta.kubernetes.io/aws-load-balancer-security-groups" = module.nlb_security_group.security_group_id
    # Deliberately no manage-backend-security-group-rules annotation. Setting it
    # would make the controller write rules onto the cluster security group, and
    # to name a source in them it needs the shared backend security group - which
    # is exactly what enable_backend_security_group = false switches off, and the
    # controller errors out rather than doing one without the other. Leaving it
    # unset (its default is false) means the controller writes no node rules, so
    # load_balancer_to_pods above is Terraform's job (rules.md G-2).
  }

  # The Service is only fulfilled once the controller is reconciling, and
  # wait = true on the release would otherwise time out waiting for a load
  # balancer nobody is creating. Ordering the module after the controller also
  # makes terraform destroy delete the Service - letting the controller remove
  # the NLB - before the controller disappears (rules.md D-2/D-4).
  depends_on = [module.network, module.eks_node_group, module.aws_load_balancer_controller]
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
  # server through the cluster's private endpoint, the only path left when
  # endpoint_public_access is turned off. The module is handed an ID list and
  # never learns that it belongs to an EKS cluster (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]
  # An EKS cluster and this instance live in the same root module, so the
  # instance is the workbench for that cluster and carries all five tools:
  # code-server (installed by the module itself), plus kubectl, eksctl, helm and
  # docker (rules.md H-1). None of them is behind a flag, and none of them is
  # used to create resources - that stays with the kubectl and helm providers
  # (rules.md E-1).
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
    # eksctl-io is the project's own org. The old weaveworks URL still
    # redirects, but the current name is what gets used (rules.md H-1).
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
# Granting the bastion's instance role cluster access joins two modules that
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
      description = "Open the IDE here. The kubectl commands below are meant to be run from its terminal"
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
    load_balancer_controller_role_arn = {
      order       = 4
      title       = "Controller IAM role"
      description = "Role the AWS Load Balancer Controller assumes through IRSA, replacing the eksctl create iamserviceaccount step and the CloudFormation stack it used to leave behind"
      value       = module.aws_load_balancer_controller.controller_role_arn
    }
    nlb_security_group_id = {
      order       = 5
      title       = "NLB frontend security group"
      description = "Group handed to the controller through the Service's aws-load-balancer-security-groups annotation. This variant's NLB is internet-facing, so this group is what decides who on the internet can reach it - and its rules are visible in the plan rather than invented by the controller"
      value       = module.nlb_security_group.security_group_id
    }
    service_dns_name_command = {
      order       = 6
      title       = "1. Check the Service"
      description = "The EXTERNAL-IP column stays empty until the controller has finished provisioning the NLB. If it never fills in, kubectl describe on the same object shows the controller's own events"
      value       = module.kube_ops_view.describe_command
    }
    service_endpoint_command = {
      order       = 7
      title       = "2. Read the NLB DNS name"
      description = "The NLB is created by the AWS Load Balancer Controller rather than by Terraform, so its address is read from the cluster instead of being a Terraform output (rules.md H-2)"
      value       = module.kube_ops_view.load_balancer_hostname_command
    }
    service_fetch_command = {
      order       = 8
      title       = "3. Fetch the dashboard through the NLB"
      description = "This variant's NLB is internet-facing, so unlike internal_nlb_service the same hostname also opens in a browser on a laptop - subject to the frontend security group above"
      value       = module.kube_ops_view.load_balancer_fetch_command
    }
    service_port_forward_command = {
      order       = 9
      title       = "Reach the dashboard without the NLB"
      description = "Port-forwards the Service to localhost, which is how to see the dashboard even before the controller has provisioned anything"
      value       = module.kube_ops_view.port_forward_command
    }
    update_kubeconfig_command = {
      order       = 10
      title       = "Re-point kubectl"
      description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
  }
  # Iterating local.outputs directly would order sections by key, which puts
  # "2. Read the NLB DNS name" above "1. Check the Service". Re-keying by the
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
