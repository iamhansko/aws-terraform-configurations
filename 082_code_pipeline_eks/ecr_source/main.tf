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
# The registry, and in this variant the pipeline's source: pushing over the image tag is the event.
module "ecr_repository" {
  source = "./modules/ecr_repository"

  name = "${var.project_name}-app"

  # A registry is not a VPC resource and needs nothing from the network module, but every module block
  # in a root that has one waits for all of it, so that a destroy tears down in one order and a reader
  # does not have to work out which modules are exceptions (rules.md D-3).
  depends_on = [module.network]
}
# The pipeline. Three stages here, because the source already holds a built image - the two sibling
# variants take a source tree instead and need a fourth stage to turn it into one.
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
    name     = "EcrSourceAction"
    provider = "ECR"
    configuration = {
      RepositoryName = module.ecr_repository.name
      ImageTag       = var.image_tag
    }
    # Required for this provider: the build stage reads #{SourceVariables.ImageURI} from it, which is the
    # digest-pinned URI of the image that triggered the run rather than the moving tag.
    namespace = "SourceVariables"
  }
  source_role_policy_statements = [{
    Effect   = "Allow"
    Action   = ["ecr:DescribeImages"]
    Resource = module.ecr_repository.arn
  }]
  # No image build stage: the image already exists, and pushing it is what started the pipeline.
  include_image_build_stage = false
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
# What starts the pipeline on a push. CodePipeline's ECR source does not poll, so without this the pipeline
# only runs when started by hand.
module "pipeline_trigger" {
  source = "./modules/ecr_push_pipeline_trigger"

  name            = var.project_name
  repository_name = module.ecr_repository.name
  image_tag       = var.image_tag
  pipeline_arn    = module.pipeline.pipeline_arn
  pipeline_name   = module.pipeline.pipeline_name
  enabled         = var.enable_pipeline_trigger

  # An EventBridge rule is not a VPC resource either, and the same reasoning applies (rules.md D-3).
  depends_on = [module.network]
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
  # all five tools (rules.md H-1). Docker earns its place here rather than being installed on principle:
  # building and pushing the application image is what starts the pipeline, and a build needs a daemon - it
  # is the one thing in this repository that cannot become a provider resource.
  #
  # Bugs from the _monolithic template that are not carried over. It ran "exec bash" partway through, which
  # replaces the shell and silently discarded every remaining line - eksctl, helm, the AWS Load Balancer
  # Controller install and the kubeconfig were all after it, so on a real boot none of them ran. It pulled
  # eksctl from weaveworks rather than eksctl-io. It wrote the "complete" line for the k alias into .bashrc
  # before the line that defines __start_kubectl, so every login printed a "function not found" error
  # (rules.md H-1). And its SSM association ran "chmod 666 /var/run/docker.sock" to get docker working for
  # ec2-user - which opens the daemon to every process on the instance; the group membership and a
  # code-server restart do the same job.
  additional_user_data = <<-EOT
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server is already running and predates the docker group, so its terminals - and anything the
    # image build below runs through them - would not have it without a restart. This is the alternative to
    # opening the socket to everyone.
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
# Builds the application image on the workbench and pushes it, which is what starts the pipeline.
#
# This stays a shell step rather than becoming a provider resource, and it is the one place in this
# repository where that is the right answer: a docker build needs a daemon, and there is no Terraform
# resource for "build this image" (rules.md H-1). What changed is where the application comes from - the
# _monolithic template echoed the Dockerfile, the pyproject and the Python source into the script as
# quoted strings, so the application existed only inside a shell heredoc inside an SSM parameter. Here the
# files come from the project's src/fastapi directory and are written out by a loop over a map, so the
# application has one copy (rules.md B-5).
resource "aws_ssm_association" "image_build" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.image_push_timeout_seconds
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
      aws ecr get-login-password --region ${data.aws_region.current.region} | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com
      docker build -t ${module.ecr_repository.repository_url}:${var.image_tag} /home/ec2-user/src
      docker push ${module.ecr_repository.repository_url}:${var.image_tag}
      STEP
      touch ${module.vscode_ec2.marker_file_path}/image_push
      EOT
  }

  # The pipeline and its trigger have to exist before the push, or the push happens and nothing reacts to it
  # - which looks like a broken trigger rather than a race (rules.md D-2).
  depends_on = [module.pipeline, module.pipeline_trigger, aws_eks_access_policy_association.pipeline]
}
locals {
  # Every output this project exposes, defined once. outputs.tf projects these and the README below renders
  # them, so no value expression is written twice (rules.md B-5/H-2).
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here. The application source is in ~/src, which is what the bootstrap built and pushed - edit it and push again to watch the pipeline run"
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
      description = "Three stages, because the source already holds a built image: pushing over the tag is the event. The two sibling variants take a source tree instead and need a fourth stage to build the image"
      value       = "${module.pipeline.pipeline_name}: ${join(" -> ", module.pipeline.stage_names)}\ntrigger: push to ${module.pipeline_trigger.watched_image} (enabled=${module.pipeline_trigger.enabled})"
    }
    ecr_repository = {
      order       = 5
      title       = "Container registry"
      description = "Where the workbench pushed the image, and what the source stage watches. The lifecycle policy removes the untagged leftovers every push over a moving tag creates - without one the repository grows by an image per run forever"
      value       = "${module.ecr_repository.repository_url}:${var.image_tag}"
    }
    pipeline_state_command = {
      order       = 6
      title       = "1. Read the pipeline's state"
      description = "Every stage and how its last run ended. The deploy stage failing on authentication rather than permissions is the interesting case: that is the EKS access entry for the pipeline's role, not its IAM policy"
      value       = module.pipeline.state_command
    }
    build_log_command = {
      order       = 7
      title       = "2. Read the build log"
      description = "The build stage prints the manifest it rendered, so a deploy stage that failed on a malformed manifest can be diagnosed from here. The log group now has a retention period, where the original let CodeBuild create one that never expires"
      value       = module.pipeline.build_log_command
    }
    workload_command = {
      order       = 8
      title       = "3. Look at what the pipeline deployed"
      description = "The Deployment carries labels naming the CodeBuild build and the pipeline execution that produced it, which is the only record of which run the running pods came from"
      value       = "kubectl -n ${module.pipeline.workload_namespace} get deploy,pods,svc -l app.kubernetes.io/name=${module.pipeline.workload_name} -o wide"
    }
    provenance_command = {
      order       = 9
      title       = "4. Ask the cluster which execution deployed it"
      description = "Compare this against the pipeline's latest successful execution. A mismatch means the last run did not reach the cluster - which is not otherwise visible, because the previous deployment is still running happily"
      value       = "kubectl -n ${module.pipeline.workload_namespace} get deploy ${module.pipeline.workload_name} -o jsonpath='{.metadata.labels}'"
    }
    rebuild_command = {
      order       = 10
      title       = "5. Change the application and watch the pipeline run"
      description = "Edit ~/src/api/main.py in the IDE, then rebuild and push. The push is the source event, so nothing else has to be started - and with the trigger disabled this does nothing, which is the comparison worth making once"
      value       = "cd ~/src && docker build -t ${module.ecr_repository.repository_url}:${var.image_tag} . && docker push ${module.ecr_repository.repository_url}:${var.image_tag}"
    }
    image_list_command = {
      order       = 11
      title       = "6. Read the images in the registry"
      description = "Oldest first. Every push over the moving tag leaves the previous image untagged, and the lifecycle policy is what removes them"
      value       = module.ecr_repository.list_images_command
    }
    adopted_load_balancer_check_command = {
      order       = 12
      title       = "7. Confirm the load balancer was adopted, not duplicated"
      description = "Lists every load balancer tagged for this cluster. One is correct. Two means the controller did not adopt the pre-created one and built its own, which is a tag mismatch rather than an error - and the application URL above would then point at the one with no listeners (rules.md G-3)"
      value       = "aws resourcegroupstaggingapi get-resources --tag-filters Key=elbv2.k8s.aws/cluster,Values=${module.eks_cluster.cluster_name} --resource-type-filters elasticloadbalancing:loadbalancer --query 'ResourceTagMappingList[].ResourceARN' --output table"
    }
    trigger_failure_command = {
      order       = 13
      title       = "8. If a push starts nothing"
      description = "Whether the EventBridge rule fired and failed to start the pipeline. A rule whose role cannot start it reports nothing anywhere else - no execution is created, so the pipeline's history is empty, and the rule itself matched successfully"
      value       = module.pipeline_trigger.failed_invocation_command
    }
    manual_execution_command = {
      order       = 14
      title       = "9. Start the pipeline without a push"
      description = "Useful for separating a source problem from a build or deploy problem: if this succeeds and a push does nothing, the trigger is the part to look at"
      value       = module.pipeline.execution_command
    }
    update_kubeconfig_command = {
      order       = 15
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
    # Waits for the image push step's marker rather than the bootstrap's, so the README lands after the first
    # pipeline execution has been started - which is when its commands become useful (rules.md D-5).
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/image_push ]; do sleep 10; done
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_readme
      EOT
  }

  depends_on = [aws_ssm_association.image_build]
}
