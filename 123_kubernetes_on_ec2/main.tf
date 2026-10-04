data "aws_region" "current" {}

module "network" {
  source = "./modules/network"

  region                         = data.aws_region.current.region
  vpc_cidr_block                 = var.vpc_cidr_block
  availability_zone_suffixes     = var.availability_zone_suffixes
  nat_availability_zone_suffixes = var.nat_availability_zone_suffixes
  vpc_name                       = "${var.project_name}-vpc"
  # No kubernetes.io/role tags. There is no cloud controller manager in this cluster -
  # kubeadm on EC2 with no AWS integration - so nothing reads subnet tags, and a
  # Service of type LoadBalancer here would stay Pending forever. The ingress is a
  # hostPort on one node with an Elastic IP instead.
  subnet_tags = {}
}

module "key_pair" {
  source = "./modules/key_pair"

  key_name = "${var.project_name}-key"

  # Nothing here reads a network output, but the root orders every module after the
  # network so the whole VPC - NAT gateway and route tables included - is finished
  # before anything starts in it (rules.md D-3).
  depends_on = [module.network]
}

# How the three machines hand files to each other. The control plane writes the admin
# kubeconfig and a join command here; the worker reads the join command, the workbench
# reads the kubeconfig.
module "cluster_state_bucket" {
  source = "./modules/cluster_state_bucket"

  name          = "${var.project_name}-state"
  bucket_prefix = "${var.project_name}-state-"

  depends_on = [module.network]
}

# The group every machine carries, and the one rule that makes a kubeadm cluster work:
# members can reach each other on any port.
module "cluster_security_group" {
  source = "./modules/cluster_security_group"

  vpc_id      = module.network.vpc_id
  name        = "${var.project_name}-default-sg"
  description = "Shared security group for the kubeadm control plane, worker and workbench"

  depends_on = [module.network]
}

# Public ingress to the Traefik hostPorts on the worker node.
module "ingress_security_group" {
  source = "./modules/ingress_security_group"

  vpc_id      = module.network.vpc_id
  name        = "${var.project_name}-ingress-sg"
  description = "Public ingress to the Traefik DaemonSet hostPorts on the worker node"
  # The same map reaches the Traefik chart's hostPorts below, so the group cannot open
  # a port the controller does not bind (rules.md B-5).
  ports                       = var.ingress_ports
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere

  depends_on = [module.network]
}

# The control plane. kubeadm init runs here, and the two files the rest of the cluster
# needs are uploaded from here.
#
# A private subnet with no public address. The _monolithic template put this instance
# in the private subnet too, but also set associate_public_ip_address = true - a
# public address in a subnet whose route table has no internet gateway route, so it
# was allocated and unreachable.
module "control_plane" {
  source = "./modules/kubeadm_instance"

  name                     = "${var.project_name}-controlplane"
  subnet_id                = module.network.private_subnet_ids_by_zone[var.availability_zone_suffixes[0]]
  key_name                 = module.key_pair.key_name
  instance_type            = var.control_plane_instance_type
  kubernetes_minor_version = var.kubernetes_minor_version
  vpc_security_group_ids   = [module.cluster_security_group.security_group_id]
  marker_file_path         = var.marker_file_path
  # Scoped to the two handoff objects in one bucket, keyed by a label because the ARN
  # is another module's output and unknown at plan time (rules.md B-8). The
  # _monolithic template attached AmazonS3FullAccess to all three roles instead.
  additional_iam_policies = {
    cluster_state = module.cluster_state_bucket.access_policy_arn
  }

  # kubeadm init, and nothing about the CNI. The _monolithic template also installed
  # Calico from here, which meant the control plane had to hold the whole CNI
  # decision - including a sed over a YAML file downloaded from GitHub to inject the
  # pod CIDR. That moved to an SSM step on the workbench, where the manifests can be
  # rendered from typed values (see local.calico_custom_resources).
  additional_user_data = <<-EOT
    IMDS_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)

    # --pod-network-cidr has to agree with the CIDR Calico is configured with, and
    # both come from one variable (rules.md B-5).
    kubeadm init \
      --pod-network-cidr="${var.pod_network_cidr}" \
      --apiserver-advertise-address="$PRIVATE_IP" \
      --node-name="$(hostname -f)"

    mkdir -p /root/.kube
    cp -f /etc/kubernetes/admin.conf /root/.kube/config
    chown root:root /root/.kube/config

    mkdir -p /home/ec2-user/.kube
    cp -f /etc/kubernetes/admin.conf /home/ec2-user/.kube/config
    chown ec2-user:ec2-user /home/ec2-user/.kube/config

    # The kubeconfig kubeadm writes names the API server by the advertise address, so
    # it is usable from anywhere inside the VPC that carries the cluster security
    # group - which is what lets the workbench use it unchanged.
    aws s3 cp /root/.kube/config s3://${module.cluster_state_bucket.bucket_name}/kubeconfig
    kubeadm token create --print-join-command > /home/ec2-user/join.sh
    aws s3 cp /home/ec2-user/join.sh s3://${module.cluster_state_bucket.bucket_name}/join.sh
  EOT

  # The bucket and its policy have to exist before the role can be granted on them,
  # and the instance boots immediately - a role attached a moment too late produces an
  # access denied in user data that looks like a missing policy (rules.md D-1/D-3).
  depends_on = [module.network, module.cluster_state_bucket]
}

# The worker. Everything it needs comes out of the handoff bucket.
#
# A public subnet, because this is the node the ingress Elastic IP is attached to -
# Traefik binds hostPort 80 and 443 here, so the node itself is the public listener.
module "worker_node" {
  source = "./modules/kubeadm_instance"

  name                     = "${var.project_name}-node"
  subnet_id                = module.network.public_subnet_ids_by_zone[var.availability_zone_suffixes[1]]
  key_name                 = module.key_pair.key_name
  instance_type            = var.worker_instance_type
  kubernetes_minor_version = var.kubernetes_minor_version
  # The cluster group for everything internal, the ingress group for the hostPorts.
  # Both are handed in as IDs; the module never learns what either is for
  # (rules.md B-6).
  vpc_security_group_ids = [
    module.cluster_security_group.security_group_id,
    module.ingress_security_group.security_group_id,
  ]
  associate_public_ip_address = true
  marker_file_path            = var.marker_file_path
  additional_iam_policies = {
    cluster_state = module.cluster_state_bucket.access_policy_arn
  }

  # The until loop is the whole difference from the _monolithic template here. That
  # one ran `aws s3 cp s3://.../join.sh` directly, with only a depends_on between the
  # two instances - and depends_on orders the API calls, not the boots. Whenever this
  # machine finished its package installs before the control plane finished kubeadm
  # init, the copy failed, the join never ran, and the cluster came up with one node
  # (rules.md D-5 is the same argument for SSM steps).
  additional_user_data = <<-EOT
    until aws s3api head-object --bucket ${module.cluster_state_bucket.bucket_name} --key join.sh >/dev/null 2>&1; do
      echo "waiting for the control plane to publish join.sh"
      sleep 15
    done
    aws s3 cp s3://${module.cluster_state_bucket.bucket_name}/join.sh /home/ec2-user/join.sh
    chmod +x /home/ec2-user/join.sh
    /home/ec2-user/join.sh
  EOT

  depends_on = [module.network, module.cluster_state_bucket, module.control_plane]
}

# The public address of the ingress. Attached to the worker rather than to a load
# balancer, because there is no cloud controller manager in this cluster to build one -
# Traefik binds the node's port 80 and 443 directly.
#
# Its own resource in the root rather than inside the instance module: the instance
# module is reused for the control plane, which has no public address at all, and
# nothing about "this node is the ingress" belongs to the notion of a kubeadm machine
# (rules.md C-1).
resource "aws_eip" "ingress" {
  domain = "vpc"
  tags = {
    Name = "${var.project_name}-ingress"
  }
}

resource "aws_eip_association" "ingress" {
  allocation_id = aws_eip.ingress.allocation_id
  instance_id   = module.worker_node.instance_id
}

module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name   = "${var.project_name}-vscode"
  vpc_id = module.network.vpc_id
  # A public subnet with a public address. This instance is the only way in, and it is
  # also where every Kubernetes object is created from - see providers.tf.
  subnet_id                   = module.network.public_subnet_ids_by_zone[var.availability_zone_suffixes[0]]
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  code_server_version         = var.code_server_version
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  marker_file_path            = var.marker_file_path
  # Carrying the cluster group is what lets this instance reach the control plane's
  # API server on its private address (rules.md B-6).
  extra_security_group_ids = [module.cluster_security_group.security_group_id]
  # Scoped read on the handoff objects. The _monolithic template gave this role
  # AdministratorAccess and AmazonS3FullAccess; the AdministratorAccess default stays
  # (the module's own default - this is a hands-on demo workbench), but the bucket
  # access is narrowed to the two objects.
  additional_iam_policies = {
    cluster_state = module.cluster_state_bucket.access_policy_arn
  }
  # kubectl and helm are how this project's Kubernetes objects get created, so
  # rules.md E-1 is inverted here - see providers.tf for why there is no alternative.
  # docker is installed for the same reason as everywhere else: an image build needs a
  # daemon on the host (rules.md H-1).
  additional_user_data = <<-EOT
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server is already running and predates the docker group, so its terminals
    # would not have it without a restart. The _monolithic template opened
    # /var/run/docker.sock to 666 instead.
    systemctl restart code-server

    # /etc/hosts, written as root before the ec2-user block: the ingress host resolves
    # nowhere in DNS, and this is what makes `curl ${var.ingress_host_name}` work from
    # the IDE terminal. The address is the Elastic IP, which Terraform knows before the
    # instance exists.
    echo '${aws_eip.ingress.public_ip} ${var.ingress_host_name}' >> /etc/hosts

    sudo -Eu ec2-user bash << 'EOF'
    export HOME=/home/ec2-user
    cd /home/ec2-user
    mkdir -p /home/ec2-user/bin
    curl -sO https://s3.us-west-2.amazonaws.com/amazon-eks/${var.kubectl_download_version}/bin/linux/amd64/kubectl
    chmod +x kubectl
    mv kubectl /home/ec2-user/bin/kubectl
    export PATH=/home/ec2-user/bin:$PATH
    echo 'export PATH=/home/ec2-user/bin:$PATH' >> ~/.bashrc
    # Order matters: kubectl's completion defines __start_kubectl, and that has to
    # exist before complete names it. The _monolithic template had the complete line
    # first, so every login printed "function not found" (rules.md H-1).
    echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
    echo 'source <(kubectl completion bash)' >> ~/.bashrc
    echo 'alias k=kubectl' >> ~/.bashrc
    echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm -f get_helm.sh
    aws configure set default.region ${data.aws_region.current.region}
    # No `exec bash` here. The _monolithic template ran one right after the completion
    # lines, which replaced the shell and discarded everything after it - helm, the
    # Traefik install, the whoami manifests and the README all never ran, on the one
    # instance the demo is driven from.
    #
    # Waits for the control plane, the same way the worker does: depends_on orders the
    # API calls, not the boots (rules.md D-5).
    until aws s3api head-object --bucket ${module.cluster_state_bucket.bucket_name} --key kubeconfig >/dev/null 2>&1; do
      echo "waiting for the control plane to publish the kubeconfig"
      sleep 15
    done
    mkdir -p /home/ec2-user/.kube
    aws s3 cp s3://${module.cluster_state_bucket.bucket_name}/kubeconfig /home/ec2-user/.kube/config
    chmod 600 /home/ec2-user/.kube/config
    # The _monolithic template also copied this to /root/.kube/config from inside the
    # ec2-user block, which could only ever fail with a permission error.
    EOF
  EOT

  depends_on = [module.network, module.cluster_state_bucket, module.control_plane]
}

locals {
  # Calico's operator custom resources, as HCL objects rather than a YAML file
  # downloaded from GitHub and edited with sed - which is what the _monolithic template
  # did to get the pod CIDR into the IP pool. Field names stay exactly as the
  # Kubernetes API spells them (rules.md E-3).
  #
  # The operator manifest itself is still applied from its upstream URL: it is around
  # ten thousand lines of CRDs and has no value to express as HCL. These two resources
  # are the part that carries decisions.
  calico_custom_resources = [
    {
      apiVersion = "operator.tigera.io/v1"
      kind       = "Installation"
      metadata   = { name = "default" }
      spec = {
        calicoNetwork = {
          ipPools = [{
            name          = "default-ipv4-ippool"
            blockSize     = var.calico_block_size
            cidr          = var.pod_network_cidr
            encapsulation = var.calico_encapsulation
            natOutgoing   = "Enabled"
            nodeSelector  = "all()"
          }]
        }
      }
    },
    {
      apiVersion = "operator.tigera.io/v1"
      kind       = "APIServer"
      metadata   = { name = "default" }
      spec       = {}
    },
  ]
  calico_custom_resources_yaml = join("\n---\n", [for m in local.calico_custom_resources : yamlencode(m)])

  # Traefik entrypoint names, which are the chart's, mapped from the port labels this
  # configuration uses everywhere else.
  traefik_entrypoints = {
    http  = "web"
    https = "websecure"
  }
  # Only the entrypoints that have both a container port and an opened host port. A
  # hostPort the security group does not open is a listener nothing can reach, and the
  # filter is what keeps the two from disagreeing (rules.md B-5).
  traefik_ports = {
    for label, entrypoint in local.traefik_entrypoints : entrypoint => {
      port     = var.traefik_container_ports[label]
      hostPort = var.ingress_ports[label]
    }
    if contains(keys(var.traefik_container_ports), label) && contains(keys(var.ingress_ports), label)
  }
  # The chart values, as an HCL object. The _monolithic template echoed this same YAML
  # into a file from a shell script, with the node name interpolated into the middle of
  # it.
  traefik_values = {
    # A DaemonSet, not a Deployment, because the pod has to be on the node the Elastic
    # IP is attached to - and pinned there by nodeSelector, since a DaemonSet alone
    # would put one pod on every node including the control plane.
    deployment = { kind = "DaemonSet" }
    nodeSelector = {
      # kubeadm was given --node-name=$(hostname -f), which on Amazon Linux is the
      # private DNS name - so the node's Kubernetes name is this value. Taken from the
      # instance module's output rather than restated (rules.md B-5).
      "kubernetes.io/hostname" = module.worker_node.private_dns
      "kubernetes.io/os"       = "linux"
    }
    updateStrategy = {
      rollingUpdate = {
        # maxSurge 0 with maxUnavailable 1, because two pods cannot bind the same
        # hostPort on the same node - a surge would leave the new pod Pending forever.
        maxUnavailable = 1
        maxSurge       = 0
      }
    }
    ports = local.traefik_ports
    securityContext = {
      capabilities = {
        drop = ["ALL"]
        # NET_BIND_SERVICE is what lets the container bind the privileged host ports
        # while dropping everything else. It is also why the container listens on high
        # ports internally and maps them: without this capability the hostPort mapping
        # is what binds 80, not the process.
        add = ["NET_BIND_SERVICE"]
      }
      readOnlyRootFilesystem   = true
      allowPrivilegeEscalation = false
    }
    # ClusterIP: the Service exists for the dashboard and for internal references. The
    # public path is the hostPort on the node, not a Service of type LoadBalancer -
    # which would stay Pending forever, because nothing in this cluster provisions load
    # balancers.
    service = { spec = { type = "ClusterIP" } }
  }
  traefik_values_yaml = yamlencode(local.traefik_values)

  # The demo workload. Two paths on one Ingress, both backed by the same Service,
  # because traefik/whoami echoes the request it received - so the response shows which
  # path was matched.
  workload_manifests = [
    {
      apiVersion = "apps/v1"
      kind       = "Deployment"
      metadata = {
        name      = var.workload_name
        namespace = var.workload_namespace
        labels    = { app = var.workload_name }
      }
      spec = {
        replicas = var.workload_replicas
        selector = { matchLabels = { app = var.workload_name } }
        template = {
          metadata = { labels = { app = var.workload_name } }
          spec = {
            containers = [{
              name  = var.workload_name
              image = var.workload_image
              ports = [{
                name          = "http"
                containerPort = var.workload_container_port
              }]
              resources = {
                requests = { cpu = "10m", memory = "32Mi" }
                limits   = { cpu = "100m", memory = "64Mi" }
              }
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
        selector = { app = var.workload_name }
        ports = [{
          name = "http"
          port = var.workload_container_port
          # The port's name, not its number. A named targetPort keeps working if the
          # container port changes, and the Deployment above names it.
          targetPort = "http"
        }]
      }
    },
    {
      apiVersion = "networking.k8s.io/v1"
      kind       = "Ingress"
      metadata = {
        name      = "${var.workload_name}-ingress"
        namespace = var.workload_namespace
        annotations = {
          "traefik.ingress.kubernetes.io/router.entrypoints" = local.traefik_entrypoints.http
        }
      }
      spec = {
        # Without this no controller claims the Ingress and it never serves anything.
        # The chart creates an IngressClass named after the release (rules.md G-1 makes
        # the same point about the AWS controller).
        ingressClassName = var.traefik_release_name
        rules = [{
          host = var.ingress_host_name
          http = {
            paths = [for path in var.ingress_paths : {
              path     = path
              pathType = "Prefix"
              backend = {
                service = {
                  name = var.workload_name
                  port = { name = "http" }
                }
              }
            }]
          }
        }]
      }
    },
  ]
  workload_yaml = join("\n---\n", [for m in local.workload_manifests : yamlencode(m)])
  # Every step below opens by waiting for the previous step's marker file, so the shell
  # enforces the order rather than depends_on (rules.md D-5). Defined once here and
  # interpolated into each step, so the loop exists in one place (rules.md B-5).
  #
  # Bounded, unlike the bare "until [ -f X ]; do sleep 10; done" this replaces. An
  # unbounded wait on a marker that never arrives holds the command open until SSM's
  # own timeout, and the provider then reports
  #
  #   waiting for SSM Association (...) create: timeout while waiting for state to
  #   become 'Success' (last state: 'Pending', timeout: 20m0s)
  #
  # which names the association that was waiting and says nothing about what it was
  # waiting for. That is the worst shape a failure in this chain can take: 'Pending'
  # means the command was still running, so unlike the 'Failed' case there is not even
  # a command invocation to read an error out of (rules.md A-4). Failing here instead
  # costs one timeout and names the marker.
  #
  # "$1" and "$waited" carry no braces, so Terraform leaves them to the shell.
  wait_for_marker = <<-EOT
    wait_for_marker() {
      waited=0
      until [ -f ${module.vscode_ec2.marker_file_path}/$1 ]; do
        if [ "$waited" -ge ${var.marker_wait_timeout_seconds} ]; then
          echo "marker $1 never appeared after ${var.marker_wait_timeout_seconds}s: the step that creates it did not finish" >&2
          exit 1
        fi
        sleep 10
        waited=$((waited + 10))
      done
    }
    EOT
}

# Step 1: the CNI. Until it is running every node stays NotReady and no pod other than
# the static control plane pods can be scheduled, so this is the first thing that has
# to happen after the cluster exists.
#
# The until loop, not depends_on, is what orders this after the workbench bootstrap:
# wait_for_success_timeout_seconds does not reliably wait for the remote command to
# finish, so each step waits for the previous step's marker and leaves its own
# (rules.md D-5).
resource "aws_ssm_association" "calico" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.cni_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The heredoc delimiters are quoted and deliberately unlikely to appear in the
    # body. Terraform has already substituted every value, so the shell has no reason
    # to touch a "$" or a backtick inside a manifest.
    #
    # A note on why the nesting works: the indentation stripping of <<-EOT is computed
    # from the template source lines only, so the second and later lines of an
    # interpolated multi-line value sit at column 0 and the closing delimiter ends up
    # at column 0 after stripping. That is also why rules.md A-4 matters twice as much
    # here - a CRLF file turns TFMANIFEST into TFMANIFEST\r and the heredoc runs to the
    # end of the script, so not one line executes.
    commands = <<-EOT
      set -euo pipefail
      ${local.wait_for_marker}
      wait_for_marker userdata
      sudo -Eu ec2-user bash << 'STEP'
      set -euo pipefail
      export HOME=/home/ec2-user
      export PATH=/home/ec2-user/bin:$PATH
      mkdir -p /home/ec2-user/manifests
      # kubectl apply, not the create the _monolithic template used, so re-running this
      # association after a parameter change is not an error. --server-side, because
      # the tigera-operator bundle's CRDs exceed the annotation size limit that
      # client-side apply records the last-applied configuration in.
      kubectl apply --server-side -f https://raw.githubusercontent.com/projectcalico/calico/${var.calico_version}/manifests/tigera-operator.yaml
      kubectl -n tigera-operator rollout status deployment/tigera-operator --timeout=${var.calico_operator_timeout_seconds}s
      cat > /home/ec2-user/manifests/calico.yaml << 'TFMANIFEST'
      ${local.calico_custom_resources_yaml}
      TFMANIFEST
      # The operator registers these CRDs itself, and the rollout above only says the
      # operator pod is running - not that it has finished registering. Waiting for the
      # CRD is what makes the apply below deterministic; the _monolithic template used
      # `sleep 30`.
      # Two waits per CRD, and the first one is the point.
      #
      # The operator registers these CRDs itself, asynchronously, after its own
      # Deployment reports rolled out - so at this moment they may not exist yet. And
      # "kubectl wait --for=condition=..." on a name that does not exist does not wait
      # for it to appear: it returns NotFound immediately and ignores --timeout
      # completely. Measured with this project's own kubectl (v1.34.11):
      #
      #   kubectl wait --for=condition=Established crd/absent --timeout=20s
      #     -> Error from server (NotFound): ... not found        after 0.4s
      #   kubectl wait --for=create crd/absent --timeout=15s
      #     -> error: timed out waiting for the condition         after 15.1s
      #
      # This is how the step used to fail, and it lost the race by three seconds: the
      # operator registered installations.operator.tigera.io at 14:25:20Z and the wait
      # ran at 14:25:17Z. Under "set -e" the step then exited without writing its
      # marker, and the Traefik step behind it sat on an unbounded wait for that marker
      # until SSM killed the command an hour later. The error that surfaced named the
      # Traefik association, two steps away from the cause.
      #
      # "$crd" carries no braces, so Terraform leaves it to the shell.
      for crd in installations.operator.tigera.io apiservers.operator.tigera.io; do
        kubectl wait --for=create "crd/$crd" --timeout=${var.calico_crd_timeout_seconds}s
        kubectl wait --for=condition=Established "crd/$crd" --timeout=${var.calico_crd_timeout_seconds}s
      done
      kubectl apply -f /home/ec2-user/manifests/calico.yaml
      # calico-system is created by the operator in response to the Installation, so
      # this both waits for the CNI to be ready and proves the Installation was
      # accepted.
      # Bounded for the same reason the marker waits are: the Installation can be
      # rejected, and an unbounded loop here turns that into a 'Pending' association
      # with nothing to read, rather than a message naming the DaemonSet.
      waited=0
      until kubectl -n calico-system get daemonset calico-node >/dev/null 2>&1; do
        if [ "$waited" -ge ${var.calico_crd_timeout_seconds} ]; then
          echo "calico-system/calico-node was not created after ${var.calico_crd_timeout_seconds}s; the operator has not accepted the Installation" >&2
          kubectl -n tigera-operator logs deploy/tigera-operator --tail 100 || true
          kubectl get installation default -o yaml || true
          exit 1
        fi
        sleep 10
        waited=$((waited + 10))
      done
      kubectl -n calico-system rollout status daemonset/calico-node --timeout=${var.calico_node_timeout_seconds}s
      STEP
      touch ${module.vscode_ec2.marker_file_path}/calico
      EOT
  }

  # The worker has to have joined before calico-node can roll out on it, and the
  # workbench needs its kubeconfig - which it waits for in user data (rules.md D-2).
  depends_on = [module.control_plane, module.worker_node, module.vscode_ec2]
}

# Step 2: the ingress controller. Pinned by nodeSelector to the worker that carries
# the Elastic IP, so the node has to be Ready first - which needs the CNI from step 1.
resource "aws_ssm_association" "traefik" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.ingress_controller_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    commands = <<-EOT
      set -euo pipefail
      ${local.wait_for_marker}
      wait_for_marker calico
      sudo -Eu ec2-user bash << 'STEP'
      set -euo pipefail
      export HOME=/home/ec2-user
      export PATH=/home/ec2-user/bin:$PATH
      # A nodeSelector on a node that is not Ready leaves the DaemonSet pod Pending and
      # helm's --wait then times out with nothing explaining why.
      #
      # The timeout is a variable rather than the literal 600s it used to be, and that
      # is the whole point: this wait runs before helm, inside the same association
      # budget, and while it was a literal no validation could see it. With
      # ingress_controller_timeout_seconds at 1200 and helm's own timeout at 600, a
      # slow node here used the remaining 600 exactly - so the command could still be
      # running when the provider gave up, and a provider that gives up on 'Pending'
      # produces no diagnosis at all (rules.md B-3 feeding B-1).
      #
      # --for=create first, for the same reason as the CRDs above: the kubelet registers
      # the Node object when it joins, and a wait for a condition on a Node that has not
      # registered yet returns NotFound in under a second rather than waiting.
      kubectl wait --for=create node/${module.worker_node.private_dns} --timeout=${var.worker_ready_timeout_seconds}s \
        || { kubectl get nodes -o wide; exit 1; }
      kubectl wait --for=condition=Ready node/${module.worker_node.private_dns} --timeout=${var.worker_ready_timeout_seconds}s \
        || { kubectl get nodes -o wide; kubectl -n calico-system get pods -o wide; exit 1; }
      helm repo add traefik ${var.traefik_chart_repository}
      helm repo update traefik
      mkdir -p /home/ec2-user/traefik
      cat > /home/ec2-user/traefik/values.yaml << 'TFVALUES'
      ${local.traefik_values_yaml}
      TFVALUES
      # An association re-runs whenever its parameters change, so this has to be
      # re-runnable - and a release whose only revision failed is the one state
      # "upgrade --install" cannot recover from: helm refuses it with "has no deployed
      # releases", which hides whatever the original failure was. Clear exactly that
      # state, never a release that has a deployed revision (rules.md E-7).
      if helm status ${var.traefik_release_name} -n ${var.traefik_namespace} >/dev/null 2>&1; then
        # grep -c over one field per line rather than "grep -q" on the raw JSON: under
        # pipefail, grep -q closing the pipe early can fail the whole pipeline even on
        # a match.
        deployed=$(helm history ${var.traefik_release_name} -n ${var.traefik_namespace} -o json | tr ',' '\n' | grep -c '"status":"deployed"' || true)
        if [ "$deployed" -eq 0 ]; then
          echo "clearing failed release with no deployed revision"
          helm uninstall ${var.traefik_release_name} -n ${var.traefik_namespace} --wait
        fi
      fi
      helm upgrade --install ${var.traefik_release_name} traefik/traefik \
        --version ${var.traefik_chart_version} \
        --namespace ${var.traefik_namespace} --create-namespace \
        --values /home/ec2-user/traefik/values.yaml \
        --wait --timeout ${var.traefik_helm_timeout_seconds}s \
        || { kubectl -n ${var.traefik_namespace} get pods -o wide; kubectl -n ${var.traefik_namespace} describe daemonset ${var.traefik_release_name}; exit 1; }
      STEP
      touch ${module.vscode_ec2.marker_file_path}/traefik
      EOT
  }

  # The Elastic IP has to be on the node before the hostPort is worth anything.
  depends_on = [aws_ssm_association.calico, aws_eip_association.ingress]
}

# Step 3: the demo workload, and the Ingress that makes it reachable.
resource "aws_ssm_association" "workload" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.workload_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    commands = <<-EOT
      set -euo pipefail
      ${local.wait_for_marker}
      wait_for_marker traefik
      sudo -Eu ec2-user bash << 'STEP'
      set -euo pipefail
      export HOME=/home/ec2-user
      export PATH=/home/ec2-user/bin:$PATH
      mkdir -p /home/ec2-user/manifests
      cat > /home/ec2-user/manifests/workload.yaml << 'TFMANIFEST'
      ${local.workload_yaml}
      TFMANIFEST
      kubectl apply -f /home/ec2-user/manifests/workload.yaml
      # kubectl apply only creates the objects. Without this the next step could write a
      # README describing something that is not serving yet.
      kubectl -n ${var.workload_namespace} rollout status deployment/${var.workload_name} --timeout=${var.workload_rollout_timeout_seconds}s
      STEP
      touch ${module.vscode_ec2.marker_file_path}/workload
      EOT
  }

  depends_on = [aws_ssm_association.traefik]
}

locals {
  # Every output this project exposes, defined once. outputs.tf projects these and the
  # README below renders them, so no value expression is written twice
  # (rules.md B-5/H-2). Adding an entry here is what makes an output possible, which is
  # what keeps the README from falling behind outputs.tf.
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here. On this project it is the only place kubectl works: the API server is on a private address inside the VPC, and this instance is the one that holds the kubeconfig"
      value       = module.vscode_ec2.vscode_url
    }
    ingress_url = {
      order       = 2
      title       = "Demo workload URL"
      description = "Reachable from the IDE terminal, because the workbench's /etc/hosts maps this host to the ingress Elastic IP. Nothing resolves it in DNS - point a real record at the IP below to change that"
      value       = "http://${var.ingress_host_name}"
    }
    ingress_public_ip = {
      order       = 3
      title       = "Ingress Elastic IP"
      description = "Attached to the worker node, where Traefik binds hostPort 80 and 443. There is no load balancer in this cluster - kubeadm on EC2 has no cloud controller manager, so a Service of type LoadBalancer would stay Pending forever"
      value       = aws_eip.ingress.public_ip
    }
    control_plane_private_ip = {
      order       = 4
      title       = "Control plane address"
      description = "The address kubeadm advertised as the API server. The kubeconfig in the handoff bucket names it, which is why that file works from anywhere in the VPC carrying the cluster security group and nowhere else"
      value       = module.control_plane.private_ip
    }
    worker_node_name = {
      order       = 5
      title       = "Worker node name"
      description = "kubeadm was given --node-name=$(hostname -f), so the Kubernetes node name is the private DNS name. The Traefik nodeSelector matches exactly this value"
      value       = module.worker_node.private_dns
    }
    cluster_state_bucket = {
      order       = 6
      title       = "Handoff bucket"
      description = "How the three machines exchange the kubeconfig and the kubeadm join command. force_destroy is on, which replaces the Lambda the _monolithic template used to empty it before delete"
      value       = module.cluster_state_bucket.bucket_name
    }
    node_status_command = {
      order       = 7
      title       = "1. Both nodes are Ready"
      description = "Two entries, both Ready. One entry means the worker never joined, which is a handoff problem - check the bucket listing below. Both present but NotReady means Calico is not running"
      value       = "kubectl get nodes -o wide"
    }
    cluster_state_objects_command = {
      order       = 8
      title       = "2. The handoff objects exist"
      description = "kubeconfig and join.sh should both be here. Neither means the control plane never finished kubeadm init, and the worker is still in its wait loop rather than failed"
      value       = module.cluster_state_bucket.objects_check_command
    }
    calico_status_command = {
      order       = 9
      title       = "3. Calico is running"
      description = "calico-node runs on every node, so DESIRED should match the node count. A DaemonSet with no pods usually means the Installation resource was rejected - kubectl describe installation default says why"
      value       = "kubectl -n calico-system get daemonset calico-node -o wide"
    }
    traefik_status_command = {
      order       = 10
      title       = "4. Traefik is on the ingress node"
      description = "One pod, on the node holding the Elastic IP. A Pending pod means the nodeSelector does not match any Ready node, or another pod already holds the hostPort"
      value       = "kubectl -n ${var.traefik_namespace} get pods -o wide"
    }
    workload_status_command = {
      order       = 11
      title       = "5. The demo workload is serving"
      description = "Deployment, Service and Ingress. An Ingress with an empty CLASS is claimed by nothing and serves nothing"
      value       = "kubectl -n ${var.workload_namespace} get deployment,service,ingress"
    }
    curl_root_command = {
      order       = 12
      title       = "6. Request the root path"
      description = "whoami echoes the request it received. Run it a few times - the reported hostname changes as the Service balances across the replicas"
      value       = "curl -s http://${var.ingress_host_name}${var.ingress_paths[0]}"
    }
    curl_second_path_command = {
      order       = 13
      title       = "7. Request the second path"
      description = "Same Service behind a second Ingress path rule. The echoed request line shows which path was matched, which is what makes the two rules distinguishable"
      value       = "curl -s http://${var.ingress_host_name}${element(var.ingress_paths, length(var.ingress_paths) - 1)}"
    }
    kubeconfig_refresh_command = {
      order       = 14
      title       = "Re-fetch the kubeconfig"
      description = "User data already did this, so kubectl works out of the box. Re-run it if the file is ever lost"
      value       = "aws s3 cp ${module.cluster_state_bucket.kubeconfig_object_uri} /home/ec2-user/.kube/config && chmod 600 /home/ec2-user/.kube/config"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the
  # order field and taking values() sorts by that instead - values() returns a map's
  # values ordered by key - so the README reads in the order the demo is run.
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
# exist, so every output above is also written to a README in the home directory the
# IDE opens (rules.md H-2). The _monolithic template wrote a README too - three lines,
# echoed from the same shell script, holding the host name twice and nothing else.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # Waits on the workload marker rather than on the bootstrap marker, so the README
    # is written after the last thing it describes is serving (rules.md D-5).
    #
    # SSM runs as root, hence the chown - without it the file is not editable from the
    # IDE.
    commands = <<-EOT
      set -eu
      ${local.wait_for_marker}
      wait_for_marker workload
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_readme
      EOT
  }

  depends_on = [aws_ssm_association.workload]
}
