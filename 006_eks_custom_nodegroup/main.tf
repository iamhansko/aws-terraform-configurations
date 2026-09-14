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
  # network module waits for all of it (rules.md #27).
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
  # worker nodes (rules.md #15).
  additional_security_group_ids = [module.node_security_group.security_group_id]
  endpoint_public_access        = var.endpoint_public_access
  public_access_cidrs           = var.public_access_cidrs

  # Referencing module.network.*_subnet_ids only orders this module after the
  # specific aws_subnet resources behind those outputs, not after the NAT
  # gateways and route table associations that never surface as outputs
  # (rules.md #27).
  depends_on = [module.network]
}
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not
  # exist until this addon creates it. As a DaemonSet it reaches ACTIVE with
  # zero nodes, so it is created before any node capacity - worker nodes need it
  # running to join the cluster Ready (rules.md #28).
  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as eks_vpc_cni_addon: kube-proxy is a DaemonSet and must
  # exist before any node capacity (rules.md #28).
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
  # (rules.md #28).
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
  # rather than before them (rules.md #28).
  depends_on = [module.eks_app_node_group, module.eks_addon_node_group]
}
# The Horizontal Pod Autoscaler has no resource metrics without metrics-server,
# so this addon is a hard prerequisite for the HPA demo below rather than an
# optional extra.
module "eks_metrics_server_addon" {
  source = "./modules/eks_metrics_server_addon"

  cluster_name = module.eks_cluster.cluster_name

  # metrics-server is a Deployment, so like coredns it needs schedulable node
  # capacity to become ACTIVE rather than DEGRADED (rules.md #28).
  depends_on = [module.eks_app_node_group, module.eks_addon_node_group]
}
module "aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"

  cluster_name      = module.eks_cluster.cluster_name
  vpc_id            = module.network.vpc_id
  aws_region        = data.aws_region.current.region
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host

  # The controller is a Deployment with wait = true, so it needs schedulable
  # capacity and working cluster DNS before the release can report ready
  # (rules.md #22).
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
  # (rules.md #22).
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
  } : {}

  # With service_type = LoadBalancer the Service is only fulfilled once the
  # controller is reconciling (rules.md #22). These are kubectl_manifest
  # resources talking straight to the API server, so ordering the module after
  # the node group also makes terraform destroy remove the Service - letting the
  # controller delete the load balancer it created - before the nodes running
  # the controller disappear (rules.md #29).
  depends_on = [module.network, module.eks_app_node_group, module.aws_load_balancer_controller]
}
module "hpa_demo" {
  source = "./modules/hpa_demo"

  target_cpu_utilization_percentage = var.hpa_target_cpu_utilization_percentage
  min_replicas                      = var.hpa_min_replicas
  max_replicas                      = var.hpa_max_replicas
  # Pins the demo pods to the application node group by reusing the very labels
  # that module was given, so the selector cannot drift from the node labels
  # (rules.md #5).
  node_selector = module.eks_app_node_group.labels

  # These are kubectl_manifest resources talking straight to the API server, and
  # the HorizontalPodAutoscaler is only functional once metrics-server is
  # serving the metrics API. Ordering the module after the node group also makes
  # terraform destroy remove these objects before the nodes running them
  # disappear (rules.md #29).
  depends_on = [module.network, module.eks_app_node_group, module.eks_metrics_server_addon]
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  # Joining the shared node security group is what lets this instance reach the
  # private API server endpoint (rules.md #15).
  extra_security_group_ids = [module.node_security_group.security_group_id]
  additional_user_data     = <<-EOT
    %{if var.build_sample_image~}
    # Building and pushing a container image needs a real Docker daemon on a
    # host, so unlike the kubectl/helm steps this cannot become a provider
    # resource and stays in user data (rules.md #18).
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
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
# either one (rules.md #14).
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
