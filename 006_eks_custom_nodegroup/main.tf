data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
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
module "ecr" {
  source = "./modules/ecr"

  name = var.ecr_repository_name

  depends_on = [module.network]
}
# Shared by the cluster's managed network interfaces and both node groups'
# launch templates, which is what lets the bastion reach the private API server
# endpoint and lets nodes talk to each other.
module "node_security_group" {
  source = "./modules/node_security_group"

  vpc_id = module.network.vpc_id

  depends_on = [module.network]
}
module "eks_cluster" {
  source = "./modules/eks_cluster"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version
  subnet_ids         = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  # Handed an ID list; the cluster module never learns this group is also on the
  # worker nodes (rules.md B-6).
  additional_security_group_ids = [module.node_security_group.security_group_id]
  endpoint_public_access        = var.endpoint_public_access
  public_access_cidrs           = var.public_access_cidrs

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
  # running to join the cluster Ready (rules.md C-4).
  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as eks_vpc_cni_addon: kube-proxy is a DaemonSet and must
  # exist before any node capacity (rules.md C-4).
  depends_on = [module.network, module.eks_cluster]
}
# Two node groups from one module, differing only in name and labels, so pods
# can be pinned to application or addon capacity. Each gets its own launch
# template and IAM role inside the module.
module "eks_app_node_group" {
  source = "./modules/eks_node_group"

  cluster_name    = module.eks_cluster.cluster_name
  node_group_name = var.app_node_group_name
  labels          = var.app_node_group_labels
  instance_types  = var.node_group_instance_types
  desired_size    = var.node_group_desired_size
  min_size        = var.node_group_min_size
  max_size        = var.node_group_max_size
  subnet_ids      = module.network.private_subnet_ids
  # The custom launch template is what this project is about: a key pair, a
  # shared security group, and optionally a custom AMI plus MIME multipart user
  # data, all attached through the template rather than through node group
  # fields.
  key_name               = module.key_pair.key_name
  vpc_security_group_ids = [module.node_security_group.security_group_id]
  custom_ami_id          = var.node_group_custom_ami_id
  custom_user_data       = var.node_group_custom_user_data

  # Nodes need vpc-cni and kube-proxy running to join the cluster Ready
  # (rules.md C-4).
  depends_on = [module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}
module "eks_addon_node_group" {
  source = "./modules/eks_node_group"

  cluster_name           = module.eks_cluster.cluster_name
  node_group_name        = var.addon_node_group_name
  labels                 = var.addon_node_group_labels
  instance_types         = var.node_group_instance_types
  desired_size           = var.node_group_desired_size
  min_size               = var.node_group_min_size
  max_size               = var.node_group_max_size
  subnet_ids             = module.network.private_subnet_ids
  key_name               = module.key_pair.key_name
  vpc_security_group_ids = [module.node_security_group.security_group_id]
  custom_ami_id          = var.node_group_custom_ami_id
  custom_user_data       = var.node_group_custom_user_data

  depends_on = [module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.eks_cluster.cluster_name

  # coredns is a Deployment and needs schedulable node capacity to leave its
  # DEGRADED state and become ACTIVE, so it is created after the node groups
  # rather than before them (rules.md C-4).
  depends_on = [module.eks_app_node_group, module.eks_addon_node_group]
}
# The Horizontal Pod Autoscaler has no resource metrics without metrics-server,
# so this addon is a hard prerequisite for the HPA demo below rather than an
# optional extra.
module "eks_metrics_server_addon" {
  source = "./modules/eks_metrics_server_addon"

  cluster_name = module.eks_cluster.cluster_name

  # metrics-server is a Deployment, so like coredns it needs schedulable node
  # capacity to become ACTIVE rather than DEGRADED (rules.md C-4).
  depends_on = [module.eks_app_node_group, module.eks_addon_node_group]
}
module "aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"

  cluster_name                  = module.eks_cluster.cluster_name
  vpc_id                        = module.network.vpc_id
  aws_region                    = data.aws_region.current.region
  oidc_provider_arn             = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host              = module.eks_cluster.oidc_issuer_host
  enable_backend_security_group = var.enable_backend_security_group

  # The controller is a Deployment with wait = true, so it needs schedulable
  # capacity and working cluster DNS before the release can report ready
  # (rules.md D-2).
  depends_on = [module.network, module.eks_coredns_addon]
}
module "cluster_autoscaler" {
  source = "./modules/cluster_autoscaler"

  cluster_name      = module.eks_cluster.cluster_name
  aws_region        = data.aws_region.current.region
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  # Both node groups have the same instance type and size, so keeping them
  # balanced stops one absorbing every scale-up.
  balance_similar_node_groups = true

  # The autoscaler discovers the node groups' Auto Scaling groups by tag, so the
  # groups must exist first; it is also a Deployment needing capacity and DNS
  # (rules.md D-2).
  #
  # aws_load_balancer_controller is in this list for a different reason: it is
  # not a runtime dependency, it serializes the two Helm installs. Both pull
  # from https:// chart repositories and so share the provider's repository
  # index cache (see providers.tf), and hashicorp/terraform-provider-helm#551
  # reports helm_release failing when several run concurrently, with
  # apply -parallelism=1 as the documented workaround. Chaining these two
  # applies that serialization to just them rather than the whole apply. Both
  # set wait = true and take minutes anyway, so the ordering costs little.
  depends_on = [
    module.network,
    module.eks_coredns_addon,
    module.eks_app_node_group,
    module.eks_addon_node_group,
    module.aws_load_balancer_controller,
  ]
}
module "nlb_security_group" {
  source = "./modules/load_balancer_security_group"

  vpc_id                      = module.network.vpc_id
  name                        = var.nlb_security_group_name
  description                 = "Frontend security group for the pre-created NLB"
  allow_inbound_from_anywhere = var.nlb_allow_inbound_from_anywhere
  ingress_cidr_blocks         = var.nlb_service_cidr_blocks

  depends_on = [module.network]
}
resource "aws_vpc_security_group_ingress_rule" "load_balancer_to_pods" {
  count = var.kube_ops_view_service_type == "LoadBalancer" ? 1 : 0

  security_group_id            = module.node_security_group.security_group_id
  description                  = "NLB to kube-ops-view pods on the container port"
  ip_protocol                  = "tcp"
  from_port                    = module.kube_ops_view.container_port
  to_port                      = module.kube_ops_view.container_port
  referenced_security_group_id = module.nlb_security_group.security_group_id
}
module "kube_ops_view" {
  source = "./modules/kube_ops_view"

  service_type = var.kube_ops_view_service_type
  # Hands provisioning to the AWS Load Balancer Controller instead of the
  # in-tree Classic Load Balancer path, and only matters when service_type is
  # LoadBalancer.
  service_annotations = var.kube_ops_view_service_type == "LoadBalancer" ? {
    "service.beta.kubernetes.io/aws-load-balancer-type"            = "external"
    "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
    "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
    "service.beta.kubernetes.io/aws-load-balancer-security-groups" = module.nlb_security_group.security_group_id
  } : {}

  # With service_type = LoadBalancer the Service is only fulfilled once the
  # controller is reconciling (rules.md D-2). These are kubectl_manifest
  # resources talking straight to the API server, so ordering the module after
  # the node group also makes terraform destroy remove the Service - letting the
  # controller delete the load balancer it created - before the nodes running
  # the controller disappear (rules.md D-4).
  depends_on = [module.network, module.eks_app_node_group, module.aws_load_balancer_controller]
}
module "hpa_demo" {
  source = "./modules/hpa_demo"

  target_cpu_utilization_percentage = var.hpa_target_cpu_utilization_percentage
  min_replicas                      = var.hpa_min_replicas
  max_replicas                      = var.hpa_max_replicas
  # Pins the demo pods to the application node group by reusing the very labels
  # that module was given, so the selector cannot drift from the node labels
  # (rules.md B-5).
  node_selector = module.eks_app_node_group.labels

  # These are kubectl_manifest resources talking straight to the API server, and
  # the HorizontalPodAutoscaler is only functional once metrics-server is
  # serving the metrics API. Ordering the module after the node group also makes
  # terraform destroy remove these objects before the nodes running them
  # disappear (rules.md D-4).
  depends_on = [module.network, module.eks_app_node_group, module.eks_metrics_server_addon]
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
  # after everything in additional_user_data has run - which here includes the
  # sample image build, so the marker can be several minutes out.
  marker_file_path = var.marker_file_path
  # Joining the shared node security group is what lets this instance reach the
  # private API server endpoint (rules.md B-6).
  extra_security_group_ids = [module.node_security_group.security_group_id]
  additional_user_data     = <<-EOT
    # An EKS cluster and this instance live in the same root module, so the
    # instance is the workbench for that cluster and carries all five tools
    # unconditionally: code-server (installed by the module itself), plus
    # kubectl, eksctl, helm and docker (rules.md H-1). Docker used to sit behind
    # build_sample_image, which left the workbench without a daemon whenever the
    # sample image was skipped - the image build below is what is optional, not
    # the tool.
    #
    # Building and pushing a container image needs a real Docker daemon on a
    # host, so unlike the kubectl/helm steps this cannot become a provider
    # resource and stays in user data (rules.md E-1).
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server is already running from the module's bootstrap, so its process
    # predates the docker group and its integrated terminals inherit whatever
    # groups that process started with. Restarting is what makes docker usable
    # from the IDE, rather than opening /var/run/docker.sock up to 666
    # (rules.md H-1).
    systemctl restart code-server
    %{if var.build_sample_image~}
    mkdir -p /home/ec2-user/match
    cat <<'GOEOF' > /home/ec2-user/match/match.go
    package main

    import (
      "encoding/json"
      "fmt"
      "log"
      "net/http"
      "strings"
    )

    type Response struct {
      STATUS string `json:"status"`
    }

    func main() {
      http.HandleFunc("/v1/match", func(w http.ResponseWriter, r *http.Request) {
        token := r.URL.Query().Get("token")
        response := Response{STATUS: "FAIL"}
        w.Header().Add("content-type", "application/json")
        if len(token) > 0 && len(token) <= 8 && strings.Count(token, string(token[0])) == len(token) {
          response.STATUS = "OK"
        }
        data, _ := json.Marshal(response)
        w.WriteHeader(http.StatusOK)
        fmt.Fprint(w, string(data))
      })
      http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
        response := Response{STATUS: "OK"}
        w.Header().Add("content-type", "application/json")
        data, _ := json.Marshal(response)
        w.WriteHeader(http.StatusOK)
        fmt.Fprint(w, string(data))
      })
      log.Println("Start server")
      http.ListenAndServe(":8080", nil)
    }
    GOEOF
    cat <<'DOCKEREOF' > /home/ec2-user/match/Dockerfile
    FROM golang:1.24 AS build
    WORKDIR /source
    COPY match.go ./
    RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o match match.go
    FROM alpine
    WORKDIR /app
    RUN apk --no-cache add ca-certificates && apk --no-cache upgrade
    COPY --from=build /source/match ./
    RUN chmod +x ./match
    RUN adduser -D appuser
    RUN chown appuser:appuser ./match
    USER appuser
    ENTRYPOINT ["./match"]
    DOCKEREOF
    chown -R ec2-user:ec2-user /home/ec2-user/match
    aws ecr get-login-password --region ${data.aws_region.current.region} | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com
    MATCH_IMAGE_TAG=${module.ecr.repository_url}:latest
    docker build -t $MATCH_IMAGE_TAG /home/ec2-user/match
    docker push $MATCH_IMAGE_TAG
    %{endif~}
    su - ec2-user << 'EOF'
    export HOME=/home/ec2-user
    cd $HOME
    curl -sO https://s3.us-west-2.amazonaws.com/amazon-eks/${var.kubectl_download_version}/bin/linux/amd64/kubectl
    chmod +x ./kubectl
    mkdir -p $HOME/bin && mv ./kubectl $HOME/bin/kubectl && export PATH=$HOME/bin:$PATH
    echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc
    echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
    echo 'source <(kubectl completion bash)' >> ~/.bashrc
    echo 'alias k=kubectl' >> ~/.bashrc
    echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
    ARCH=amd64
    PLATFORM=$(uname -s)_$ARCH
    curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
    tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
    sudo install -m 0755 /tmp/eksctl /usr/local/bin && rm /tmp/eksctl
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
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
      description = "Open the IDE here. Every command below is meant to be run from its terminal, and it already has kubectl, eksctl, helm and docker installed (rules.md H-1)"
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
    app_node_group_name = {
      order       = 4
      title       = "Application node group"
      description = "Managed node group carrying application workloads, and the one the cluster autoscaler grows when the HPA demo below runs out of room"
      value       = module.eks_app_node_group.node_group_name
    }
    addon_node_group_name = {
      order       = 5
      title       = "Addon node group"
      description = "Separate node group carrying cluster addons, so a scale-out of the application group cannot evict the controllers that manage it"
      value       = module.eks_addon_node_group.node_group_name
    }
    app_node_group_launch_template_id = {
      order       = 6
      title       = "Custom launch template"
      description = "Launch template backing the application node group. Supplying one is what this project demonstrates: EKS accepts only MIME multipart user data there, and a bare shell script is silently ignored"
      value       = module.eks_app_node_group.launch_template_id
    }
    ecr_repository_url = {
      order       = 7
      title       = "ECR repository"
      description = "Repository the instance pushes the sample match-making image to when build_sample_image is true. Building an image is the one task here that genuinely needs a Docker daemon rather than a Terraform provider"
      value       = module.ecr.repository_url
    }
    kube_ops_view_service_command = {
      order       = 8
      title       = "1. Check the dashboard Service"
      description = "The EXTERNAL-IP column fills in with the NLB's DNS name once the AWS Load Balancer Controller has reconciled the Service. If it never fills in, the controller is not handling the Service - check its log (rules.md G-1)"
      value       = module.kube_ops_view.describe_command
    }
    kube_ops_view_endpoint_command = {
      order       = 9
      title       = "2. Read the NLB DNS name"
      description = "The NLB is created by the controller rather than by Terraform, so its address cannot be a Terraform output and is read from the cluster instead (rules.md H-2/G-1)"
      value       = module.kube_ops_view.load_balancer_hostname_command
    }
    kube_ops_view_fetch_command = {
      order       = 10
      title       = "3. Reach the dashboard"
      description = "Null unless kube_ops_view_service_type is LoadBalancer. This project's NLB is internet-facing, so the same hostname also opens in a browser"
      value       = module.kube_ops_view.load_balancer_fetch_command
    }
    kube_ops_view_port_forward_command = {
      order       = 11
      title       = "Reach the dashboard without the NLB"
      description = "Port-forwards the Service to http://localhost:8080. The way to use kube_ops_view_service_type = ClusterIP, and it works regardless of the Service type"
      value       = module.kube_ops_view.port_forward_command
    }
    hpa_load_generator_command = {
      order       = 12
      title       = "4. Drive load and watch the scale-out"
      description = "Pushes CPU load into the demo Service so the HorizontalPodAutoscaler adds pods, and then - once the application node group has no room left - the cluster autoscaler adds nodes. Watch both happen in the dashboard from step 3"
      value       = module.hpa_demo.load_generator_command
    }
  }
  # Iterating local.outputs directly would order sections by key, which puts
  # "2. Read the NLB DNS name" above "1. Check the dashboard Service". Re-keying
  # by the order field and taking values() sorts by that instead - values()
  # returns a map's values ordered by key - so the README reads in the order the
  # demo is run, and the order is still fully determined by the configuration
  # rather than shuffling between applies.
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
