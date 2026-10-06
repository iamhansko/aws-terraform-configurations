data "aws_region" "current" {}

# The addresses CloudFront's edge locations make origin requests from.
#
# Looked up by name, where the _monolithic template carried a mapping of hardcoded prefix
# list IDs keyed by region. Two things were wrong with that: the IDs are per-region values
# AWS can change, and a region missing from the table failed with an error about a map key
# rather than about a region.
data "aws_ec2_managed_prefix_list" "cloudfront_origin_facing" {
  name = var.cloudfront_prefix_list_name
}

# The managed origin request policy, by name rather than by the UUID the console shows.
data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = var.cloudfront_origin_request_policy_name
}

module "network" {
  source = "./modules/network"

  vpc_cidr_block           = var.vpc_cidr_block
  vpc_name                 = "${var.project_name}-vpc"
  internet_gateway_name    = "${var.project_name}-igw"
  public_subnet_name       = "${var.project_name}-public"
  private_subnet_name      = "${var.project_name}-private"
  public_route_table_name  = "${var.project_name}-public-rt"
  private_route_table_name = "${var.project_name}-private-rt"
  nat_gateway_name         = "${var.project_name}-natgw"
  # No kubernetes.io/role tags. Nothing here asks for a load balancer: a Spark job is driver and
  # executor pods that exit, and the only thing reaching into the cluster is the workbench.
  # Tagging subnets for a controller that is not installed would be a claim the configuration
  # does not back up (rules.md G-1).
  public_subnet_tags  = {}
  private_subnet_tags = {}
}

module "key_pair" {
  source = "./modules/key_pair"

  key_name = "${var.project_name}-key"

  # Nothing here reads a network output, but the root orders every module after the network
  # so the whole VPC - NAT gateways and route tables included - is finished before anything
  # starts in it (rules.md D-3).
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

# vpc-cni and kube-proxy are DaemonSets, so they reach ACTIVE with zero nodes. They come
# before the node group because a node cannot join Ready without them, and with
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

# The node group that runs the cluster's own controllers. Karpenter and the device plugin land
# here, which is not an accident: a controller that provisions nodes cannot depend on the nodes
# it provisions, and the GPU pools are tainted anyway.
#
# The Spark driver and executors do not land here - their pod templates select the x86-cpu
# Karpenter pool, so Karpenter provisions m5 capacity for the job and consolidates it away
# afterwards.
module "eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name    = module.eks_cluster.cluster_name
  node_group_name = var.core_node_group_name
  instance_types  = var.core_node_instance_types
  labels          = var.core_node_labels
  desired_size    = var.core_node_desired_size
  min_size        = var.core_node_min_size
  max_size        = var.core_node_max_size
  key_name        = module.key_pair.key_name
  subnet_ids      = module.network.private_subnet_ids

  depends_on = [module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}

# coredns is a Deployment, so unlike the DaemonSets it needs schedulable node capacity to
# leave DEGRADED and become ACTIVE (rules.md C-4).
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name          = module.eks_cluster.cluster_name
  coredns_replica_count = var.coredns_replica_count

  depends_on = [
  module.network, module.eks_node_group]
}

# Karpenter's controller, its IAM role and the node role its instances assume. The pools
# are separate modules below.
#
# The _monolithic template installed this by writing a shell script onto the bastion from
# user data and running it, so the release existed in no state file - and the script
# exported KARPENTER_VERSION, K8S_VERSION, AWS_ACCOUNT_ID and a TEMPOUT it never used
# (rules.md E-1).
module "karpenter" {
  source = "./modules/karpenter"

  cluster_name      = module.eks_cluster.cluster_name
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  chart_version     = var.karpenter_chart_version

  # The controller runs on the core node group, and its pods need DNS to reach the EKS and
  # EC2 APIs. Neither is expressed by a value reference (rules.md D-2).
  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}

# One module per pool. for_each over a map whose keys are literals in this configuration,
# so they are known at plan time and safe as resource addresses - the values inside
# (subnet IDs, the security group ID, the node role name) are what come from other modules
# (rules.md B-7/B-8).
module "karpenter_node_pool" {
  source   = "./modules/karpenter_node_pool"
  for_each = var.karpenter_node_pools

  name               = each.key
  node_iam_role_name = module.karpenter.node_role_name
  # Private subnets only. Karpenter nodes pull multi-gigabyte model images through the NAT
  # gateways, and nothing outside the VPC has a reason to reach them.
  subnet_ids         = module.network.private_subnet_ids
  security_group_ids = [module.eks_cluster.cluster_security_group_id]

  instance_families     = each.value.instance_families
  instance_sizes        = each.value.instance_sizes
  capacity_types        = each.value.capacity_types
  node_labels           = each.value.node_labels
  taints                = each.value.taints
  ami_alias             = each.value.ami_alias
  block_device_mappings = each.value.block_device_mappings
  instance_store_policy = each.value.instance_store_policy
  cpu_limit             = each.value.cpu_limit
  memory_limit          = each.value.memory_limit

  # The CRDs these instantiate ship with the Karpenter chart, so the release has to be
  # installed first. Stated on the module block rather than injected into the module as a
  # dependency variable, so the module never learns a Helm release exists
  # (rules.md D-2/D-4).
  depends_on = [
  module.network, module.karpenter]
}

# What makes a GPU node's GPUs schedulable. Without it the g5 and g6 nodes join, report
# Ready, and advertise no nvidia.com/gpu - so a pod asking for a GPU stays Pending on a cluster
# that physically has the hardware.
#
# A Helm release rather than the plugin's static DaemonSet manifest applied from a GitHub
# raw URL, which is what the _monolithic template did at a pinned v0.17.1 - neither
# versioned by Helm nor upgradeable (rules.md E-1).
module "nvidia_device_plugin" {
  source = "./modules/nvidia_device_plugin"

  chart_version = var.nvidia_device_plugin_chart_version
  # No time slicing. Nothing in this variant asks for a fraction of a GPU, and splitting one
  # device between pods that each want all of it only makes them contend for memory
  # (rules.md B-4).
  time_slicing_replicas = null

  depends_on = [
  module.network, module.eks_node_group, module.eks_coredns_addon]
}

# What makes the namespace usable by EMR on EKS: the namespace itself, a Role and RoleBinding in
# it, and the service-linked role mapped to a Kubernetes user through aws-auth.
#
# None of this existed in the _monolithic template, which declared a virtual cluster pointed at a
# namespace nothing created - so CreateVirtualCluster failed with "Unauthorized to perform read
# namespace on (big-data)". The mapping has to go through aws-auth rather than an access entry
# because the principal is a service-linked role (rules.md E-6).
module "emr_namespace_access" {
  source = "./modules/emr_namespace_access"

  namespace = var.emr_namespace

  # These are Kubernetes objects, so the cluster's API server has to be reachable and there has to
  # be somewhere for nothing in particular to run - but aws-auth is a ConfigMap the managed node
  # group has already written into, so the node group has to be there first or the merge has
  # nothing to merge with (rules.md D-2/E-6).
  depends_on = [
  module.network, module.eks_node_group, module.eks_coredns_addon]
}

# The virtual cluster, the role its jobs assume, and the bucket and log group a job writes to.
module "emr_virtual_cluster" {
  source = "./modules/emr_virtual_cluster"

  cluster_name = module.eks_cluster.cluster_name
  # Taken from the module that authorised EMR in it rather than restated, so the virtual cluster
  # cannot be bound to a namespace nothing granted access to (rules.md B-5).
  namespace         = module.emr_namespace_access.namespace
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  name              = var.emr_virtual_cluster_name
  bucket_prefix     = "${var.project_name}-"
  log_group_name    = var.emr_log_group_name

  # CreateVirtualCluster reads the namespace as the service-linked role, so the RBAC and the
  # aws-auth mapping have to be in place first. This is the ordering the _monolithic template was
  # missing entirely (rules.md D-2/E-6).
  depends_on = [
  module.network, module.emr_namespace_access]
}

module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name                = "${var.project_name}-bastion"
  vpc_id              = module.network.vpc_id
  subnet_id           = module.network.public_subnet_a_id
  key_name            = module.key_pair.key_name
  instance_type       = var.bastion_instance_type
  code_server_version = var.code_server_version
  security_group_name = "${var.project_name}-bastion-sg"
  # False, as the _monolithic template had it: the only inbound rule is the CloudFront
  # origin-facing prefix list below, so the IDE is reached through the distribution.
  allow_inbound_from_anywhere = var.allow_bastion_inbound_from_anywhere
  ingress_prefix_list_ids     = [data.aws_ec2_managed_prefix_list.cloudfront_origin_facing.id]
  marker_file_path            = var.marker_file_path
  # Carrying the cluster security group is what lets kubectl on this instance reach the API
  # server without leaving the VPC. The module is handed an ID list and never learns what it
  # belongs to (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]
  # An EKS cluster and this instance share a root module, so this instance is the workbench
  # for that cluster and carries all five tools (rules.md H-1).
  #
  # None of them creates anything here. The _monolithic template used this same script to
  # install Karpenter and had an SSM Association apply three Karpenter pools and the device
  # plugin; all of those are provider resources now (rules.md E-1). What is left is what a
  # person needs to watch a node being provisioned.
  additional_user_data = <<-EOT
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server is already running and predates the docker group, so its terminals would
    # not have it without a restart. The _monolithic template commented out the usermod and
    # opened /var/run/docker.sock to 666 instead, which grants the same access to every
    # process on the host.
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
    # Order matters: bash_completion has to be sourced before kubectl's own completion,
    # which is what defines __start_kubectl, and that function has to exist before complete
    # references it. The _monolithic template had the complete line before the source line,
    # so every login printed "function not found" (rules.md H-1).
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
    # Without this - and without the access entry below - kubectl is installed but every
    # command answers "You must be logged in to the server" (rules.md H-1).
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}
    EOF
  EOT

  depends_on = [module.network]
}

# code-server in front of the bastion, so the IDE is served over HTTPS from an edge
# location rather than over plain HTTP from the instance's own address.
module "cloudfront_code_server" {
  source = "./modules/cloudfront_code_server"

  name               = var.project_name
  origin_domain_name = module.vscode_ec2.public_dns
  # The port from the module that configured code-server, so the origin and the listener
  # cannot disagree (rules.md B-5).
  origin_port              = module.vscode_ec2.code_server_port
  origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id
  price_class              = var.cloudfront_price_class

  depends_on = [
  module.network, module.vscode_ec2]
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

  # EKS rejects a policy association for a principal with no access entry yet, and the two
  # resources share only literal argument values, so nothing orders them (rules.md D-1).
  # The _monolithic template had no ordering here at all.
  depends_on = [aws_eks_access_entry.vscode_access_entry]
}

# Not converted, deliberately: the cluster autoscaler.
#
# The _monolithic template created an IRSA role named cluster_autoscaler_role with an
# inline policy for autoscaling and EC2 describe calls - and then left the helm install
# that would have used it commented out, because Karpenter provisions the nodes here.
# The role was a permission granted for a workflow that does not exist, so it is dropped
# rather than carried forward. Adding the cluster autoscaler to a cluster Karpenter also
# manages would give two controllers the same job.

locals {
  # Every output this project exposes, defined once. outputs.tf projects these and the
  # README below renders them, so no value expression is written twice
  # (rules.md B-5/H-2). Adding an entry here is what makes an output possible, which is
  # what keeps the README from falling behind outputs.tf.
  # The Spark job's pod templates, as HCL objects rendered with yamlencode rather than YAML text
  # echoed out of a shell script (rules.md E-3). Two things they carry come from elsewhere in the
  # configuration and were literals in the _monolithic template: the namespace, and the node
  # selector that puts the job on the CPU Karpenter pool (rules.md B-5).
  #
  # Both are deliberately partial. EMR merges them into the pod it builds, so naming the container
  # without configuring it is how an initContainer gets added without taking ownership of the
  # driver's image, resources or arguments - which EMR decides.
  spark_pod_templates = {
    driver = {
      apiVersion = "v1"
      kind       = "Pod"
      metadata = {
        name      = "${var.spark_job_name}-driver"
        namespace = module.emr_virtual_cluster.namespace
      }
      spec = {
        nodeSelector = module.karpenter_node_pool[var.spark_node_pool].node_labels
        initContainers = [{
          name  = "volume-permission"
          image = var.spark_volume_permission_image
          # Spark is told to use /data1 as its scratch directory, and it runs as a non-root user -
          # so something has to create that directory and hand it over first.
          command = ["sh", "-c", "mkdir -p ${var.spark_local_dir}; chown -R 999:1000 ${var.spark_local_dir}"]
        }]
        containers = [{ name = "spark-kubernetes-driver" }]
      }
    }
    executor = {
      apiVersion = "v1"
      kind       = "Pod"
      metadata = {
        name      = "${var.spark_job_name}-exec"
        namespace = module.emr_virtual_cluster.namespace
      }
      spec = {
        nodeSelector = module.karpenter_node_pool[var.spark_node_pool].node_labels
        initContainers = [{
          name    = "volume-permission"
          image   = var.spark_volume_permission_image
          command = ["sh", "-c", "mkdir -p ${var.spark_local_dir}; chown -R 999:1000 ${var.spark_local_dir}"]
        }]
        containers = [{ name = "spark-kubernetes-executor" }]
      }
    }
  }

  # The start-job-run call, as a JSON object rather than a JSON string embedded in a shell script
  # inside a Terraform heredoc - which is what the _monolithic template had, four levels of
  # quoting deep and with every "$VARIABLE" inside single quotes so the shell never expanded them.
  # The paths in its jobDriver were therefore the literal text "$SCRIPTS_S3_PATH/...".
  spark_scripts_uri = "${module.emr_virtual_cluster.bucket_uri}/${module.emr_virtual_cluster.virtual_cluster_id}/${var.spark_job_name}/scripts"
  spark_input_uri   = "${module.emr_virtual_cluster.bucket_uri}/${module.emr_virtual_cluster.virtual_cluster_id}/${var.spark_job_name}/input"
  spark_output_uri  = "${module.emr_virtual_cluster.bucket_uri}/${module.emr_virtual_cluster.virtual_cluster_id}/${var.spark_job_name}/output"

  spark_job_driver = {
    sparkSubmitJobDriver = {
      entryPoint          = "${local.spark_scripts_uri}/pyspark-taxi-trip.py"
      entryPointArguments = [local.spark_input_uri, local.spark_output_uri]
      sparkSubmitParameters = join(" ", [
        "--conf spark.executor.instances=${var.spark_executor_instances}",
      ])
    }
  }

  spark_configuration_overrides = {
    applicationConfiguration = [{
      classification = "spark-defaults"
      properties = {
        "spark.driver.cores"                            = tostring(var.spark_driver_cores)
        "spark.executor.cores"                          = tostring(var.spark_executor_cores)
        "spark.driver.memory"                           = var.spark_driver_memory
        "spark.executor.memory"                         = var.spark_executor_memory
        "spark.kubernetes.driver.podTemplateFile"       = "${local.spark_scripts_uri}/driver-pod-template.yaml"
        "spark.kubernetes.executor.podTemplateFile"     = "${local.spark_scripts_uri}/executor-pod-template.yaml"
        "spark.local.dir"                               = var.spark_local_dir
        "spark.kubernetes.submission.connectionTimeout" = "60000000"
        "spark.kubernetes.submission.requestTimeout"    = "60000000"
        "spark.kubernetes.driver.connectionTimeout"     = "60000000"
        "spark.kubernetes.driver.requestTimeout"        = "60000000"
        "spark.kubernetes.executor.podNamePrefix"       = var.spark_job_name
        "spark.metrics.appStatusSource.enabled"         = "true"
      }
    }]
    monitoringConfiguration = {
      persistentAppUI = "ENABLED"
      cloudWatchMonitoringConfiguration = {
        logGroupName        = module.emr_virtual_cluster.log_group_name
        logStreamNamePrefix = var.spark_job_name
      }
      s3MonitoringConfiguration = {
        logUri = "${module.emr_virtual_cluster.bucket_uri}/logs/"
      }
    }
  }

  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here and run the job from its terminal. It is served through CloudFront over HTTPS; the instance's own port is only open to the CloudFront origin-facing prefix list"
      value       = module.cloudfront_code_server.url
    }
    cluster_name = {
      order       = 2
      title       = "EKS cluster name"
      description = "Name of the EKS cluster the virtual cluster is backed by"
      value       = module.eks_cluster.cluster_name
    }
    emr_virtual_cluster_id = {
      order       = 3
      title       = "EMR virtual cluster"
      description = "The ID a start-job-run call names. It exists only because the namespace was authorised first - the RBAC and the aws-auth mapping the _monolithic template had neither of"
      value       = module.emr_virtual_cluster.virtual_cluster_id
    }
    emr_job_execution_role_arn = {
      order       = 4
      title       = "Job execution role"
      description = "The role a Spark job assumes. Its trust policy matches emr-containers-sa-* in the namespace, because EMR names the service account after this role and the name is not knowable in advance"
      value       = module.emr_virtual_cluster.job_execution_role_arn
    }
    emr_bucket = {
      order       = 5
      title       = "Job data bucket"
      description = "Scripts, input, output and logs. Terraform created it with encryption, public access blocked and force_destroy on - the _monolithic template declared a bare bucket with none of those, so a destroy stopped on it once a job had run"
      value       = module.emr_virtual_cluster.bucket_name
    }
    aws_auth_check_command = {
      order       = 6
      title       = "1. The aws-auth mapping is there"
      description = "Two entries: the EMR service-linked role and the node instance role. If the node entry is gone, something replaced the ConfigMap instead of merging into it and the nodes have left the cluster"
      value       = module.emr_namespace_access.aws_auth_check_command
    }
    emr_access_check_command = {
      order       = 7
      title       = "2. EMR may read the namespace"
      description = "Asks the API server the exact question CreateVirtualCluster asks. A \"no\" here is the \"Unauthorized to perform read namespace\" failure, before it happens"
      value       = module.emr_namespace_access.access_check_command
    }
    upload_job_command = {
      order       = 8
      title       = "3. Upload the scripts and the input data"
      description = "Downloads one month of NYC taxi trip data, copies it enough times to give the executors something to do, and syncs both it and the scripts into the bucket. Several gigabytes, so it takes a few minutes"
      value       = "/home/ec2-user/spark/upload.sh"
    }
    start_job_command = {
      order       = 9
      title       = "4. Start the job"
      description = "Every path and ID in it was substituted by Terraform. The _monolithic template built the same call in a shell script where the paths were single-quoted, so Spark received the literal text \"$SCRIPTS_S3_PATH/pyspark-taxi-trip.py\" as its entry point"
      value       = "/home/ec2-user/spark/start-job.sh"
    }
    job_runs_command = {
      order       = 10
      title       = "5. Watch the job"
      description = "PENDING while Karpenter provisions an m5 node for the driver, then RUNNING, then COMPLETED. FAILED comes with a stateDetails line"
      value       = module.emr_virtual_cluster.job_runs_command
    }
    spark_pods_command = {
      order       = 11
      title       = "6. The driver and executors"
      description = "EMR creates them in the namespace with the pod templates Terraform rendered. The NODE column should show an m5 instance from the x86-cpu Karpenter pool, not one of the core node group's t3s"
      value       = "kubectl -n ${module.emr_virtual_cluster.namespace} get pods -o wide"
    }
    job_log_command = {
      order       = 12
      title       = "7. Read the job log"
      description = "The driver's own output. A job that reaches RUNNING and logs nothing usually could not assume the execution role, which is a trust policy problem rather than a Spark one"
      value       = module.emr_virtual_cluster.job_log_command
    }
    output_listing_command = {
      order       = 13
      title       = "8. The output is written"
      description = "Parquet files under the output prefix are what say the job did its work rather than just finishing"
      value       = module.emr_virtual_cluster.output_listing_command
    }
    update_kubeconfig_command = {
      order       = 14
      title       = "Re-point kubectl"
      description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the order
  # field and taking values() sorts by that instead - values() returns a map's values
  # ordered by key - so the README reads in the order the demo is run.
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
# exist, so every output above is also written to a README in the home directory the IDE
# opens (rules.md H-2). The _monolithic template wrote no README at all here.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is what orders
    # this after the instance bootstrap, and the marker this command leaves behind is what
    # a later association would wait on (rules.md D-5). The marker path comes back out of
    # the module it was passed into, so it is defined in exactly one place
    # (rules.md B-5).
    #
    # SSM runs as root, hence the chown. The heredoc delimiter is quoted and deliberately
    # unlikely to appear in the body: Terraform has already substituted every value, so the
    # shell has no reason to touch a "$" or a backtick in the README - and the commands in
    # it contain both.
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/spark_assets ]; do sleep 10; done
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_readme
      EOT
  }

  depends_on = [aws_ssm_association.spark_job_assets]
}

# The job's assets, delivered onto the workbench.
#
# Four files, none of them a Terraform resource: the two pod templates and the two shell scripts
# are things a person runs, and the job run they start is not infrastructure - EMR creates the
# driver and executor pods, and they exit. What Terraform does own is every value inside them.
#
# The _monolithic template produced the same four files by echoing them out of an SSM Association,
# and its job.sh was the worst of it: the JSON payloads were single-quoted, so the shell never
# expanded "$SCRIPTS_S3_PATH" and Spark received that literal text as its entry point path.
#
# The until loop, not depends_on, is what orders this after the instance bootstrap:
# wait_for_success_timeout_seconds does not reliably wait for the remote command to finish, so the
# step waits for the bootstrap marker and leaves its own (rules.md D-5).
#
# Every heredoc delimiter is quoted and deliberately unlikely to appear in its body. Terraform has
# already substituted every value, so the shell has no reason to touch a "$" or a backtick inside
# a manifest or a JSON payload - and A-4 matters twice over here, since a CRLF file would turn a
# delimiter into TFSOMETHING\r and run the heredoc to the end of the script.
resource "aws_ssm_association" "spark_job_assets" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.spark_assets_timeout_seconds
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
      mkdir -p /home/ec2-user/spark

      cat > /home/ec2-user/spark/driver-pod-template.yaml << 'TFDRIVER'
      ${yamlencode(local.spark_pod_templates.driver)}
      TFDRIVER

      cat > /home/ec2-user/spark/executor-pod-template.yaml << 'TFEXECUTOR'
      ${yamlencode(local.spark_pod_templates.executor)}
      TFEXECUTOR

      cat > /home/ec2-user/spark/pyspark-taxi-trip.py << 'TFPYSPARK'
      ${file("${path.module}/files/spark/pyspark-taxi-trip.py")}
      TFPYSPARK

      cat > /home/ec2-user/spark/job-driver.json << 'TFJOBDRIVER'
      ${jsonencode(local.spark_job_driver)}
      TFJOBDRIVER

      cat > /home/ec2-user/spark/configuration-overrides.json << 'TFOVERRIDES'
      ${jsonencode(local.spark_configuration_overrides)}
      TFOVERRIDES

      # Two scripts rather than one, so the several-gigabyte upload is not repeated every time the
      # job is run. The _monolithic template's single job.sh re-downloaded and re-synced the input
      # data on every invocation.
      cat > /home/ec2-user/spark/upload.sh << 'TFUPLOAD'
      #!/bin/bash
      set -euo pipefail
      cd /home/ec2-user/spark
      # The scripts and the pod templates, which the job's configuration references by S3 path.
      aws s3 cp driver-pod-template.yaml ${local.spark_scripts_uri}/driver-pod-template.yaml
      aws s3 cp executor-pod-template.yaml ${local.spark_scripts_uri}/executor-pod-template.yaml
      aws s3 cp pyspark-taxi-trip.py ${local.spark_scripts_uri}/pyspark-taxi-trip.py
      # One month of trip data, copied to give the executors more than one file to read. Copies
      # rather than more months, because the point is parallelism rather than the data.
      rm -rf /home/ec2-user/spark/input
      mkdir -p /home/ec2-user/spark/input
      curl -fsSL -o /home/ec2-user/spark/input/yellow_tripdata_2022-0.parquet ${var.spark_input_data_url}
      for i in $(seq 1 ${var.spark_input_copies}); do
        cp -f /home/ec2-user/spark/input/yellow_tripdata_2022-0.parquet /home/ec2-user/spark/input/yellow_tripdata_2022-$i.parquet
      done
      aws s3 sync /home/ec2-user/spark/input ${local.spark_input_uri}
      # Removed once uploaded: the copies are several gigabytes and the root volume is not large.
      rm -rf /home/ec2-user/spark/input
      echo "uploaded to ${local.spark_scripts_uri} and ${local.spark_input_uri}"
      TFUPLOAD
      chmod +x /home/ec2-user/spark/upload.sh

      cat > /home/ec2-user/spark/start-job.sh << 'TFSTART'
      #!/bin/bash
      set -euo pipefail
      cd /home/ec2-user/spark
      # The two JSON payloads are passed as file:// rather than inline. That is the fix for the
      # _monolithic template's quoting: nothing here has to survive a shell, so no path can arrive
      # as its own literal name.
      aws emr-containers start-job-run \
        --virtual-cluster-id ${module.emr_virtual_cluster.virtual_cluster_id} \
        --name ${var.spark_job_name} \
        --region ${data.aws_region.current.region} \
        --execution-role-arn ${module.emr_virtual_cluster.job_execution_role_arn} \
        --release-label ${var.spark_release_label} \
        --job-driver file:///home/ec2-user/spark/job-driver.json \
        --configuration-overrides file:///home/ec2-user/spark/configuration-overrides.json
      TFSTART
      chmod +x /home/ec2-user/spark/start-job.sh
      STEP
      touch ${module.vscode_ec2.marker_file_path}/spark_assets
      EOT
  }

  # The IDs and paths inside those files come from the virtual cluster, so it has to exist before
  # they are written - and the workbench has to have finished bootstrapping before anything can be
  # written onto it.
  depends_on = [module.emr_virtual_cluster, module.vscode_ec2]
}
