data "aws_region" "current" {}
module "network" {
  source = "./modules/network"
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name = var.key_name

  # key_pair consumes no network output, so nothing would otherwise order it against
  # the network module's resources (rules.md D-3).
  depends_on = [module.network]
}
module "eks_cluster" {
  source = "./modules/eks_cluster"

  name                   = var.cluster_name
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  # Referencing module.network.*_subnet_ids only orders this after the specific
  # aws_subnet resources behind those outputs, not after the NAT gateways and route
  # table associations that never surface as outputs (rules.md D-3).
  depends_on = [module.network]
}
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not exist
  # until this addon creates it. As a DaemonSet it reaches ACTIVE with zero nodes, so it
  # comes before any capacity (rules.md C-4) - and nodes need it to join Ready.
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

  depends_on = [module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.eks_cluster.cluster_name

  # coredns is a Deployment and needs schedulable capacity to leave DEGRADED and become
  # ACTIVE (rules.md C-4). It is also the first workload whose logs this project collects,
  # since nothing else runs on the cluster.
  depends_on = [
  module.network, module.eks_node_group]
}
# cert-manager, which the ADOT add-on needs rather than merely benefits from: the add-on
# installs the OpenTelemetry Operator, whose admission webhook serves TLS from a certificate
# cert-manager issues. Without it the add-on installs, the operator never becomes ready, and
# the collector object is never reconciled into anything.
#
# The _monolithic template installed it with an unpinned helm command from an SSM
# Association on the bastion (rules.md E-1).
module "cert_manager" {
  source = "./modules/cert_manager"

  chart_version = var.cert_manager_chart_version

  # The release waits for its own webhook to be serving, which needs schedulable capacity
  # and working cluster DNS (rules.md D-2).
  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}
# The RBAC that lets EKS install the add-on at all. Five cluster-scoped objects the
# _monolithic template fetched with "kubectl apply -f https://amazon-eks.s3.amazonaws.com/..."
# from the bastion, leaving them outside Terraform entirely (rules.md E-1/E-2).
module "adot_addon_permissions" {
  source = "./modules/adot_addon_permissions"

  # kubectl_manifest resources against the cluster's API server, so they need nodes for the
  # API server to be reachable through and CoreDNS for the provider's token exec to resolve.
  # Ordering the module after the nodes also makes terraform destroy remove this RBAC while
  # the cluster is still there (rules.md D-4).
  depends_on = [
  module.network, module.eks_node_group, module.eks_coredns_addon]
}
# The variant. One collector, accepting traces over OTLP from instrumented applications and
# forwarding them to X-Ray.
#
# Unlike the container logs collector this one is a Deployment behind a Service rather than a
# DaemonSet: nothing is scraped, applications send to it. So a workload has to be pointed at
# its endpoint, which is what module.otel_sample_app below does.
module "eks_adot_addon" {
  source = "./modules/eks_adot_addon"

  cluster_name      = module.eks_cluster.cluster_name
  addon_version     = var.adot_addon_version
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  otlp_ingest = {
    enable_xray = var.enable_xray
  }
  # container_logs and prometheus_metrics are left null: those are what the cloudwatch_log and
  # amp_metric variants enable. Each variant owns its own copy of this module
  # (rules.md A-1), so they can diverge without affecting each other.

  # Both edges are load-bearing and neither is a value reference, so neither is implied
  # (rules.md D-2). module.adot_addon_permissions because EKS installs this add-on as the
  # eks:addon-manager user, which cannot create the operator without that RBAC.
  # module.cert_manager because the operator's webhook needs a certificate.
  #
  # The _monolithic template expressed the same ordering as a single depends_on against the
  # SSM Association that did both.
  depends_on = [
  module.network, module.adot_addon_permissions, module.cert_manager]
}
# What produces the traces. An OTLP collector with nothing sending to it leaves the X-Ray
# console empty, which is indistinguishable from a broken pipeline.
module "otel_sample_app" {
  source = "./modules/otel_sample_app"

  namespace               = var.sample_app_namespace
  sample_app_image        = var.sample_app_image
  traffic_generator_image = var.traffic_generator_image
  otel_service_namespace  = var.otel_service_namespace
  otel_service_name       = var.otel_service_name
  aws_region              = data.aws_region.current.region
  oidc_provider_arn       = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host        = module.eks_cluster.oidc_issuer_host
  # Taken from the add-on module rather than restated. The collector's Service name is the
  # add-on's to choose, and a wrong endpoint leaves the application running and exporting
  # into nothing - visible only in its own log (rules.md B-5).
  otlp_endpoint = module.eks_adot_addon.otlp_endpoint

  # The collector has to exist before anything sends to it, and the endpoint is a string
  # rather than a resource attribute, so the reference above does not order them
  # (rules.md D-1/D-2). Ordering the module after the nodes also makes terraform destroy
  # remove these manifests while the cluster is still there (rules.md D-4).
  depends_on = [
  module.network, module.eks_node_group, module.eks_coredns_addon, module.eks_adot_addon]
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  marker_file_path            = var.marker_file_path
  # Joining the cluster security group is what lets this instance reach the API server.
  # The module is handed an ID list and never learns it belongs to an EKS cluster
  # (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]

  # An EKS cluster and this instance share a root module, so it is the workbench for that
  # cluster and carries all five tools (rules.md H-1). None of them creates anything:
  # cert-manager and the add-on's RBAC, which the _monolithic template applied from here, are
  # Terraform resources now (rules.md E-1).
  #
  # Two bugs from that template are fixed here rather than carried over. It ran "exec bash"
  # partway through, which replaces the shell and silently discarded every remaining line -
  # update-kubeconfig, eksctl and helm were all after it, so the instance came up with no
  # kubeconfig while the SSM Association that followed depended on kubectl working. And it
  # pulled eksctl from weaveworks; eksctl-io is the project's own org (rules.md H-1).
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
    # Order matters: kubectl's completion defines __start_kubectl, and that has to exist
    # before complete names it, or every login prints "function not found"
    # (rules.md H-1).
    echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
    echo 'source <(kubectl completion bash)' >> ~/.bashrc
    echo 'alias k=kubectl' >> ~/.bashrc
    echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
    PLATFORM=$(uname -s)_amd64
    curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
    tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
    sudo install -m 0755 /tmp/eksctl /usr/local/bin && rm /tmp/eksctl
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    aws configure set default.region ${data.aws_region.current.region}
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}
    EOF
  EOT

  depends_on = [module.network]
}
# Granting the bastion's instance role cluster access joins two modules that know nothing
# about each other, so it belongs in the root (rules.md C-1).
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
  # Every output this project exposes, defined once. outputs.tf projects these and the
  # README below renders them, so no value expression is written twice (rules.md B-5/H-2).
  # Adding an entry here is what makes an output possible, which is what keeps the README
  # from falling behind outputs.tf.
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
      description = "API server endpoint. Public so the helm and kubectl providers could reach it during apply - narrow public_access_cidrs to your own address"
      value       = module.eks_cluster.cluster_endpoint
    }
    trace_service = {
      order       = 4
      title       = "What to look for in X-Ray"
      description = "The service namespace and name the sample application labels its traces with. These are OpenTelemetry resource attributes rather than Kubernetes namespaces, and they are what the node in the X-Ray service map is called"
      value       = module.otel_sample_app.otel_service_name
    }
    otlp_endpoint = {
      order       = 5
      title       = "Collector endpoint"
      description = "Where an instrumented application sends traces. This collector is a Deployment behind a Service, not a DaemonSet - nothing is scraped, applications send to it, which is why a workload has to be pointed here"
      value       = module.eks_adot_addon.otlp_endpoint
    }
    addon_configuration = {
      order       = 6
      title       = "The add-on configuration"
      description = "The JSON the adot add-on received. Read it first when no traces arrive: a key in the wrong place is valid JSON the add-on ignores, and nothing anywhere reports that (rules.md E-5)"
      value       = module.eks_adot_addon.configuration_values
    }
    collector_role = {
      order       = 7
      title       = "Collector IAM role"
      description = "The IRSA role the OTLP collector assumes to put trace segments. Its trust policy names the service account the add-on creates - a name this configuration cannot choose, so a mismatch shows up as an exporter that cannot authenticate rather than as anything Terraform reports"
      value       = module.eks_adot_addon.collector_role_arns["otlp_ingest"]
    }
    sample_app_role = {
      order       = 8
      title       = "Sample application IAM role"
      description = "The role the application assumes for its /aws-sdk-call endpoint, which lists S3 buckets. Scoped to s3:ListAllMyBuckets, where the _monolithic template attached AmazonS3FullAccess - read, write and delete on every bucket in the account - to satisfy that one call"
      value       = module.otel_sample_app.iam_role_arn
    }
    permission_check_command = {
      order       = 9
      title       = "1. Confirm EKS could install the add-on"
      description = "The RBAC that lets the eks:addon-manager user create the operator. If the add-on reports a create failure, the message names the object it could not create and every one of them is covered here"
      value       = module.adot_addon_permissions.permission_check_command
    }
    collector_status_command = {
      order       = 10
      title       = "2. Confirm the collector was built"
      description = "An OpenTelemetryCollector with no matching Deployment means the operator has not reconciled it, which is almost always its webhook failing to serve - check cert-manager before anything else"
      value       = module.eks_adot_addon.collector_status_command
    }
    cert_manager_command = {
      order       = 11
      title       = "3. Check cert-manager"
      description = "The operator's webhook certificate comes from here. cert-manager not being ready is the single most common reason this project appears to install cleanly and collect nothing"
      value       = "kubectl -n ${module.cert_manager.namespace} get pods"
    }
    rollout_status_command = {
      order       = 12
      title       = "4. Wait for the sample application"
      description = "It is a JVM, so it takes the longer of the two Deployments. Until it is up the traffic generator's requests fail and no traces are produced at all"
      value       = module.otel_sample_app.rollout_status_command
    }
    manual_call_command = {
      order       = 13
      title       = "5. Produce one trace by hand"
      description = "The fastest way to get something to look for. This endpoint is the one that uses the IRSA role, so a failure here is a permissions problem rather than a tracing one"
      value       = module.otel_sample_app.manual_call_command
    }
    sample_app_log_command = {
      order       = 14
      title       = "6. Read the application's exporter log"
      description = "Where a wrong OTLP endpoint appears. The application stays running and healthy while every export fails here, and nothing else reports it"
      value       = module.otel_sample_app.sample_app_log_command
    }
    collector_log_command = {
      order       = 15
      title       = "7. Read the collector's own log"
      description = "Where an AccessDenied from X-Ray appears. The collector stays Running either way, so this is the only place a permissions problem is visible"
      value       = module.eks_adot_addon.collector_log_command
    }
    xray_trace_command = {
      order       = 16
      title       = "8. Read the traces from the CLI"
      description = "Trace summaries for the last ten minutes, without opening the console. Empty while the pods are healthy means the pipeline is dropping them - work backwards through the two log commands above"
      value       = "aws xray get-trace-summaries --start-time $(date -u -d '10 minutes ago' +%s) --end-time $(date -u +%s) --query 'TraceSummaries[].{Id:Id,Duration:Duration,Http:Http.HttpURL}' --output table"
    }
    service_graph_command = {
      order       = 17
      title       = "9. Read the service map"
      description = "The same data as the console's service map. Two nodes are expected: the sample application, and the AWS service its SDK call reaches"
      value       = "aws xray get-service-graph --start-time $(date -u -d '10 minutes ago' +%s) --end-time $(date -u +%s) --query 'Services[].{Name:Name,Type:Type,Ok:SummaryStatistics.OkCount,Error:SummaryStatistics.ErrorStatistics.TotalCount}' --output table"
    }
    update_kubeconfig_command = {
      order       = 18
      title       = "Re-point kubectl"
      description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the order
  # field and taking values() - which returns a map's values ordered by key - makes the
  # README read top to bottom while the order stays decided by configuration.
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
# The work happens inside code-server in a browser, where terraform output is not
# available, so every output above is also written to a README in the home directory the
# IDE opens (rules.md H-2). Combining several modules' outputs is the root's job, so this
# lives here rather than inside the instance module.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is what orders
    # this after the bootstrap (rules.md D-5). The marker path comes back out of the
    # module it was passed into, so it is defined once (rules.md B-5).
    #
    # SSM runs as root, hence the chown.
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
