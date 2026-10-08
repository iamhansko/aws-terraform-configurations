# code-server running as a pod, reached through an ALB the AWS Load Balancer Controller manages.
#
# The _monolithic template built all five of these objects by echoing one 3.5 KB single-quoted YAML
# string into a file from an SSM Association and running kubectl apply on it. Nothing about that was
# recoverable: the manifest existed only on the workbench's disk, a change to it was invisible to
# plan, and `terraform destroy` left the objects - and the load balancer the controller built for
# them - behind. Here each object is a kubectl_manifest, declared as an HCL object and rendered with
# yamlencode, so the field names stay the ones the Kubernetes API uses (rules.md E-1/E-2/E-3).
locals {
  labels = {
    statefulset = var.name
  }
  # A kubeconfig assembled from what Terraform already knows, mounted into the pod as a ConfigMap.
  #
  # This replaces `aws eks update-kubeconfig` running inside the container. The endpoint, the CA and
  # the cluster name are all known at apply time; the only part that needs credentials is the token,
  # and that is fetched per call by the exec block using whatever identity the pod has. The
  # _monolithic template ran update-kubeconfig through kubectl exec, so the file was lost on every
  # pod restart.
  kubeconfig = yamlencode({
    apiVersion = "v1"
    kind       = "Config"
    clusters = [{
      name = var.cluster_name
      cluster = {
        server                     = var.cluster_endpoint
        certificate-authority-data = var.certificate_authority_data
      }
    }]
    contexts = [{
      name    = var.cluster_name
      context = { cluster = var.cluster_name, user = var.cluster_name }
    }]
    current-context = var.cluster_name
    users = [{
      name = var.cluster_name
      user = {
        exec = {
          apiVersion = "client.authentication.k8s.io/v1beta1"
          command    = "aws"
          args       = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.aws_region]
        }
      }
    }]
  })
  # Volume mounts the container always has, plus whatever the caller's storage adds. Built here so
  # the container spec and the pod's volume list cannot disagree (rules.md B-5).
  base_volume_mounts = concat(
    [
      {
        name      = "config"
        mountPath = "/home/coder/.config/code-server"
        readOnly  = true
      },
      {
        name      = "kubeconfig"
        mountPath = "/home/coder/.kube/config"
        subPath   = "config"
        readOnly  = true
      },
    ],
    var.install_tools ? [{ name = "tools", mountPath = var.tools_path }] : [],
  )
  storage_volume_mounts = concat(
    [for v in var.volume_claim_templates : {
      name      = v.name
      mountPath = v.mount_path
    }],
    [for v in var.persistent_volume_claims : {
      name      = v.name
      mountPath = v.mount_path
      readOnly  = v.read_only
    }],
  )
  volume_mounts = concat(local.base_volume_mounts, local.storage_volume_mounts)
  volumes = concat(
    [
      {
        name = "config"
        configMap = {
          name  = var.name
          items = [{ key = "config.yaml", path = "config.yaml" }]
        }
      },
      {
        name = "kubeconfig"
        configMap = {
          name  = "${var.name}-kubeconfig"
          items = [{ key = "config", path = "config" }]
        }
      },
    ],
    # emptyDir, not a claim: the init container refills it on every start, so there is nothing worth
    # keeping across a reschedule.
    var.install_tools ? [{ name = "tools", emptyDir = {} }] : [],
    [for v in var.persistent_volume_claims : {
      name                  = v.name
      persistentVolumeClaim = { claimName = v.claim_name }
    }],
  )
  # Downloads only. Every one of these is a single binary or a tarball, which is why the init
  # container can be alpine while the pod is Fedora - nothing is executed here, only unpacked.
  #
  # The _monolithic template did this with `kubectl exec ... sh` and a nested heredoc, where the
  # inner echo's single quotes closed the outer ones. The PATH lines it wrote came out expanded by
  # the wrong shell, and the whole script ran once, unrecorded, never to run again.
  tools_script = <<-SCRIPT
    set -eu
    mkdir -p /tools/bin
    cd /tmp

    wget -qO /tools/bin/kubectl https://s3.us-west-2.amazonaws.com/amazon-eks/${var.kubectl_download_version}/bin/linux/amd64/kubectl
    chmod +x /tools/bin/kubectl

    wget -qO helm.tar.gz https://get.helm.sh/helm-v${var.helm_version}-linux-amd64.tar.gz
    tar -xzf helm.tar.gz
    install -m 0755 linux-amd64/helm /tools/bin/helm

    wget -qO eksctl.tar.gz https://github.com/eksctl-io/eksctl/releases/download/v${var.eksctl_version}/eksctl_Linux_amd64.tar.gz
    tar -xzf eksctl.tar.gz
    install -m 0755 eksctl /tools/bin/eksctl

    wget -qO terraform.zip https://releases.hashicorp.com/terraform/${var.terraform_version}/terraform_${var.terraform_version}_linux_amd64.zip
    unzip -qo terraform.zip
    install -m 0755 terraform /tools/bin/terraform

    %{if var.install_aws_cli~}
    # Extracted rather than installed. The bundle's own installer expects to run on the system it is
    # installing onto, and this is not that system - but aws/dist is a self-contained glibc build, so
    # copying it and linking the entry point is enough for the Fedora container to run it.
    wget -qO awscliv2.zip https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip
    unzip -qo awscliv2.zip
    cp -r aws/dist /tools/aws-cli
    ln -sf /tools/aws-cli/aws /tools/bin/aws
    %{endif~}

    rm -rf /tmp/helm.tar.gz /tmp/linux-amd64 /tmp/eksctl.tar.gz /tmp/eksctl /tmp/terraform.zip /tmp/terraform /tmp/awscliv2.zip /tmp/aws
  SCRIPT
}

# The code-server settings file. auth: none is what the _monolithic template set, and it is why the
# frontend security group in front of this matters: anyone who reaches the load balancer gets a shell
# in the cluster.
resource "kubectl_manifest" "config_map" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = var.name
      namespace = var.namespace
    }
    data = {
      "config.yaml" = yamlencode({
        auth = "none"
        cert = false
      })
    }
  })

  depends_on = [var.capability_dependency]
}

resource "kubectl_manifest" "kubeconfig_config_map" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "${var.name}-kubeconfig"
      namespace = var.namespace
    }
    data = {
      config = local.kubeconfig
    }
  })

  depends_on = [var.capability_dependency]
}

resource "kubectl_manifest" "service_account" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ServiceAccount"
    metadata = merge(
      {
        name      = var.name
        namespace = var.namespace
      },
      # Only when the caller has annotations to add. An empty annotations map is harmless but shows
      # up as a diff against what the API server returns (rules.md B-4).
      length(var.service_account_annotations) > 0 ? { annotations = var.service_account_annotations } : {},
    )
  })

  depends_on = [var.capability_dependency]
}

resource "kubectl_manifest" "stateful_set" {
  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "StatefulSet"
    metadata = {
      name      = var.name
      namespace = var.namespace
    }
    spec = merge(
      {
        # A StatefulSet rather than a Deployment, as the _monolithic template had it. What it buys
        # here is the stable pod name - vscode-0 - which every verification command below relies on,
        # and volumeClaimTemplates for the variants that give the pod its own disk.
        serviceName = var.name
        replicas    = var.replicas
        selector    = { matchLabels = local.labels }
        template = {
          metadata = { labels = local.labels }
          spec = merge(
            {
              serviceAccountName = var.name
              containers = [{
                name  = "code-server"
                image = var.image
                ports = [{
                  containerPort = var.container_port
                  name          = "vscode"
                }]
                env = concat(
                  [
                    { name = "AWS_REGION", value = var.aws_region },
                    { name = "AWS_DEFAULT_REGION", value = var.aws_region },
                    # Points kubectl at the mounted ConfigMap instead of expecting a file that
                    # something wrote at runtime.
                    { name = "KUBECONFIG", value = "/home/coder/.kube/config" },
                  ],
                  # PATH has to be set on the container rather than appended to .bashrc: the IDE's
                  # own process is not a login shell, so an extension looking for kubectl reads this
                  # and not the shell profile.
                  var.install_tools ? [{
                    name  = "PATH"
                    value = "${var.tools_path}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
                  }] : [],
                )
                resources = {
                  requests = {
                    cpu    = var.cpu_request
                    memory = var.memory_request
                  }
                }
                volumeMounts = local.volume_mounts
              }]
              volumes = local.volumes
            },
            var.install_tools ? {
              initContainers = [{
                name         = "tools"
                image        = var.tools_init_image
                command      = ["sh", "-c", local.tools_script]
                volumeMounts = [{ name = "tools", mountPath = "/tools" }]
              }]
            } : {},
            var.fs_group != null ? { securityContext = { fsGroup = var.fs_group } } : {},
          )
        }
      },
      length(var.volume_claim_templates) > 0 ? {
        volumeClaimTemplates = [for v in var.volume_claim_templates : {
          metadata = { name = v.name }
          spec = {
            accessModes      = v.access_modes
            storageClassName = v.storage_class_name
            resources        = { requests = { storage = v.size } }
          }
        }]
      } : {},
    )
  })

  # The Ingress's target group points at pod IPs, so the pods have to be the thing that exists
  # before the controller can register anything. Ordering the StatefulSet before the Ingress also
  # means a destroy removes the Ingress first, while the controller is still alive to clean up the
  # load balancer (rules.md D-4).
  depends_on = [
    kubectl_manifest.config_map,
    kubectl_manifest.kubeconfig_config_map,
    kubectl_manifest.service_account,
  ]
}

resource "kubectl_manifest" "service" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = var.name
      namespace = var.namespace
      labels    = local.labels
    }
    spec = {
      # ClusterIP, which is all target-type ip needs: the load balancer talks to pod addresses
      # directly and the Service only supplies the endpoint list (rules.md G-1).
      ports = [{
        port       = var.container_port
        targetPort = var.container_port
        name       = "vscode"
      }]
      selector = local.labels
    }
  })

  depends_on = [kubectl_manifest.stateful_set]
}

resource "kubectl_manifest" "ingress" {
  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name        = var.ingress_name
      namespace   = var.namespace
      annotations = var.ingress_annotations
    }
    spec = {
      # Without this the Ingress is created, nothing claims it, and no load balancer appears - with
      # no error and no event to explain it (rules.md G-1).
      ingressClassName = var.ingress_class_name
      rules = [{
        http = {
          paths = [{
            path     = "/"
            pathType = "Prefix"
            backend = {
              service = {
                name = var.name
                port = { number = var.container_port }
              }
            }
          }]
        }
      }]
    }
  })

  depends_on = [kubectl_manifest.service]
}
