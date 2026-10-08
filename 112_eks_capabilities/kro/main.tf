data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

locals {
  # The capability name, as the _monolithic template composed it: the cluster name with a suffix.
  # Written once here because the module receives it and the verification commands read it back
  # (rules.md B-5).
  capability_name = "${var.cluster_name}-${var.capability_name_suffix}"
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
# account - but a definition that composes ACK resources will, so it is kept.
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

# The kro capability: an AWS-managed installation of the Kube Resource Orchestrator, plus the IAM
# role AWS assumes to run it.
#
# type = "KRO", which the _monolithic template got wrong. Its capability was named "<cluster>-kro"
# and asked for type = "ACK", so the cluster came up with the ACK controllers installed, no kro
# anywhere, and a name that said otherwise. Nothing reports that as an error - ACK is a valid type,
# and the name is just a string.
#
# Ordered after the node group and CoreDNS because the controller it installs is a pod - a
# capability created against a cluster with no schedulable capacity sits in CREATING until it times
# out, and the pod cannot resolve the AWS endpoints it calls without DNS (rules.md D-2).
module "eks_capability" {
  source = "./modules/eks_capability"

  cluster_name    = module.eks_cluster.cluster_name
  name            = local.capability_name
  type            = "KRO"
  iam_policy_arns = var.capability_iam_policy_arns
  # The gap between creating the capability role and handing it to EKS. Needed because
  # iam_policy_arns is empty here, which leaves the module's role-to-capability ordering resting on
  # zero resources - see the variable, and time_sleep.role_propagation in the module.
  role_propagation_wait_seconds = var.capability_role_propagation_wait_seconds

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
# Not optional in practice for kro. The baseline policy EKS attaches, AmazonEKSKROPolicy, covers
# ResourceGraphDefinitions and their instances and nothing else - so without this the definition
# goes Active, the instance is accepted, and the Deployment it describes is never created. The
# refusal lands in the instance's status conditions, where no apply looks (see the variable).
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

# A new Kubernetes API, defined as a graph of a Deployment and a Service. The _monolithic template
# created the capability and stopped there, which left a cluster where the whole feature was
# invisible: no definition had ever been processed, and the only evidence of the capability was a
# console page - one which, because of the type mismatch above, described ACK.
module "kro_resource_graph_definition" {
  source = "./modules/kro_resource_graph_definition"
  count  = var.create_demo_resource_graph ? 1 : 0

  name = var.demo_api_name
  kind = var.demo_api_kind
  # Passed only to order this after the capability. The ResourceGraphDefinition CRD does not exist
  # until the capability has installed kro (rules.md D-4).
  capability_dependency = module.eks_capability.capability_arn

  # module.network's value references only order this after the specific aws_subnet or
  # aws_vpc that produced them, not after the NAT gateway and route tables the network
  # module also owns. depends_on states "after the whole network" (rules.md D-3).
  depends_on = [module.network]
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

# Waits until the cluster actually serves the kind the definition describes.
#
# This step exists because nothing in the Terraform graph can express it. Applying the definition
# returns as soon as the API server has stored the object; kro then reads it, generates a CRD, and
# waits for that CRD to be established - work that happens between two applies. An instance applied
# at that moment fails with "no matches for kind", which reads like a typo in the manifest rather
# than a race.
#
# It runs on the workbench because that is where a kubectl with cluster credentials already is, and
# the until loop - not depends_on - is what orders it after the instance bootstrap (rules.md D-5).
resource "aws_ssm_association" "wait_for_generated_api" {
  count = var.create_demo_resource_graph ? 1 : 0

  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.api_wait_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    commands = <<-EOT
      set -euo pipefail
      until [ -f ${module.vscode_ec2.marker_file_path}/userdata ]; do sleep 10; done
      sudo -Eu ec2-user bash << 'STEP'
      set -euo pipefail
      export HOME=/home/ec2-user
      export PATH=/home/ec2-user/bin:$PATH
      # First the definition's own state. kro sets it to Active once it has accepted the graph;
      # Inactive means the graph was rejected, and the reason is in status.conditions.
      attempt=0
      until [ "$(kubectl get resourcegraphdefinition ${var.demo_api_name} -o jsonpath='{.status.state}' 2>/dev/null)" = "Active" ]; do
        attempt=$((attempt + 1))
        if [ "$attempt" -gt 40 ]; then
          echo "resourcegraphdefinition ${var.demo_api_name} never became Active"
          kubectl get resourcegraphdefinition ${var.demo_api_name} -o yaml || true
          exit 1
        fi
        sleep 10
      done
      # Then whether the generated kind is being served. Active is kro's view; this is the API
      # server's, and it is the one the next apply depends on. Asking for the resource by its
      # lowercased kind goes through discovery, so there is no need to guess how kro pluralised it
      # for the CRD name.
      attempt=0
      until kubectl get ${lower(var.demo_api_kind)} -A >/dev/null 2>&1; do
        attempt=$((attempt + 1))
        if [ "$attempt" -gt 30 ]; then
          echo "the cluster does not serve ${var.demo_api_kind} yet"
          kubectl get crd | grep -i kro || true
          exit 1
        fi
        sleep 10
      done
      STEP
      touch ${module.vscode_ec2.marker_file_path}/kro_api
      EOT
  }

  depends_on = [module.kro_resource_graph_definition]
}

# One instance of the new API: four lines of spec that kro turns into a Deployment and a Service,
# neither of which is declared anywhere in this configuration.
module "kro_demo_instance" {
  source = "./modules/kro_demo_instance"
  count  = var.create_demo_resource_graph ? 1 : 0

  name          = var.demo_instance_name
  namespace     = var.demo_namespace
  workload_name = var.demo_workload_name
  # Taken from the definition module rather than restated, so the instance cannot end up naming a
  # kind or a version the definition does not create (rules.md B-5).
  api_version = module.kro_resource_graph_definition[0].api_version
  kind        = module.kro_resource_graph_definition[0].kind
  # Passed only to order this after the step that confirmed the kind is served (rules.md D-5).
  api_dependency = aws_ssm_association.wait_for_generated_api[0].association_id

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
      title       = "kro capability"
      description = "Name of the EKS capability. AWS installs and runs the kro controller itself, so there is no Helm release here and nothing on the cluster for this configuration to upgrade. The _monolithic template named this one kro and asked for type ACK, which installed the wrong controllers without reporting anything"
      value       = module.eks_capability.capability_name
    }
    capability_role_arn = {
      order       = 4
      title       = "Capability IAM role"
      description = "The role AWS assumes to run kro. It carries no managed policies: kro calls no AWS API of its own, and what it needs is Kubernetes permission, which comes from the access policy association below"
      value       = module.eks_capability.iam_role_arn
    }
    capability_status_command = {
      order       = 5
      title       = "1. The capability is ACTIVE"
      description = "CREATING for several minutes is normal. Stuck in CREATING usually means there was no schedulable node capacity when it started, because the controller it installs is a pod. Check the type column too - it should say KRO"
      value       = "aws eks describe-capability --cluster-name ${module.eks_cluster.cluster_name} --capability-name ${local.capability_name} --query 'capability.[status,type,version]' --output table"
    }
    definition_status_command = {
      order       = 6
      title       = "2. The definition is Active"
      description = "Active means kro accepted the graph and generated a CRD for the new kind. Inactive means it rejected it, and the reason is in status.conditions rather than anywhere apply would show it"
      value       = var.create_demo_resource_graph ? module.kro_resource_graph_definition[0].status_command : "create_demo_resource_graph is false, so no definition was created"
    }
    generated_api_command = {
      order       = 7
      title       = "3. The cluster serves the new kind"
      description = "A kind that did not exist before this definition. An SSM step waited for exactly this before the instance was applied, because the CRD is generated between two applies"
      value       = var.create_demo_resource_graph ? "kubectl get ${lower(var.demo_api_kind)} -A" : "create_demo_resource_graph is false, so no API was generated"
    }
    demo_instance_status_command = {
      order       = 8
      title       = "4. The instance reconciled"
      description = "The status fields the definition declared, copied out of the objects kro created. A forbidden message in the conditions is the capability role's cluster access policy, not the definition"
      value       = var.create_demo_resource_graph ? module.kro_demo_instance[0].instance_status_command : "create_demo_resource_graph is false, so no instance was created"
    }
    expanded_objects_command = {
      order       = 9
      title       = "5. The objects kro built"
      description = "The point of kro: a Deployment and a Service that four lines of instance spec produced, neither of them declared anywhere in this configuration"
      value       = var.create_demo_resource_graph ? module.kro_demo_instance[0].expanded_objects_command : "create_demo_resource_graph is false, so nothing was expanded"
    }
    capability_access_entry_command = {
      order       = 10
      title       = "The capability's own access entry"
      description = "Created by EKS rather than by this configuration, which is why the root declares only a policy association and never an access entry. AmazonEKSKROPolicy is the baseline it comes with, and it covers only definitions and their instances - AmazonEKSClusterAdminPolicy is what lets kro create the objects a definition composes"
      value       = "aws eks list-associated-access-policies --cluster-name ${module.eks_cluster.cluster_name} --principal-arn ${module.eks_capability.iam_role_arn} --query 'associatedAccessPolicies[].policyArn' --output table"
    }
    node_check_command = {
      order       = 11
      title       = "The nodes are Ready"
      description = "Two t3.large nodes. The capability's controller runs on them, so a capability that never becomes ACTIVE is worth checking here first"
      value       = "kubectl get nodes -o wide"
    }
    update_kubeconfig_command = {
      order       = 12
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
