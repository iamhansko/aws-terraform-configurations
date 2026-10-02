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
  # ACTIVE (rules.md C-4). The operator also needs it: its controller reaches the API
  # server by Service name, and the managed workload is addressed by one.
  depends_on = [
  module.network, module.eks_node_group]
}
# The registry the operator image goes into. Terraform owns the repository; the image is
# built by the step below, because there is no source to build until operator-sdk has
# generated it.
module "operator_ecr" {
  source = "./modules/operator_ecr"

  name      = var.ecr_repository_name
  image_tag = var.ecr_image_tag

  # No network dependency: an ECR repository is a regional resource with nothing in the
  # VPC, so it is one of the few things here that genuinely does not need
  # depends_on = [module.network] (rules.md D-3).

  # module.network's value references only order this after the specific aws_subnet or
  # aws_vpc that produced them, not after the NAT gateway and route tables the network
  # module also owns. depends_on states "after the whole network" (rules.md D-3).
  depends_on = [module.network]
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  root_volume_size            = var.vscode_root_volume_size
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  marker_file_path            = var.marker_file_path
  # Joining the cluster security group is what lets this instance reach the API server.
  # The module is handed an ID list and never learns it belongs to an EKS cluster
  # (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]

  # An EKS cluster and this instance share a root module, so it is the workbench for that
  # cluster and carries all five tools (rules.md H-1). Here docker is not a convenience:
  # the whole project is a container image built on this instance, which is the case H-1
  # names as the reason docker is on the list at all.
  #
  # Three bugs from the _monolithic template are fixed here rather than carried over.
  #
  # It ran "exec bash" partway through, which replaces the shell and silently discarded
  # every remaining line. update-kubeconfig was the first casualty, so the instance came
  # up with no kubeconfig - and every later step in that template ended in kubectl or
  # "make deploy", none of which could have worked (rules.md H-1).
  #
  # It commented out "usermod -aG docker ec2-user" and ran "chmod 666
  # /var/run/docker.sock" instead, which grants every process on the instance full
  # control of the Docker daemon. The group membership is what H-1 calls for, and it is
  # enough: sudo -u recomputes supplementary groups, so the build step below gets the
  # socket without the file mode being touched.
  #
  # And it pulled eksctl from weaveworks; eksctl-io is the project's own org.
  additional_user_data = <<-EOT
    dnf install -yq docker git
    dnf groupinstall -yq "Development Tools"
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server is already running and predates the docker group, so its terminals
    # would not have it without a restart.
    systemctl restart code-server

    # Go from the official tarball rather than the distribution package. operator-sdk's
    # generated Makefile builds controller-gen and kustomize with "go install", against a
    # go.mod whose minimum version tracks the SDK release - and the packaged Go trails it,
    # which surfaces as "go.mod requires go >= x.y" minutes into "make manifests".
    curl -sLO https://go.dev/dl/go${var.go_version}.linux-amd64.tar.gz
    rm -rf /usr/local/go
    tar -C /usr/local -xzf go${var.go_version}.linux-amd64.tar.gz
    rm -f go${var.go_version}.linux-amd64.tar.gz
    echo 'export PATH=/usr/local/go/bin:$PATH' > /etc/profile.d/golang.sh

    sudo -Eu ec2-user bash << 'EOF'
    export HOME=/home/ec2-user
    cd /home/ec2-user
    mkdir -p /home/ec2-user/bin
    curl -sO https://s3.us-west-2.amazonaws.com/amazon-eks/${var.kubectl_download_version}/bin/linux/amd64/kubectl
    chmod +x kubectl
    mv kubectl /home/ec2-user/bin/kubectl
    export PATH=/home/ec2-user/bin:/usr/local/go/bin:$PATH
    echo 'export PATH=/home/ec2-user/bin:/usr/local/go/bin:$PATH' >> ~/.bashrc
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
# about each other, so it belongs in the root (rules.md C-1). Without it "make deploy"
# below ends in "You must be logged in to the server", even though kubectl is installed
# and the kubeconfig is correct (rules.md H-1).
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
  # operator-sdk derives all three of these from the project directory name, so they are
  # computed here rather than restated as literals anywhere they are needed
  # (rules.md B-5). Getting one wrong produces a rollout wait that times out against a
  # Deployment that does not exist, which reads as a failed deploy.
  operator_namespace  = "${var.operator_project_name}-system"
  operator_deployment = "${var.operator_project_name}-controller-manager"
  operator_directory  = "/home/ec2-user/projects/${var.operator_project_name}"
  # The scaffolding names the sample after the group, version and lowercased kind.
  sample_manifest = "config/samples/${var.operator_api_group}_${var.operator_api_version}_${lower(var.operator_kind)}.yaml"
  # The name operator-sdk gives the sample custom resource, and therefore the name the generated
  # controller gives the Deployment it creates for it - the deploy-image plugin names the Deployment
  # after the resource it is reconciling. Derived rather than restated so the two cannot drift
  # (rules.md B-5).
  managed_sample     = "${lower(var.operator_kind)}-sample"
  managed_deployment = local.managed_sample
  # The full group, as it appears on the CRD once the API is generated.
  crd_name = "${lower(var.operator_kind)}s.${var.operator_api_group}.${var.operator_domain}"
}
# Step one: install operator-sdk.
#
# Its own step rather than part of the build below, because it is the part that fails for
# reasons outside the project - a keyserver being unreachable - and separating it means
# the failure names itself instead of appearing halfway through a thirty-minute build.
resource "aws_ssm_association" "operator_sdk" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.operator_sdk_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is what orders
    # this after the bootstrap (rules.md D-5). The marker path comes back out of the
    # module it was passed into, so it is defined once (rules.md B-5).
    commands = <<-EOT
      set -euo pipefail
      until [ -f ${module.vscode_ec2.marker_file_path}/userdata ]; do sleep 10; done
      # dirmngr is what gpg shells out to in order to reach a keyserver, and it is not
      # installed on AL2023 by default. --allowerasing because it conflicts with the
      # minimal gnupg2 package the image ships.
      dnf install -yq dirmngr --allowerasing
      sudo -Eu ec2-user bash << 'STEP'
      set -euo pipefail
      export HOME=/home/ec2-user
      cd /home/ec2-user
      DL=https://github.com/operator-framework/operator-sdk/releases/download/${var.operator_sdk_version}
      curl -sLO $DL/operator-sdk_linux_amd64
      curl -sLO $DL/checksums.txt
      curl -sLO $DL/checksums.txt.asc
      gpg --batch --keyserver ${var.operator_sdk_gpg_keyserver} --recv-keys ${var.operator_sdk_gpg_key_id}
      # Two arguments: the signature and the file it signs. The _monolithic template wrote
      # "gpg -u <name> --verify checksums.txt.asc" instead - -u selects a key for signing
      # and does nothing for a verification, and with the signed file left implicit gpg
      # would have to guess it. The checksum comparison that follows is only meaningful
      # once this has passed, since the binary and the checksum come from the same place.
      gpg --batch --verify checksums.txt.asc checksums.txt
      grep operator-sdk_linux_amd64 checksums.txt | sha256sum -c -
      sudo install -m 0755 operator-sdk_linux_amd64 /usr/local/bin/operator-sdk
      rm -f operator-sdk_linux_amd64 checksums.txt checksums.txt.asc
      operator-sdk version
      STEP
      touch ${module.vscode_ec2.marker_file_path}/operator_sdk
      EOT
  }
}
# Step two: scaffold the operator, build its image, push it, deploy it, and create one
# custom resource for it to act on.
#
# This is the E-1 exception the providers.tf comment sets out. Nothing here could be a
# Terraform resource: the manifests "make deploy" applies are generated by the two
# operator-sdk commands above them, and the image is built from source that does not exist
# until then.
resource "aws_ssm_association" "memcached_operator" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.operator_build_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    commands = <<-EOT
      set -euo pipefail
      until [ -f ${module.vscode_ec2.marker_file_path}/operator_sdk ]; do sleep 10; done
      sudo -Eu ec2-user bash << 'STEP'
      set -euo pipefail
      export HOME=/home/ec2-user
      export PATH=/home/ec2-user/bin:/usr/local/go/bin:$PATH
      # The scaffolding inputs, recorded next to the project so a change to any of them actually
      # reaches the generated code.
      #
      # The PROJECT guard below is necessary - "operator-sdk init" refuses a directory that already
      # holds a project, so without it a re-run fails instead of continuing - but on its own it also
      # makes these three variables inert after the first apply: the generator is skipped, the Go
      # source keeps whatever command it was first given, and "make docker-build" rebuilds an
      # identical image. That is how a corrected operator_container_command would have looked like
      # it had no effect.
      SCAFFOLD_INPUTS='image=${var.operator_managed_image} command=${var.operator_container_command} user=${var.operator_run_as_user}'
      SCAFFOLD_CHANGED=no
      if [ -f ${local.operator_directory}/PROJECT ] && \
         [ "$(cat ${local.operator_directory}/.scaffold_inputs 2>/dev/null)" != "$SCAFFOLD_INPUTS" ]; then
        SCAFFOLD_CHANGED=yes
        # Moved aside rather than deleted, so the superseded project is still there to look at from
        # the IDE and nothing recursive runs on a path built from variables.
        mv ${local.operator_directory} ${local.operator_directory}.superseded.$(date +%s)
      fi
      mkdir -p ${local.operator_directory}
      cd ${local.operator_directory}

      # Guarded on the PROJECT file operator-sdk writes, because an association re-runs
      # whenever its parameters change and "operator-sdk init" refuses a directory that
      # already holds a project. Without this the whole step fails on the second run
      # rather than picking up where it left off.
      if [ ! -f PROJECT ]; then
        operator-sdk init --domain ${var.operator_domain} --repo ${var.operator_go_module}
        # The deploy-image plugin generates a controller that deploys a given image for
        # each custom resource, so the demo has a working operator rather than an empty
        # reconcile loop to fill in.
        operator-sdk create api \
          --group ${var.operator_api_group} \
          --version ${var.operator_api_version} \
          --kind ${var.operator_kind} \
          --plugins="deploy-image/v1-alpha" \
          --image=${var.operator_managed_image} \
          --image-container-command="${var.operator_container_command}" \
          --run-as-user="${var.operator_run_as_user}"
        printf '%s\n' "$SCAFFOLD_INPUTS" > .scaffold_inputs
      fi
      make manifests

      ${module.operator_ecr.login_command}
      make docker-build docker-push IMG=${module.operator_ecr.image}
      make deploy IMG=${module.operator_ecr.image}
      # A rebuild under the same tag produces no rollout on its own, which is why a corrected
      # scaffolding still ran as the old operator.
      #
      # The image reference never changes - it is ${module.operator_ecr.image} every time - so the
      # Deployment "make deploy" applies is byte-identical to the one already there and Kubernetes
      # does nothing. The pod keeps running the image it pulled the first time, and since the
      # controller bakes the managed container's command into its own binary, it keeps creating
      # Deployments from the superseded code. Observed directly: a new image pushed to ECR, and a
      # controller pod still from the original apply, 35 minutes older than the image it claims to
      # run.
      #
      # imagePullPolicy is already Always, so a restart is enough to pick the new image up; the pod
      # just has to be replaced for that policy to apply at all. This is the same step the project's
      # own rebuild_command output tells a human to run by hand.
      kubectl -n ${local.operator_namespace} rollout restart deployment ${local.operator_deployment}

      # Wait for the controller rather than assuming "make deploy" means it is running.
      # The deploy only applies manifests; the image still has to be pulled from ECR by
      # the node, which is where a missing AmazonEC2ContainerRegistryReadOnly or an empty
      # repository would show up. Without this wait the sample below is created against a
      # controller that is not watching yet, and nothing happens.
      kubectl -n ${local.operator_namespace} rollout status deployment ${local.operator_deployment} --timeout=10m \
        || { kubectl -n ${local.operator_namespace} get pods -o wide; kubectl -n ${local.operator_namespace} describe deployment ${local.operator_deployment}; exit 1; }

      kubectl apply -f ${local.sample_manifest}
      # A Deployment created by an earlier controller keeps its old container spec: the generated
      # controller reconciles the replica count and nothing else, so it will not correct a command
      # it did not write. Removing it lets the current controller recreate it.
      #
      # Compared against what this apply asked for rather than gated on whether the scaffolding was
      # regenerated this run. The two come apart: the inputs file is written when the project is
      # generated, so a run that regenerates the code and fails to roll the controller out leaves
      # the inputs looking current while the cluster is still running the old spec - and the next
      # run would then skip the fix. Comparing the live command converges either way.
      DESIRED_COMMAND='${jsonencode(split(",", var.operator_container_command))}'
      CURRENT_COMMAND=$(kubectl get deployment ${local.managed_deployment} -o jsonpath='{.spec.template.spec.containers[0].command}' 2>/dev/null || true)
      if [ -n "$CURRENT_COMMAND" ] && [ "$CURRENT_COMMAND" != "$DESIRED_COMMAND" ]; then
        echo "managed Deployment command is $CURRENT_COMMAND, expected $DESIRED_COMMAND - recreating it"
        kubectl delete deployment ${local.managed_deployment} --ignore-not-found
      fi
      # Then wait for the thing the controller produces, which nothing here used to check.
      #
      # The rollout wait above covers the controller; this covers its output. Without it the
      # association reports Success as soon as the custom resource is accepted, so a managed pod
      # that crash-loops is invisible to Terraform - which is exactly how a container command that
      # memcached rejects shipped as a successful apply.
      attempt=0
      until kubectl get deployment ${local.managed_deployment} >/dev/null 2>&1; do
        attempt=$((attempt + 1))
        if [ "$attempt" -gt 60 ]; then
          echo "the controller never created a Deployment for ${local.managed_sample}"
          kubectl get ${lower(var.operator_kind)} ${local.managed_sample} -o yaml || true
          kubectl -n ${local.operator_namespace} logs deploy/${local.operator_deployment} --tail 50 || true
          exit 1
        fi
        sleep 5
      done
      kubectl rollout status deployment ${local.managed_deployment} --timeout=5m \
        || { kubectl describe deployment ${local.managed_deployment}; kubectl get pods -o wide; kubectl logs deploy/${local.managed_deployment} --tail 30 || true; exit 1; }
      STEP
      touch ${module.vscode_ec2.marker_file_path}/memcached_operator
      EOT
  }

  # Both halves of rules.md D-5, doing different jobs. The marker loop above proves the previous
  # step's remote command finished, which depends_on cannot observe. depends_on decides when this
  # resource is created, and that is what starts its wait_for_success_timeout_seconds clock -
  # without it Terraform creates every association at once and this one spends its whole timeout
  # inside the until loop, failing with "timeout while waiting for state to become 'Success'
  # (last state: 'Pending')" about a command that never ran.
  depends_on = [aws_ssm_association.operator_sdk]
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
      description = "Open the IDE here. The generated operator project is already on disk, and the commands below are meant to be run from its terminal"
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
      description = "API server endpoint. Reached from this instance rather than from the machine running terraform: everything Kubernetes-side here is applied by make deploy, so no Terraform provider ever needed it"
      value       = module.eks_cluster.cluster_endpoint
    }
    operator_project = {
      order       = 4
      title       = "The generated project"
      description = "Where operator-sdk scaffolded the operator. Open it in the IDE: this is the point of the project, and the Terraform configuration exists to give it a cluster and a registry to build against"
      value       = local.operator_directory
    }
    operator_image = {
      order       = 5
      title       = "Operator image"
      description = "Built on this instance and pushed here, then pulled by the controller running on a node. Terraform owns the repository but not the image - there is no source to build until operator-sdk has generated it, which is why this is a build step rather than a resource"
      value       = module.operator_ecr.image
    }
    ecr_image_list_command = {
      order       = 6
      title       = "1. Confirm the image was pushed"
      description = "An empty list means the build step did not reach the push. Check this first if the controller pods are in ImagePullBackOff - it separates a build failure from a registry permission problem"
      value       = module.operator_ecr.image_list_command
    }
    controller_status_command = {
      order       = 7
      title       = "2. Confirm the controller is running"
      description = "The Deployment make deploy created. Its namespace and name are both derived from the project directory name, which is why they are not stated anywhere by hand"
      value       = "kubectl -n ${local.operator_namespace} get deployment ${local.operator_deployment} -o wide && kubectl -n ${local.operator_namespace} get pods"
    }
    crd_command = {
      order       = 8
      title       = "3. Confirm the CRD is registered"
      description = "The custom resource definition the generated API produced. This is what make deploy installs alongside the controller, and what makes the sample below a valid object at all"
      value       = "kubectl get crd ${local.crd_name} -o jsonpath='{.spec.versions[*].name}'"
    }
    custom_resource_command = {
      order       = 9
      title       = "4. Read the custom resource"
      description = "The one sample instance the build step created. Its status is written by the controller, so a resource with no status means the controller is not reconciling even though it is running"
      value       = "kubectl get ${lower(var.operator_kind)} -A -o wide"
    }
    managed_workload_command = {
      order       = 10
      title       = "5. See what the operator built"
      description = "The Deployment the controller created in response to that resource. This is the operator actually working - nothing in Terraform or in the build step asked for these pods"
      value       = "kubectl get deployments,pods -A -l app.kubernetes.io/managed-by=${var.operator_kind}Controller -o wide"
    }
    controller_log_command = {
      order       = 11
      title       = "6. Read the reconcile loop"
      description = "Where a controller that is running but not acting explains itself. An RBAC error here is the usual cause: the generated role covers the kinds the scaffolding knows about, and anything added by hand to the controller needs a matching marker and another make manifests"
      value       = "kubectl -n ${local.operator_namespace} logs deploy/${local.operator_deployment} --tail 100"
    }
    scale_command = {
      order       = 12
      title       = "7. Change the resource and watch it converge"
      description = "Edit the size field on the custom resource and the controller resizes the workload. This is the difference between an operator and a Helm chart: the desired state lives in the cluster, and something is continuously making it true"
      value       = "kubectl edit ${lower(var.operator_kind)} ${lower(var.operator_kind)}-sample"
    }
    rebuild_command = {
      order       = 13
      title       = "8. Rebuild after changing the controller"
      description = "Run from the project directory after editing the reconcile code. Terraform is not involved: the image tag is mutable on purpose, so the same tag is overwritten and the Deployment picks it up on restart"
      value       = "cd ${local.operator_directory} && make manifests && make docker-build docker-push IMG=${module.operator_ecr.image} && kubectl -n ${local.operator_namespace} rollout restart deployment ${local.operator_deployment}"
    }
    update_kubeconfig_command = {
      order       = 14
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
# IDE opens (rules.md H-2). Last in the chain, so the README appears once the operator is
# actually deployed and every check in it has something to report.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # Waits on the build step's marker, not on depends_on (rules.md D-5).
    #
    # SSM runs as root, hence the chown.
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/memcached_operator ]; do sleep 10; done
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_readme
      EOT
  }

  # Both halves of rules.md D-5, doing different jobs. The marker loop above proves the previous
  # step's remote command finished, which depends_on cannot observe. depends_on decides when this
  # resource is created, and that is what starts its wait_for_success_timeout_seconds clock -
  # without it Terraform creates every association at once and this one spends its whole timeout
  # inside the until loop, failing with "timeout while waiting for state to become 'Success'
  # (last state: 'Pending')" about a command that never ran.
  depends_on = [aws_ssm_association.memcached_operator]
}
