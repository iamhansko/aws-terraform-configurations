data "aws_region" "current" {}

# Only needed to build the registry hostname of the pull-through cache further down.
# Read in the root rather than inside a module because every module here carries a
# depends_on, which would defer the read to apply (rules.md D-6).
data "aws_caller_identity" "current" {}

module "network" {
  source = "./modules/network"

  region                         = data.aws_region.current.region
  vpc_cidr_block                 = var.vpc_cidr_block
  availability_zone_suffixes     = var.availability_zone_suffixes
  nat_availability_zone_suffixes = var.nat_availability_zone_suffixes
  vpc_name                       = "${var.project_name}-vpc"
  # No kubernetes.io/role tags. Nothing in this project asks the AWS Load Balancer
  # Controller to build a load balancer - the chart is installed so it is there, and
  # the subject is the cluster's security group, not ingress. Tagging subnets for a
  # controller that has nothing to place would be a claim the configuration does not
  # back up (rules.md G-1 covers the case where Terraform has to write them).
  subnet_tags = {}
}

module "key_pair" {
  source = "./modules/key_pair"

  key_name = "${var.project_name}-key"

  # Nothing here reads a network output, but the root orders every module after the
  # network so the whole VPC - NAT gateway and route tables included - is finished
  # before anything starts in it (rules.md D-3).
  depends_on = [module.network]
}

module "eks_cluster" {
  source = "./modules/eks_cluster"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version
  # Private subnets only, unlike most projects here, which hand the cluster both
  # tiers. The control plane's cross-account ENIs belong in the subnets the nodes are
  # in, and with no public endpoint there is no reason to put them anywhere
  # reachable from outside.
  subnet_ids                = module.network.private_subnet_ids
  endpoint_private_access   = var.endpoint_private_access
  endpoint_public_access    = var.endpoint_public_access
  enabled_cluster_log_types = var.enabled_cluster_log_types

  # module.network.private_subnet_ids orders this after the specific aws_subnet
  # resources behind it and nothing else - not the NAT gateway, not the route table
  # associations (rules.md D-3).
  depends_on = [module.network]
}

# The endpoints, and the security group in front of them. This is the pair the whole
# project is about: the group is separate from the cluster's, so reaching it takes an
# explicit egress rule on the cluster security group rather than the blanket
# "all outbound" a cluster group starts with.
#
# Created after the cluster because the group admits the cluster's own group as a
# source, which is another module's output (rules.md B-6/B-8).
module "vpc_endpoints" {
  source = "./modules/vpc_endpoints"

  vpc_id          = module.network.vpc_id
  subnet_ids      = module.network.private_subnet_ids
  route_table_ids = module.network.route_table_ids
  # Only the group this module creates goes on the endpoint ENIs. Passing the cluster
  # group here as well - which is what 041_eks_private_cluster does - would let pods
  # reach the endpoints through the group's self-rule and make the cluster's egress
  # rule below unnecessary, and that rule is the thing being demonstrated.
  additional_security_group_ids = []
  interface_services            = var.interface_endpoint_services
  security_group_name           = var.vpc_endpoint_security_group_name
  endpoint_port                 = var.endpoint_port
  # Keyed by a label, not iterated as a list: the cluster security group ID is
  # another module's output and unknown at plan time, so it cannot be a for_each key
  # (rules.md B-8).
  ingress_source_security_groups = {
    eks_cluster = module.eks_cluster.cluster_security_group_id
  }
  name_prefix = var.project_name

  depends_on = [module.network, module.eks_cluster]
}

# The egress rules that replace the blanket rule EKS ships on the cluster security
# group. Both exist before aws_ssm_association.revoke_default_cluster_egress takes
# that blanket rule away, which is the ordering the whole lower half of this file is
# arranged around: what the cluster is allowed to reach has to be written down before
# the rule that allowed everything is removed, not after.
#
# They modify the EKS-managed cluster security group, which no module here owns
# outright, so they belong in the root (rules.md C-1). Standalone rule resources, not
# inline blocks - EKS adds control-plane-to-node rules to this group itself, and an
# inline block would revoke them on the next apply (rules.md F-2).
#
# There is deliberately no rule here for traffic inside the cluster, and that is the
# easiest thing in this file to get wrong, because such a rule is clearly necessary:
# the control plane's cross-account ENIs, every node and every pod IP sit in this one
# group, so a kubelet could not reach the API server without it. It is not here
# because EKS already creates it. The group ships with three rules, not two:
#
#   inbound   all protocols, source self        "Allows EFA traffic, which is not
#                                                matched by CIDR rules."
#   outbound  all protocols, destination self   same description
#   outbound  all protocols, 0.0.0.0/0          no description - the one revoked below
#
# Only the third is removed, so intra-cluster traffic keeps working on EKS's own rule
# and this configuration never has to decide which ports to open. That matters more
# than it sounds: AWS documents the minimum for a restricted cluster group as TCP 443,
# TCP 10250 and TCP/UDP 53 to this same group
# (https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html), and that
# list is not sufficient here - the load balancer controller's admission webhook
# listens on 9443 and the API server calls it, which would fail a failurePolicy: Fail
# webhook and break Service creation cluster-wide (rules.md G-4 is the same webhook
# from the other direction). EKS's self rule is all protocols and sidesteps the whole
# question.
#
# Declaring the self rule anyway is what the first version of this did, and the apply
# fails on it:
#
#   Error: creating VPC Security Group Rule ... InvalidPermission.Duplicate:
#   the specified rule "peer: sg-..., ALL, ALLOW" already exists
#
# The same page says EKS recreates the self rules if they are removed, so they are
# EKS's to own in both directions and there is nothing to adopt or import.
#
# Note also that the Amazon-provided DNS resolver at the VPC base address plus two is
# not reachable through any of these rules and does not need to be: "You cannot
# filter traffic to or from the Amazon DNS server using network ACLs or security
# groups" (https://docs.aws.amazon.com/vpc/latest/userguide/AmazonDNS-concepts.html).
# That is what still lets a node resolve the endpoint hostnames below with no egress
# rule naming the resolver.
resource "aws_vpc_security_group_egress_rule" "cluster_to_vpc_endpoints" {
  security_group_id            = module.eks_cluster.cluster_security_group_id
  description                  = "HTTPS to the interface VPC endpoints"
  ip_protocol                  = "tcp"
  from_port                    = var.endpoint_port
  to_port                      = var.endpoint_port
  referenced_security_group_id = module.vpc_endpoints.security_group_id
}

# The S3 gateway endpoint has no ENI and no security group, so a rule toward it names
# the service's managed prefix list as its destination instead.
#
# The prefix list ID comes straight off the gateway endpoint resource. The
# _monolithic template looked the same value up by name through a Python Lambda -
# packaged with archive_file, given an IAM role and ec2:DescribeManagedPrefixLists,
# and invoked with aws_lambda_invocation - five resources and a build artifact for
# one attribute the provider already exposes.
resource "aws_vpc_security_group_egress_rule" "cluster_to_s3" {
  count = var.create_cluster_egress_to_s3 ? 1 : 0

  security_group_id = module.eks_cluster.cluster_security_group_id
  description       = "HTTPS to S3 through the gateway endpoint prefix list"
  ip_protocol       = "tcp"
  from_port         = var.endpoint_port
  to_port           = var.endpoint_port
  prefix_list_id    = module.vpc_endpoints.s3_prefix_list_id
}

# The controller image, moved off ECR Public onto a pull-through cache in this
# account. The last of the four things that have to exist before the blanket egress
# rule is revoked, and the only one that is not a security group rule.
#
# The chart's default image is public.ecr.aws/eks/aws-load-balancer-controller, and
# ECR Public is not a PrivateLink service - there is no com.amazonaws.<region>
# endpoint for it to add to interface_endpoint_services. So once the blanket rule is
# gone a node has no route to the registry the chart names, and the helm install in
# the SSM step further down sits in ImagePullBackOff until its own timeout expires.
#
# A pull-through cache turns that into an ordinary private ECR pull: ECR fetches the
# upstream image over its own network, and the node reaches the result through the
# ecr.api, ecr.dkr and S3 endpoints it already has egress rules for. The alternative
# is the regional EKS add-on registry
# (602401143452.dkr.ecr.<region>.amazonaws.com/amazon/aws-load-balancer-controller),
# which needs no resource at all but assumes the chart's exact tag was mirrored there
# - an assumption that cannot be checked from outside the cluster's account, and that
# breaks on a chart bump rather than at the time it was made. The cache assumes
# nothing: it imports whichever tag is asked for.
#
# The permissions the pulling principal needs for this - ecr:BatchImportUpstreamImage
# and ecr:CreateRepository - are already on the node role through
# AmazonEC2ContainerRegistryFullAccess. node_iam_policy_arns describes that policy as
# "broader than a node needs for pulling, kept because the original had it"; it is
# now also load-bearing, which is worth knowing before narrowing it (rules.md E-9
# covers the same pairing, and the failure when it is missing: ECR answers a pull for
# an image it may not import with "not found" rather than with a permission error).
locals {
  # Derived rather than literal. A pull-through cache prefix is unique per registry,
  # so it is account- and region-wide rather than per project: a shared literal such
  # as "ecr-public" makes the second project in an account fail on
  # PullThroughCacheRuleAlreadyExistsException (rules.md B-4).
  controller_image_cache_prefix = coalesce(var.controller_image_cache_prefix, "${var.project_name}-ecr-public")
  # Only the repository half is rewritten. The tag stays whatever the pinned chart's
  # appVersion is, so the cache imports exactly the image that chart asked for and a
  # chart bump needs no change here.
  controller_image_repository = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com/${local.controller_image_cache_prefix}/${var.controller_upstream_image_path}"
}

resource "aws_ecr_pull_through_cache_rule" "controller_image" {
  ecr_repository_prefix = local.controller_image_cache_prefix
  upstream_registry_url = "public.ecr.aws"
}

# Declared rather than left to the cache's on-demand creation, which would work -
# ecr:CreateRepository is only needed when the repository does not already exist - but
# would leave it behind. Deleting a pull-through cache rule does not delete the
# repositories it populated, so destroy would finish cleanly and leave a repository
# full of cached layers in the account with nothing reporting it.
resource "aws_ecr_repository" "controller_image" {
  name = "${local.controller_image_cache_prefix}/${var.controller_upstream_image_path}"
  # The images in here are put there by ECR on first pull, not by this configuration,
  # so destroy has to be allowed to delete a repository it did not fill.
  force_delete = true

  depends_on = [aws_ecr_pull_through_cache_rule.controller_image]
}

# The workbench, and note where it now sits: ahead of every cluster-dependent module
# rather than after them, as it is in the other EKS roots here.
#
# That is a consequence of revoking the blanket egress rule through an SSM
# Association. An association runs commands on an instance, this is the only instance
# in the project, and the revocation has to happen before the node group is created -
# so the instance is now a prerequisite of the data plane rather than a place to go
# and look at it afterwards. The practical cost is that the node group waits out this
# instance's bootstrap, since the revocation step waits for its marker file.
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name   = "${var.project_name}-vscode"
  vpc_id = module.network.vpc_id
  # A public subnet with a public address, unlike the cluster. This instance is the
  # only way in: it needs internet egress to download kubectl, helm and the chart,
  # and it needs to be inside the VPC to reach the private API server. Both halves
  # are why the chart is installed from here (rules.md E-9).
  subnet_id                   = module.network.public_subnet_ids_by_zone[var.availability_zone_suffixes[0]]
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  code_server_version         = var.code_server_version
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  marker_file_path            = var.marker_file_path
  # Joining the cluster security group is what lets this instance reach the private
  # API server at all. The module is handed an ID list and never learns it belongs to
  # an EKS cluster (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]
  # All five tools, because an EKS cluster and this instance share a root module
  # (rules.md H-1). Here kubectl and helm are not only for debugging: they are how the
  # controller chart gets installed, which is the one place rules.md E-1 is inverted -
  # see providers.tf and rules.md E-9.
  additional_user_data = <<-EOT
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server is already running and predates the docker group, so its terminals
    # would not have it without a restart. The _monolithic template opened
    # /var/run/docker.sock to 666 instead.
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
    # Order matters: kubectl's completion defines __start_kubectl, and that has to
    # exist before complete names it. The _monolithic template had the complete line
    # first, so every login printed "function not found" (rules.md H-1).
    echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
    echo 'source <(kubectl completion bash)' >> ~/.bashrc
    echo 'alias k=kubectl' >> ~/.bashrc
    echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
    # eksctl-io is the project's own org; the weaveworks URL the _monolithic template
    # used still redirects, but the current name is what gets used (rules.md H-1).
    PLATFORM=$(uname -s)_amd64
    curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
    tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
    sudo install -m 0755 /tmp/eksctl /usr/local/bin && rm /tmp/eksctl
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm -f get_helm.sh
    aws configure set default.region ${data.aws_region.current.region}
    # The _monolithic user data ran "exec bash" just above this line, which replaced
    # the shell and meant nothing after it ever ran - the kubeconfig write, eksctl,
    # helm and the whole controller install included. Dropped.
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}
    EOF
  EOT

  depends_on = [module.network]
}

# The revocation. This is what the project is for: of the three egress rules EKS
# creates, this removes the one toward 0.0.0.0/0, leaving the group able to reach
# itself on EKS's own self rule, the interface endpoints on 443, S3 on 443, and
# nothing else - no internet, no other VPC resource, no other security group.
#
# Done from an SSM Association rather than from Terraform because the rule is not a
# Terraform resource and cannot be made into one. EKS creates it as part of the
# cluster, inside a group EKS also owns; there is no ID to import, and an
# aws_vpc_security_group_egress_rule declared against it would try to create a second
# identical rule rather than adopt the existing one. Removing it means calling
# RevokeSecurityGroupEgress against a rule ID that is only discoverable at apply
# time, which is a command, not a declaration.
#
# Two things follow from that, and both are costs worth stating plainly:
#
#   - The revocation is not in Terraform state. terraform plan will never show the
#     rule, never notice it coming back, and never offer to remove it again. The only
#     thing that says whether the group is still restricted is
#     cluster_security_group_rules_command in the outputs below.
#   - Ordering the rest of the configuration after this depends on the association's
#     own success status, which rules.md D-5 warns is not a reliable signal that the
#     remote command finished. That is why the script below ends by re-reading the
#     group and exiting non-zero if the rule is still there: a Success status on this
#     association means the rule was observed gone, not merely that a revoke call was
#     issued.
#
# What it does not protect against is EKS putting the rule back. A cluster version
# update recreates both the inbound all-traffic self rule and this outbound rule -
# that is the behaviour the project README tabulates, and the reason the revoke
# command is exposed as an output for re-running by hand.
resource "aws_ssm_association" "revoke_default_cluster_egress" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.revoke_cluster_egress_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The IsEgress test is written as a truthiness filter rather than as
    # IsEgress == `true`, because a JMESPath literal is backquoted and a backquote
    # inside a double-quoted shell string is command substitution. Both CIDRs are
    # matched so this stays correct for an ipv6 cluster, where EKS writes the same
    # rule toward ::/0 - the eks_cluster module accepts ip_family = "ipv6", even
    # though this root does not set it.
    #
    # Everything here is re-runnable, which matters because an association re-runs
    # whenever its parameters change: a missing rule is reported and skipped rather
    # than treated as an error.
    commands = <<-EOT
      set -euo pipefail
      until [ -f ${module.vscode_ec2.marker_file_path}/userdata ]; do sleep 10; done
      group_id=${module.eks_cluster.cluster_security_group_id}
      region=${data.aws_region.current.region}
      query="SecurityGroupRules[?IsEgress && IpProtocol=='-1' && (CidrIpv4=='0.0.0.0/0' || CidrIpv6=='::/0')].SecurityGroupRuleId"
      rule_ids=$(aws ec2 describe-security-group-rules --region "$region" --filters "Name=group-id,Values=$group_id" --query "$query" --output text)
      if [ -n "$rule_ids" ]; then
        echo "revoking allow-all egress on $group_id: $rule_ids"
        aws ec2 revoke-security-group-egress --region "$region" --group-id "$group_id" --security-group-rule-ids $rule_ids
      else
        echo "no allow-all egress rule on $group_id - nothing to revoke"
      fi
      remaining=$(aws ec2 describe-security-group-rules --region "$region" --filters "Name=group-id,Values=$group_id" --query "$query" --output text)
      if [ -n "$remaining" ]; then
        echo "allow-all egress rule is still present on $group_id: $remaining" >&2
        exit 1
      fi
      aws ec2 describe-security-group-rules --region "$region" --filters "Name=group-id,Values=$group_id" \
        --query 'SecurityGroupRules[].[SecurityGroupRuleId,IsEgress,IpProtocol,FromPort,ToPort,CidrIpv4,ReferencedGroupInfo.GroupId,PrefixListId,Description]' \
        --output table
      touch ${module.vscode_ec2.marker_file_path}/cluster_egress_revoked
      EOT
  }

  # Everything that replaces the blanket rule has to exist before the blanket rule is
  # taken away, so all of it is named here: the two egress rules, the endpoints they
  # point at, and the image cache that stands in for the ECR Public pull the cluster
  # can no longer make. Revoking first and adding second would leave a window in
  # which the cluster can reach nothing, and a node group created in that window does
  # not recover - it times out fifteen minutes later with nothing saying why.
  #
  # Intra-cluster traffic is not in this list because it is not this configuration's
  # to arrange: EKS's own outbound self rule covers it and is not touched here.
  depends_on = [
    module.vpc_endpoints,
    aws_vpc_security_group_egress_rule.cluster_to_vpc_endpoints,
    aws_vpc_security_group_egress_rule.cluster_to_s3,
    aws_ecr_pull_through_cache_rule.controller_image,
    aws_ecr_repository.controller_image,
  ]
}

# Everything from here down is cluster-dependent, and everything from here down is
# ordered after aws_ssm_association.revoke_default_cluster_egress - directly, in the
# first wave below, or through one of those modules further on. The point of the
# ordering is that nothing on this cluster is ever created in a world where the
# blanket egress rule still exists: the nodes join, the addons schedule and the
# controller installs against the restricted group, so a missing egress rule shows up
# as a failure during apply rather than as something that worked once and breaks the
# next time the cluster is rebuilt.
#
# The invariant is kept whole rather than carved out per resource. An aws_eks_addon
# is an EKS API call that would succeed with the group in either state, so a case
# could be made for letting these three run early - but then the ordering becomes a
# judgement to re-make for every resource added later, and the one that gets it wrong
# fails somewhere other than here (rules.md D-3 makes the same argument for network).

# vpc-cni and kube-proxy are DaemonSets, so they reach ACTIVE with zero nodes. They
# are created before the node group because a node cannot join Ready without them,
# and with bootstrap_self_managed_addons = false nothing installs them otherwise
# (rules.md C-4). The _monolithic template declared all four addons with no ordering
# and left the cluster bootstrapping unmanaged copies alongside them.
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  depends_on = [module.network, module.eks_cluster, aws_ssm_association.revoke_default_cluster_egress]
}

module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  depends_on = [module.network, module.eks_cluster, aws_ssm_association.revoke_default_cluster_egress]
}

# The Pod Identity agent, which is how the load balancer controller gets its
# credentials. A DaemonSet, so like the two above it needs no node capacity to become
# ACTIVE - but it does have to exist before any pod tries to exchange a token.
module "eks_pod_identity_agent_addon" {
  source = "./modules/eks_pod_identity_agent_addon"

  cluster_name = module.eks_cluster.cluster_name

  depends_on = [module.network, module.eks_cluster, aws_ssm_association.revoke_default_cluster_egress]
}

module "eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name         = module.eks_cluster.cluster_name
  node_group_name      = var.node_group_name
  instance_types       = var.node_instance_types
  labels               = var.node_labels
  desired_size         = var.node_desired_size
  min_size             = var.node_min_size
  max_size             = var.node_max_size
  key_name             = module.key_pair.key_name
  subnet_ids           = module.network.private_subnet_ids
  node_iam_policy_arns = var.node_iam_policy_arns

  # Nodes need vpc-cni and kube-proxy to join Ready, and they reach the EC2, ECR and
  # SSM APIs through the endpoints - the endpoints being unreachable does not produce
  # an error here, it produces a node group create that times out after fifteen
  # minutes with nothing explaining why (rules.md C-4/D-2).
  #
  # The association rather than the individual egress rules it already waits on: this
  # is the resource whose success means the group is in its final, restricted state,
  # and it is the whole reason the nodes in this node group are the first things to
  # join a cluster whose security group no longer allows arbitrary outbound.
  depends_on = [
    module.network,
    module.vpc_endpoints,
    module.eks_vpc_cni_addon,
    module.eks_kube_proxy_addon,
    aws_ssm_association.revoke_default_cluster_egress,
  ]
}

# coredns is a Deployment, so unlike the DaemonSets it needs schedulable node
# capacity to leave DEGRADED and become ACTIVE (rules.md C-4).
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name          = module.eks_cluster.cluster_name
  coredns_replica_count = var.coredns_replica_count

  depends_on = [
  module.network, module.eks_node_group]
}

# The role and its Pod Identity association only. The chart is installed by the SSM
# step further down, because a helm provider on the machine running terraform apply
# cannot reach this cluster's private API server - see providers.tf.
module "aws_load_balancer_controller_iam_role" {
  source = "./modules/aws_load_balancer_controller_iam_role"

  cluster_name = module.eks_cluster.cluster_name

  # The association is created on the cluster, and the agent has to be running before
  # a pod can use it (rules.md D-2).
  depends_on = [
  module.network, module.eks_cluster, module.eks_pod_identity_agent_addon]
}

# Without this the instance has kubectl but every command fails with "You must be
# logged in to the server", so the SSM step below would fail too. Joining two modules
# that know nothing about each other belongs in the root (rules.md C-1).
resource "aws_eks_access_entry" "vscode_access_entry" {
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.vscode_ec2.iam_role_arn
  type          = "STANDARD"

  # Named explicitly even though the revocation needs none of this: the association
  # runs against the EC2 API with the instance profile, not against the cluster. It
  # is here because this is a resource on the cluster and the invariant above has no
  # exceptions - and because the ordering is free, the association already being
  # ordered after the instance whose role this entry names.
  depends_on = [aws_ssm_association.revoke_default_cluster_egress]
}

resource "aws_eks_access_policy_association" "vscode_access_policy_association" {
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.vscode_ec2.iam_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }

  # EKS rejects a policy association for a principal with no access entry yet, and the
  # two resources share only literal argument values, so nothing orders them
  # (rules.md D-1). The _monolithic template had no ordering here at all.
  depends_on = [aws_eks_access_entry.vscode_access_entry]
}

# The AWS Load Balancer Controller, installed by an SSM Association running helm on
# the workbench rather than by a helm_release. The cluster's API server is private, so
# a provider on the machine running terraform apply cannot reach it (rules.md E-9);
# providers.tf spells out what that costs.
#
# The until loop, not depends_on, is what orders this after the previous step:
# wait_for_success_timeout_seconds does not reliably wait for the remote command to
# finish, so each step waits for the previous step's marker and leaves its own
# (rules.md D-5). The marker it waits on is the revocation's, not the bootstrap's,
# which keeps the chain linear - userdata, then cluster_egress_revoked, then this
# step, then the README - and means the chart is installed against the restricted
# security group like everything else on this cluster.
#
# image.repository is overridden to the pull-through cache. The chart's own default is
# public.ecr.aws, which no node can reach any more; without this the install waits out
# its timeout on ImagePullBackOff and the association reports a bare "Failed".
#
# Two chart values that would matter if this project grew an Ingress and do not now:
# AWS recommends enable-shield, enable-waf and enable-wafv2 be set false on a cluster
# without outbound internet access, because those APIs have no interface endpoint. The
# controller only calls them while reconciling an Ingress, and nothing here creates
# one, so they are left at their defaults rather than carrying three settings the
# configuration does not exercise.
#
# No serviceAccount.annotations here, unlike the IRSA form: the Pod Identity
# association the role module created is what binds the account to the role, so there
# is no ARN to interpolate into an escaped annotation key.
resource "aws_ssm_association" "load_balancer_controller" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.controller_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    commands = <<-EOT
      set -euo pipefail
      until [ -f ${module.vscode_ec2.marker_file_path}/cluster_egress_revoked ]; do sleep 10; done
      sudo -Eu ec2-user bash << 'STEP'
      set -euo pipefail
      export HOME=/home/ec2-user
      export PATH=/home/ec2-user/bin:$PATH
      helm repo add eks https://aws.github.io/eks-charts
      helm repo update eks
      # An association re-runs whenever its parameters change, so this step has to be
      # re-runnable - and a release whose only revision failed is the one state
      # "upgrade --install" cannot recover from: helm refuses it with "has no deployed
      # releases", which hides whatever the original failure was. Clear exactly that
      # state, never a release that has a deployed revision (rules.md E-7).
      if helm status ${var.controller_release_name} -n ${module.aws_load_balancer_controller_iam_role.namespace} >/dev/null 2>&1; then
        # grep -c over one field per line rather than "grep -q" on the raw JSON:
        # under pipefail, grep -q closing the pipe early can fail the whole pipeline
        # even on a match.
        deployed=$(helm history ${var.controller_release_name} -n ${module.aws_load_balancer_controller_iam_role.namespace} -o json | tr ',' '\n' | grep -c '"status":"deployed"' || true)
        if [ "$deployed" -eq 0 ]; then
          echo "clearing failed release with no deployed revision"
          helm uninstall ${var.controller_release_name} -n ${module.aws_load_balancer_controller_iam_role.namespace} --wait
        fi
      fi
      helm upgrade --install ${var.controller_release_name} eks/aws-load-balancer-controller \
        --version ${var.aws_load_balancer_controller_chart_version} \
        --namespace ${module.aws_load_balancer_controller_iam_role.namespace} \
        --set image.repository=${local.controller_image_repository} \
        --set clusterName=${module.eks_cluster.cluster_name} \
        --set region=${data.aws_region.current.region} \
        --set vpcId=${module.network.vpc_id} \
        --set serviceAccount.create=true \
        --set serviceAccount.name=${module.aws_load_balancer_controller_iam_role.service_account_name} \
        --set enableBackendSecurityGroup=${var.enable_backend_security_group} \
        --wait --timeout ${var.controller_helm_timeout_seconds}s \
        || { kubectl -n ${module.aws_load_balancer_controller_iam_role.namespace} get pods -l app.kubernetes.io/name=aws-load-balancer-controller -o wide; exit 1; }
      STEP
      touch ${module.vscode_ec2.marker_file_path}/load_balancer_controller
      EOT
  }

  # The controller's pods need a node to run on, DNS to resolve, the EKS Auth and
  # elasticloadbalancing APIs to reach, and the access entry to exist before kubectl
  # on this instance works at all.
  #
  # The image cache is named too. It is already ordered ahead of this through the
  # revocation, but this is the resource that pulls the image, and the ordering that
  # matters is easier to see from here than from three hops away.
  depends_on = [
    module.eks_node_group,
    module.eks_coredns_addon,
    module.vpc_endpoints,
    module.aws_load_balancer_controller_iam_role,
    aws_eks_access_policy_association.vscode_access_policy_association,
    aws_ecr_pull_through_cache_rule.controller_image,
    aws_ecr_repository.controller_image,
  ]
}

locals {
  # Every output this project exposes, defined once. outputs.tf projects these and the
  # README below renders them, so no value expression is written twice
  # (rules.md B-5/H-2). Adding an entry here is what makes an output possible, which
  # is what keeps the README from falling behind outputs.tf.
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here. On this project it is not a convenience: the cluster's API server is private, so this instance is the only place kubectl works at all"
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
      title       = "EKS cluster endpoint (private)"
      description = "Resolves only inside the VPC. There is no public endpoint, which is why the load balancer controller chart was installed by an SSM Association on this instance rather than by a Terraform provider"
      value       = module.eks_cluster.cluster_endpoint
    }
    cluster_security_group_id = {
      order       = 4
      title       = "Cluster security group"
      description = "The group this project is about. EKS creates it, attaches it to the control plane ENIs and to every node, and rewrites its rules on some cluster updates - see the project README for which ones"
      value       = module.eks_cluster.cluster_security_group_id
    }
    vpc_endpoint_security_group_id = {
      order       = 5
      title       = "VPC endpoint security group"
      description = "Separate from the cluster's group on purpose. Reaching the endpoints therefore takes an explicit egress rule on the cluster group, which is the rule being demonstrated"
      value       = module.vpc_endpoints.security_group_id
    }
    s3_prefix_list_id = {
      order       = 6
      title       = "S3 gateway endpoint prefix list"
      description = "The destination of the cluster's second egress rule. Read straight off the gateway endpoint resource; the _monolithic template used a Python Lambda, an IAM role and aws_lambda_invocation to look the same value up by name"
      value       = module.vpc_endpoints.s3_prefix_list_id
    }
    controller_image_repository = {
      order       = 7
      title       = "Load balancer controller image"
      description = "Not the chart's default. ECR Public has no interface endpoint, so with the cluster's blanket egress rule revoked a node cannot reach public.ecr.aws at all, and the image is pulled through a pull-through cache in this account instead. The tag is still the chart's own"
      value       = local.controller_image_repository
    }
    cluster_security_group_rules_command = {
      order       = 8
      title       = "1. Read the cluster security group's rules"
      description = "The demonstration, in one command. There should be no egress rule with protocol -1 to 0.0.0.0/0 - an SSM Association revoked the one EKS created - leaving EKS's two self rules, which carry the EFA description and are recreated if removed, plus the two this configuration adds: HTTPS to the endpoint group and HTTPS to the S3 prefix list. Run it again after a cluster version update and compare against the project README's table"
      value       = "aws ec2 describe-security-group-rules --filters Name=group-id,Values=${module.eks_cluster.cluster_security_group_id} --query 'SecurityGroupRules[].[SecurityGroupRuleId,IsEgress,IpProtocol,FromPort,ToPort,CidrIpv4,ReferencedGroupInfo.GroupId,PrefixListId,Description]' --output table"
    }
    endpoint_check_command = {
      order       = 9
      title       = "2. Confirm the VPC endpoints are available"
      description = "An endpoint in any state other than available means that API is unreachable from the private subnets, which shows up as nodes not joining or images not pulling rather than as a clear error"
      value       = module.vpc_endpoints.endpoint_check_command
    }
    node_status_command = {
      order       = 10
      title       = "3. The nodes joined Ready"
      description = "These nodes joined a cluster whose security group was already restricted, which is what the ordering in main.tf is for. A node that never reaches Ready here is almost always an endpoint or egress-rule problem: the kubelet could not reach the API server, or the CNI image never pulled"
      value       = "kubectl get nodes -o wide"
    }
    controller_status_command = {
      order       = 11
      title       = "4. The load balancer controller is running"
      description = "Installed by the SSM Association above. Because it is not in Terraform state, this command is the only thing that says whether it is still there"
      value       = "kubectl -n ${module.aws_load_balancer_controller_iam_role.namespace} get deployment ${var.controller_release_name}"
    }
    controller_log_command = {
      order       = 12
      title       = "5. Read the controller log"
      description = "Where an AWS-side permission problem shows up. The controller gets its credentials through a Pod Identity association rather than a service account annotation, so a failure here reads as an access-denied from the AWS SDK rather than as a missing role. On this cluster it is also where a missing eks-auth endpoint would appear, in the same shape"
      value       = "kubectl -n ${module.aws_load_balancer_controller_iam_role.namespace} logs deploy/${var.controller_release_name} --tail 100"
    }
    revoke_cluster_egress_command = {
      order       = 13
      title       = "6. Re-revoke the rule after a cluster version update"
      description = "What the SSM Association ran, as one command. Keep it: an EKS version update recreates the rule this removed, and nothing reports that - the rule is not a Terraform resource, so no plan shows it coming back. Run the command above first to see whether it is there"
      value       = "aws ec2 revoke-security-group-egress --group-id ${module.eks_cluster.cluster_security_group_id} --security-group-rule-ids $(aws ec2 describe-security-group-rules --filters Name=group-id,Values=${module.eks_cluster.cluster_security_group_id} --query \"SecurityGroupRules[?IsEgress && IpProtocol=='-1' && CidrIpv4=='0.0.0.0/0'].SecurityGroupRuleId\" --output text)"
    }
    update_kubeconfig_command = {
      order       = 14
      title       = "Re-point kubectl"
      description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the
  # order field and taking values() sorts by that instead - values() returns a map's
  # values ordered by key - so the README reads in the order the demo is run.
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

# The work happens inside code-server in a browser, where "terraform output" does not
# exist, so every output above is also written to a README in the home directory the
# IDE opens (rules.md H-2). The _monolithic template wrote this file too, with a
# single `echo '# EKS Cluster'` - a title and nothing else.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # Waits on the controller step's marker rather than on the bootstrap marker, so
    # the README is written after the last thing it describes exists (rules.md D-5).
    #
    # SSM runs as root, hence the chown. The heredoc delimiter is quoted and
    # deliberately unlikely to appear in the body: Terraform has already substituted
    # every value, so the shell has no reason to touch a "$" or a backtick in the
    # README - and the commands in it contain both.
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/load_balancer_controller ]; do sleep 10; done
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_readme
      EOT
  }

  depends_on = [aws_ssm_association.load_balancer_controller]
}
