data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
locals {
  # Everything named from one value, so the three variants of this project can coexist in one account -
  # which the _monolithic templates could not, since all three derived their names from the same stack name
  # (rules.md B-1).
  key_name                          = var.key_name == null ? "${var.project_name}-key" : var.key_name
  load_balancer_security_group_name = var.load_balancer_security_group_name == null ? "${var.project_name}-nlb-sg" : var.load_balancer_security_group_name
  # The stack tag the pre-created load balancer must carry to be adopted rather than duplicated
  # (rules.md G-3). Derived here rather than read from the pipeline module, because the load balancer needs
  # the tag before that module runs - both sides read the same two variables (rules.md B-5).
  workload_stack_tag = "${var.workload_namespace}/${var.workload_name}"
  # The application, read from the one copy in the project rather than echoed into a shell script three
  # times over. This is a deliberate reach outside the variant directory: src/ is shared reference material
  # for all three variants like a manifests/ directory elsewhere, and duplicating the application into each
  # would be three copies to keep in step. A-1's self-containment rule is about modules, which each variant
  # still owns outright.
  app_source_dir = "${path.root}/../src/fastapi"
  app_files = {
    "Dockerfile"      = file("${local.app_source_dir}/Dockerfile")
    "pyproject.toml"  = file("${local.app_source_dir}/pyproject.toml")
    "api/main.py"     = file("${local.app_source_dir}/api/main.py")
    "api/__init__.py" = file("${local.app_source_dir}/api/__init__.py")
  }
}
module "network" {
  source = "./modules/network"

  vpc_name                 = "${var.project_name}-vpc"
  internet_gateway_name    = "${var.project_name}-igw"
  public_subnet_name       = "${var.project_name}-public"
  private_subnet_name      = "${var.project_name}-private"
  public_route_table_name  = "${var.project_name}-public-rt"
  private_route_table_name = "${var.project_name}-private-rt"
  nat_gateway_name         = "${var.project_name}-natgw"
  # The tags the AWS Load Balancer Controller discovers subnets by (rules.md G-1).
  public_subnet_tags  = var.public_subnet_tags
  private_subnet_tags = var.private_subnet_tags
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

  name                   = "${var.project_name}-cluster"
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  # Referencing module.network.*_subnet_ids only orders this after the specific aws_subnet resources behind
  # those outputs, not after the NAT gateways and route table associations that never surface as outputs
  # (rules.md D-3).
  depends_on = [module.network]
}
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not exist until this addon
  # creates it. As a DaemonSet it reaches ACTIVE with zero nodes, so it comes before any capacity - and
  # nodes need it to join Ready (rules.md C-4). It is also what makes nlb-target-type ip work, by putting
  # pod addresses in the VPC (rules.md G-1).
  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as eks_vpc_cni_addon (rules.md C-4).
  depends_on = [module.network, module.eks_vpc_cni_addon]
}
module "eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name    = module.eks_cluster.cluster_name
  node_group_name = "${var.project_name}-nodegroup"
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

  # coredns is a Deployment and needs schedulable capacity to leave DEGRADED and become ACTIVE
  # (rules.md C-4).
  depends_on = [
  module.network, module.eks_node_group]
}
# What turns the Service the pipeline applies into an NLB. Its IRSA role and Helm release are one module
# (rules.md C-2).
module "aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"

  cluster_name      = module.eks_cluster.cluster_name
  vpc_id            = module.network.vpc_id
  aws_region        = data.aws_region.current.region
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  chart_version     = var.aws_load_balancer_controller_chart_version
  # False, and the Service the pipeline renders deliberately does not set
  # manage-backend-security-group-rules. The _monolithic template's Service set that annotation to "true"
  # while leaving this at the controller's default - the one combination that works - and this is the other
  # one: the path from the load balancer to the pod is the declared rule below, visible in plan
  # (rules.md G-2).
  enable_backend_security_group = false
  # Off: the one Service of type LoadBalancer here names the controller itself with aws-load-balancer-type,
  # so the webhook has nothing to mutate, and its failurePolicy: Fail would otherwise gate a Service created
  # by a pipeline stage on a controller pod being Ready (rules.md G-4).
  enable_service_mutator_webhook = var.enable_service_mutator_webhook

  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}
# Standalone rule resources rather than inline blocks, and revoke_rules_on_delete, because the controller
# may add its own rules to this group (rules.md F-2).
module "load_balancer_security_group" {
  source = "./modules/load_balancer_security_group"

  vpc_id      = module.network.vpc_id
  name        = local.load_balancer_security_group_name
  description = "Frontend security group for the NLB fronting the pipeline-deployed application"
  ports = {
    http = var.workload_service_port
  }
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere

  depends_on = [module.network]
}
# Created here and adopted by the controller, which is what the _monolithic template was reaching for with
# its own aws_lb carrying the three controller tags - but it built that load balancer with the VPC's default
# security group while the Service's annotation asked for a different one, and gave it only two of the
# public subnets. Both are fixed by handing the same values to the load balancer and to the Service
# (rules.md B-5/G-3).
#
# It matters more here than in most of these projects: the Service is created by a pipeline stage rather
# than by Terraform, so without a pre-created load balancer the application's address would not exist until
# a pipeline execution had finished.
module "synced_load_balancer" {
  source = "./modules/synced_load_balancer"

  cluster_name       = module.eks_cluster.cluster_name
  load_balancer_type = "network"
  internal           = false
  subnet_ids         = module.network.public_subnet_ids
  security_group_ids = [module.load_balancer_security_group.security_group_id]
  # service.k8s.aws/*, not ingress.k8s.aws/*: this fronts a Service of type LoadBalancer (rules.md G-3).
  resource_tag_prefix = "service"
  stack               = local.workload_stack_tag

  depends_on = [module.network]
}
# With manage-backend-security-group-rules unset the controller writes no node-side rules at all, so the
# path from load balancer to pod has to be declared here or every target stays unhealthy with no error
# anywhere (rules.md G-2). nlb-target-type is ip, so traffic arrives at the application's container port.
#
# It modifies the cluster security group, which no module here owns outright, so it belongs in the root
# (rules.md C-1).
resource "aws_vpc_security_group_ingress_rule" "load_balancer_to_pods" {
  security_group_id            = module.eks_cluster.cluster_security_group_id
  description                  = "Application container port from the NLB frontend security group"
  ip_protocol                  = "tcp"
  from_port                    = var.workload_container_port
  to_port                      = var.workload_container_port
  referenced_security_group_id = module.load_balancer_security_group.security_group_id
}
# The pipeline's source: an archive of the application in S3. Uploading a new one is the event that starts a
# run, which is the one thing that differs between this variant and its two siblings.
#
# The bucket owns the object key and re-exposes it, so the source stage, the trigger's event pattern and the
# IAM statement below all read one value (rules.md B-5).
module "source_bucket" {
  source = "./modules/s3_source_bucket"

  name                               = var.project_name
  object_key                         = var.source_object_key
  noncurrent_version_expiration_days = var.source_archive_versions_kept_days

  # A bucket is not a VPC resource and needs nothing from the network module, but every module block in
  # a root that has one waits for all of it (rules.md D-3).
  depends_on = [module.network]
}
# The registry the pipeline builds into. Nothing watches it here - that is the ECR-source variant - so it is
# purely downstream of the image build stage.
module "ecr_repository" {
  source = "./modules/ecr_repository"

  name = "${var.project_name}-app"

  # A registry is not a VPC resource and needs nothing from the network module, but every module block
  # in a root that has one waits for all of it, so that a destroy tears down in one order and a reader
  # does not have to work out which modules are exceptions (rules.md D-3).
  depends_on = [module.network]
}
# The pipeline. Four stages, where the ECR-source variant has three: the source is a directory tree rather
# than a built image, so something has to turn it into one before the manifest can name it.
module "pipeline" {
  source = "./modules/eks_deploy_pipeline"

  name         = var.project_name
  cluster_name = module.eks_cluster.cluster_name
  cluster_arn  = module.eks_cluster.cluster_arn
  # The deploy stage creates a network interface in the VPC and talks to the cluster's API server through it,
  # so it needs the cluster security group and a subnet with a route out.
  deploy_security_group_ids = [module.eks_cluster.cluster_security_group_id]
  deploy_subnet_ids         = module.network.private_subnet_ids
  ecr_repository_name       = module.ecr_repository.name
  ecr_repository_arn        = module.ecr_repository.arn
  image_tags                = var.image_tag
  source_action = {
    name     = "S3SourceAction"
    provider = "S3"
    configuration = {
      S3Bucket    = module.source_bucket.bucket_name
      S3ObjectKey = module.source_bucket.object_key
      # False, which the _monolithic template left unset - and unset means true. It got both change
      # detection mechanisms at once: the EventBridge rule started a run on upload, and the pipeline also
      # polled the object every minute for the rest of its life. AWS recommends against polling, and with a
      # rule in place it is pure duplication.
      #
      # A string, because every value in a stage configuration map is a string whatever it represents.
      PollForSourceChanges = "false"
    }
    # No namespace: the S3 source exports no variable any later stage reads. The image the manifest names
    # comes from the image build stage's own namespace instead.
  }
  source_role_policy_statements = [
    {
      Effect = "Allow"
      # Scoped to the one object the source stage reads, where the _monolithic template granted these on the
      # bucket and everything in it. The pipeline reads one key.
      Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:GetObjectTagging", "s3:GetObjectVersionTagging"]
      Resource = [module.source_bucket.object_arn]
    },
    {
      # Bucket-level reads, which cannot be scoped to a key: CodePipeline checks that versioning is on before
      # it reads an object version.
      Effect   = "Allow"
      Action   = ["s3:GetBucketVersioning", "s3:GetBucketLocation"]
      Resource = [module.source_bucket.bucket_arn]
    },
  ]
  # The stage that turns the uploaded tree into an image. It is a CodePipeline action rather than a docker
  # build on the workbench, so the build that produces what runs in the cluster happens in the pipeline -
  # and the manifest names the digest that stage published rather than a moving tag.
  include_image_build_stage = true
  workload_name             = var.workload_name
  workload_namespace        = var.workload_namespace
  workload_replicas         = var.workload_replicas
  workload_container_port   = var.workload_container_port
  workload_service_port     = var.workload_service_port
  service_annotations = {
    # The switch that decides whether any of the others mean anything. Without it the in-tree cloud provider
    # claims the Service and builds a Classic Load Balancer, ignoring the scheme, the target type and the
    # security group - and the pre-created NLB is never adopted (rules.md G-1). The _monolithic template's
    # Service manifest did not set it.
    "service.beta.kubernetes.io/aws-load-balancer-type" = "external"
    # Has to agree with internal = false and the public subnets above (rules.md G-3).
    "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
    # nlb-target-type, not target-type: the Service spelling carries the nlb- prefix (rules.md G-1).
    "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
    # Only the frontend group, and no manage-backend-security-group-rules: the path to the pod is the rule
    # declared above rather than something the controller writes (rules.md G-2).
    "service.beta.kubernetes.io/aws-load-balancer-security-groups" = module.load_balancer_security_group.security_group_id
  }

  # The load balancer has to exist before the controller reconciles the Service the deploy stage applies, or
  # the controller builds its own and the pre-created one is orphaned (rules.md G-3). The controller itself
  # has to be running for the same reason.
  depends_on = [
    module.network,
    module.eks_node_group,
    module.eks_coredns_addon,
    module.aws_load_balancer_controller,
    module.synced_load_balancer,
  ]
}
# What starts the pipeline on an upload. With PollForSourceChanges off this rule is the only thing that
# does, so without it the pipeline only runs when started by hand.
module "pipeline_trigger" {
  source = "./modules/s3_upload_pipeline_trigger"

  name          = var.project_name
  bucket_name   = module.source_bucket.bucket_name
  object_key    = module.source_bucket.object_key
  pipeline_arn  = module.pipeline.pipeline_arn
  pipeline_name = module.pipeline.pipeline_name
  enabled       = var.enable_pipeline_trigger

  # The rule matches the S3 event notifications the bucket emits, and that flag is a separate resource from
  # the bucket itself - referencing the bucket's name orders this after the bucket and nothing else
  # (rules.md D-2). A rule that exists before notifications are on matches nothing.
  depends_on = [module.network, module.source_bucket]
}
# The deploy stage authenticates to the cluster as the pipeline's role, so the cluster has to know that
# principal. Without this the stage fails with an authentication error rather than a permissions one, and the
# pipeline's own IAM policy looks like the place to fix it.
#
# Joining the pipeline module and the cluster module is the root's job (rules.md C-1).
resource "aws_eks_access_entry" "pipeline" {
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.pipeline.pipeline_role_arn
  type          = "STANDARD"
}
resource "aws_eks_access_policy_association" "pipeline" {
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.pipeline.pipeline_role_arn
  # Admin on the cluster, as the _monolithic template granted. A narrower policy would be
  # AmazonEKSEditPolicy scoped to the one namespace the stage applies into - worth doing for anything
  # longer lived than a demo, and it is the access entry rather than the IAM policy that would carry it.
  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.pipeline]
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  marker_file_path            = var.marker_file_path
  extra_security_group_ids    = [module.eks_cluster.cluster_security_group_id]

  # An EKS cluster and this instance share a root module, so it is the workbench for that cluster and carries
  # all five tools (rules.md H-1). Docker is one of them even though nothing here uses it: the image is built
  # by a pipeline stage in this variant, not on this machine. H-1 asks for all five anyway, and the reason
  # holds - a build daemon is the one thing on a workbench that cannot become a provider resource, and the
  # ECR-source sibling does use it.
  #
  # zip is added because the upload step needs it and Amazon Linux 2023 does not ship it. The _monolithic
  # template's SSM association ran "zip -r src.zip ./" without installing it, on an instance whose only
  # package installs were git and Development Tools.
  #
  # Bugs from the _monolithic template that are not carried over. It ran "exec bash" partway through user
  # data, which replaces the shell and silently discarded every remaining line - eksctl, helm, the AWS Load
  # Balancer Controller install and the kubeconfig were all after it, so on a real boot none of them ran. It
  # pulled eksctl from weaveworks rather than eksctl-io. And it wrote the "complete" line for the k alias
  # into .bashrc before the line that defines __start_kubectl, so every login printed a "function not found"
  # error (rules.md H-1).
  additional_user_data = <<-EOT
    dnf install -yq docker zip
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server is already running and predates the docker group, so its terminals would not have it
    # without a restart. This is the alternative to opening the socket to everyone with chmod 666, which is
    # what the ECR-source template did.
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
    # Order matters: kubectl's completion defines __start_kubectl, and that has to exist before complete
    # names it, or every login prints "function not found" (rules.md H-1).
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

  depends_on = [aws_eks_access_entry.vscode]
}
# Writes the application onto the workbench, packages it and uploads it, which is what starts the pipeline.
#
# This is the counterpart of the ECR-source variant's docker build, and it is a much smaller thing: no
# daemon, no registry login, no base image pull - a zip and a copy. Everything the image needs is in the
# archive, and the pipeline's image build stage does the rest.
#
# What changed from the _monolithic template is where the application comes from. It echoed the Dockerfile,
# the pyproject and the Python source into the script as quoted strings, so the application existed only
# inside a shell heredoc inside an SSM parameter. Here the files come from the project's src/fastapi
# directory and are written out by a loop over a map, so the application has one copy (rules.md B-5).
resource "aws_ssm_association" "source_upload" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.source_upload_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is what orders this after the
    # bootstrap (rules.md D-5). The marker path comes back out of the module it was passed into
    # (rules.md B-5).
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/userdata ]; do sleep 10; done
      sudo -Eu ec2-user bash << 'STEP'
      set -euo pipefail
      export HOME=/home/ec2-user
      export PATH=/home/ec2-user/bin:$PATH
      mkdir -p /home/ec2-user/src/api
      %{for path, content in local.app_files~}
      cat > /home/ec2-user/src/${path} << 'TFAPPFILE'
      ${content}
      TFAPPFILE
      %{endfor~}
      cd /home/ec2-user/src
      # The archive is written to the home directory rather than into src, because writing it inside the
      # directory being packaged means the next run packs the previous archive into itself.
      rm -f /home/ec2-user/${module.source_bucket.object_key}
      zip -rq /home/ec2-user/${module.source_bucket.object_key} .
      aws s3 cp /home/ec2-user/${module.source_bucket.object_key} ${module.source_bucket.source_uri}
      STEP
      touch ${module.vscode_ec2.marker_file_path}/source_upload
      EOT
  }

  # The pipeline and its trigger have to exist before the upload, or the upload happens and nothing reacts to
  # it - which looks like a broken trigger rather than a race (rules.md D-2).
  depends_on = [module.pipeline, module.pipeline_trigger, aws_eks_access_policy_association.pipeline]
}
locals {
  # Every output this project exposes, defined once. outputs.tf projects these and the README below renders
  # them, so no value expression is written twice (rules.md B-5/H-2).
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here. The application source is in ~/src, which is what the bootstrap packaged and uploaded - edit it and upload again to watch the pipeline run"
      value       = module.vscode_ec2.vscode_url
    }
    application_url = {
      order       = 2
      title       = "Application URL"
      description = "The address is known from state because Terraform created the load balancer and the controller adopted the Service the pipeline applied (rules.md G-3). It answers only after a pipeline execution has deployed the application - before that the load balancer exists with no targets"
      value       = "${module.synced_load_balancer.url}/docs"
    }
    cluster_name = {
      order       = 3
      title       = "EKS cluster name"
      description = "Name of the EKS cluster. The pipeline's deploy stage names it too, and authenticates to it as the pipeline's role"
      value       = module.eks_cluster.cluster_name
    }
    pipeline = {
      order       = 4
      title       = "The pipeline and what starts it"
      description = "Four stages, where the ECR-source variant has three: the source is a directory tree rather than a built image, so a stage has to turn it into one before the manifest can name it"
      value       = "${module.pipeline.pipeline_name}: ${join(" -> ", module.pipeline.stage_names)}\ntrigger: upload to ${module.pipeline_trigger.watched_object} (enabled=${module.pipeline_trigger.enabled})"
    }
    source_archive = {
      order       = 5
      title       = "The source"
      description = "The archive the pipeline reads. Uploading a new one is the source event - the pipeline does not poll for it, because the source stage sets PollForSourceChanges to false and the EventBridge rule above does that job"
      value       = module.source_bucket.source_uri
    }
    ecr_repository = {
      order       = 6
      title       = "Container registry"
      description = "Where the image build stage pushes. Nothing watches it in this variant, which is the difference from the ECR-source sibling - here it is downstream of the source rather than being it. The lifecycle policy removes the untagged leftovers every run over a moving tag creates"
      value       = "${module.ecr_repository.repository_url}:${var.image_tag}"
    }
    pipeline_state_command = {
      order       = 7
      title       = "1. Read the pipeline's state"
      description = "Every stage and how its last run ended. The deploy stage failing on authentication rather than permissions is the interesting case: that is the EKS access entry for the pipeline's role, not its IAM policy"
      value       = module.pipeline.state_command
    }
    build_log_command = {
      order       = 8
      title       = "2. Read the build log"
      description = "The build stage prints the manifest it rendered, so a deploy stage that failed on a malformed manifest can be diagnosed from here. This is also where the digest the image build stage published becomes visible, since the manifest names the image by digest rather than by tag"
      value       = module.pipeline.build_log_command
    }
    workload_command = {
      order       = 9
      title       = "3. Look at what the pipeline deployed"
      description = "The Deployment carries labels naming the CodeBuild build and the pipeline execution that produced it, which is the only record of which run the running pods came from"
      value       = "kubectl -n ${module.pipeline.workload_namespace} get deploy,pods,svc -l app.kubernetes.io/name=${module.pipeline.workload_name} -o wide"
    }
    provenance_command = {
      order       = 10
      title       = "4. Ask the cluster which execution deployed it"
      description = "Compare this against the pipeline's latest successful execution. A mismatch means the last run did not reach the cluster - which is not otherwise visible, because the previous deployment is still running happily"
      value       = "kubectl -n ${module.pipeline.workload_namespace} get deploy ${module.pipeline.workload_name} -o jsonpath='{.metadata.labels}'"
    }
    reupload_command = {
      order       = 11
      title       = "5. Change the application and watch the pipeline run"
      description = "Edit ~/src/api/main.py in the IDE, then repackage and upload. The upload is the source event, so nothing else has to be started - and with the trigger disabled this does nothing, which is the comparison worth making once"
      value       = module.source_bucket.upload_command
    }
    archive_versions_command = {
      order       = 12
      title       = "6. Read the versions of the archive"
      description = "Every upload, which is the record of how many times the pipeline was triggered this way. Versioning cannot be turned off on a CodePipeline S3 source, so the lifecycle rule is what keeps this list from growing forever"
      value       = module.source_bucket.object_versions_command
    }
    image_list_command = {
      order       = 13
      title       = "7. Read the images in the registry"
      description = "Oldest first. Every run pushes over the same tag and leaves the previous image untagged, and the lifecycle policy is what removes them"
      value       = module.ecr_repository.list_images_command
    }
    adopted_load_balancer_check_command = {
      order       = 14
      title       = "8. Confirm the load balancer was adopted, not duplicated"
      description = "Lists every load balancer tagged for this cluster. One is correct. Two means the controller did not adopt the pre-created one and built its own, which is a tag mismatch rather than an error - and the application URL above would then point at the one with no listeners (rules.md G-3)"
      value       = "aws resourcegroupstaggingapi get-resources --tag-filters Key=elbv2.k8s.aws/cluster,Values=${module.eks_cluster.cluster_name} --resource-type-filters elasticloadbalancing:loadbalancer --query 'ResourceTagMappingList[].ResourceARN' --output table"
    }
    trigger_failure_command = {
      order       = 15
      title       = "9. If an upload starts nothing"
      description = "Whether the EventBridge rule fired and failed to start the pipeline. A rule whose role cannot start it reports nothing anywhere else - no execution is created, so the pipeline's history is empty, and the rule itself matched successfully. If the metric is empty too, the rule never matched: check that the bucket is emitting Object Created events at all"
      value       = module.pipeline_trigger.failed_invocation_command
    }
    manual_execution_command = {
      order       = 16
      title       = "10. Start the pipeline without an upload"
      description = "Useful for separating a source problem from a build or deploy problem: if this succeeds and an upload does nothing, the trigger is the part to look at"
      value       = module.pipeline.execution_command
    }
    update_kubeconfig_command = {
      order       = 17
      title       = "Re-point kubectl"
      description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
  }
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
# The work happens inside code-server in a browser, where terraform output is not available, so every output
# above is also written to a README in the home directory the IDE opens (rules.md H-2).
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # Waits for the upload step's marker rather than the bootstrap's, so the README lands after the first
    # pipeline execution has been started - which is when its commands become useful (rules.md D-5).
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/source_upload ]; do sleep 10; done
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_readme
      EOT
  }

  depends_on = [aws_ssm_association.source_upload]
}
