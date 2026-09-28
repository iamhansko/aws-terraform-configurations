data "aws_region" "current" {}
module "network" {
  source = "./modules/network"

  public_subnet_tags  = var.public_subnet_tags
  private_subnet_tags = var.private_subnet_tags
  # The defining choice of this project. With no NAT gateway the private subnets
  # have no route off the VPC, so the cluster reaches AWS only through the endpoints
  # below and can only run images that came through the ECR cache.
  enable_nat_gateway = var.enable_nat_gateway
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name = var.key_name

  # key_pair consumes no network output, so nothing would otherwise order it
  # against the network module's resources (rules.md D-3).
  depends_on = [module.network]
}
module "eks_cluster" {
  source = "./modules/eks_cluster"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version
  # Private subnets only, unlike every other project here, which hands the cluster
  # both tiers. The control plane's cross-account ENIs belong in the subnets the
  # nodes are in, and there is no reason to put them anywhere reachable.
  subnet_ids             = module.network.private_subnet_ids
  endpoint_public_access = var.endpoint_public_access

  # Referencing module.network.private_subnet_ids only orders this after the
  # specific aws_subnet resources behind that output, not after the route tables
  # (rules.md D-3).
  depends_on = [module.network]
}
# Everything the cluster can reach. Created after the cluster because they are given
# the cluster's own security group: pods carry that group and it admits traffic from
# itself, so no extra rule is needed for pods to use the endpoints. The cost of that
# convenience is this ordering constraint.
module "vpc_endpoints" {
  source = "./modules/vpc_endpoints"

  vpc_id             = module.network.vpc_id
  subnet_ids         = module.network.private_subnet_ids
  route_table_ids    = module.network.private_route_table_ids
  security_group_ids = [module.eks_cluster.cluster_security_group_id]
  interface_services = var.interface_endpoint_services
  name_prefix        = var.cluster_name

  depends_on = [module.network, module.eks_cluster]
}
# Without this the cluster cannot run any image at all: the nodes can reach ECR in
# this account and nothing else, so a reference to public.ecr.aws or to the regional
# EKS registry fails. Not ordered against the cluster - these are account-level ECR
# resources - but the node group below waits for it, because the first thing a node
# does is pull images.
module "ecr_pull_through_cache" {
  source = "./modules/ecr_pull_through_cache"

  eks_registry_account_id = var.eks_registry_account_id

  depends_on = [module.network]
}
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not
  # exist until this addon creates it. As a DaemonSet it reaches ACTIVE with zero
  # nodes, so it comes before any capacity (rules.md C-4) - and nodes need it to
  # join Ready. Its pods reach the EC2 API through the ec2 interface endpoint.
  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as eks_vpc_cni_addon (rules.md C-4).
  depends_on = [module.network, module.eks_cluster]
}
module "eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name   = module.eks_cluster.cluster_name
  instance_types = var.node_group_instance_types
  desired_size   = var.node_group_desired_size
  min_size       = var.node_group_min_size
  max_size       = var.node_group_max_size
  subnet_ids     = module.network.private_subnet_ids
  # The kubelet is what asks for an image, so the node role is the principal a
  # pull-through cache pull is authorised against. On a first pull the cache
  # repository does not exist yet and ECR has to create it and import the upstream
  # image, which AmazonEC2ContainerRegistryReadOnly does not allow - and the refusal
  # arrives as "not found", indistinguishable from a wrong image path. Keyed by a
  # label because the ARN is another module's output, unknown at plan (rules.md B-8).
  additional_iam_policies = {
    ecr_pull_through_cache = module.ecr_pull_through_cache.pull_policy_arn
  }

  # The endpoints and the cache matter more here than anywhere else in this
  # repository. A node with no route to ECR never pulls the CNI image, never reports
  # Ready, and the node group create call eventually fails on a timeout with nothing
  # explaining why - so both are named rather than left to chance (rules.md D-2).
  depends_on = [
    module.network,
    module.vpc_endpoints,
    module.ecr_pull_through_cache,
    module.eks_vpc_cni_addon,
    module.eks_kube_proxy_addon,
  ]
}
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.eks_cluster.cluster_name

  # coredns is a Deployment and needs schedulable capacity to leave DEGRADED and
  # become ACTIVE (rules.md C-4).
  depends_on = [
  module.network, module.eks_node_group]
}
# The role only. The chart is installed by an SSM step further down, because a helm
# provider on the machine running terraform apply cannot reach this cluster's
# private API server - see providers.tf for what that trade costs.
module "aws_load_balancer_controller_iam_role" {
  source = "./modules/aws_load_balancer_controller_iam_role"

  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host

  depends_on = [
  module.network, module.eks_cluster]
}
# Standalone rule resources rather than inline blocks, and revoke_rules_on_delete,
# because the controller adds its own rules to this group (rules.md F-2).
module "alb_security_group" {
  source = "./modules/load_balancer_security_group"

  vpc_id                      = module.network.vpc_id
  name                        = var.alb_security_group_name
  description                 = "Frontend security group for the ALB the controller adopts from the demo Ingress"
  port                        = var.alb_port
  allow_inbound_from_anywhere = var.allow_load_balancer_inbound_from_anywhere

  depends_on = [module.network]
}
# The path from the load balancer to the pods, which nothing else creates now. With
# its backend security group turned off the controller does not write a reduced set of
# pod-side rules - it leaves the networking spec out of the TargetGroupBinding
# altogether, so not one rule is created and every target reports unhealthy while the
# load balancer itself looks fine (rules.md G-2).
#
# It modifies the cluster security group, which no module here owns outright, so it
# belongs in the root (rules.md C-1). Pods share their node's ENIs under the default
# CNI, and those carry the cluster security group, so that is where traffic addressed
# to a pod IP arrives.
resource "aws_vpc_security_group_ingress_rule" "load_balancer_to_pods" {
  # Exactly one owner. When the annotation is on, the controller writes these rules
  # and this must not (rules.md F-2).
  count = var.manage_backend_security_group_rules ? 0 : 1

  security_group_id = module.eks_cluster.cluster_security_group_id
  description       = "Container port from the ALB frontend security group"
  ip_protocol       = "tcp"
  # target-type ip sends traffic to the container port on the pod, and the ALB health
  # check uses traffic-port, so this one rule covers both.
  from_port                    = var.workload_container_port
  to_port                      = var.workload_container_port
  referenced_security_group_id = module.alb_security_group.security_group_id
}
locals {
  # The stack tag the ALB must carry to be adopted rather than duplicated. ingress.
  # k8s.aws/* because it fronts an Ingress, not a Service of type LoadBalancer - the
  # wrong prefix is not an error, the controller just builds its own (rules.md G-3).
  #
  # Defined here because the workload is a manifest applied by SSM rather than a
  # module with outputs, so the root is the only place that knows both the namespace
  # and the Ingress name (rules.md B-5).
  ingress_stack_tag = "${var.workload_namespace}/${var.workload_name}"
}
# Created here and adopted by the controller, which is what makes the ALB's DNS name
# available as an output at apply time. Otherwise it would only be discoverable by
# querying the cluster afterwards, and on a private cluster that means going through
# the bastion (rules.md G-3).
module "synced_load_balancer" {
  source = "./modules/synced_load_balancer"

  cluster_name       = module.eks_cluster.cluster_name
  load_balancer_type = "application"
  internal           = false
  # internet-facing, so public subnets. The cluster is private; the load balancer in
  # front of it is not, and it has to agree with the Ingress's scheme annotation or
  # the controller builds a second one (rules.md G-3).
  subnet_ids          = module.network.public_subnet_ids
  security_group_ids  = [module.alb_security_group.security_group_id]
  resource_tag_prefix = "ingress"
  stack               = local.ingress_stack_tag

  depends_on = [module.network]
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  vpc_id = module.network.vpc_id
  # A public subnet with a public address, unlike the cluster. This instance is the
  # only way in: it needs internet egress to download kubectl, helm and the chart,
  # and it needs to be inside the VPC to reach the private API server. Both halves
  # are why the Kubernetes objects are applied from here.
  subnet_id     = module.network.public_subnet_a_id
  key_name      = module.key_pair.key_name
  instance_type = var.vscode_instance_type
  # Opens this port to 0.0.0.0/0 in the instance's own security group. Separate from
  # the ALB's switch on purpose - see allow_vscode_inbound_from_anywhere for what
  # being reachable actually exposes here.
  code_server_port            = var.vscode_code_server_port
  allow_inbound_from_anywhere = var.allow_vscode_inbound_from_anywhere
  marker_file_path            = var.marker_file_path
  # Joining the cluster security group is what lets this instance reach the private
  # API server at all. The module is handed an ID list and never learns it belongs to
  # an EKS cluster (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]

  # All five tools, because an EKS cluster and this instance share a root module
  # (rules.md H-1). Here they are not only for debugging: kubectl and helm are how
  # the cluster's Kubernetes objects get created, so this is the one project in the
  # repository where rules.md E-1 does not hold - see providers.tf.
  additional_user_data = <<-EOT
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server is already running and predates the docker group, so its terminals
    # would not have it without a restart.
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
    # exist before complete names it, or every login prints "function not found"
    # (rules.md H-1).
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
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    aws configure set default.region ${data.aws_region.current.region}
    # The _monolithic user data ran "exec bash" before this line, which replaced the
    # shell and meant nothing after it ever ran - including the kubeconfig write and
    # the whole controller install. Dropped.
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}
    EOF
  EOT

  depends_on = [module.network]
}
# Without this the instance has kubectl but every command fails with "You must be
# logged in to the server", so the SSM steps below would all fail. Joining two
# modules that know nothing about each other belongs in the root (rules.md C-1).
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
  # The demo workload, built with yamlencode so the manifest is HCL rather than a
  # YAML string pasted into a shell script - the field names stay camelCase exactly
  # as the Kubernetes API spells them (rules.md E-3). It reaches the cluster through
  # kubectl on the bastion rather than through a provider, but it is still defined
  # once, here, from typed values.
  workload_manifests = [
    {
      apiVersion = "apps/v1"
      kind       = "Deployment"
      metadata = {
        name      = var.workload_name
        namespace = var.workload_namespace
      }
      spec = {
        replicas = var.workload_replicas
        selector = {
          matchLabels = { "app.kubernetes.io/name" = var.workload_name }
        }
        template = {
          metadata = {
            labels = { "app.kubernetes.io/name" = var.workload_name }
          }
          spec = {
            containers = [{
              name = var.workload_name
              # Through the cache, not from public.ecr.aws. The nodes have no route
              # to the internet, so a public reference here is an ImagePullBackOff.
              image           = "${module.ecr_pull_through_cache.public_image_prefix}/${var.workload_image_repository}"
              imagePullPolicy = "Always"
              ports           = [{ containerPort = var.workload_container_port }]
            }]
          }
        }
      }
    },
    {
      apiVersion = "v1"
      kind       = "Service"
      metadata = {
        name      = var.workload_name
        namespace = var.workload_namespace
      }
      spec = {
        selector = { "app.kubernetes.io/name" = var.workload_name }
        ports = [{
          port       = var.workload_container_port
          targetPort = var.workload_container_port
          protocol   = "TCP"
        }]
      }
    },
    {
      apiVersion = "networking.k8s.io/v1"
      kind       = "Ingress"
      metadata = {
        name      = var.workload_name
        namespace = var.workload_namespace
        annotations = merge(
          {
            "alb.ingress.kubernetes.io/scheme"          = "internet-facing"
            "alb.ingress.kubernetes.io/target-type"     = "ip"
            "alb.ingress.kubernetes.io/security-groups" = module.alb_security_group.security_group_id
          },
          # Turning this on makes the controller write the node-side rules itself,
          # which is why enable_backend_security_group has to be true - the
          # controller refuses the combination otherwise, and refuses it silently
          # (rules.md G-2).
          var.manage_backend_security_group_rules ? {
            "alb.ingress.kubernetes.io/manage-backend-security-group-rules" = "true"
          } : {},
        )
      }
      spec = {
        # Without this the Ingress is created and no controller ever looks at it
        # (rules.md G-1).
        ingressClassName = "alb"
        rules = [{
          http = {
            paths = [{
              path     = "/"
              pathType = "Prefix"
              backend = {
                service = {
                  name = var.workload_name
                  port = { number = var.workload_container_port }
                }
              }
            }]
          }
        }]
      }
    },
  ]
  # One document per manifest, joined the way kubectl reads a multi-document file.
  workload_yaml = join("\n---\n", [for m in local.workload_manifests : yamlencode(m)])
}
# Step 1 of the cluster bootstrap: the load balancer controller. An SSM Association
# rather than a helm_release, because this cluster's API server is private - see
# providers.tf.
#
# The until loop, not depends_on, is what orders this after the instance bootstrap:
# wait_for_success_timeout_seconds does not reliably wait for the remote command to
# finish, so each step waits for the previous step's marker file and leaves its own
# (rules.md D-5).
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
      until [ -f ${module.vscode_ec2.marker_file_path}/userdata ]; do sleep 10; done
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
        --set clusterName=${module.eks_cluster.cluster_name} \
        --set region=${data.aws_region.current.region} \
        --set vpcId=${module.network.vpc_id} \
        --set serviceAccount.create=true \
        --set serviceAccount.name=${module.aws_load_balancer_controller_iam_role.service_account_name} \
        --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=${module.aws_load_balancer_controller_iam_role.controller_role_arn} \
        --set enableBackendSecurityGroup=${var.enable_backend_security_group} \
        --set image.repository=${module.ecr_pull_through_cache.public_image_prefix}/eks/aws-load-balancer-controller \
        --wait --timeout ${var.controller_helm_timeout_seconds}s \
        || { kubectl -n ${module.aws_load_balancer_controller_iam_role.namespace} get pods -l app.kubernetes.io/name=aws-load-balancer-controller -o wide; exit 1; }
      STEP
      touch ${module.vscode_ec2.marker_file_path}/load_balancer_controller
      EOT
  }

  # The controller's pods pull their image through the cache and reach the EKS and
  # elasticloadbalancing APIs through the endpoints, so all three have to be in
  # place - and there has to be a node to schedule them on.
  depends_on = [
    module.eks_node_group,
    module.eks_coredns_addon,
    module.vpc_endpoints,
    module.ecr_pull_through_cache,
    aws_eks_access_policy_association.vscode_access_policy_association,
  ]
}
# Step 2: repoint coredns at the pull-through cache, which is what the _monolithic
# template did to show the cache working. Its own step rather than part of step 1
# because it is optional and unrelated to the controller.
#
# Worth knowing: the coredns EKS addon reconciles its own Deployment, so this
# override is not durable - the addon can put its image back. It demonstrates the
# cache rather than configuring the cluster. E-5 would normally move a change like
# this into the addon's configuration_values, but the addon schema has no image
# override, so there is nowhere declarative to put it.
resource "aws_ssm_association" "coredns_image" {
  count = var.override_coredns_image ? 1 : 0

  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.controller_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    commands = <<-EOT
      set -euo pipefail
      until [ -f ${module.vscode_ec2.marker_file_path}/load_balancer_controller ]; do sleep 10; done
      sudo -Eu ec2-user bash << 'STEP'
      set -euo pipefail
      export HOME=/home/ec2-user
      export PATH=/home/ec2-user/bin:$PATH
      kubectl -n kube-system set image deployment/coredns \
        coredns=${module.ecr_pull_through_cache.eks_image_prefix}/eks/coredns:${var.coredns_image_tag}
      kubectl -n kube-system rollout status deployment coredns --timeout=5m
      STEP
      touch ${module.vscode_ec2.marker_file_path}/coredns_image
      EOT
  }

  depends_on = [aws_ssm_association.load_balancer_controller]
}
# Step 3: the demo workload. The Ingress is what makes the controller adopt the
# pre-created ALB, so this has to run after the controller is serving - otherwise
# nothing reconciles the Ingress and the load balancer is never wired up
# (rules.md G-1/G-3).
resource "aws_ssm_association" "workload" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.workload_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # Waits on whichever step actually ran before it: the coredns override is
    # optional, so the marker to wait for depends on that (rules.md D-5).
    #
    # The heredoc delimiter is quoted and deliberately unlikely to appear in the
    # body. Terraform has already substituted every value, so the shell has no
    # reason to touch a "$" or a backtick inside the manifest.
    commands = <<-EOT
      set -euo pipefail
      until [ -f ${module.vscode_ec2.marker_file_path}/${var.override_coredns_image ? "coredns_image" : "load_balancer_controller"} ]; do sleep 10; done
      sudo -Eu ec2-user bash << 'STEP'
      set -euo pipefail
      export HOME=/home/ec2-user
      export PATH=/home/ec2-user/bin:$PATH
      mkdir -p /home/ec2-user/manifests
      cat > /home/ec2-user/manifests/workload.yaml << 'TFMANIFEST'
      ${local.workload_yaml}
      TFMANIFEST
      kubectl apply -f /home/ec2-user/manifests/workload.yaml
      kubectl -n ${var.workload_namespace} rollout status deployment ${var.workload_name} --timeout=10m
      STEP
      touch ${module.vscode_ec2.marker_file_path}/workload
      EOT
  }

  # The ALB has to exist before the controller reconciles the Ingress, or the
  # controller builds its own and the pre-created one is orphaned (rules.md G-3).
  depends_on = [
    aws_ssm_association.load_balancer_controller,
    module.synced_load_balancer,
  ]
}
locals {
  # Every output this project exposes, defined once. outputs.tf projects these and
  # the README below renders them, so no value expression is written twice
  # (rules.md B-5/H-2). Adding an entry here is what makes an output possible,
  # which is what keeps the README from falling behind outputs.tf.
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here. On this project it is not just a convenience: the cluster's API server is private, so this instance is the only place kubectl works at all"
      value       = module.vscode_ec2.vscode_url
    }
    cluster_name = {
      order       = 2
      title       = "EKS cluster name"
      description = "Name of the EKS cluster. The AWS Load Balancer Controller also writes this into the elbv2.k8s.aws/cluster tag it uses to find load balancers it owns"
      value       = module.eks_cluster.cluster_name
    }
    cluster_endpoint = {
      order       = 3
      title       = "EKS cluster endpoint (private)"
      description = "Resolves only inside the VPC. There is no public endpoint, which is the point of this project - every Kubernetes object here was created by an SSM Association running on this instance rather than by a Terraform provider"
      value       = module.eks_cluster.cluster_endpoint
    }
    ingress_url = {
      order       = 4
      title       = "Demo workload URL"
      description = "The pre-created ALB the controller adopted from the demo Ingress. Known from state because Terraform created the load balancer rather than leaving it to the controller - on a private cluster the alternative would be querying the cluster through this bastion (rules.md G-3)"
      value       = module.synced_load_balancer.url
    }
    own_registry = {
      order       = 5
      title       = "ECR registry every image comes from"
      description = "The nodes can reach ECR in this account and nothing else, so every image runs from here - pulled on demand from upstream by the pull-through cache rules"
      value       = module.ecr_pull_through_cache.own_registry
    }
    workload_image = {
      order       = 6
      title       = "Demo workload image"
      description = "An ECR Public image addressed through this account's cache prefix rather than as public.ecr.aws/... A public reference would be an ImagePullBackOff on this cluster"
      value       = "${module.ecr_pull_through_cache.public_image_prefix}/${var.workload_image_repository}"
    }
    endpoint_check_command = {
      order       = 7
      title       = "1. Confirm the VPC endpoints are available"
      description = "With no NAT gateway these are the cluster's only path to AWS. An endpoint in any state other than available means that API is unreachable, which shows up as nodes not joining or images not pulling rather than as a clear error"
      value       = module.vpc_endpoints.endpoint_check_command
    }
    cache_rules_check_command = {
      order       = 8
      title       = "2. Confirm the pull-through cache rules"
      description = "A missing or misprefixed rule is the usual cause of ImagePullBackOff here, because there is no fallback path to a public registry"
      value       = module.ecr_pull_through_cache.cache_rules_check_command
    }
    cache_repositories_check_command = {
      order       = 9
      title       = "3. Confirm the cache actually materialised a repository"
      description = "A cache rule pre-creates nothing: the repository is created by the first pull, and that pull needs ecr:CreateRepository and ecr:BatchImportUpstreamImage on the principal asking for it - the node role here. An empty list while pods sit in ImagePullBackOff means those permissions are missing, which ECR reports as \"not found\" and so reads like a wrong image path"
      value       = module.ecr_pull_through_cache.cache_repositories_check_command
    }
    workload_check_command = {
      order       = 10
      title       = "3. Check the demo workload"
      description = "Terraform's SSM step already applied this and waited for the rollout, so the pods should be Running. A pod stuck in ImagePullBackOff points back at step 2"
      value       = "kubectl -n ${var.workload_namespace} get pods,svc,ingress"
    }
    controller_log_command = {
      order       = 11
      title       = "4. Read the load balancer controller log"
      description = "Where to look if the Ingress never gets an address. The backend security group message described in rules.md G-2 appears only here - the apply succeeds either way"
      value       = "kubectl -n ${module.aws_load_balancer_controller_iam_role.namespace} logs deploy/aws-load-balancer-controller --tail 100"
    }
    adopted_load_balancer_check_command = {
      order       = 12
      title       = "5. Confirm the ALB was adopted, not duplicated"
      description = "Lists every load balancer tagged for this cluster. One is correct. Two means the controller did not adopt the pre-created one and built its own, which is a tag mismatch rather than an error (rules.md G-3)"
      value       = "aws resourcegroupstaggingapi get-resources --tag-filters Key=elbv2.k8s.aws/cluster,Values=${module.eks_cluster.cluster_name} --resource-type-filters elasticloadbalancing:loadbalancer --query 'ResourceTagMappingList[].ResourceARN' --output table"
    }
    update_kubeconfig_command = {
      order       = 13
      title       = "Re-point kubectl"
      description = "User data already ran this, so kubectl works out of the box on this instance. It will not work anywhere outside the VPC"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the
  # order field and taking values() - which returns a map's values ordered by key -
  # makes the README read top to bottom while the order stays decided by
  # configuration.
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
# Step 4, and the last of the chain: the README. Every output above is written into
# the home directory code-server opens, because that browser session has no
# terraform output available (rules.md H-2).
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # Waits for the workload step's marker, so the README lands only once the demo
    # it describes is actually up (rules.md D-5).
    #
    # SSM runs as root, hence the chown - without it the file is not editable from
    # the IDE.
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/workload ]; do sleep 10; done
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_readme
      EOT
  }

  depends_on = [aws_ssm_association.workload]
}
