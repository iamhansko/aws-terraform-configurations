data "aws_region" "current" {}
locals {
  key_name = var.key_name == null ? "${var.cluster_name}-key" : var.key_name
  # The two CRD bundles this project installs, and the one place either URL is written.
  #
  # The AWS-vended bundle is pinned to the controller release rather than fetched from the main branch, which
  # is what the _monolithic template did. A branch URL means the CRDs that arrive depend on the day, and the
  # failure mode of a CRD newer than the controller reading it is a field that is accepted and ignored.
  gateway_api_crd_url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/${var.gateway_api_version}/standard-install.yaml"
  controller_crd_url  = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v${var.aws_load_balancer_controller_version}/config/crd/gateway/gateway-crds.yaml"
}
# Public and private subnets, a regional NAT gateway, and the subnet role tags the load balancer controller
# discovers load balancer placement by (rules.md G-1).
module "network" {
  source = "./modules/network"

  region                         = data.aws_region.current.region
  vpc_cidr_block                 = var.vpc_cidr_block
  availability_zone_suffixes     = var.availability_zone_suffixes
  nat_availability_zone_suffixes = var.availability_zone_suffixes
  public_subnet_tags             = var.public_subnet_tags
  private_subnet_tags            = var.private_subnet_tags
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name = local.key_name

  # key_pair consumes no network output, so nothing would otherwise order it against the network module's
  # resources. Every module in a root with a network module waits for all of it (rules.md D-3).
  depends_on = [module.network]
}
module "eks_cluster" {
  source = "./modules/eks_cluster"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version
  # Private subnets only, as the _monolithic template had it. The control plane's cross-account interfaces
  # belong where the nodes are, and with no public endpoint there is nothing for the public subnets to do here.
  subnet_ids = module.network.private_subnet_ids
  # False, pinned by its validation. It is the reason there are no kubectl or helm providers in this root -
  # see providers.tf (rules.md E-9).
  endpoint_public_access = var.endpoint_public_access
  service_ipv4_cidr      = var.service_ipv4_cidr

  # Referencing module.network.private_subnet_ids only orders this after the specific aws_subnet resources
  # behind that output, not after the route tables or the NAT gateway (rules.md D-3).
  depends_on = [module.network]
}
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not exist until this addon creates
  # it. As a DaemonSet it reaches ACTIVE with zero nodes, so it comes before any capacity - and nodes need it
  # to join Ready (rules.md C-4).
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

  cluster_name    = module.eks_cluster.cluster_name
  node_group_name = "${var.cluster_name}-core"
  instance_types  = var.node_group_instance_types
  desired_size    = var.node_group_desired_size
  min_size        = var.node_group_min_size
  max_size        = var.node_group_max_size
  subnet_ids      = module.network.private_subnet_ids
  key_name        = module.key_pair.key_name
  # No extra security groups on the nodes, deliberately. With target type ip the controller picks the security
  # group on the backend pod's ENI to write its rules onto, and when an ENI carries more than one group it
  # requires exactly one of them to be tagged kubernetes.io/cluster/<name>. Leaving the nodes with only the
  # cluster security group keeps that unambiguous (rules.md G-2).
  #
  # Those rules land on a group EKS creates and Terraform does not own, so rules.md F-2's
  # revoke_rules_on_delete has nowhere to be set here. That is the destroy hazard the teardown output
  # describes: delete the Gateway while the controller is alive and it withdraws its own rules and load
  # balancer; tear the cluster down first and it cannot.

  # Nodes need vpc-cni and kube-proxy running to join the cluster Ready (rules.md C-4).
  depends_on = [module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.eks_cluster.cluster_name

  # coredns is a Deployment and needs schedulable capacity to leave DEGRADED and become ACTIVE. The
  # _monolithic template declared all three addons with no ordering at all, on a cluster that had
  # BootstrapSelfManagedAddons: false - so coredns raced the node group (rules.md C-4).
  depends_on = [module.network, module.eks_node_group]
}
# The controller's IRSA role, and only the role. The chart is installed by an SSM step further down, because a
# helm provider on the machine running terraform apply cannot reach this cluster's private API server - see
# providers.tf for what that trade costs.
#
# The _monolithic template had no equivalent of this module at all: it installed the chart with nothing but
# --set serviceAccount.name, so the controller had no credentials of its own (rules.md A-5).
module "aws_load_balancer_controller_iam_role" {
  source = "./modules/aws_load_balancer_controller_iam_role"

  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  role_name_prefix  = "${var.cluster_name}-alb-controller-"

  depends_on = [module.network, module.eks_cluster]
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name   = "vscode"
  vpc_id = module.network.vpc_id
  # A public subnet with a public address, unlike the cluster. This instance is the only way in: it needs
  # internet egress to download kubectl, helm, the CRD bundles and the chart, and it needs to be inside the
  # VPC to reach the private API server. Both halves are why the Kubernetes objects are applied from here.
  subnet_id                   = module.network.public_subnet_ids_by_zone[var.availability_zone_suffixes[0]]
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  security_group_name         = "${var.cluster_name}-vscode-sg"
  security_group_description  = "Security group for the VS Code EC2 instance fronting the ${var.cluster_name} cluster"
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  ingress_cidr_blocks         = var.vscode_ingress_cidr_blocks
  marker_file_path            = var.marker_file_path
  # Joining the cluster security group is what lets this instance reach the private API server at all: that
  # group admits traffic from itself, and the control plane's interfaces carry it. The module is handed an ID
  # list and never learns it belongs to an EKS cluster (rules.md B-6).
  #
  # The _monolithic template did not do this. Its instance carried only its own security group, so the
  # update-kubeconfig and every kubectl call in its user data would have hung against an endpoint nothing
  # allowed it to reach - on a cluster whose endpoint was private by that same template's choice.
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]

  # All five tools, because an EKS cluster and this instance share a root module (rules.md H-1). Here they are
  # not only for debugging: kubectl and helm are how the cluster's Kubernetes objects get created, so this is
  # one of two projects in the repository where rules.md E-1 does not hold - see providers.tf.
  additional_user_data = <<-EOT
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server is already running and predates the docker group, so its terminals would not have it
    # without a restart.
    systemctl restart code-server

    sudo -Eu ec2-user bash << 'EOF'
    set -euo pipefail
    # HOME is set explicitly because user data runs as root and sudo -E preserves the environment, so "~"
    # can still resolve to /root - and writing there as ec2-user fails with Permission denied (rules.md H-1).
    export HOME=/home/ec2-user
    cd /home/ec2-user
    mkdir -p /home/ec2-user/bin
    curl -sO https://s3.us-west-2.amazonaws.com/amazon-eks/${var.kubectl_download_version}/bin/linux/amd64/kubectl
    chmod +x kubectl
    mv kubectl /home/ec2-user/bin/kubectl
    export PATH=/home/ec2-user/bin:$PATH
    echo 'export PATH=/home/ec2-user/bin:$PATH' >> ~/.bashrc
    # Order matters: kubectl's completion defines __start_kubectl, and that has to exist before complete
    # names it, or every login prints "function not found". The _monolithic template had these two lines the
    # other way round (rules.md H-1).
    echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
    echo 'source <(kubectl completion bash)' >> ~/.bashrc
    echo 'alias k=kubectl' >> ~/.bashrc
    echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
    # eksctl-io is the project's own org; the weaveworks URL the _monolithic template used still redirects,
    # but the current name is what gets used (rules.md H-1).
    PLATFORM=$(uname -s)_amd64
    curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
    tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
    sudo install -m 0755 /tmp/eksctl /usr/local/bin && rm /tmp/eksctl
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm get_helm.sh
    aws configure set default.region ${data.aws_region.current.region}
    # The _monolithic template ran "exec bash" before this line, which replaced the shell and meant nothing
    # after it ever ran - the kubeconfig write, the CRD installs and the whole controller install included.
    # So on a real boot that template produced an instance with kubectl on it and an empty cluster.
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}
    EOF
  EOT

  depends_on = [module.network]
}
# Without this the instance has kubectl but every command fails with "You must be logged in to the server", so
# all three SSM steps below would fail. Joining two modules that know nothing about each other belongs in the
# root (rules.md C-1).
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

  # The _monolithic template expressed both of these as one AWS::EKS::AccessEntry with an inline
  # AccessPolicies list, which CloudFormation ordered for it. Split into two resources, nothing orders the
  # association after the entry it attaches to unless it is said (rules.md D-1).
  depends_on = [aws_eks_access_entry.vscode]
}
# Step 1: the Gateway API CRDs.
#
# These come first, and that ordering is the one piece of this project that is easy to get wrong. The
# controller decides at startup which of its controllers to run by looking for the Gateway CRDs - the ALB
# Gateway controller needs Gateway, GatewayClass, HTTPRoute and GRPCRoute plus the AWS-vended
# TargetGroupConfiguration, LoadBalancerConfiguration and ListenerRuleConfiguration. A controller that starts
# before them simply never reconciles a Gateway, and reports nothing about why.
#
# The until loop, not depends_on, is what orders this after the instance bootstrap:
# wait_for_success_timeout_seconds does not reliably wait for the remote command to finish, so each step waits
# for the previous step's marker file and leaves its own (rules.md D-5).
resource "aws_ssm_association" "gateway_api_crds" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.crd_timeout_seconds
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
      # --server-side is not optional on the standard bundle: the CRDs are large enough that a client-side
      # apply exceeds the 262144-byte last-applied-configuration annotation and is refused outright.
      kubectl apply --server-side=true -f ${local.gateway_api_crd_url}
      # The AWS-vended CRDs, from the same controller release the chart below installs.
      kubectl apply --server-side=true -f ${local.controller_crd_url}
      # Established, not just created: the controller looks these up at startup, and a CRD whose
      # NamesAccepted/Established conditions have not settled is not yet discoverable.
      for crd in gateways.gateway.networking.k8s.io gatewayclasses.gateway.networking.k8s.io \
                 httproutes.gateway.networking.k8s.io \
                 loadbalancerconfigurations.gateway.k8s.aws targetgroupconfigurations.gateway.k8s.aws; do
        # --for=create before the condition wait. The applies above are server-side and
        # synchronous, so these CRDs do exist by now - but a wait for a condition on a
        # name that does not exist returns NotFound in under a second and ignores
        # --timeout entirely, so the cheap insurance is worth having. 123_kubernetes_on_ec2
        # lost a step to exactly that, waiting on CRDs an operator registers asynchronously.
        kubectl wait --for=create "crd/$crd" --timeout=120s
        kubectl wait --for=condition=Established "crd/$crd" --timeout=120s
      done
      STEP
      touch ${module.vscode_ec2.marker_file_path}/gateway_api_crds
      EOT
  }

  # The CRDs only need an API server to accept them, but the steps after this one need somewhere to run, and
  # the access entry is what lets kubectl authenticate at all.
  depends_on = [
    module.eks_node_group,
    module.eks_coredns_addon,
    aws_eks_access_policy_association.vscode,
  ]
}
# Step 2: the AWS Load Balancer Controller. An SSM Association rather than a helm_release, because this
# cluster's API server is private - see providers.tf.
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
      until [ -f ${module.vscode_ec2.marker_file_path}/gateway_api_crds ]; do sleep 10; done
      sudo -Eu ec2-user bash << 'STEP'
      set -euo pipefail
      export HOME=/home/ec2-user
      export PATH=/home/ec2-user/bin:$PATH
      helm repo add eks https://aws.github.io/eks-charts
      helm repo update eks
      # An association re-runs whenever its parameters change, so this step has to be re-runnable - and a
      # release whose only revision failed is the one state "upgrade --install" cannot recover from: helm
      # refuses it with "has no deployed releases", which hides whatever the original failure was. Clear
      # exactly that state, never a release that has a deployed revision (rules.md E-7).
      if helm status ${var.aws_load_balancer_controller_release_name} -n ${module.aws_load_balancer_controller_iam_role.namespace} >/dev/null 2>&1; then
        # grep -c over one field per line rather than "grep -q" on the raw JSON: under pipefail, grep -q
        # closing the pipe early can fail the whole pipeline even on a match.
        deployed=$(helm history ${var.aws_load_balancer_controller_release_name} -n ${module.aws_load_balancer_controller_iam_role.namespace} -o json | tr ',' '\n' | grep -c '"status":"deployed"' || true)
        if [ "$deployed" -eq 0 ]; then
          echo "clearing failed release with no deployed revision"
          helm uninstall ${var.aws_load_balancer_controller_release_name} -n ${module.aws_load_balancer_controller_iam_role.namespace} --wait
        fi
      fi
      # enableBackendSecurityGroup and enableServiceMutatorWebhook are passed without --set-string on
      # purpose. The chart guards the first with {{ if kindIs "bool" ... }} and the second with a plain
      # truthiness test, so a quoted "false" would drop the flag entirely in one case and leave the webhook
      # installed in the other - both silently the opposite of what was asked (rules.md E-7/G-2/G-4).
      helm upgrade --install ${var.aws_load_balancer_controller_release_name} eks/aws-load-balancer-controller \
        --version ${var.aws_load_balancer_controller_version} \
        --namespace ${module.aws_load_balancer_controller_iam_role.namespace} \
        --set clusterName=${module.eks_cluster.cluster_name} \
        --set region=${data.aws_region.current.region} \
        --set vpcId=${module.network.vpc_id} \
        --set replicaCount=${var.aws_load_balancer_controller_replica_count} \
        --set serviceAccount.create=true \
        --set serviceAccount.name=${module.aws_load_balancer_controller_iam_role.service_account_name} \
        --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=${module.aws_load_balancer_controller_iam_role.controller_role_arn} \
        --set enableBackendSecurityGroup=${var.enable_backend_security_group} \
        --set enableServiceMutatorWebhook=${var.enable_service_mutator_webhook} \
        --wait --timeout ${var.controller_helm_timeout_seconds}s \
        || { kubectl -n ${module.aws_load_balancer_controller_iam_role.namespace} get pods -l app.kubernetes.io/name=aws-load-balancer-controller -o wide; exit 1; }
      # Which Gateway controllers actually came up. This is the check worth having: the flags are detected
      # rather than configured, so the only confirmation that the ALB Gateway controller is running is in its
      # own startup log.
      kubectl -n ${module.aws_load_balancer_controller_iam_role.namespace} logs deploy/${var.aws_load_balancer_controller_release_name} --tail 200 | grep -i gateway || true
      STEP
      touch ${module.vscode_ec2.marker_file_path}/load_balancer_controller
      EOT
  }

  # The controller's pods need a node to run on, DNS to resolve the EKS and elasticloadbalancing endpoints,
  # and its role to already carry the policy - a controller that starts before the policy attaches reports
  # AccessDenied against every AWS call it makes (rules.md D-1/D-2).
  depends_on = [
    aws_ssm_association.gateway_api_crds,
    module.aws_load_balancer_controller_iam_role,
    module.eks_coredns_addon,
  ]
}
locals {
  workload_labels = { "app.kubernetes.io/name" = var.workload_name }
  # The demo, built with yamlencode so the manifests are HCL rather than YAML pasted into a shell script - the
  # field names stay camelCase exactly as the Kubernetes API spells them (rules.md E-3). They reach the cluster
  # through kubectl on the workbench rather than through a provider, but they are still defined once, here,
  # from typed values.
  #
  # Seven objects, and each one is load-bearing:
  #
  #   GatewayClass               - controllerName gateway.k8s.aws/alb is what hands Gateways of this class to
  #                                the ALB half of the controller. A different string, or none, and nothing
  #                                reconciles them.
  #   LoadBalancerConfiguration  - the ALB's scheme. The controller's default for a Gateway is internal, so
  #                                without this the load balancer comes up with no public address.
  #   TargetGroupConfiguration   - target type ip, attached to the Service. The default is instance, which
  #                                registers nodes on a NodePort the ClusterIP Service does not have.
  #   Gateway                    - one ALB. infrastructure.parametersRef is how the configuration above
  #                                attaches; it is namespace-local, which is why everything here shares one
  #                                namespace.
  #   Deployment + Service       - the backend. Nothing about either mentions a Gateway; the controller finds
  #                                them through the route's backendRef.
  #   HTTPRoute                  - the listener rules and the target group. sectionName names the listener on
  #                                the Gateway rather than relying on a default.
  demo_manifests = [
    {
      apiVersion = "gateway.networking.k8s.io/v1"
      kind       = "GatewayClass"
      metadata = {
        name = var.gateway_class_name
      }
      spec = {
        controllerName = "gateway.k8s.aws/alb"
      }
    },
    {
      apiVersion = "gateway.k8s.aws/v1"
      kind       = "LoadBalancerConfiguration"
      metadata = {
        name      = var.gateway_name
        namespace = var.workload_namespace
      }
      spec = {
        scheme = var.gateway_scheme
      }
    },
    {
      apiVersion = "gateway.k8s.aws/v1"
      kind       = "TargetGroupConfiguration"
      metadata = {
        name      = var.workload_name
        namespace = var.workload_namespace
      }
      spec = {
        targetReference = {
          kind = "Service"
          name = var.workload_name
        }
        defaultConfiguration = {
          targetType = var.gateway_target_type
        }
      }
    },
    {
      apiVersion = "gateway.networking.k8s.io/v1"
      kind       = "Gateway"
      metadata = {
        name      = var.gateway_name
        namespace = var.workload_namespace
      }
      spec = {
        gatewayClassName = var.gateway_class_name
        infrastructure = {
          parametersRef = {
            group = "gateway.k8s.aws"
            kind  = "LoadBalancerConfiguration"
            name  = var.gateway_name
          }
        }
        listeners = [{
          name     = "http"
          protocol = "HTTP"
          port     = var.gateway_listener_port
          allowedRoutes = {
            namespaces = { from = "Same" }
          }
        }]
      }
    },
    {
      apiVersion = "apps/v1"
      kind       = "Deployment"
      metadata = {
        name      = var.workload_name
        namespace = var.workload_namespace
        labels    = local.workload_labels
      }
      spec = {
        replicas = var.workload_replicas
        selector = { matchLabels = local.workload_labels }
        template = {
          metadata = { labels = local.workload_labels }
          spec = {
            containers = [{
              name            = var.workload_name
              image           = var.workload_image
              imagePullPolicy = "Always"
              ports = [{
                name          = "http"
                containerPort = var.workload_container_port
              }]
              env = [{
                # What the sample server puts in its response body, so a response shows which pod answered.
                name  = "PodName"
                value = "${var.workload_name} pod"
              }]
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
        # ClusterIP. It matters that it is not LoadBalancer: the Gateway is what fronts this workload, and a
        # Service of type LoadBalancer would ask the controller for a second load balancer (rules.md G-1).
        type     = var.workload_service_type
        selector = local.workload_labels
        ports = [{
          name       = "http"
          port       = var.workload_service_port
          targetPort = var.workload_container_port
          protocol   = "TCP"
        }]
      }
    },
    {
      apiVersion = "gateway.networking.k8s.io/v1"
      kind       = "HTTPRoute"
      metadata = {
        name      = var.workload_name
        namespace = var.workload_namespace
      }
      spec = {
        parentRefs = [{
          group = "gateway.networking.k8s.io"
          kind  = "Gateway"
          name  = var.gateway_name
          # Names the listener rather than attaching to all of them, which is what makes it obvious where a
          # second listener's rules would and would not appear.
          sectionName = "http"
        }]
        rules = [{
          matches = [{
            path = {
              type  = "PathPrefix"
              value = var.route_path_prefix
            }
          }]
          backendRefs = [{
            group = ""
            kind  = "Service"
            name  = var.workload_name
            port  = var.workload_service_port
          }]
        }]
      }
    },
  ]
  # One document per manifest, joined the way kubectl reads a multi-document file.
  demo_yaml = join("\n---\n", [for m in local.demo_manifests : yamlencode(m)])
}
# Step 3: the demo. The Gateway is what makes the controller provision an ALB, so this has to run after the
# controller is serving - otherwise nothing reconciles it and the Gateway sits with no address (rules.md G-1).
resource "aws_ssm_association" "gateway_api_demo" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.demo_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The heredoc delimiter is quoted and deliberately unlikely to appear in the body. Terraform has already
    # substituted every value, so the shell has no reason to touch a "$" or a backtick inside the manifests.
    #
    # The nested heredoc works because <<-EOT strips indentation based on the template source lines only: the
    # second and later lines of an interpolated multi-line value sit at column 0, so TFMANIFEST lands at
    # column 0 too. This is also why rules.md A-4 matters twice over here - a CRLF-saved .tf makes the
    # terminator "TFMANIFEST\r", the heredoc runs to the end of the file, and not one line of the script runs.
    commands = <<-EOT
      set -euo pipefail
      until [ -f ${module.vscode_ec2.marker_file_path}/load_balancer_controller ]; do sleep 10; done
      sudo -Eu ec2-user bash << 'STEP'
      set -euo pipefail
      export HOME=/home/ec2-user
      export PATH=/home/ec2-user/bin:$PATH
      mkdir -p /home/ec2-user/manifests
      cat > /home/ec2-user/manifests/gateway-api-demo.yaml << 'TFMANIFEST'
      ${local.demo_yaml}
      TFMANIFEST
      kubectl apply -f /home/ec2-user/manifests/gateway-api-demo.yaml
      kubectl -n ${var.workload_namespace} rollout status deployment ${var.workload_name} --timeout=${var.workload_rollout_timeout_seconds}s
      # Programmed is the condition that means the controller created the ALB and it became active, which
      # takes minutes. Waiting for it here is what makes a failed apply point at the Gateway rather than
      # leaving a healthy-looking cluster whose address never appears.
      kubectl -n ${var.workload_namespace} wait --for=condition=Programmed gateway/${var.gateway_name} --timeout=${var.gateway_wait_timeout_seconds}s \
        || { kubectl -n ${var.workload_namespace} describe gateway ${var.gateway_name}; kubectl -n ${var.workload_namespace} describe httproute ${var.workload_name}; exit 1; }
      kubectl -n ${var.workload_namespace} get gateway ${var.gateway_name} -o jsonpath='{.status.addresses[0].value}{"\n"}'
      STEP
      touch ${module.vscode_ec2.marker_file_path}/gateway_api_demo
      EOT
  }

  depends_on = [aws_ssm_association.load_balancer_controller]
}
locals {
  # Every output this project exposes, defined once. outputs.tf projects these and the README below renders
  # them, so no value expression is written twice (rules.md B-5/H-2). Adding an entry here is what makes an
  # output possible, which is what keeps the README from falling behind outputs.tf.
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here. On this project it is not just a convenience: the cluster's API server is private, so this instance is the only place kubectl works at all"
      value       = module.vscode_ec2.vscode_url
    }
    what_this_shows = {
      order       = 2
      title       = "What this project demonstrates"
      description = "The Kubernetes Gateway API satisfied by an AWS ALB. A GatewayClass naming the controller gateway.k8s.aws/alb, a Gateway that becomes one ALB, and an HTTPRoute that becomes its listener rules and target group - with the two AWS-vended CRDs supplying the parts the Gateway API has no field for: the ALB's scheme and the target group's target type"
      value       = "GatewayClass ${var.gateway_class_name} (gateway.k8s.aws/alb)\n  -> Gateway ${var.workload_namespace}/${var.gateway_name}  = one ${var.gateway_scheme} ALB, listener ${var.gateway_listener_port}/HTTP\n    -> HTTPRoute ${var.workload_namespace}/${var.workload_name}  ${var.route_path_prefix}\n      -> Service ${var.workload_namespace}/${var.workload_name}:${var.workload_service_port}  (target type ${var.gateway_target_type})\n        -> ${var.workload_replicas} x ${var.workload_name} pods on :${var.workload_container_port}"
    }
    gateway_address_command = {
      order       = 3
      title       = "1. The Gateway's address"
      description = "Run it on the workbench. This is the ALB's DNS name, and it is not a Terraform output because the controller created the load balancer, not Terraform - on a private cluster that means reading it from here. Empty means the Gateway is not Programmed yet, or not at all"
      value       = "kubectl -n ${var.workload_namespace} get gateway ${var.gateway_name} -o jsonpath='{.status.addresses[0].value}{\"\\n\"}'"
    }
    curl_command = {
      order       = 4
      title       = "2. Does it answer"
      description = "Repeat it a few times: the sample server names the pod that handled the request, so the responses alternate once both pod addresses are registered in the target group. A hang rather than a refusal usually means the ALB's own security group, which the controller created - a 503 means the target group has no healthy target"
      value       = "curl -s \"http://$(kubectl -n ${var.workload_namespace} get gateway ${var.gateway_name} -o jsonpath='{.status.addresses[0].value}')${var.route_path_prefix}\""
    }
    gateway_status_command = {
      order       = 5
      title       = "3. Read the Gateway and the route"
      description = "Where the controller writes back what it did, and the first place to look when there is no address. 'couldn't auto-discover subnets' means the public subnets are missing the kubernetes.io/role/elb tag; a route that is not Accepted means its parentRef or sectionName does not match a listener (rules.md G-1)"
      value       = "kubectl -n ${var.workload_namespace} describe gateway ${var.gateway_name} && kubectl -n ${var.workload_namespace} describe httproute ${var.workload_name}"
    }
    controller_log_command = {
      order       = 6
      title       = "4. Read the controller log"
      description = "The only place that says whether the ALB Gateway controller is even running. The controller detects the Gateway CRDs at startup and enables its Gateway controllers if they are present, so CRDs installed after the controller leave it reconciling nothing - and saying nothing about it. That is why the CRDs are step 1 of the bootstrap"
      value       = "kubectl -n ${module.aws_load_balancer_controller_iam_role.namespace} logs deploy/${var.aws_load_balancer_controller_release_name} --tail 200"
    }
    load_balancer_check_command = {
      order       = 7
      title       = "5. What the controller built in AWS"
      description = "Every load balancer tagged for this cluster. One is correct. Zero with a Programmed Gateway is not possible; two means something else in the cluster also asked for one"
      value       = "aws resourcegroupstaggingapi get-resources --tag-filters Key=elbv2.k8s.aws/cluster,Values=${module.eks_cluster.cluster_name} --resource-type-filters elasticloadbalancing:loadbalancer --query 'ResourceTagMappingList[].ResourceARN' --output table"
    }
    target_health_command = {
      order       = 8
      title       = "6. Are the targets healthy"
      description = "Run this first when the Gateway has an address but answers 502. With target type ip the members are pod addresses and the health check port is the container port, so an unhealthy target is usually one of three things, in this order of likelihood: nothing is listening on workload_container_port inside the pod (probe it directly with the second command - a wrong port here is invisible to Terraform, to the API server and to the controller, because containerPort is only documentation); the health check path does not return 200; or the controller has not written its rule onto the security group on the pod ENIs, which is the one case that looks like a timeout rather than a failed check"
      value       = "aws elbv2 describe-target-health --target-group-arn $(aws elbv2 describe-target-groups --query \"TargetGroups[?starts_with(TargetGroupName, 'k8s-${var.workload_namespace}-${var.workload_name}')].TargetGroupArn\" --output text) --output table\nkubectl -n ${var.workload_namespace} get pods -l app.kubernetes.io/name=${var.workload_name} -o jsonpath='{range .items[*]}{.status.podIP}{\"\\n\"}{end}' | while read ip; do curl -s -m 4 -o /dev/null -w \"$ip:${var.workload_container_port} -> %%{http_code}\\n\" \"http://$ip:${var.workload_container_port}${var.route_path_prefix}\"; done"
    }
    crd_check_command = {
      order       = 9
      title       = "7. Which CRDs the controller can see"
      description = "The standard-channel bundle plus the three AWS-vended ones. The ALB Gateway controller needs Gateway, GatewayClass, HTTPRoute and GRPCRoute alongside TargetGroupConfiguration, LoadBalancerConfiguration and ListenerRuleConfiguration; a missing one disables the controller rather than failing anything"
      value       = "kubectl get crd | grep -E 'gateway.networking.k8s.io|gateway.k8s.aws'"
    }
    gateway_api_version = {
      order       = 10
      title       = "Pinned versions"
      description = "The Gateway API release and the controller release, which have to agree: the controller is built against one Gateway API version, and the AWS-vended CRDs have to come from the same release as the controller that reads them. The _monolithic template pinned the first and fetched the second from a branch, with no version on the chart at all"
      value       = "Gateway API ${var.gateway_api_version} (standard channel)\nAWS Load Balancer Controller ${var.aws_load_balancer_controller_version} (chart and AWS-vended CRDs)"
    }
    cluster_name = {
      order       = 11
      title       = "EKS cluster name"
      description = "Name of the EKS cluster. The controller also writes this into the elbv2.k8s.aws/cluster tag it uses to find load balancers it owns"
      value       = module.eks_cluster.cluster_name
    }
    cluster_endpoint = {
      order       = 12
      title       = "EKS cluster endpoint (private)"
      description = "Resolves only inside the VPC. There is no public endpoint, which is what the _monolithic template chose - and the reason every Kubernetes object here was created by an SSM Association on this instance rather than by a Terraform provider (rules.md E-9)"
      value       = module.eks_cluster.cluster_endpoint
    }
    service_ipv4_cidr = {
      order       = 13
      title       = "Service CIDR the cluster actually got"
      description = "Read back from the cluster rather than echoed from the variable. EKS substitutes a range of its own if the requested one overlaps the VPC, and this is where that shows"
      value       = module.eks_cluster.service_ipv4_cidr
    }
    update_kubeconfig_command = {
      order       = 14
      title       = "Re-point kubectl"
      description = "User data already ran this. Re-run it if the kubeconfig is ever lost - and note it only works from inside the VPC"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
    private_key_command = {
      order       = 15
      title       = "The workbench's SSH private key"
      description = "Written to SSM Parameter Store as a SecureString, which is where CloudFormation puts a generated key pair's private half"
      value       = "aws ssm get-parameter --name ${module.key_pair.private_key_parameter_name} --with-decryption --query Parameter.Value --output text"
    }
    ssm_failure_diagnosis = {
      order       = 16
      title       = "If an apply failed on an SSM association"
      description = "SSM reports only that the association did not reach Success, so the real error has to be read out of the command invocation. An ExecutionElapsedTime of 0.0x seconds means the script was never run - it failed to parse, which on a .tf file saved with CRLF line endings is what a heredoc terminator carrying a stray carriage return does (rules.md A-4/E-9)"
      value       = "aws ssm describe-association-executions --association-id <id>\naws ssm describe-association-execution-targets --association-id <id> --execution-id <exec-id>\naws ssm get-command-invocation --command-id <command-id> --instance-id ${module.vscode_ec2.instance_id}"
    }
    teardown = {
      order       = 17
      title       = "Before terraform destroy"
      description = "Delete the Gateway first, from the workbench. The ALB and its target groups were created by the controller rather than by Terraform, so they are not in state and destroy does not remove them - it removes the cluster, and with it the controller that would have cleaned them up, leaving the load balancer behind. Deleting the Gateway while the controller is still running is what releases them (rules.md E-9; G-3 is the structural fix, and it does not apply to Gateways)"
      value       = "kubectl -n ${var.workload_namespace} delete -f /home/ec2-user/manifests/gateway-api-demo.yaml\naws resourcegroupstaggingapi get-resources --tag-filters Key=elbv2.k8s.aws/cluster,Values=${module.eks_cluster.cluster_name} --resource-type-filters elasticloadbalancing:loadbalancer   # expect an empty list\nterraform destroy"
    }
  }
  # Iterating the map directly would order the sections by key, which is deterministic and unrelated to
  # reading order. Re-keying by the order field and taking values() - which returns a map's values in key
  # order - restores the intended sequence while leaving it decided by configuration alone.
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
# template wrote a README containing the single line "# Gateway API".
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # Waits for the demo step's marker rather than the bootstrap's, so the README lands once the cluster it
    # describes is actually serving (rules.md D-5).
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/gateway_api_demo ]; do sleep 10; done
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_readme
      EOT
  }

  depends_on = [aws_ssm_association.gateway_api_demo]
}
