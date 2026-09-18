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
  # exist until this addon creates it. As a DaemonSet it reaches ACTIVE with zero
  # nodes, so it is created before any capacity exists (rules.md C-4). On this
  # Fargate-only cluster it never runs a pod - Fargate pods get their ENI from the
  # Fargate control plane - but it is declared so all three EKS-managed addons are
  # Terraform-tracked rather than half managed and half invisible.
  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as eks_vpc_cni_addon (rules.md C-4).
  depends_on = [module.network, module.eks_cluster]
}
# The workload's Fargate profile. Its pod execution role is what Fluent Bit
# writes to CloudWatch as, which is why the logging module below is handed this
# module's role name.
module "eks_app_fargate_profile" {
  source = "./modules/eks_fargate_profile"

  cluster_name = module.eks_cluster.cluster_name
  profile_name = var.app_fargate_profile_name
  namespace    = var.app_namespace
  # The selector names this namespace but does not create it, and the _monolithic
  # template created it with "kubectl create ns" from the bastion's user data - so
  # nothing tracked it. True here makes it a resource; the kube-system profile below
  # leaves its namespace alone because Kubernetes ships that one.
  create_namespace = true
  # Private subnets only. Fargate rejects public subnets outright.
  subnet_ids = module.network.private_subnet_ids

  depends_on = [module.network, module.eks_cluster]
}
module "eks_kubesystem_fargate_profile" {
  source = "./modules/eks_fargate_profile"

  cluster_name = module.eks_cluster.cluster_name
  profile_name = var.kubesystem_fargate_profile_name
  namespace    = "kube-system"
  subnet_ids   = module.network.private_subnet_ids

  # EKS allows one Fargate profile create at a time per cluster and returns
  # ResourceInUseException for a concurrent second one. Nothing in the value
  # references expresses that, so it is stated (rules.md D-2).
  depends_on = [module.network, module.eks_app_fargate_profile]
}
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name          = module.eks_cluster.cluster_name
  coredns_replica_count = var.coredns_replica_count
  # Fargate, not ec2: this cluster has no nodes. Without it the CoreDNS pods keep
  # the eks.amazonaws.com/compute-type: ec2 annotation EKS ships and stay Pending
  # forever - the state the _monolithic template left the cluster in, which is why
  # its demo had the stress pod curl a hand-edited pod IP instead of a name.
  compute_type = "Fargate"

  # coredns is a Deployment and needs schedulable capacity to leave DEGRADED and
  # become ACTIVE. Here that capacity is the kube-system Fargate profile, not a
  # node group (rules.md C-4).
  depends_on = [module.eks_kubesystem_fargate_profile]
}
# The sink. The KMS key that encrypts it at rest lives in the same module: the
# domain cannot be created without one and nothing else uses it (rules.md C-2).
module "opensearch_domain" {
  source = "./modules/opensearch_domain"

  domain_name          = var.opensearch_domain_name
  instance_type        = var.opensearch_instance_type
  master_user_name     = var.opensearch_master_user_name
  master_user_password = var.opensearch_master_user_password

  depends_on = [module.network]
}
# The other half of the permission. The inline policy in the logging module below
# gets Fluent Bit's requests past the domain's IAM access policy; this maps the
# same role onto an OpenSearch security role so fine-grained access control lets
# them through too. Both are required, and having only one produces a domain that
# stays empty with no error anywhere.
#
# Joining the domain to the Fargate profile's role is the root's job - neither
# module knows the other exists (rules.md C-1), which is the same split as the EKS
# access entry further down.
module "opensearch_log_writer_role" {
  source = "./modules/opensearch_log_writer_role"

  role_name = var.opensearch_log_writer_role_name
  # Derived from the index name rather than configured separately, so the role
  # cannot end up scoped to a pattern the ConfigMap does not write to
  # (rules.md B-5). The trailing wildcard covers a date suffix if Logstash_Format
  # is ever turned on.
  index_patterns = ["${var.opensearch_index_name}*"]
  # The identity Fluent Bit signs as. AWS_Auth On in the ConfigMap means the log
  # router uses the pod execution role, so this is the ARN that has to appear here
  # - a pod service account would not.
  backend_role_arns = [module.eks_app_fargate_profile.pod_execution_role_arn]

  # The provider for this module authenticates against the domain's endpoint, so
  # the domain must exist and be resolvable first. The provider argument reference
  # does not order the module's resources on its own (rules.md D-2), and ordering
  # it after the domain is also what makes terraform destroy remove the mapping
  # while the domain is still up (rules.md D-4).
  depends_on = [module.opensearch_domain]
}
# What the project is about: the namespace and ConfigMap that turn on Fargate's
# built-in Fluent Bit log router, pointed at the domain above, plus the signing
# permission on the pod execution role. The _monolithic template wrote the manifest
# to disk from user data and ran "kubectl apply -f" over SSM, so nothing connected
# the rendered endpoint to Terraform afterwards; here it is a resource argument
# (rules.md E-1/E-2).
module "fargate_fluentbit_logging" {
  source = "./modules/fargate_fluentbit_logging"

  aws_region = data.aws_region.current.region
  # The role the profile module created, handed over by name. The logging module
  # never learns which profile it belongs to (rules.md B-6), and the name is not
  # restated anywhere (rules.md B-5).
  pod_execution_role_name = module.eks_app_fargate_profile.pod_execution_role_name
  # Endpoint for the ConfigMap, ARN for the IAM policy. Both come from the domain
  # module rather than being rebuilt, so the ConfigMap cannot point at one domain
  # while the policy grants another (rules.md B-5).
  opensearch_endpoint       = module.opensearch_domain.endpoint
  opensearch_arn            = module.opensearch_domain.arn
  index_name                = var.opensearch_index_name
  match                     = var.log_match
  include_kubernetes_filter = var.include_kubernetes_filter
  flb_log_cw                = var.flb_log_cw

  # These are kubectl_manifest resources talking straight to the API server, so
  # the cluster has to exist and its DNS has to work before the provider can
  # authenticate. Ordering the module after coredns also makes terraform destroy
  # delete the ConfigMap while the cluster is still up (rules.md D-4).
  depends_on = [module.network, module.eks_coredns_addon]
}
# The demo workload. The _monolithic template staged these as two manifest files
# in the bastion's home directory for someone to apply by hand, after pasting the
# nginx pod's IP into the second one; both are resources here (rules.md E-1), and
# the IP substitution is gone because the stress pod requests a Service name.
module "demo_workload" {
  source = "./modules/fargate_demo_workload"

  namespace   = var.app_namespace
  create_pods = var.create_demo_workload

  # Ordering after the logging module is the load-bearing part of this block.
  # Fargate reads the aws-logging ConfigMap when it schedules a pod and does not
  # revisit it, so a pod created before the ConfigMap exists runs with no log
  # router for its whole life - and nothing about it looks wrong: the pod is
  # Running, the ConfigMap is correct, and the sink is simply empty. Running the
  # two kubectl commands in the wrong order used to be enough to produce that, and
  # this dependency is what removes the possibility.
  #
  # It also gets the namespace (created by the app Fargate profile) and CoreDNS,
  # which the Service DNS name depends on, both transitively through the logging
  # module. They are named anyway, because relying on another module's depends_on
  # list to supply them means this one breaks if that list ever changes.
  depends_on = [
    module.network,
    module.eks_app_fargate_profile,
    module.eks_coredns_addon,
    module.fargate_fluentbit_logging,
  ]
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
  # server through the cluster's private endpoint. The module is handed an ID list
  # and never learns that it belongs to an EKS cluster (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]
  # An EKS cluster and this instance live in the same root module, so the instance
  # is the workbench for that cluster and carries all five tools: code-server
  # (installed by the module itself), plus kubectl, eksctl, helm and docker
  # (rules.md H-1). None of them is used to create resources - the logging
  # ConfigMap that user data used to apply is a Terraform resource now
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
  # Every output this project exposes, defined once. outputs.tf projects these and
  # the README below renders them, so no value expression is written twice
  # (rules.md B-5/H-2). Adding an entry here is what makes an output possible,
  # which is what keeps the README from silently falling behind outputs.tf.
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
      description = "API server endpoint. Public here so the kubectl provider could create the logging ConfigMap during apply - narrow public_access_cidrs to your own address"
      value       = module.eks_cluster.cluster_endpoint
    }
    app_fargate_profile_name = {
      order       = 4
      title       = "Fargate profile: workload"
      description = "Profile selecting the workload namespace. Any pod created there runs on Fargate and gets the Fluent Bit log router"
      value       = module.eks_app_fargate_profile.fargate_profile_name
    }
    opensearch_dashboard_url = {
      order       = 5
      title       = "OpenSearch Dashboards"
      description = "Log in with opensearch_master_user_name and the password you passed in - this is a domain-internal user, not IAM. Then open Discover and add the index below as a pattern"
      value       = module.opensearch_domain.dashboard_url
    }
    opensearch_log_writer_role_name = {
      order       = 6
      title       = "OpenSearch role mapped to the log router"
      description = "Fine-grained access control is a second authorization layer inside the domain, independent of IAM. The Fargate pod execution role is mapped onto this OpenSearch role as a backend role; without that mapping the domain answers 403 to every write even with the IAM policy correct"
      value       = module.opensearch_log_writer_role.role_name
    }
    logging_configmap_command = {
      order       = 7
      title       = "1. Read the Fluent Bit configuration"
      description = "The rendered filters.conf and output.conf as the cluster has them. First thing to check when logs do not arrive"
      value       = module.fargate_fluentbit_logging.configmap_check_command
    }
    namespace_label_command = {
      order       = 8
      title       = "2. Confirm logging is enabled"
      description = "The aws-observability: enabled label is what switches the log router on. Without it the ConfigMap is ignored and no pod produces logs, with no error anywhere"
      value       = module.fargate_fluentbit_logging.namespace_label_check_command
    }
    pods_check_command = {
      order       = 9
      title       = "3. Watch the pods land on Fargate"
      description = "Terraform created both pods, so they are already here. Each shows a fargate-ip- node of its own, which is the thing this project is demonstrating - there is no node group, and each pod got its own microVM"
      value       = module.demo_workload.pods_check_command
    }
    stress_log_command = {
      order       = 10
      title       = "4. Confirm the request loop is running"
      description = "A column of 200s means the stress pod is reaching the web pod through the Service by DNS name. The _monolithic demo needed the nginx pod IP pasted into a manifest here; a Service name is known before either pod exists, so there is nothing to substitute"
      value       = module.demo_workload.stress_log_command
    }
    index_check_command = {
      order       = 11
      title       = "5. Confirm the index exists"
      description = "Export OPENSEARCH_USER and OPENSEARCH_PASSWORD first so the credential stays out of shell history. A single-node domain reports the index as yellow, which is expected - there is no second node to hold a replica"
      value       = module.opensearch_domain.index_check_command
    }
    roles_mapping_check_command = {
      order       = 12
      title       = "6. If the index never appears, check the role mapping"
      description = "Shows the fine-grained access control mapping as the domain holds it. The backend_roles list has to contain the Fargate pod execution role ARN - an IAM policy allowing es:ESHttp* is not enough on its own, and a missing mapping shows up only as 403s the domain does not report anywhere else. Export OPENSEARCH_ENDPOINT, OPENSEARCH_USER and OPENSEARCH_PASSWORD first"
      value       = module.opensearch_log_writer_role.roles_mapping_check_command
    }
    fluentbit_process_log_command = {
      order       = 13
      title       = "7. Read Fluent Bit's own log"
      description = "flb_log_cw is on, so the log router reports its own startup and errors here - including a write the domain rejected with 403 because the signing role was not mapped. The Fargate control plane names the group <cluster>-fluent-bit-logs and creates it as the pod execution role, so an empty result means the router either never started or lacks the CloudWatch permission"
      value       = "aws logs tail ${var.cluster_name}-fluent-bit-logs --since 15m"
    }
    demo_cleanup_command = {
      order       = 14
      title       = "8. Stop the demo workload"
      description = "Fargate bills per pod. The pods are Terraform resources now, so deleting them with kubectl only gets them recreated on the next apply - set create_demo_workload to false instead, which stops the per-pod charge and leaves the cluster and the log pipeline intact. Run this where the state is, not on the bastion. The domain is the expensive part and it bills whether anything logs or not, so terraform destroy is what actually stops the meter"
      value       = "terraform apply -var create_demo_workload=false"
    }
    update_kubeconfig_command = {
      order       = 15
      title       = "Re-point kubectl"
      description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
  }
  # Iterating local.outputs directly would order sections by key, which puts "3.
  # Start the web pod" after "5. Tail the logs". Re-keying by the order field and
  # taking values() sorts by that instead - values() returns a map's values
  # ordered by key - so the README reads in the order the demo is run, and the
  # order is still fully determined by the configuration.
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
    # orders this after the instance bootstrap, and the marker this command leaves
    # behind is what a later association would wait on (rules.md D-5). The marker
    # path comes back out of the module it was passed into, so it is defined in
    # exactly one place (rules.md B-5).
    #
    # SSM runs as root, hence the chown - without it the file is not editable from
    # the IDE. The heredoc delimiter is quoted and deliberately unlikely to appear
    # in the body: Terraform has already substituted every value, so the shell has
    # no reason to touch a "$" or a backtick in the README.
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
