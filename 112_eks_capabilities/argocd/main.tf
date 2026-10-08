data "aws_region" "current" {}

# The account's IAM Identity Center instance, which Argo CD authenticates against. Read rather than
# created: there is at most one instance per region, and enabling it is an account-level action
# outside what a project like this should take.
#
# Read rather than created is also the only option available. The AWS provider has no resource for an
# instance - 6.66 has the data source below and aws_ssoadmin_instance_access_control_attributes, which
# configures an instance that already exists - so there is nothing to declare even if this project
# wanted to own it.
#
# And in an AWS Workshop Studio account there is nothing to declare it with. Creating an account
# instance out of band fails too:
#
#   aws sso-admin create-instance --region ap-northeast-2 --name eks-capabilities-argocd
#   AccessDeniedException: ... not authorized to perform: sso:CreateInstance on resource:
#   arn:aws:sso:::instance/* with an explicit deny in a service control policy
#
# An explicit deny in an SCP belongs to the organization's management account, so it cannot be worked
# around from here. That makes this variant unrunnable in such an account while kro and ack are fine,
# and it is worth knowing before a cluster is built rather than after: Argo CD as a capability has no
# local users, so an instance is the one prerequisite with no substitute.
#
# A plural data source, so an account without an instance produces empty lists rather than an error.
# That is what lets the capability module's own validation be the thing that reports the missing
# prerequisite, in terms of Identity Center rather than in terms of a provider block. It reports it
# during plan, before anything is created.
data "aws_ssoadmin_instances" "current" {}

locals {
  # The capability name, as the _monolithic template composed it: the cluster name with a suffix.
  # Written once here because the module receives it and the verification commands read it back
  # (rules.md B-5).
  capability_name = "${var.cluster_name}-${var.capability_name_suffix}"
  # An explicit ARN wins over discovery, which matters when the instance lives in another region or
  # is delegated from an organization's management account.
  idc_instance_arn   = var.idc_instance_arn != null ? var.idc_instance_arn : try(tolist(data.aws_ssoadmin_instances.current.arns)[0], null)
  idc_identity_store = try(tolist(data.aws_ssoadmin_instances.current.identity_store_ids)[0], null)
  # A user can only be created where there is an identity store to create it in. This is known at
  # plan time - the data source resolves then - so it can drive a count.
  create_identity_center_user = var.create_identity_center_user && local.idc_identity_store != null
  # ADMIN maps to the created user plus whatever groups the caller names. Left empty the capability
  # still installs, and nobody can log in to it.
  argocd_admin_identities = concat(
    local.create_identity_center_user ? [{ id = module.identity_center_user[0].user_id, type = "SSO_USER" }] : [],
    [for id in var.argocd_admin_group_ids : { id = id, type = "SSO_GROUP" }],
  )
}

module "network" {
  source = "./modules/network"

  region                         = data.aws_region.current.region
  vpc_cidr_block                 = var.vpc_cidr_block
  availability_zone_suffixes     = var.availability_zone_suffixes
  nat_availability_zone_suffixes = var.nat_availability_zone_suffixes
  vpc_name                       = "${var.project_name}-vpc"
}

module "key_pair" {
  source = "./modules/key_pair"

  key_name = "${var.project_name}-key"

  # Nothing here reads a network output, but the root orders every module after the network so the
  # whole VPC - NAT gateway and route tables included - is finished before anything starts in it
  # (rules.md D-3).
  depends_on = [module.network]
}

module "eks_cluster" {
  source = "./modules/eks_cluster"

  name                   = var.cluster_name
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  depends_on = [module.network]
}

# vpc-cni and kube-proxy are DaemonSets, so they reach ACTIVE with zero nodes. They come before the
# node group because a node cannot join Ready without them, and with
# bootstrap_self_managed_addons = false nothing installs them otherwise (rules.md C-4).
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

# The Pod Identity agent, which the _monolithic template also installed. The capability itself does
# not use it - AWS assumes the capability role from outside the cluster, not through a service
# account - but a synced application that needs AWS credentials will, so it is kept.
module "eks_pod_identity_agent_addon" {
  source = "./modules/eks_pod_identity_agent_addon"

  cluster_name = module.eks_cluster.cluster_name

  depends_on = [module.network, module.eks_cluster]
}

module "eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name    = module.eks_cluster.cluster_name
  node_group_name = var.node_group_name
  instance_types  = var.node_instance_types
  desired_size    = var.node_desired_size
  min_size        = var.node_min_size
  max_size        = var.node_max_size
  key_name        = module.key_pair.key_name
  subnet_ids      = module.network.private_subnet_ids

  depends_on = [module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}

# coredns is a Deployment, so unlike the DaemonSets it needs schedulable node capacity to leave
# DEGRADED and become ACTIVE (rules.md C-4).
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name          = module.eks_cluster.cluster_name
  coredns_replica_count = var.coredns_replica_count

  depends_on = [
  module.network, module.eks_node_group]
}

# The user Argo CD's ADMIN role is mapped to. Created before the capability because the capability's
# RBAC mapping references its id, which is what orders the two.
#
# Skipped when the account has no Identity Center instance - there is no identity store to create it
# in, and the check block above has already said so.
module "identity_center_user" {
  source = "./modules/identity_center_user"
  count  = local.create_identity_center_user ? 1 : 0

  identity_store_id = local.idc_identity_store
  user_name         = var.identity_center_user_name
  email             = var.identity_center_user_email

  # module.network's value references only order this after the specific aws_subnet or
  # aws_vpc that produced them, not after the NAT gateway and route tables the network
  # module also owns. depends_on states "after the whole network" (rules.md D-3).
  depends_on = [module.network]
}

# The Argo CD capability: an AWS-managed installation of Argo CD, plus the IAM role AWS assumes to
# run it. Unlike ACK and kro, this is the one capability type that takes configuration - the
# namespace, the Identity Center instance, and who gets which Argo CD role.
#
# Ordered after the node group and CoreDNS because the components it installs are pods - a capability
# created against a cluster with no schedulable capacity sits in CREATING until it times out, and the
# pods cannot resolve the endpoints they call without DNS (rules.md D-2).
module "eks_capability" {
  source = "./modules/eks_capability"

  cluster_name    = module.eks_cluster.cluster_name
  name            = local.capability_name
  type            = "ARGOCD"
  iam_policy_arns = var.capability_iam_policy_arns
  # The gap between creating the capability role and handing it to EKS. Needed because
  # iam_policy_arns is empty here, which leaves the module's role-to-capability ordering resting on
  # zero resources - see the variable, and time_sleep.role_propagation in the module.
  role_propagation_wait_seconds = var.capability_role_propagation_wait_seconds

  argo_cd_configuration = {
    namespace = var.argocd_namespace
    # Null when the account has no Identity Center instance, which the module rejects with a message
    # about Identity Center rather than letting the provider complain about a missing block.
    idc_instance_arn = local.idc_instance_arn
    # Null unless the caller named an instance in another region. Discovery only ever finds one in
    # this region, and the provider omits the field when it is null.
    idc_region = var.idc_region
    vpce_ids   = var.argocd_vpce_ids
    # ADMIN, EDITOR and VIEWER are Argo CD's built-in roles and the names are case sensitive. Only
    # the roles with identities are sent; an empty map means single sign-on is configured and nobody
    # is authorised, which is not an error anywhere.
    rbac_role_mappings = length(local.argocd_admin_identities) > 0 ? {
      ADMIN = local.argocd_admin_identities
    } : {}
  }

  depends_on = [
    module.network,
    module.eks_node_group,
    module.eks_coredns_addon,
    module.eks_pod_identity_agent_addon,
  ]
}

# An extra cluster access policy for the capability role, when the caller asks for one.
#
# Only the association, never the access entry: creating a capability makes EKS create the entry
# itself, and a second aws_eks_access_entry for the same principal fails with
# ResourceInUseException. That is the opposite of the pattern everywhere else in this repository,
# where the root creates both halves (rules.md C-1).
#
# Not optional in practice here. The two baseline policies EKS attaches give Argo CD cluster-wide
# discovery and write access inside its own namespace only, so without this the Application below is
# accepted and reports OutOfSync forever with the refusal in its status conditions (see the
# variable).
resource "aws_eks_access_policy_association" "capability_access_policy_association" {
  count = var.capability_cluster_access_policy_arn == null ? 0 : 1

  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.eks_capability.iam_role_arn
  policy_arn    = var.capability_cluster_access_policy_arn
  access_scope {
    type = "cluster"
  }

  # The entry this associates with is created by the capability, so this has to wait for it. The
  # principal_arn reference only orders this after the role (rules.md D-1).
  depends_on = [module.eks_capability]
}

# One Application, so Argo CD has something to reconcile. The _monolithic template created the
# capability and stopped there, which left an Argo CD with no applications - and since signing in
# needs a one-time password sent to the user's email, there was no way to see the feature working at
# all.
module "argocd_demo_application" {
  source = "./modules/argocd_demo_application"
  count  = var.create_demo_application ? 1 : 0

  name = var.demo_application_name
  # The namespace Argo CD runs in, which is where it reads Applications from. An Application in any
  # other namespace is ignored silently, so this is taken from the same variable the capability
  # configuration uses rather than restated (rules.md B-5).
  argocd_namespace      = var.argocd_namespace
  repo_url              = var.demo_application_repo_url
  path                  = var.demo_application_path
  target_revision       = var.demo_application_target_revision
  destination_namespace = var.demo_application_namespace
  # Passed only to order this after the capability. The Application CRD does not exist until the
  # capability has installed Argo CD (rules.md D-4).
  capability_dependency = module.eks_capability.capability_arn

  # The Application is accepted without this and then cannot sync anything outside the Argo CD
  # namespace, so the association has to land first - otherwise the demo's first state is a failure
  # that clears itself minutes later, which is the hardest kind of thing to read.
  depends_on = [
  module.network, aws_eks_access_policy_association.capability_access_policy_association]
}

module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name                        = "${var.project_name}-vscode"
  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_ids_by_zone[var.availability_zone_suffixes[0]]
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  code_server_version         = var.code_server_version
  security_group_name         = "${var.project_name}-vscode-sg"
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  marker_file_path            = var.marker_file_path
  # Carrying the cluster security group is what lets kubectl on this instance reach the API server
  # without leaving the VPC. The module is handed an ID list and never learns what it belongs to
  # (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]
  # An EKS cluster and this instance share a root module, so this instance is the workbench for that
  # cluster and carries all five tools (rules.md H-1).
  #
  # The _monolithic template's script had three problems that all show up only at runtime. It called
  # "exec bash" partway through, which replaced the shell and silently discarded every remaining
  # line - including the kubeconfig write, so kubectl was installed and unable to reach anything. It
  # wrote the completion alias before sourcing the completion that defines __start_kubectl, so every
  # login printed a "function not found" error. And it never installed eksctl or helm at all
  # (rules.md H-1).
  additional_user_data = <<-EOT
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server is already running and predates the docker group, so its terminals would not have
    # it without a restart.
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
    # Order matters: bash_completion has to be sourced before kubectl's own completion, which is
    # what defines __start_kubectl, and that function has to exist before complete references it
    # (rules.md H-1).
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
    rm -f get_helm.sh
    aws configure set default.region ${data.aws_region.current.region}
    # Without this - and without the access entry below - kubectl is installed but every command
    # answers "You must be logged in to the server" (rules.md H-1).
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}
    EOF
  EOT

  depends_on = [module.network]
}

# What the workbench may do inside the cluster. Joining two modules that know nothing about each
# other belongs in the root (rules.md C-1).
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

  # EKS rejects a policy association for a principal with no access entry yet, and the two resources
  # share only literal argument values, so nothing orders them (rules.md D-1).
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
      description = "Open the IDE here and run every command below from its terminal"
      value       = module.vscode_ec2.vscode_url
    }
    cluster_name = {
      order       = 2
      title       = "EKS cluster name"
      description = "Name of the EKS cluster the capability is installed on"
      value       = module.eks_cluster.cluster_name
    }
    capability_name = {
      order       = 3
      title       = "Argo CD capability"
      description = "Name of the EKS capability. AWS installs and runs Argo CD itself, so there is no Helm release here and nothing on the cluster for this configuration to upgrade"
      value       = module.eks_capability.capability_name
    }
    argocd_server_url = {
      order       = 4
      title       = "Argo CD URL"
      description = "The managed Argo CD API server, assigned by AWS rather than configured here. Signing in goes through IAM Identity Center - Argo CD as a capability has no local users, so there is no admin password to look up"
      value       = module.eks_capability.argo_cd_server_url
    }
    identity_center_console = {
      order       = 5
      title       = "IAM Identity Center console"
      description = "Where the created user's one-time password is sent from, and where more users and groups are added. The default email is example.com, so change identity_center_user_email before expecting to receive it"
      value       = "https://${data.aws_region.current.region}.console.aws.amazon.com/singlesignon/home?region=${data.aws_region.current.region}"
    }
    argocd_admin_user = {
      order       = 6
      title       = "Argo CD ADMIN identity"
      description = "The identity store user mapped to Argo CD's ADMIN role. A role mapping takes the user id rather than the name, which is why the user is created here rather than left to the console"
      value       = local.create_identity_center_user ? module.identity_center_user[0].user_check_command : "No Identity Center instance was found, so no user was created - Argo CD requires Identity Center and EKS will reject this capability"
    }
    capability_status_command = {
      order       = 7
      title       = "1. The capability is ACTIVE"
      description = "CREATING for several minutes is normal. Rejected immediately usually means the aws_idc block was missing, because Argo CD requires Identity Center; stuck in CREATING usually means there was no schedulable node capacity when it started"
      value       = "aws eks describe-capability --cluster-name ${module.eks_cluster.cluster_name} --capability-name ${local.capability_name} --query 'capability.[status,type,version]' --output table"
    }
    argocd_pods_command = {
      order       = 8
      title       = "2. Argo CD is running"
      description = "The components the capability installed into its namespace. Nothing here is declared in this configuration - AWS owns these pods"
      value       = "kubectl -n ${var.argocd_namespace} get pods"
    }
    application_status_command = {
      order       = 9
      title       = "3. The Application synced"
      description = "Synced and Healthy is the end state. OutOfSync that never clears is usually the capability role's cluster access policy, since its baseline policies only cover the Argo CD namespace"
      value       = var.create_demo_application ? module.argocd_demo_application[0].application_status_command : "create_demo_application is false, so no Application was created"
    }
    deployed_objects_command = {
      order       = 10
      title       = "4. What Argo CD deployed"
      description = "The point of the capability: objects from a git repository, in a namespace Argo CD created, none of it declared here. Edit the Deployment with kubectl and self-heal puts it back"
      value       = var.create_demo_application ? module.argocd_demo_application[0].deployed_objects_command : "create_demo_application is false, so nothing was deployed"
    }
    capability_access_entry_command = {
      order       = 11
      title       = "The capability's own access entry"
      description = "Created by EKS rather than by this configuration, which is why the root declares only a policy association and never an access entry. AmazonEKSArgoCDClusterPolicy and AmazonEKSArgoCDPolicy are the baselines it comes with, and neither grants write access outside the Argo CD namespace"
      value       = "aws eks list-associated-access-policies --cluster-name ${module.eks_cluster.cluster_name} --principal-arn ${module.eks_capability.iam_role_arn} --query 'associatedAccessPolicies[].policyArn' --output table"
    }
    node_check_command = {
      order       = 12
      title       = "The nodes are Ready"
      description = "Two t3.large nodes. Argo CD's components run on them, so a capability that never becomes ACTIVE is worth checking here first"
      value       = "kubectl get nodes -o wide"
    }
    update_kubeconfig_command = {
      order       = 13
      title       = "Re-point kubectl"
      description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the order field and
  # taking values() sorts by that instead - values() returns a map's values ordered by key - so the
  # README reads in the order the demo is run.
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  readme_body = join("\n", concat(
    ["# ${var.project_name}", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}

# The work happens inside code-server in a browser, where "terraform output" does not exist, so
# every output above is also written to a README in the home directory the IDE opens
# (rules.md H-2). The _monolithic template wrote one line into that file - the project title - and
# left the reader to find everything else.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on, is what orders this after the instance bootstrap - the marker
    # is written as the last line of user data (rules.md D-5).
    #
    # SSM runs as root, hence the chown. The heredoc delimiter is quoted and deliberately unlikely
    # to appear in the body: Terraform has already substituted every value, so the shell has no
    # reason to touch a "$" or a backtick in the README - and the commands in it contain both.
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
