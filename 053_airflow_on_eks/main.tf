# Read once here and passed to the modules that need them, rather than read again inside each. Most
# of those modules are called with depends_on, which defers every data source inside them to apply
# whenever a dependency has changes pending - and the region and account end up in IAM policies, VPC
# endpoint service names and a kubeconfig, where an unknown value shows as a pointless diff or a
# forced replacement (rules.md D-6).
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
locals {
  # The kubeconfig MWAA's KubernetesPodOperator reads, and the context in it the DAG selects. Each
  # appears both in the file and in the DAG, so each is defined once (rules.md B-5).
  kube_config_file = "kube_config.yaml"
  kube_context     = "mwaa"
}

# --- Network ---------------------------------------------------------------------------------------

# The blueprint's VPC: three zones, private /20s, public /24s, one NAT gateway.
module "network" {
  source = "./modules/network"

  name           = var.name
  vpc_cidr_block = var.vpc_cidr_block
  # The blueprint also tagged every subnet kubernetes.io/cluster/<name> = shared. Nothing requires it
  # any more, but it is how a reader of the VPC console sees which cluster the subnets belong to.
  public_subnet_tags = merge(var.public_subnet_tags, {
    "kubernetes.io/cluster/${var.name}" = "shared"
  })
  private_subnet_tags = merge(var.private_subnet_tags, {
    "kubernetes.io/cluster/${var.name}" = "shared"
  })
}
# On module ordering in this root: every module starts after the whole of module.network, either by
# naming it in depends_on or by naming a module that does. Value references such as
# module.network.private_subnet_ids only order a module after the subnets themselves, not after the
# NAT gateway and the route table associations - and the nodes, MWAA's workers and the workbench all
# need a route out from the moment they start (rules.md D-3).
module "vpc_endpoints" {
  source = "./modules/vpc_endpoints"

  region              = data.aws_region.current.region
  vpc_id              = module.network.vpc_id
  subnet_ids          = module.network.private_subnet_ids
  route_table_ids     = module.network.private_route_table_ids
  interface_services  = var.vpc_endpoint_services
  security_group_name = "${var.name}-vpc-endpoints"
  # The root variable rather than the network module's output: these are for_each keys, and a root
  # variable is known at plan (rules.md B-8).
  ingress_cidr_blocks = [var.vpc_cidr_block]
  name_prefix         = var.name

  depends_on = [module.network]
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name = var.key_name

  # key_pair consumes no network output, so nothing would otherwise order it against the network
  # module's resources (rules.md D-3).
  depends_on = [module.network]
}

# --- EKS -------------------------------------------------------------------------------------------

# The blueprint's terraform-aws-modules/eks call, minus what that module did by default and this one
# does not need: a customer managed KMS key for Secrets (EKS encrypts all API data by default now) and
# a separate node security group (the managed node group here uses the cluster security group, which
# already admits all traffic between its members - the blueprint's two extra node rules, node-to-node
# on all ports and node-to-control-plane on 1025-65535, are what that group does on its own).
#
# Private subnets only, as the blueprint passed them. The API server's public endpoint is what the
# kubectl and helm providers use from the machine running terraform; the private endpoint is what
# the nodes, MWAA's workers and the workbench use from inside the VPC.
module "eks_cluster" {
  source = "./modules/eks_cluster"

  name                      = var.name
  kubernetes_version        = var.kubernetes_version
  subnet_ids                = module.network.private_subnet_ids
  endpoint_public_access    = var.endpoint_public_access
  public_access_cidrs       = var.public_access_cidrs
  enabled_cluster_log_types = var.cluster_log_types
  log_retention_days        = var.cluster_log_retention_days

  depends_on = [module.network]
}
# bootstrap_self_managed_addons = false on the cluster means vpc-cni, kube-proxy and coredns do not
# exist until these addons create them. The blueprint let EKS install them self-managed and then
# adopted them through eks-blueprints-addons (preserve = true); creating them as managed addons from
# the start is the same end state without the takeover (rules.md C-4).
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  # A DaemonSet, so it reaches ACTIVE with zero nodes - and nodes need it to join Ready, so it comes
  # before any capacity (rules.md C-4).
  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as eks_vpc_cni_addon (rules.md C-4).
  depends_on = [module.network, module.eks_vpc_cni_addon]
}
# The blueprint's core_node_group. AL2023 rather than its AL2_x86_64: EKS publishes no AL2 AMI for
# Kubernetes 1.33 or later, which includes the version this cluster runs. The module's own default is
# AL2023_x86_64_STANDARD, which is why ami_type is not passed.
#
# No key pair, as the blueprint had none on its nodes; they are reachable through SSM Session
# Manager, which the node role's AmazonSSMManagedInstanceCore allows. Its cluster autoscaler tags are
# not carried over either: they sat on the node group resource, which EKS does not propagate to the
# Auto Scaling group, and EKS tags the group for auto-discovery on its own.
module "eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name     = module.eks_cluster.cluster_name
  instance_types   = var.node_group_instance_types
  desired_size     = var.node_group_desired_size
  min_size         = var.node_group_min_size
  max_size         = var.node_group_max_size
  root_volume_size = var.node_group_root_volume_size
  labels           = var.node_group_labels
  subnet_ids       = module.network.private_subnet_ids

  # Nodes need vpc-cni and kube-proxy running to join the cluster Ready (rules.md C-4).
  depends_on = [module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.eks_cluster.cluster_name

  # A Deployment, so it needs schedulable capacity to leave DEGRADED and become ACTIVE (rules.md C-4).
  depends_on = [module.network, module.eks_node_group]
}
module "eks_metrics_server_addon" {
  source = "./modules/eks_metrics_server_addon"

  cluster_name = module.eks_cluster.cluster_name

  # A Deployment, like coredns (rules.md C-4).
  depends_on = [module.network, module.eks_node_group]
}
module "eks_ebs_csi_driver_addon" {
  source = "./modules/eks_ebs_csi_driver_addon"

  cluster_name      = module.eks_cluster.cluster_name
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  # A prefix rather than the blueprint's fixed <name>-ebs-csi-driver, because IAM is global: a fixed
  # name collides the moment this project is applied in a second region.
  role_name_prefix = "${substr(var.name, 0, 23)}-ebs-csi-"

  # The controller is a Deployment, so it needs nodes to become ACTIVE (rules.md C-4).
  depends_on = [module.network, module.eks_node_group]
}
# The blueprint's cluster autoscaler. Its IRSA role and Helm release are one module, because the
# release has to annotate the service account with the role's ARN (rules.md C-2). The scale-down
# settings are left at the autoscaler's own defaults, as eks-blueprints-addons left them.
module "cluster_autoscaler" {
  source = "./modules/cluster_autoscaler"

  cluster_name      = module.eks_cluster.cluster_name
  aws_region        = data.aws_region.current.region
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  chart_version     = var.cluster_autoscaler_chart_version

  # The autoscaler resolves Service DNS names and talks to the API server, so CoreDNS has to be
  # answering before its pod is useful (rules.md D-2).
  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}

# --- EMR on EKS ------------------------------------------------------------------------------------

# The namespace, its RBAC and the service-linked role's aws-auth entry. Kubernetes objects, so they
# come after the nodes: terraform destroy then removes them while there is still a kubelet to
# terminate whatever ran in the namespace (rules.md D-4).
module "emr_namespace_access" {
  source = "./modules/emr_namespace_access"

  account_id = data.aws_caller_identity.current.account_id
  namespace  = var.emr_namespace

  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}
module "emr_virtual_cluster" {
  source = "./modules/emr_virtual_cluster"

  cluster_name = module.eks_cluster.cluster_name
  # Taken from the module that authorised EMR in it rather than restated, so the virtual cluster
  # cannot be bound to a namespace nothing granted access to (rules.md B-5).
  namespace         = module.emr_namespace_access.namespace
  account_id        = data.aws_caller_identity.current.account_id
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  # Both names as the blueprint's virtual-cluster module derived them.
  name                   = "${var.name}-emr-mwaa-team"
  log_group_name         = "/emr-on-eks-logs/emr-workload/${module.emr_namespace_access.namespace}"
  additional_policy_arns = var.emr_job_role_additional_policy_arns

  # CreateVirtualCluster reads the namespace as the service-linked role, so the RBAC and the aws-auth
  # mapping have to be in place first - and nothing here references them by value (rules.md D-2).
  depends_on = [module.emr_namespace_access]
}

# --- MWAA ------------------------------------------------------------------------------------------

module "mwaa_namespace_access" {
  source = "./modules/mwaa_namespace_access"

  namespace = var.mwaa_namespace

  # Kubernetes objects, ordered after the nodes for the same destroy-time reason as
  # emr_namespace_access (rules.md D-4).
  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}
locals {
  # The kubeconfig the KubernetesPodOperator DAG uses, as the blueprint wrote it: the cluster's
  # endpoint and CA, and an exec entry that has the AWS CLI on the MWAA worker fetch a token as the
  # environment's execution role. v1beta1 for the exec API, as the blueprint had it: the kubernetes
  # client rejects a token whose apiVersion differs from the one it asked for, and v1beta1 is the one
  # older AWS CLIs (which always answer with it) and newer ones (which answer with whatever is asked)
  # both satisfy - the worker image decides which CLI is there, not this configuration.
  kube_config = yamlencode({
    apiVersion      = "v1"
    kind            = "Config"
    current-context = local.kube_context
    clusters = [{
      name = module.eks_cluster.cluster_arn
      cluster = {
        certificate-authority-data = module.eks_cluster.certificate_authority_data
        server                     = module.eks_cluster.cluster_endpoint
      }
    }]
    contexts = [{
      name = local.kube_context
      context = {
        cluster = module.eks_cluster.cluster_arn
        user    = local.kube_context
      }
    }]
    users = [{
      name = local.kube_context
      user = {
        exec = {
          apiVersion = "client.authentication.k8s.io/v1beta1"
          command    = "aws"
          args       = ["--region", data.aws_region.current.region, "eks", "get-token", "--cluster-name", module.eks_cluster.cluster_name]
        }
      }
    }]
  })
  # The blueprint's dags/ folder plus the kubeconfig, rendered here rather than uploaded as files, so
  # the values each DAG has to agree with come from the resources they describe (rules.md B-5). The
  # keys are fixed file names, so they are known at plan even though the kubeconfig's content is not
  # (rules.md B-8).
  dag_files = {
    "example_emr_eks_new.py" = templatefile("${path.module}/dags/example_emr_eks_new.py.tftpl", {
      connection_id  = var.emr_connection_id
      release_label  = var.emr_release_label
      log_group_name = module.emr_virtual_cluster.log_group_name
    })
    "mwaa_pod_example.py" = templatefile("${path.module}/dags/mwaa_pod_example.py.tftpl", {
      namespace        = module.mwaa_namespace_access.namespace
      kube_config_file = local.kube_config_file
      kube_context     = local.kube_context
    })
    (local.kube_config_file) = local.kube_config
  }
}
# The ceiling on max_workers, as this account has it in this region. AWS's default is 25, but the
# applied value can be lower - CreateEnvironment failed with "MaxWorkers has a limit of 10" in an
# account given 10 - and that failure only comes at apply. Read here, with no depends_on, so it is
# known at plan for the module's validation (rules.md D-6). Falls back to the default when the quota
# was never changed; needs servicequotas:ListAWSDefaultServiceQuotas and servicequotas:GetServiceQuota.
data "aws_servicequotas_service_quota" "mwaa_workers" {
  service_code = "airflow"
  quota_code   = "L-78AC1883"
}
# Created side by side with the cluster rather than after it: the environment itself references
# nothing on the EKS side, and only the kubeconfig and the EMR DAG wait for the resources whose
# values they carry. MWAA takes 20-30 minutes on its own, so this is most of the apply's length.
module "mwaa_environment" {
  source = "./modules/mwaa_environment"

  name                  = var.name
  account_id            = data.aws_caller_identity.current.account_id
  region                = data.aws_region.current.region
  airflow_version       = var.airflow_version
  environment_class     = var.mwaa_environment_class
  min_workers           = var.mwaa_min_workers
  max_workers           = var.mwaa_max_workers
  max_workers_quota     = data.aws_servicequotas_service_quota.mwaa_workers.value
  webserver_access_mode = var.mwaa_webserver_access_mode
  vpc_id                = module.network.vpc_id
  # The first two, as the blueprint sliced them - MWAA takes exactly two.
  subnet_ids = slice(module.network.private_subnet_ids, 0, 2)
  # The blueprint's source_cidr, the VPC's own range. A root variable, because these are for_each keys
  # (rules.md B-8).
  webserver_ingress_cidr_blocks = [var.vpc_cidr_block]
  dag_files                     = local.dag_files
  requirements                  = file("${path.module}/dags/requirements.txt")
  airflow_configuration_options = var.airflow_configuration_options
  # The EMR DAG's connection, which the blueprint left as a form to fill in in the Airflow UI. Stored
  # in Secrets Manager by the module, where the environment's secrets backend looks first. Airflow's
  # JSON form: the DAG reads only extra, and conn_type "aws" is the "Amazon Web Services" type the
  # blueprint's instructions picked. The values come from the module that created what they name, so
  # the connection cannot point at a virtual cluster or role that is not there (rules.md B-5).
  #
  # Keyed by the root variable the DAG is rendered with, so the secret's name and the DAG's
  # conn.<id> lookup are the same string. A root variable is known at plan, which is what the
  # module's for_each over these keys needs (rules.md B-8).
  connections = {
    (var.emr_connection_id) = jsonencode({
      conn_type = "aws"
      extra = {
        virtual_cluster_id = module.emr_virtual_cluster.virtual_cluster_id
        job_role_arn       = module.emr_virtual_cluster.job_execution_role_arn
      }
    })
  }

  # The blueprint made the environment wait for the VPC endpoints, and vpc_endpoints is what reaches
  # module.network for this module (rules.md D-3).
  depends_on = [module.vpc_endpoints]
}

# --- Joining MWAA to EMR and EKS -------------------------------------------------------------------
#
# Each of these grants the MWAA execution role something on a resource another module owns, so they
# belong to the root rather than to either module (rules.md C-1).

# The blueprint's mwaa-emr-job policy, as an inline policy on the execution role rather than a managed
# policy plus an attachment: it is deleted with the role, and nothing else attaches it. "*" as the
# blueprint wrote it - EmrContainerOperator calls StartJobRun, DescribeJobRun and CancelJobRun, the
# blueprint added ListJobRuns, and none of the four reaches anything but EMR on EKS job runs.
resource "aws_iam_role_policy" "mwaa_emr_job" {
  name = "mwaa-emr-job"
  role = module.mwaa_environment.execution_role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "emr-containers:StartJobRun",
        "emr-containers:ListJobRuns",
        "emr-containers:DescribeJobRun",
        "emr-containers:CancelJobRun",
      ]
      Resource = "*"
    }]
  })
}
# MWAA's workers reach the API server's private endpoint - the cluster has private access on, so its
# hostname resolves to the control plane ENIs inside the VPC - and those ENIs carry the cluster
# security group. The blueprint's allow_access_from_mwaa rule.
resource "aws_vpc_security_group_ingress_rule" "mwaa_to_cluster_api" {
  security_group_id            = module.eks_cluster.cluster_security_group_id
  description                  = "Kubernetes API from the MWAA environment"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = module.mwaa_environment.security_group_id
}
# Authenticates the execution role as the Kubernetes user mwaa_namespace_access binds its Role to. No
# access policy: that Role is all it gets. The blueprint mapped the role to system:masters through
# aws-auth instead, which an access entry cannot express - EKS reserves the system: prefix - and which
# made every DAG cluster-admin (see modules/mwaa_namespace_access).
resource "aws_eks_access_entry" "mwaa" {
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.mwaa_environment.execution_role_arn
  type          = "STANDARD"
  user_name     = module.mwaa_namespace_access.user_name
}

# --- Workbench -------------------------------------------------------------------------------------

module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name                        = var.instance_name
  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  key_name                    = module.key_pair.key_name
  instance_type               = var.instance_type
  root_volume_size            = var.root_volume_size
  code_server_version         = var.code_server_version
  security_group_name         = var.security_group_name
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  marker_file_path            = var.marker_file_path
  # Joining the cluster security group is what lets this instance reach the API server's private
  # endpoint. The module is handed an ID list and never learns it belongs to an EKS cluster
  # (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]

  # An EKS cluster and this instance share a root module, so it is the workbench for that cluster and
  # carries all five tools (rules.md H-1). None of them creates anything: the instance used to clone
  # the blueprint and run its install.sh, a second Terraform apply whose state lived on this disk, and
  # everything that apply built is a resource in this state now (rules.md E-1).
  #
  # Three bugs from the _monolithic template stay fixed. It ran "exec bash" partway through, which
  # replaces the shell and silently discarded every remaining line. It pulled eksctl from weaveworks
  # rather than eksctl-io. And it wrote the "complete" line for the k alias into .bashrc before the
  # line that defines __start_kubectl, so every login printed a "function not found" error.
  #
  # The marker file is the last thing the script does, which is what the README association below
  # waits for (rules.md B-4/D-5).
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
    # Order matters: kubectl's completion defines __start_kubectl, and that has to exist before
    # complete names it, or every login prints "function not found" (rules.md H-1).
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
# Granting the workbench's instance role cluster access joins two modules that know nothing about each
# other, so it belongs in the root (rules.md C-1).
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

# --- Outputs and the README ------------------------------------------------------------------------

locals {
  # Every output this project exposes, defined once. outputs.tf projects these and the README below
  # renders them, so no value expression is written twice (rules.md B-5/H-2). Adding an entry here is
  # what makes an output possible, which is what keeps the README from falling behind outputs.tf.
  #
  # Values rather than commands wherever this state has them. The _monolithic template's README could
  # only tell the reader to go and run terraform output inside the nested run's directory, because
  # none of this was in the outer state; now all of it is.
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here. The kubectl and aws commands below are meant to be run from its terminal. This editor has no authentication and the instance role behind it is AdministratorAccess with cluster-admin on the cluster, so do not leave it reachable from the internet longer than the demo needs"
      value       = module.vscode_ec2.vscode_url
    }
    mwaa_status_command = {
      order       = 2
      title       = "1. Confirm the MWAA environment is available"
      description = "MWAA takes 20-30 minutes to create and as long again for every update. A login page that will not load usually means this still says CREATING or UPDATING rather than anything being wrong"
      value       = module.mwaa_environment.status_command
    }
    airflow_login_command = {
      order       = 3
      title       = "2. Sign in to the Airflow UI"
      description = "Prints a one-time sign-in link. MWAA signs you in through IAM, so whoever runs this needs airflow:CreateWebLoginToken - the workbench's role has it. The link is valid for 60 seconds, so open it right away"
      value       = module.mwaa_environment.login_url_command
    }
    emr_connection_command = {
      order       = 4
      title       = "3. Check the EMR connection"
      description = "Nothing to add by hand: Terraform stores the connection the EMR DAG reads in Secrets Manager, and the environment's secrets backend finds it there. It does not appear under Admin > Connections, which lists only the metadata database. This prints exactly what the DAG gets - the virtual cluster ID and the job role ARN in extra"
      value       = "aws secretsmanager get-secret-value --secret-id ${module.mwaa_environment.connection_secret_names[var.emr_connection_id]} --query SecretString --output text"
    }
    emr_pods_command = {
      order       = 5
      title       = "4. Unpause emr_eks_pi_job and watch its pods"
      description = "MWAA creates DAGs paused, so unpause emr_eks_pi_job in the UI; it runs once. The job it submits appears here as a job submitter pod, then a Spark driver and its executors - in the EMR namespace, not in MWAA's"
      value       = "kubectl get pods --namespace ${module.emr_virtual_cluster.namespace} --watch"
    }
    emr_job_runs_command = {
      order       = 6
      title       = "5. Check the job run"
      description = "The job's state from EMR's side. FAILED comes with a stateDetails line, which is the first place to look; a run that never appears means the task could not call StartJobRun, which the task log below shows"
      value       = module.emr_virtual_cluster.job_runs_command
    }
    emr_job_log_command = {
      order       = 7
      title       = "6. Read the Spark driver's output"
      description = "The job's monitoringConfiguration writes here, which is the group the job execution role may write to. pi.py prints its estimate of pi near the end"
      value       = module.emr_virtual_cluster.job_log_command
    }
    pod_example_command = {
      order       = 8
      title       = "7. Trigger kubernetes_pod_example and read its pod"
      description = "The second DAG runs one ubuntu pod through the KubernetesPodOperator, using the kubeconfig in its DAG folder and the namespace-scoped Role it is granted. It has no schedule, so trigger it from the UI. The pod is kept after it finishes, so this shows its output"
      value       = "kubectl --namespace ${module.mwaa_namespace_access.namespace} get pods -l foo=bar && kubectl --namespace ${module.mwaa_namespace_access.namespace} logs -l foo=bar"
    }
    mwaa_rbac_check_command = {
      order       = 9
      title       = "Check what the DAG may do in its namespace"
      description = "The execution role is authenticated as this user and granted only a Role in the namespace. A \"no\" on any line is the pod task failing with 403 Forbidden"
      value       = module.mwaa_namespace_access.access_check_command
    }
    task_logs_command = {
      order       = 10
      title       = "Read the task logs"
      description = "Where a failed operator's traceback lands - a missing connection, a 403 from the API server or an AccessDenied from EMR"
      value       = module.mwaa_environment.task_logs_command
    }
    dag_import_errors_command = {
      order       = 11
      title       = "Find a DAG that does not show up"
      description = "A DAG file that is in the bucket but not in the UI failed to import, and the DAG processor says why"
      value       = module.mwaa_environment.dag_processing_logs_command
    }
    dag_files_command = {
      order       = 12
      title       = "List the DAG folder"
      description = "Both DAGs, requirements.txt and the kubeconfig the pod DAG uses, all written by Terraform. Edit them through main.tf and dags/ rather than here: the next apply puts Terraform's version back"
      value       = "aws s3 ls ${module.mwaa_environment.dag_s3_uri}"
    }
    mwaa_webserver_url = {
      order       = 13
      title       = "Airflow web server"
      description = "The web server's address. Opening it directly lands on MWAA's sign-in redirect rather than the UI - use the sign-in link above"
      value       = module.mwaa_environment.webserver_url
    }
    cluster_name = {
      order       = 14
      title       = "EKS cluster name"
      description = "Name of the EKS cluster, which the blueprint named after its name variable like everything else"
      value       = module.eks_cluster.cluster_name
    }
    cluster_endpoint = {
      order       = 15
      title       = "EKS cluster endpoint"
      description = "API server endpoint. Public so the helm and kubectl providers can reach it during apply - narrow public_access_cidrs to your own address"
      value       = module.eks_cluster.cluster_endpoint
    }
    cluster_nodes_command = {
      order       = 16
      title       = "Check the nodes"
      description = "The core node group, three m5.xlarge across three zones to start. The cluster autoscaler adds nodes when a Spark job's executors do not fit"
      value       = "kubectl get nodes -L node.kubernetes.io/instance-type,topology.kubernetes.io/zone"
    }
    autoscaler_status_command = {
      order       = 17
      title       = "Check the cluster autoscaler"
      description = "The status the autoscaler keeps for every node group it manages. An empty list means auto-discovery matched nothing, which looks the same as a cluster that simply needs no more nodes"
      value       = module.cluster_autoscaler.status_command
    }
    emr_virtual_cluster_id = {
      order       = 18
      title       = "EMR virtual cluster ID"
      description = "The connection's virtual_cluster_id, on its own"
      value       = module.emr_virtual_cluster.virtual_cluster_id
    }
    emr_job_role_arn = {
      order       = 19
      title       = "EMR job execution role ARN"
      description = "The connection's job_role_arn, on its own"
      value       = module.emr_virtual_cluster.job_execution_role_arn
    }
    update_kubeconfig_command = {
      order       = 20
      title       = "Re-point kubectl"
      description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
    teardown_command = {
      order       = 21
      title       = "Tearing this down"
      description = "One destroy removes everything, because everything is in this state now - the _monolithic template needed the blueprint's cleanup.sh run from inside the instance first. MWAA's deletion alone takes 20-30 minutes. The connection secret goes at once rather than after Secrets Manager's 30-day recovery window, so applying again straight after does not collide with its name. Left behind: the airflow-<name>-* log groups MWAA creates for itself, which no Terraform resource owns"
      value       = "terraform destroy"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the order field and
  # taking values() - which returns a map's values ordered by key - makes the README read top to
  # bottom while the order stays decided by configuration.
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  readme_body = join("\n", concat(
    ["# ${var.name}", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}
# The work happens inside code-server in a browser, where terraform output is not available, so every
# output above is also written to a README in the home directory the IDE opens (rules.md H-2).
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is what orders this after
    # the bootstrap (rules.md D-5). The marker path comes back out of the module it was passed into,
    # so it is defined once (rules.md B-5).
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
