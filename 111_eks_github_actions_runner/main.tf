data "aws_region" "current" {}
locals {
  key_name = var.key_name == null ? "${var.cluster_name}-key" : var.key_name
  # A repository-level scale set when a repository is named, an organisation-level one when it is not.
  #
  # The repository form reads the URL off the repository this root creates rather than rebuilding it from owner
  # and name, which does two things: the scale set cannot register against a URL that does not exist, and the
  # value reference is what orders the ARC module after the repository (rules.md B-5).
  #
  # The _monolithic template could only produce the repository form, and produced it wrongly twice over: the
  # URL contained a literal UNSUPPORTED_REF_GitHubRepository left behind by the CloudFormation resource that
  # failed to convert, and that same failure meant the repository was never created either.
  github_config_url = var.github_repository == "" ? "https://github.com/${var.github_owner}" : module.github_repository[0].repository_url
  # The workflow seeded into the repository, and the thing that makes this project testable: without a workflow
  # whose runs-on matches the scale set, the runners sit at zero forever and nothing distinguishes that from a
  # broken install.
  #
  # runs-on reads var.runner_set_name rather than module.actions_runner_controller.runner_set_name, which would
  # be the B-5 shape. It cannot: the ARC module already depends on this repository for its URL, so taking the
  # name back out of that module would close a cycle. The root variable is the single source either way.
  #
  # No GitHub expression syntax in here. The ${...} form is Terraform interpolation first, so a $${{ }} escape
  # would be needed for every one - and the environment variables below say the same things without it.
  demo_workflow = <<-WORKFLOW
    # Managed by Terraform (111_eks_github_actions_runner). Edit it here and re-apply, or in GitHub and expect
    # the next apply to put this content back.
    name: arc-demo

    # workflow_dispatch to start it by hand from the Actions tab; push so that committing this file is itself
    # the first run - the pipeline gets exercised by the apply that creates it.
    on:
      workflow_dispatch:
      push:

    jobs:
      where-does-this-run:
        # This one line is what connects this repository to the EKS cluster. It has to equal the runner scale
        # set's name exactly; anything else queues the job forever and reports nothing.
        runs-on: ${var.runner_set_name}
        steps:
          - name: Identify the runner
            run: |
              echo "runner pod:       $HOSTNAME"
              echo "kubernetes api:   $KUBERNETES_SERVICE_HOST"
              echo "eks cluster:      ${var.cluster_name}"
              echo "runner scale set: ${var.runner_set_name}"
          - name: Show that this is a container in the cluster
            run: |
              uname -srm
              sed -n '1,2p' /etc/os-release
              if [ -f /var/run/secrets/kubernetes.io/serviceaccount/token ]; then
                echo "service account token mounted: yes"
              else
                echo "service account token mounted: no"
              fi
          - name: Prove the pod is ephemeral
            run: |
              echo "this pod exists only for run $GITHUB_RUN_NUMBER of $GITHUB_WORKFLOW"
              echo "watch it appear and go: kubectl -n arc-runners get pods -w"
    WORKFLOW
}
# The repository the runner scale set registers against.
#
# This is the resource the _monolithic template declared as AWS::CodeStar::GitHubRepository and the conversion
# dropped, telling the reader to use the GitHub provider instead. Nothing did, and the modularised
# configuration recorded the loss as a documented gap rather than closing it - so the controller asked GitHub
# for a registration token for a repository that did not exist, got a 404, never created a listener, and the
# apply reported success anyway. The module header has the detail.
module "github_repository" {
  source = "./modules/github_repository"
  # None when the scale set is registered at the organisation level: there is no single repository to create,
  # and the organisation already exists (rules.md B-4).
  count = var.github_repository == "" ? 0 : 1

  name       = var.github_repository
  visibility = var.github_repository_visibility
  # Null leaves the repository empty, which is a repository the runners can register with and no workflow to
  # exercise them (rules.md B-4).
  workflow_content = var.seed_demo_workflow ? local.demo_workflow : null

  # Nothing in here touches the VPC. It waits anyway, because the rule is that a root with a network module has
  # no exceptions - one module starting early is one module whose destroy order is also different (rules.md D-3).
  depends_on = [module.network]
}
module "network" {
  source = "./modules/network"

  region                         = data.aws_region.current.region
  vpc_cidr_block                 = var.vpc_cidr_block
  availability_zone_suffixes     = var.availability_zone_suffixes
  nat_availability_zone_suffixes = var.nat_availability_zone_suffixes
  vpc_name                       = "${var.cluster_name}-vpc"
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

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version
  subnet_ids         = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  # Both, as the _monolithic template had them. Public because the providers that install ARC run outside the
  # VPC; private because the nodes reach the API server without leaving it.
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  # Referencing module.network.*_subnet_ids only orders this after the specific aws_subnet resources behind
  # those outputs, not after the NAT gateway and route table associations that never surface as outputs
  # (rules.md D-3).
  depends_on = [module.network]
}
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not exist until this addon creates
  # it. As a DaemonSet it reaches ACTIVE with zero nodes, so it comes before any capacity - and nodes need it
  # to join Ready (rules.md C-4). The _monolithic template declared its four addons with no ordering at all
  # and no bootstrap flag, so EKS installed three of them as unmanaged self-managed addons first and the
  # aws_eks_addon resources then collided with them.
  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as eks_vpc_cni_addon (rules.md C-4).
  depends_on = [module.network, module.eks_vpc_cni_addon]
}
# The runner pods need no AWS credentials of their own, so nothing here uses Pod Identity - but the addon was
# in the _monolithic template and is kept, because it is the mechanism a workflow would use to reach AWS from a
# runner, which is most of the reason to put runners in EKS rather than on a VM.
module "eks_pod_identity_agent_addon" {
  source = "./modules/eks_pod_identity_agent_addon"

  cluster_name = module.eks_cluster.cluster_name

  # A DaemonSet, so it reaches ACTIVE with no nodes and belongs before them (rules.md C-4).
  depends_on = [module.network, module.eks_vpc_cni_addon]
}
module "eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name    = module.eks_cluster.cluster_name
  node_group_name = "${var.cluster_name}-nodegroup"
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

  # coredns is a Deployment and needs schedulable capacity to leave DEGRADED and become ACTIVE (rules.md C-4).
  # The _monolithic template created it alongside the other three with no ordering, so on a cluster with
  # bootstrap addons disabled it would have sat DEGRADED until the node group happened to come up.
  depends_on = [
  module.network, module.eks_node_group]
}
# Actions Runner Controller and one runner scale set.
#
# Installed by the helm and kubectl providers rather than by helm commands in the workbench's user data, which
# is where the _monolithic template had them - after an "exec bash" line that replaced the shell and discarded
# every remaining command, so on a real boot none of it ran (rules.md E-1).
module "actions_runner_controller" {
  source = "./modules/actions_runner_controller"

  chart_version     = var.arc_chart_version
  github_config_url = local.github_config_url
  github_token      = var.github_token
  runner_set_name   = var.runner_set_name
  min_runners       = var.min_runners
  max_runners       = var.max_runners
  container_mode    = var.runner_container_mode

  # The controller and the listener are Deployments, so they need schedulable capacity - and CoreDNS has to be
  # answering before the listener can resolve github.com. Neither is implied by anything in the arguments
  # above (rules.md D-2/D-4).
  #
  # The repository is in the list as well as being referenced through github_config_url. The reference alone
  # orders this after the one github_repository resource; the module edge also covers the workflow file, and
  # on destroy it keeps the scale set being deregistered before the repository it is registered against
  # disappears (rules.md D-2/D-4).
  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon, module.github_repository]
}
# The workbench's role needs cluster access, and joining two modules is the root's job (rules.md C-1).
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name                        = "vscode"
  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_ids[0]
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  security_group_name         = "${var.cluster_name}-vscode-sg"
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  marker_file_path            = var.marker_file_path
  # The cluster security group, so the instance can reach the API server without going out to the public
  # endpoint. Injected as an ID list so the module never learns what it belongs to (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]

  # An EKS cluster and this instance share a root module, so it carries the workbench tooling (rules.md H-1).
  # Docker is the one omission: nothing here builds an image, and a runner pod that needs Docker gets it from
  # the chart's containerMode rather than from this instance.
  #
  # Bugs from the _monolithic template that are not carried over. It ran "exec bash" partway through user
  # data, which replaces the shell and silently discarded everything after it - helm, the kubeconfig and both
  # ARC installs were all below that line, so on a real boot the instance came up with kubectl and nothing
  # else and the project did nothing. It also wrote the "complete" line for the k alias into .bashrc before
  # the line that defines __start_kubectl, so every login printed a "function not found" error
  # (rules.md H-1).
  additional_user_data = <<-EOT
    sudo -Eu ec2-user bash << 'EOF'
    set -euo pipefail
    export HOME=/home/ec2-user
    cd /home/ec2-user
    mkdir -p /home/ec2-user/bin
    curl -sO https://s3.us-west-2.amazonaws.com/amazon-eks/${var.kubectl_download_version}/bin/linux/amd64/kubectl
    chmod +x kubectl
    mv kubectl /home/ec2-user/bin/kubectl
    export PATH=/home/ec2-user/bin:$PATH
    echo 'export PATH=/home/ec2-user/bin:$PATH' >> ~/.bashrc
    # Order matters: kubectl's completion defines __start_kubectl, and that has to exist before complete names
    # it, or every login prints "function not found" (rules.md H-1).
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

  # The _monolithic template declared the policy association and the access entry as unrelated resources, so
  # nothing ordered the association after the entry it depends on (rules.md D-1).
  depends_on = [aws_eks_access_entry.vscode]
}
# Fails the apply when the scale set did not register with GitHub.
#
# It exists because of what this project cannot otherwise detect. The listener is not created by the Helm
# release - the chart's only real object is the AutoscalingRunnerSet custom resource, and helm's wait does not
# wait on custom resources. The controller reconciles that resource afterwards, asks GitHub for a runner
# registration token, and creates the listener only if it gets one. Every Terraform resource is green either
# way, so a wrong token, a wrong URL or a missing repository produced a successful apply and a cluster that
# does nothing - which is exactly how this project was found to be broken.
#
# The listener's existence is the one signal that the token, the URL and the repository all line up, and
# nothing in the Terraform graph can see it. A command on the workbench can.
resource "aws_ssm_association" "verify_runner_registration" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.verify_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on, is what orders this after the bootstrap that installed kubectl
    # (rules.md D-5).
    commands = <<-EOT
      # set -e on the outer script, which is what makes the inner one's failure count. Without it the exit 1
      # below ends only the sudo subshell, the script carries on to touch the marker, and the association's
      # status becomes touch's - so SSM reports Success while its own output says the check failed. That is
      # what this step did on its first run.
      set -e
      until [ -f ${module.vscode_ec2.marker_file_path}/userdata ]; do sleep 10; done
      sudo -Eu ec2-user bash << 'STEP'
      set -euo pipefail
      export HOME=/home/ec2-user
      export PATH=/home/ec2-user/bin:$PATH
      # The controller's namespace, not the runners'. ARC puts the listener next to the controller and records
      # which runner namespace it serves in a label, so looking for it beside the runner pods finds nothing -
      # this check named the runner namespace at first and reported the failure it was built to detect.
      namespace=${module.actions_runner_controller.controller_namespace}
      # Registration is a round trip to GitHub that starts when the controller first reconciles the scale set,
      # and the controller backs off exponentially between attempts - so this polls rather than reading once.
      for attempt in $(seq 1 ${var.verify_attempts}); do
        if [ -n "$(kubectl -n $namespace get autoscalinglistener -o name 2>/dev/null)" ]; then
          break
        fi
        sleep 10
      done
      ${module.actions_runner_controller.runner_scale_set_command}
      ${module.actions_runner_controller.listener_command}
      if [ -z "$(kubectl -n $namespace get autoscalinglistener -o name 2>/dev/null)" ]; then
        # The controller log carries the actual reason, so it goes into this command's output rather than
        # leaving the operator to go and find it. A 404 on the registration-token endpoint is the repository;
        # a 401 is the token; a 403 is a token without the scope.
        echo "no AutoscalingListener exists, so the controller never registered the scale set with GitHub" >&2
        ${module.actions_runner_controller.controller_logs_command} >&2
        exit 1
      fi
      echo "registered: the listener exists, so GitHub accepted the token and the target URL"
      STEP
      touch ${module.vscode_ec2.marker_file_path}/verify_runner_registration
      EOT
  }

  # kubectl on the instance needs the access entry to have been granted, and there is nothing to verify until
  # both charts are installed (rules.md D-2).
  depends_on = [module.vscode_ec2, module.actions_runner_controller, aws_eks_access_policy_association.vscode]
}
locals {
  # Every output this project exposes, defined once. outputs.tf projects these and the README below renders
  # them, so no value expression is written twice (rules.md B-5/H-2).
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here. kubectl is already pointed at the cluster, and the commands below are meant to be run in its terminal"
      value       = module.vscode_ec2.vscode_url
    }
    cluster_name = {
      order       = 2
      title       = "EKS cluster name"
      description = "Name of the EKS cluster the runners run in"
      value       = module.eks_cluster.cluster_name
    }
    github_target = {
      order       = 3
      title       = "What the runners registered with"
      description = "Created by this root, which is the fix for the thing that made this project do nothing. The _monolithic template created it with AWS::CodeStar::GitHubRepository, the conversion dropped that resource as having no Terraform equivalent, and the URL it left behind contained a literal UNSUPPORTED_REF_GitHubRepository - so the controller asked GitHub for a registration token for a repository that did not exist, got a 404, and never created a listener"
      value       = local.github_config_url
    }
    pipeline_test_procedure = {
      order       = 4
      title       = "1. Run the pipeline"
      description = "The workflow was committed by the apply, so its first run has already been queued by that commit. Everything needed to watch it is below: open the watch command in one terminal before dispatching, because a runner pod for a job this small lives under a minute"
      value = var.github_repository == "" ? join("\n", [
        "No repository was created: github_repository is empty, so the scale set is registered at the",
        "organisation level. Add the workflow below to any repository the organisation owns, then run it.",
        ]) : join("\n", [
        "1. watch   : kubectl -n ${module.actions_runner_controller.runner_namespace} get pods -w",
        "2. open    : ${module.github_repository[0].actions_url}",
        "3. run     : select the arc-demo workflow, then Run workflow (or push any commit)",
        "4. expect  : a ${module.actions_runner_controller.runner_set_name}-... pod appears, runs, and is deleted",
        "5. confirm : the job log prints this cluster's name and the pod's own hostname",
        "",
        var.seed_demo_workflow ? "The workflow is ${module.github_repository[0].workflow_path} on branch ${module.github_repository[0].workflow_branch}." : "No workflow was seeded: add one with the runs-on value below.",
      ])
    }
    workflow_snippet = {
      order       = 5
      title       = "2. What makes a workflow land here"
      description = "The seeded workflow already says this. It matters when adding a second workflow or a second repository: runs-on has to match the runner scale set's name exactly, and a workflow naming anything else queues forever and reports nothing - the single most common way this setup appears broken"
      value       = "jobs:\n  build:\n    ${module.actions_runner_controller.workflow_runs_on_snippet}\n    steps:\n      - run: echo \"running on $(hostname) in ${module.eks_cluster.cluster_name}\""
    }
    runner_scale_set_command = {
      order       = 6
      title       = "3. Look at the scale set"
      description = "With minRunners at zero the expected state is the two custom resources and no pods. The listener is not here - see the next entry, which is the thing most likely to be mistaken for a failure"
      value       = module.actions_runner_controller.runner_scale_set_command
    }
    listener_command = {
      order       = 7
      title       = "4. Look at the listener, which is somewhere else"
      description = "The listener runs in the controller's namespace, not the runners'. Looking for it beside the runner pods returns nothing and reads exactly like a scale set that never registered - and no AutoscalingListener anywhere really does mean that, which is what the apply now checks"
      value       = module.actions_runner_controller.listener_command
    }
    watch_runners_command = {
      order       = 8
      title       = "5. Watch a runner appear and disappear"
      description = "Run this before dispatching the workflow. A pod is created for the job and deleted when it finishes - that ephemerality is the whole point of ARC over a persistent self-hosted runner, and it is also why there is nothing left to inspect afterwards"
      value       = "kubectl -n ${module.actions_runner_controller.runner_namespace} get pods -w"
    }
    listener_logs_command = {
      order       = 9
      title       = "6. Read the listener's log"
      description = "It records each job assignment it receives from GitHub. This is where to look when a workflow queues and no runner appears - if the listener logs nothing, GitHub never offered it the job, which points back at runs-on"
      value       = module.actions_runner_controller.listener_logs_command
    }
    controller_logs_command = {
      order       = 10
      title       = "7. Read the controller's log"
      description = "Where a failure to reach GitHub is reported. A 401 here is the token; a 403 is a token without the scope; a 404 on the registration-token endpoint is the repository or the URL"
      value       = module.actions_runner_controller.controller_logs_command
    }
    scaling_bounds = {
      order       = 11
      title       = "Runner scaling bounds, and the real ceiling"
      description = "maxRunners is what ARC will ask for. What it can get is the node group, which nothing scales - so concurrent jobs beyond what two nodes can hold stay Pending rather than failing, which looks like a slow queue"
      value       = "minRunners=${module.actions_runner_controller.min_runners} maxRunners=${module.actions_runner_controller.max_runners}, node group fixed at ${var.node_group_desired_size} x ${join(",", var.node_group_instance_types)}"
    }
    repository_lifecycle = {
      order       = 12
      title       = "Two things about the repository before you destroy anything"
      description = "Both are deliberate and neither is visible in a plan. The visibility differs from the _monolithic template, which created the repository public; a public repository with self-hosted runners lets a pull request from a fork run code on a runner pod inside this VPC, which GitHub's own hardening guide advises against. And this is the only resource here that is not in AWS, so destroying this root reaches outside the account"
      value = var.github_repository == "" ? "No repository is managed here: github_repository is empty, so nothing outside AWS is created or destroyed." : join("\n", [
        "visibility        : ${module.github_repository[0].visibility} (the original was public)",
        "terraform destroy : ${module.github_repository[0].archive_on_destroy ? "archives" : "DELETES"} ${module.github_repository[0].full_name}, with its history and workflow runs",
      ])
    }
    arc_version = {
      order       = 13
      title       = "Chart version"
      description = "Both ARC charts, pinned. The _monolithic template's helm commands took whatever the registry served at boot, so two instances built a week apart ran different controllers"
      value       = module.actions_runner_controller.chart_version
    }
    token_handling = {
      order       = 14
      title       = "Where the GitHub token lives"
      description = "A Kubernetes Secret the chart is pointed at by name. The _monolithic template passed it as a helm --set on a command line inside EC2 user data, which put it in the instance metadata, the cloud-init log and the process list at once - its own parameter description recommended against that"
      value       = "kubectl -n ${module.actions_runner_controller.runner_namespace} get secret github-runner-credentials -o jsonpath='{.metadata.name}'"
    }
    update_kubeconfig_command = {
      order       = 15
      title       = "Re-point kubectl"
      description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
    private_key_command = {
      order       = 16
      title       = "The workbench's SSH private key"
      description = "Written to SSM Parameter Store as a SecureString, which is where CloudFormation puts a generated key pair's private half. Needed only for SSH - code-server is reached over HTTP"
      value       = "aws ssm get-parameter --name /ec2/keypair/${module.key_pair.key_pair_id} --with-decryption --query Parameter.Value --output text"
    }
  }
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
# above is also written to a README in the home directory the IDE opens (rules.md H-2).
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # Waits for the verification step's marker rather than the bootstrap's, so the README describing how to
    # test the pipeline only lands once the runners are known to be registered (rules.md D-5). The marker path
    # comes back out of the module it was passed into (rules.md B-5).
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/verify_runner_registration ]; do sleep 10; done
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_readme
      EOT
  }

  depends_on = [aws_ssm_association.verify_runner_registration]
}
