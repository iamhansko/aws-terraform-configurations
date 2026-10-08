data "aws_region" "current" {}
locals {
  key_name = var.key_name == null ? "${var.cluster_name}-key" : var.key_name
  # The API server's hostname, without the scheme.
  #
  # Derived once. The _monolithic template wrote element(split("//", endpoint), 1) in four separate places - the
  # resource configuration's custom_domain_name, its DNS resource definition, the Route 53 zone name and the
  # record name - so all four had to be edited together and any one of them could drift (rules.md B-5).
  #
  # Lowercased, and that is not cosmetic. EKS returns the endpoint with the cluster's 32-character id in
  # uppercase hex (https://018520D1274DAA3BEA8F179F2C3AFCF4.gr7.<region>.eks.amazonaws.com), while VPC Lattice
  # stores the domain name it is given in lowercase. Passing the hostname through as EKS reports it makes the
  # apply fail after the resource configuration has already been created:
  #
  #   Error: Provider produced inconsistent result after apply
  #   .custom_domain_name: was cty.StringVal("018520D1...eks.amazonaws.com"), but now
  #   cty.StringVal("018520d1...eks.amazonaws.com")
  #
  # The message blames the provider and names only the casing, so it reads as a provider bug rather than as
  # something this configuration controls - and the resource it is about exists in state by then, which makes
  # the next plan propose replacing it. DNS and TLS verification are both case-insensitive, so normalising here
  # costs nothing: the kubeconfig that aws eks update-kubeconfig writes with the uppercase name still resolves
  # against the lowercase private hosted zone, and the certificate still matches.
  api_server_hostname = lower(replace(module.eks_cluster.cluster_endpoint, "https://", ""))
}
# The cluster's VPC: public and private subnets, a regional NAT gateway. The API server's private endpoint lives
# here, and so does the Lattice resource gateway that reaches it.
module "network" {
  source = "./modules/network"

  region                         = data.aws_region.current.region
  vpc_cidr_block                 = var.cluster_vpc_cidr_block
  availability_zone_suffixes     = var.availability_zone_suffixes
  nat_availability_zone_suffixes = var.availability_zone_suffixes
  vpc_name                       = "${var.cluster_name}-cluster-vpc"
  internet_gateway_name          = "${var.cluster_name}-cluster-igw"
  public_subnet_name_prefix      = "${var.cluster_name}-cluster-public"
  private_subnet_name_prefix     = "${var.cluster_name}-cluster-private"
  public_route_table_name        = "${var.cluster_name}-cluster-public-rt"
  private_route_table_name       = "${var.cluster_name}-cluster-private-rt"
  nat_gateway_name               = "${var.cluster_name}-cluster-natgw"
}
# The client VPC: no private subnets, no NAT gateway, and no route to the cluster's network at all. That last
# part is the demonstration - the only path between the two is the Lattice endpoint.
module "client_network" {
  source = "./modules/client_network"

  region                     = data.aws_region.current.region
  vpc_cidr_block             = var.client_vpc_cidr_block
  availability_zone_suffixes = var.availability_zone_suffixes
  vpc_name                   = "${var.cluster_name}-client-vpc"
  internet_gateway_name      = "${var.cluster_name}-client-igw"
  public_subnet_name_prefix  = "${var.cluster_name}-client-public"
  route_table_name           = "${var.cluster_name}-client-rt"

  # The two networks are independent, but every module in a root with a network module waits for all of it
  # (rules.md D-3).
  depends_on = [module.network]
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name = local.key_name

  depends_on = [module.network]
}
module "eks_cluster" {
  source = "./modules/eks_cluster"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version
  # Private subnets only, as the _monolithic template had it. With a private-only endpoint there is nothing for
  # the public subnets to do here, and the control plane's interfaces belong where the nodes are.
  subnet_ids = module.network.private_subnet_ids
  # False, pinned by its validation. Everything else in this root exists to reach it (rules.md E-9).
  endpoint_public_access = var.endpoint_public_access

  depends_on = [module.network]
}
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

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
  # The _monolithic template declared all three addons together with no ordering, so on a cluster with bootstrap
  # addons disabled coredns would have sat DEGRADED until the node group happened to come up.
  depends_on = [
  module.network, module.eks_node_group]
}
# The cluster-VPC half: a resource gateway in the private subnets, a resource configuration naming the API
# server, a service network, and the association between them.
module "lattice_api_server_access" {
  source = "./modules/vpc_lattice_api_server_access"

  name_prefix         = var.cluster_name
  vpc_id              = module.network.vpc_id
  subnet_ids          = module.network.private_subnet_ids
  api_server_hostname = local.api_server_hostname
  # The gateway has to be allowed to reach the API server, and the rule for that goes on the cluster's own
  # security group - which no module here owns, so the ID is injected (rules.md B-6).
  cluster_security_group_id = module.eks_cluster.cluster_security_group_id
  port_ranges               = var.lattice_port_ranges

  depends_on = [module.network, module.eks_cluster]
}
# The client-VPC half: one endpoint onto the service network, plus the private hosted zone that makes the
# cluster's own hostname resolve to it.
#
# This is also where the _monolithic template's Lambda used to be - see the module for the three separate reasons
# it could not have run, and for the data source that replaced it.
module "lattice_client_endpoint" {
  source = "./modules/lattice_client_endpoint"

  name_prefix                 = var.cluster_name
  vpc_id                      = module.client_network.vpc_id
  vpc_cidr_block              = module.client_network.vpc_cidr_block
  subnet_ids                  = module.client_network.public_subnet_ids
  service_network_arn         = module.lattice_api_server_access.service_network_arn
  api_server_hostname         = module.lattice_api_server_access.api_server_hostname
  allowed_ingress_cidr_blocks = var.allowed_endpoint_ingress_cidr_blocks
  create_private_hosted_zone  = var.create_private_hosted_zone

  # The resource configuration has to be associated with the service network before the endpoint has anything to
  # resolve, and the ARN reference alone only orders this after the service network itself (rules.md D-2). It
  # also decides whether the association data source inside the module reads anything at all.
  depends_on = [module.network, module.client_network, module.lattice_api_server_access]
}
# The workbench, in the client VPC.
#
# That placement is the demonstration: it holds no cluster security group, has no route to the cluster's network,
# and still reaches the API server - through the Lattice endpoint, under the cluster's own hostname.
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name                        = "vscode"
  vpc_id                      = module.client_network.vpc_id
  subnet_id                   = module.client_network.public_subnet_ids[0]
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  security_group_name         = "${var.cluster_name}-vscode-sg"
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  marker_file_path            = var.marker_file_path
  # No extra_security_group_ids, unlike every other EKS root here. The cluster's security group is in the other
  # VPC and could not be attached to this instance even if it were useful - the endpoint's own group is what
  # allows the traffic, and it accepts the whole client VPC.

  # An EKS cluster and this instance share a root module, so it carries the workbench tooling (rules.md H-1).
  # Docker is omitted: nothing here builds an image.
  #
  # Bugs from the _monolithic template that are not carried over. It wrote the "complete" line for the k alias
  # into .bashrc before the line that defines __start_kubectl, so every login printed a "function not found"
  # error. And its update-kubeconfig ran inside user data with no way to report whether it worked, on an
  # instance whose path to the API server depends on a private hosted zone that may not exist yet
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
    # The kubeconfig is written here, but it only works once the Lattice endpoint and the private hosted zone
    # exist - so the association below writes it again, after both do.
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}
    EOF
  EOT

  depends_on = [
  module.network, module.client_network]
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
# Re-runs update-kubeconfig and proves the path works, after the endpoint and the private zone exist.
#
# It exists because of the ordering this project creates: the instance boots before the Lattice endpoint is
# associated and before the private hosted zone answers, so the kubeconfig written in user data is correct and
# unusable at the moment it is written. Verifying from here is also the only check that the whole arrangement
# works - there is no provider that could have done it.
resource "aws_ssm_association" "verify_api_server_access" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is what orders this after the bootstrap
    # (rules.md D-5). The marker path comes back out of the module it was passed into (rules.md B-5).
    commands = <<-EOT
      # set -e on the outer script, which is what makes the inner one's failure count. Without it a failing
      # command inside the sudo heredoc ends only that subshell, the script carries on to touch the marker, and
      # the association's status becomes touch's - so SSM reports Success while its own output shows the
      # verification failing. For a step whose only purpose is to verify, that is the whole value lost.
      set -e
      until [ -f ${module.vscode_ec2.marker_file_path}/userdata ]; do sleep 10; done
      sudo -Eu ec2-user bash << 'STEP'
      set -euo pipefail
      export HOME=/home/ec2-user
      export PATH=/home/ec2-user/bin:$PATH
      aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}
      # The name has to resolve to an address in this VPC - the endpoint's - rather than to the cluster VPC's
      # endpoint or to nothing. A failure here is the private hosted zone, not the cluster.
      getent hosts ${local.api_server_hostname}
      # And the API server has to answer. If DNS resolves and this times out, the path is the security groups:
      # either the endpoint's ingress or the cluster group's rule for the resource gateway.
      kubectl version --request-timeout=30s
      kubectl get nodes
      STEP
      touch ${module.vscode_ec2.marker_file_path}/verify_api_server_access
      EOT
  }

  depends_on = [module.vscode_ec2, module.lattice_client_endpoint, aws_eks_access_policy_association.vscode, module.eks_coredns_addon]
}
locals {
  # Every output this project exposes, defined once. outputs.tf projects these and the README below renders them,
  # so no value expression is written twice (rules.md B-5/H-2).
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here. It runs in the client VPC, which has no route to the cluster's network - and kubectl in its terminal still works, which is the whole demonstration"
      value       = module.vscode_ec2.vscode_url
    }
    what_this_shows = {
      order       = 2
      title       = "What this project demonstrates"
      description = "A cluster whose API server has no public endpoint, reached from a second VPC that is not peered to the first. The path is a VPC Lattice resource gateway in the cluster's VPC, a resource configuration naming the API server, a service network, and one endpoint in the client VPC - plus a private hosted zone so the client resolves the cluster's real hostname and the certificate matches"
      value       = "cluster VPC ${module.network.vpc_id} (${var.cluster_vpc_cidr_block}) -> resource gateway -> resource configuration -> service network -> endpoint -> client VPC ${module.client_network.vpc_id} (${var.client_vpc_cidr_block})\nno peering, no transit gateway, no route between the two"
    }
    api_server_endpoint = {
      order       = 3
      title       = "The API server endpoint"
      description = "Private only. Resolving this name from outside the client VPC returns nothing useful - that is the point, and it is why every other project here with a public endpoint needs none of the Lattice machinery"
      value       = module.eks_cluster.cluster_endpoint
    }
    resolve_command = {
      order       = 4
      title       = "1. Does the name resolve to the endpoint"
      description = "Run it on the workbench. It should return a private address in the client VPC. NXDOMAIN means the private hosted zone is missing or not associated with this VPC; an address in the cluster VPC's range means the zone is there and the alias points at the wrong target"
      value       = module.lattice_client_endpoint.resolve_command
    }
    kubectl_command = {
      order       = 5
      title       = "2. Does the API server answer"
      description = "If step 1 resolves and this times out, the path is the security groups rather than DNS: either the endpoint's ingress rule or the cluster security group's rule for the resource gateway. The apply already ran both of these once through an SSM association, so a failure here after a successful apply means something changed"
      value       = "kubectl version --request-timeout=30s && kubectl get nodes"
    }
    lattice_configuration_command = {
      order       = 6
      title       = "3. The resource configuration"
      description = "Its status and what it forwards. ACTIVE here with a client that cannot connect points at the security groups. Note the port ranges: the _monolithic template opened 1-65535 on a resource that serves one port"
      value       = module.lattice_api_server_access.describe_command
    }
    lattice_association_command = {
      order       = 7
      title       = "4. Is the configuration attached to the service network"
      description = "A status other than ACTIVE means the client endpoint has nothing to resolve, however healthy the endpoint itself looks - and the endpoint reports available either way"
      value       = module.lattice_api_server_access.association_status_command
    }
    endpoint_associations_command = {
      order       = 8
      title       = "5. What the endpoint publishes"
      description = "The DNS name and hosted zone the alias record points at. This is the call the _monolithic template shipped a Lambda with AmazonEC2FullAccess to make - a Lambda that could not run, because the file it was packaged from contained a Python dict repr of a CloudFormation Fn::Sub rather than code"
      value       = module.lattice_client_endpoint.associations_command
    }
    endpoint_state_command = {
      order       = 9
      title       = "6. Did the endpoint come up"
      description = "A state other than available usually means the subnets or the security group were rejected"
      value       = module.lattice_client_endpoint.endpoint_state_command
    }
    private_dns = {
      order       = 10
      title       = "The private hosted zone"
      description = "What makes the cluster's own hostname resolve inside the client VPC, and therefore what makes a kubeconfig from aws eks update-kubeconfig work unchanged. Without it a client would have to target the endpoint's own name and TLS verification would fail on the mismatch - which reads as a certificate problem rather than a DNS one"
      value       = "zone ${coalesce(module.lattice_client_endpoint.private_hosted_zone_id, "not created")} for ${local.api_server_hostname} -> ${coalesce(module.lattice_client_endpoint.endpoint_dns_name, "n/a")}"
    }
    cluster_name = {
      order       = 11
      title       = "EKS cluster name"
      description = "Name of the EKS cluster"
      value       = module.eks_cluster.cluster_name
    }
    update_kubeconfig_command = {
      order       = 12
      title       = "Re-point kubectl"
      description = "User data ran this at boot, before the endpoint and the private zone existed - so an SSM association ran it again afterwards. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
    private_key_command = {
      order       = 13
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
# above is also written to a README in the home directory the IDE opens (rules.md H-2). The _monolithic template
# wrote none at all.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # Waits for the verification step's marker rather than the bootstrap's, so the README lands once the path it
    # describes has been shown to work (rules.md D-5).
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/verify_api_server_access ]; do sleep 10; done
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_readme
      EOT
  }

  depends_on = [aws_ssm_association.verify_api_server_access]
}
