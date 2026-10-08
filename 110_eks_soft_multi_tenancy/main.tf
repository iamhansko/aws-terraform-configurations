data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
locals {
  key_name = var.key_name == null ? "${var.cluster_name}-key" : var.key_name
}
module "network" {
  source = "./modules/network"

  region                         = data.aws_region.current.region
  vpc_cidr_block                 = var.vpc_cidr_block
  availability_zone_suffixes     = var.availability_zone_suffixes
  nat_availability_zone_suffixes = var.availability_zone_suffixes
  vpc_name                       = "${var.cluster_name}-vpc"
  # The tags the AWS Load Balancer Controller discovers subnets by. Without them the controller fails with
  # "couldn't auto-discover subnets" - and the management UI Service sits with no address (rules.md G-1).
  subnet_tags = {}
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
# The addon that decides whether this project demonstrates anything.
#
# enableNetworkPolicy is a top-level key in the addon's configuration schema, not a DaemonSet environment
# variable - a value placed under env renders and is silently ignored (rules.md E-5). The _monolithic template
# declared this addon with no configuration at all, so the six NetworkPolicies it applied were accepted by the
# API server and enforced by nothing.
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name          = module.eks_cluster.cluster_name
  enable_network_policy = var.enable_network_policy

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not exist until this addon creates
  # it. As a DaemonSet it reaches ACTIVE with zero nodes, so it comes before any capacity - and nodes need it to
  # join Ready (rules.md C-4).
  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  depends_on = [module.network, module.eks_vpc_cni_addon]
}
# Required by the load balancer controller's Pod Identity association: the agent is what delivers credentials to
# the pod.
module "eks_pod_identity_agent_addon" {
  source = "./modules/eks_pod_identity_agent_addon"

  cluster_name = module.eks_cluster.cluster_name

  depends_on = [module.network, module.eks_vpc_cni_addon]
}
module "eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name    = module.eks_cluster.cluster_name
  node_group_name = "${var.cluster_name}-core"
  instance_types  = var.node_group_instance_types
  desired_size    = var.node_group_desired_size
  min_size        = var.node_group_min_size
  max_size        = var.node_group_max_size
  subnet_ids      = module.network.private_subnet_ids
  key_name        = module.key_pair.key_name

  # Nodes need vpc-cni and kube-proxy running to join the cluster Ready (rules.md C-4).
  depends_on = [module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.eks_cluster.cluster_name

  # coredns is a Deployment and needs schedulable capacity to leave DEGRADED and become ACTIVE (rules.md C-4).
  # It matters more here than usual: every probe reaches its targets by service DNS name, so a cluster without
  # working CoreDNS produces the same fully-connected-failure appearance as a missing policy.
  depends_on = [
  module.network, module.eks_node_group]
}
# What turns the management UI Service into an NLB. Its IAM role, Pod Identity association and Helm release are
# one module (rules.md C-2), and it uses Pod Identity rather than IRSA - as the _monolithic template did.
module "aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"

  cluster_name  = module.eks_cluster.cluster_name
  vpc_id        = module.network.vpc_id
  aws_region    = data.aws_region.current.region
  chart_version = var.aws_load_balancer_controller_chart_version
  # False, and the Service below deliberately does not set manage-backend-security-group-rules: the path from
  # the load balancer to the pod is the rule declared at the bottom of this file, visible in plan
  # (rules.md G-2).
  enable_backend_security_group = false
  # Off: the one Service of type LoadBalancer here names the controller with aws-load-balancer-type, so the
  # webhook has nothing to mutate, and its failurePolicy: Fail would otherwise gate every Service creation in
  # the cluster on a controller pod being Ready (rules.md G-4).
  enable_service_mutator_webhook = false

  # The Pod Identity agent has to be running before the controller pod starts, and CoreDNS has to be answering
  # before it can reach the EKS API (rules.md D-2).
  depends_on = [module.network, module.eks_pod_identity_agent_addon, module.eks_node_group, module.eks_coredns_addon]
}
# The frontend security group for the NLB. Standalone rule resources rather than inline blocks, because the
# controller may add its own rules to this group (rules.md F-2) - the _monolithic template used an inline
# dynamic "ingress".
module "load_balancer_security_group" {
  source = "./modules/load_balancer_security_group"

  vpc_id      = module.network.vpc_id
  name        = "${var.cluster_name}-nlb-sg"
  description = "Frontend security group for the NLB fronting the management UI"
  ports = {
    http = var.management_ui_service_port
  }
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere

  depends_on = [module.network]
}
# The tenant workload: namespaces, quotas, probes, the management UI and the policies.
#
# Applied by the kubectl provider rather than by a 200-line shell script in an SSM association, which is where
# the _monolithic template had all of it (rules.md E-1/E-2).
module "tenant_workload" {
  source = "./modules/soft_multi_tenant_workload"

  tenants                    = var.tenants
  apply_network_policies     = var.apply_network_policies
  management_ui_service_port = var.management_ui_service_port
  service_annotations = {
    # The switch that decides whether any of the others mean anything. Without it the in-tree cloud provider
    # claims the Service and builds a Classic Load Balancer, ignoring the scheme, the target type and the
    # security groups - and the pre-created NLB is never adopted (rules.md G-1). The _monolithic template's
    # Service manifest did not set it, so its own pre-created aws_lb could not have been adopted either.
    "service.beta.kubernetes.io/aws-load-balancer-type" = "external"
    # Has to agree with internal = false and the public subnets below (rules.md G-3).
    "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
    # nlb-target-type, not target-type: the Service spelling carries the nlb- prefix (rules.md G-1).
    "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
    # Only the frontend group, where the _monolithic template listed this group and the cluster security group
    # together - which attaches the cluster's own group to a public load balancer. The path to the pod is the
    # declared rule below instead (rules.md G-2).
    "service.beta.kubernetes.io/aws-load-balancer-security-groups" = module.load_balancer_security_group.security_group_id
  }

  # Every object here needs the API server and a schedulable node, and the Service needs the controller to be
  # running before it can get an address. Ordering the module after the node group is also what keeps
  # terraform destroy removing these manifests before the nodes disappear, rather than leaving deletes waiting
  # on controllers that no longer exist (rules.md D-4).
  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon, module.aws_load_balancer_controller]
}
# Created here and adopted by the controller, which is what the _monolithic template was reaching for with its
# own aws_lb carrying the three controller tags. Two things stopped that from working: it gave the load balancer
# the VPC's default security group while the Service asked for two different ones, and its Service manifest had
# no aws-load-balancer-type annotation at all - so the in-tree provider would have built a Classic Load
# Balancer and left this NLB untouched (rules.md B-5/G-3).
module "synced_load_balancer" {
  source = "./modules/synced_load_balancer"

  cluster_name       = module.eks_cluster.cluster_name
  load_balancer_type = "network"
  internal           = false
  subnet_ids         = module.network.public_subnet_ids
  security_group_ids = [module.load_balancer_security_group.security_group_id]
  # service.k8s.aws/*, not ingress.k8s.aws/*: this fronts a Service of type LoadBalancer (rules.md G-3).
  resource_tag_prefix = "service"
  # Taken from the workload module rather than restating "management-ui/management-ui", so the tag cannot drift
  # from the Service the controller is reconciling (rules.md B-5).
  stack = module.tenant_workload.stack_tag

  depends_on = [module.network]
}
# With manage-backend-security-group-rules unset the controller writes no node-side rules at all, so the path
# from load balancer to pod has to be declared here or every target stays unhealthy with no error anywhere
# (rules.md G-2). nlb-target-type is ip, so traffic arrives at the collector's container port.
#
# It modifies the cluster security group, which no module here owns outright, so it belongs in the root
# (rules.md C-1).
resource "aws_vpc_security_group_ingress_rule" "load_balancer_to_management_ui" {
  security_group_id            = module.eks_cluster.cluster_security_group_id
  description                  = "Management UI container port from the NLB frontend security group"
  ip_protocol                  = "tcp"
  from_port                    = module.tenant_workload.management_ui_container_port
  to_port                      = module.tenant_workload.management_ui_container_port
  referenced_security_group_id = module.load_balancer_security_group.security_group_id
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
  # The cluster security group, so kubectl reaches the API server without leaving the VPC (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]

  # An EKS cluster and this instance share a root module, so it carries the workbench tooling (rules.md H-1).
  #
  # Bugs from the _monolithic template that are not carried over. It ran "exec bash" partway through user data,
  # which replaces the shell and silently discarded everything after it - the kubeconfig, helm and the load
  # balancer controller install were all below that line. And it wrote the "complete" line for the k alias into
  # .bashrc before the line that defines __start_kubectl, so every login printed a "function not found" error
  # (rules.md H-1).
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
# The tenant roles, and their namespace-scoped access into the cluster. Joining the cluster module and the
# workbench's role is the root's job (rules.md C-1).
module "tenant_access_roles" {
  source = "./modules/tenant_access_roles"

  cluster_name = module.eks_cluster.cluster_name
  tenants      = var.tenants
  # Short enough that the tenant label fits inside IAM's 64 character role name limit.
  role_name_prefix = "${substr(var.cluster_name, 0, 30)}-tenant"
  # The workbench's role rather than the account root, which is what the _monolithic template trusted. The demo
  # still works - the workbench is where the roles are assumed from - and the boundary is narrower.
  trusted_principal_arns = var.tenant_role_trusts_account_root ? ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"] : [module.vscode_ec2.iam_role_arn]

  # The namespaces have to exist before an access scope naming them means anything - a scope pointing at a
  # missing namespace grants nothing and reports nothing (rules.md D-2).
  depends_on = [module.network, module.tenant_workload]
}
locals {
  # Every output this project exposes, defined once. outputs.tf projects these and the README below renders
  # them, so no value expression is written twice (rules.md B-5/H-2).
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here. kubectl is already pointed at the cluster as a cluster admin, and the tenant commands below switch it to a namespace-scoped identity"
      value       = module.vscode_ec2.vscode_url
    }
    management_ui_url = {
      order       = 2
      title       = "Management UI"
      description = "The graph. Terraform created the load balancer and the controller adopted the Service, so this address is known from state rather than only after a reconcile (rules.md G-3). It answers once the collector pod is running and the targets are healthy"
      value       = module.synced_load_balancer.url
    }
    what_to_look_for = {
      order       = 3
      title       = "What the graph should show"
      description = "Each tenant's frontend reaching its own backend and nothing else, and the management UI reaching everything. A fully connected graph means either the policies were not applied or the CNI is not enforcing them - and those two look identical from Kubernetes, which is what the next two outputs are for"
      value       = "policies applied: ${module.tenant_workload.network_policies_applied}\nCNI enforcement enabled: ${module.eks_vpc_cni_addon.network_policy_enabled}\ntenants: ${join(", ", [for label, namespace in var.tenants : "${label} -> ${namespace}"])}"
    }
    cni_enforcement_command = {
      order       = 4
      title       = "1. Is the CNI enforcing policies at all"
      description = "The addon's configuration. enableNetworkPolicy missing or false here is the _monolithic template's state: every policy is accepted by the API server and implemented by nothing, so the demo inverts silently (rules.md E-5)"
      value       = "aws eks describe-addon --cluster-name ${module.eks_cluster.cluster_name} --addon-name vpc-cni --query 'addon.configurationValues' --output text"
    }
    policy_list_command = {
      order       = 5
      title       = "2. Which policies exist"
      description = "Three per tenant. This lists what the API server holds and says nothing about enforcement, which is why it comes after the addon check rather than before it"
      value       = module.tenant_workload.policy_list_command
    }
    cross_tenant_test_command = {
      order       = 6
      title       = "3. Test the isolation from inside a tenant"
      description = "Runs a probe from one tenant's frontend against every tenant's backend. Its own answers; the others time out. This is the same thing the graph shows, in a form that can be read from a terminal"
      value       = module.tenant_workload.cross_tenant_test_commands[keys(var.tenants)[0]]
    }
    quota_command = {
      order       = 7
      title       = "4. The quotas and limit ranges"
      description = "The other half of soft multi-tenancy, and the half the IAM access scope does nothing about: namespace isolation stops one tenant reading another's data, a quota stops one tenant consuming the cluster. The limit range is what makes the quota real - a container with no requests counts as zero against a requests quota"
      value       = module.tenant_workload.quota_command
    }
    assume_tenant_command = {
      order       = 8
      title       = "5. Become a tenant"
      description = "Assume the role, export the credentials, then run kubectl. The same cluster answers for that tenant's namespace and refuses every other with a forbidden error - which is the IAM half of the boundary, enforced by the access entry's namespace scope rather than by RBAC written into the cluster"
      value       = module.tenant_access_roles.assume_role_commands[keys(var.tenants)[0]]
    }
    tenant_scope_command = {
      order       = 9
      title       = "6. What each tenant is actually allowed"
      description = "Read from the cluster rather than from the configuration. An accessScope type of cluster rather than namespace means the isolation is not in place, and nothing else would show it"
      value       = module.tenant_access_roles.describe_access_scope_commands[keys(var.tenants)[0]]
    }
    adopted_load_balancer_check_command = {
      order       = 10
      title       = "7. Confirm the load balancer was adopted, not duplicated"
      description = "Lists every load balancer tagged for this cluster. One is correct. Two means the controller built its own instead of adopting the pre-created one - a tag or annotation mismatch rather than an error, and the URL above would then point at the one with no listeners (rules.md G-3)"
      value       = "aws resourcegroupstaggingapi get-resources --tag-filters Key=elbv2.k8s.aws/cluster,Values=${module.eks_cluster.cluster_name} --resource-type-filters elasticloadbalancing:loadbalancer --query 'ResourceTagMappingList[].ResourceARN' --output table"
    }
    service_address_command = {
      order       = 11
      title       = "8. The address the controller attached"
      description = "Compare it against the management UI URL above. They should be the same load balancer"
      value       = module.tenant_workload.load_balancer_hostname_command
    }
    tenant_roles = {
      order       = 12
      title       = "The tenant roles"
      description = "One per tenant, each mapped into the cluster with edit access to one namespace. They trust the workbench's role rather than the account root, which is what the _monolithic template trusted - that let any principal in the account become either tenant"
      value       = join("\n", [for label, arn in module.tenant_access_roles.role_arns : "${label} -> ${arn} (namespace ${var.tenants[label]})"])
    }
    update_kubeconfig_command = {
      order       = 13
      title       = "Re-point kubectl"
      description = "User data already ran this, as the cluster admin. Re-run it after assuming a tenant role to see the scoped view"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
    private_key_command = {
      order       = 14
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
# above is also written to a README in the home directory the IDE opens (rules.md H-2).
#
# The _monolithic template wrote a README too, with an echo whose body contained both unescaped double quotes
# and unescaped $(...) command substitutions - so the shell closed the string early, ran the substitutions as
# root at write time, and the file came out mangled.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is what orders this after the
    # bootstrap (rules.md D-5). The marker path comes back out of the module it was passed into (rules.md B-5).
    #
    # The heredoc delimiter is quoted, so the $(...) in the tenant test commands reaches the file intact rather
    # than being run while the README is written.
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
