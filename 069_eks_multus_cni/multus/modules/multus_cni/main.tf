# Multus CNI, thick plugin, as AWS publishes it.
#
# The _monolithic template installed this with
#
#   kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml
#
# from a shell on the bastion. Three problems with that, and only the first is the usual one
# (rules.md E-1/E-2/E-3):
#
#   - none of it was in state, so it appeared in no plan and was removed by no destroy;
#   - the URL points at master, so the Multus version installed was whatever upstream's default
#     branch held on the day the instance booted - for a CNI that sits in front of every pod's
#     networking, that is a large thing to leave to chance;
#   - upstream's own manifest pulls its image from a public registry and does not carry AWS's EKS
#     build. AWS publishes a pinned one under amazon-vpc-cni-k8s/config/multus/, and it is that
#     object set which is declared here.
#
# What Multus does, because it decides how the rest of this project reads: it inserts itself as the
# node's CNI, delegates the pod's primary interface to the CNI named by multusMasterCNI, and adds
# further interfaces for any NetworkAttachmentDefinition a pod's annotation names. So it is an
# addition to the VPC CNI rather than a replacement - and if multusMasterCNI names the wrong file,
# every pod on the node loses its primary interface.
locals {
  labels = {
    tier = "node"
    app  = var.name
    name = var.name
  }
  selector_labels = {
    name = var.name
  }
  config_map_name = "multus-daemon-config"
  daemon_config = {
    chrootDir = "/hostroot"
    confDir   = "/host/etc/cni/net.d"
    logFile   = "/var/log/multus.log"
    logLevel  = var.log_level
    socketDir = "/host/run/multus/"
    # The CNI spec version Multus writes into the configuration it generates. A
    # NetworkAttachmentDefinition declaring a different one is rejected at pod creation rather than
    # at apply.
    cniVersion          = var.cni_version
    cniConfigDir        = "/host/etc/cni/net.d"
    multusConfigFile    = "auto"
    multusAutoconfigDir = "/host/etc/cni/net.d"
    # The file the primary interface is delegated to - what the VPC CNI writes on an EKS node.
    multusMasterCNI = var.master_cni_config_file
  }
}
# The CRD that NetworkAttachmentDefinition objects are instances of. Declared through
# alekc/kubectl rather than hashicorp/kubernetes for the usual reason - the cluster is created in
# this same apply - and for a second one that applies to every CRD: hashicorp/kubernetes resolves a
# custom resource's schema at plan time, which cannot work when the CRD is created by the same
# apply (rules.md E-2/E-3).
resource "kubectl_manifest" "network_attachment_definition_crd" {
  yaml_body = yamlencode({
    apiVersion = "apiextensions.k8s.io/v1"
    kind       = "CustomResourceDefinition"
    metadata = {
      name = "network-attachment-definitions.k8s.cni.cncf.io"
    }
    spec = {
      group = "k8s.cni.cncf.io"
      scope = "Namespaced"
      names = {
        plural     = "network-attachment-definitions"
        singular   = "network-attachment-definition"
        kind       = "NetworkAttachmentDefinition"
        shortNames = ["net-attach-def"]
      }
      versions = [{
        name    = "v1"
        served  = true
        storage = true
        schema = {
          openAPIV3Schema = {
            description = "NetworkAttachmentDefinition is a CRD schema specified by the Network Plumbing Working Group to express the intent for attaching pods to one or more logical or physical networks."
            type        = "object"
            properties = {
              apiVersion = { type = "string" }
              kind       = { type = "string" }
              metadata   = { type = "object" }
              spec = {
                description = "NetworkAttachmentDefinition spec defines the desired state of a network attachment"
                type        = "object"
                properties = {
                  # A JSON-formatted CNI configuration, carried as a string. That is why the
                  # attachment module builds its config with jsonencode and hands over the result
                  # rather than nesting an object here.
                  config = {
                    description = "NetworkAttachmentDefinition config is a JSON-formatted CNI configuration"
                    type        = "string"
                  }
                }
              }
            }
          }
        }
      }]
    }
  })
}
resource "kubectl_manifest" "service_account" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ServiceAccount"
    metadata = {
      name      = var.name
      namespace = var.namespace
    }
  })
}
resource "kubectl_manifest" "cluster_role" {
  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "ClusterRole"
    metadata   = { name = var.name }
    rules = [
      {
        # Everything in its own API group: Multus reads NetworkAttachmentDefinitions and writes
        # status back onto them.
        apiGroups = ["k8s.cni.cncf.io"]
        resources = ["*"]
        verbs     = ["*"]
      },
      {
        # Reads the pod to find its network annotation, and updates it with the interfaces it
        # attached - which is what puts the k8s.v1.cni.cncf.io/network-status annotation on a
        # running pod.
        apiGroups = [""]
        resources = ["pods", "pods/status"]
        verbs     = ["get", "update"]
      },
      {
        apiGroups = ["", "events.k8s.io"]
        resources = ["events"]
        verbs     = ["create", "patch", "update"]
      },
    ]
  })
}
resource "kubectl_manifest" "cluster_role_binding" {
  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "ClusterRoleBinding"
    metadata   = { name = var.name }
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io"
      kind     = "ClusterRole"
      name     = var.name
    }
    subjects = [{
      kind      = "ServiceAccount"
      name      = var.name
      namespace = var.namespace
    }]
  })

  # roleRef and the subject name the role and the account as literal strings, so nothing else tells
  # Terraform they have to exist first (rules.md D-1).
  depends_on = [kubectl_manifest.cluster_role, kubectl_manifest.service_account]
}
resource "kubectl_manifest" "daemon_config" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = local.config_map_name
      namespace = var.namespace
      labels = {
        tier = "node"
        app  = var.name
      }
    }
    data = {
      # jsonencode rather than a heredoc, so the values above are typed and the file cannot end up
      # with a trailing comma or an unquoted string.
      "daemon-config.json" = jsonencode(local.daemon_config)
    }
  })
}
resource "kubectl_manifest" "daemon_set" {
  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "DaemonSet"
    metadata = {
      name      = "kube-multus-ds"
      namespace = var.namespace
      labels    = local.labels
    }
    spec = {
      selector       = { matchLabels = local.selector_labels }
      updateStrategy = { type = "RollingUpdate" }
      template = {
        metadata = { labels = local.labels }
        spec = {
          affinity = {
            nodeAffinity = {
              requiredDuringSchedulingIgnoredDuringExecution = {
                nodeSelectorTerms = [{
                  matchExpressions = [
                    {
                      key      = "kubernetes.io/os"
                      operator = "In"
                      values   = ["linux"]
                    },
                    {
                      # Fargate nodes have no host filesystem to install a CNI binary onto, and the
                      # DaemonSet would sit Pending on them forever.
                      key      = "eks.amazonaws.com/compute-type"
                      operator = "NotIn"
                      values   = ["fargate"]
                    },
                  ]
                }]
              }
            }
          }
          # Both required: Multus writes CNI configuration and binaries onto the host and works in
          # the host's network namespaces.
          hostNetwork = true
          hostPID     = true
          tolerations = [
            { operator = "Exists", effect = "NoSchedule" },
            { operator = "Exists", effect = "NoExecute" },
          ]
          serviceAccountName            = var.name
          terminationGracePeriodSeconds = 10
          # Copies the shim the kubelet actually calls into the host's CNI binary directory. Until
          # this has run on a node, Multus is installed as far as Kubernetes is concerned and does
          # nothing.
          initContainers = [{
            name  = "install-multus-binary"
            image = var.image
            command = [
              "cp",
              "/usr/src/multus-cni/bin/multus-shim",
              "/host/opt/cni/bin/multus-shim",
            ]
            resources = {
              requests = {
                cpu    = "10m"
                memory = "15Mi"
              }
            }
            securityContext = { privileged = true }
            volumeMounts = [{
              name      = "cnibin"
              mountPath = "/host/opt/cni/bin"
              # Bidirectional, so the copy is visible to the kubelet on the host rather than only
              # inside this container.
              mountPropagation = "Bidirectional"
            }]
          }]
          containers = [{
            name            = "kube-multus"
            image           = var.image
            command         = ["/usr/src/multus-cni/bin/multus-daemon"]
            securityContext = { privileged = true }
            resources = {
              requests = {
                cpu    = var.cpu_request
                memory = var.memory_request
              }
              limits = {
                cpu    = var.cpu_request
                memory = var.memory_request
              }
            }
            volumeMounts = [
              { name = "cni", mountPath = "/host/etc/cni/net.d" },
              { name = "host-run", mountPath = "/host/run" },
              { name = "host-var-lib-cni-multus", mountPath = "/var/lib/cni/multus" },
              { name = "host-var-lib-kubelet", mountPath = "/var/lib/kubelet" },
              { name = "host-run-k8s-cni-cncf-io", mountPath = "/run/k8s.cni.cncf.io" },
              {
                name      = "host-run-netns"
                mountPath = "/run/netns"
                # HostToContainer, so network namespaces created after this container started are
                # visible to it - which is every pod the node schedules from now on.
                mountPropagation = "HostToContainer"
              },
              {
                name      = "multus-daemon-config"
                mountPath = "/etc/cni/net.d/multus.d"
                readOnly  = true
              },
              {
                name             = "hostroot"
                mountPath        = "/hostroot"
                mountPropagation = "HostToContainer"
              },
            ]
          }]
          volumes = [
            { name = "cni", hostPath = { path = "/etc/cni/net.d" } },
            { name = "cnibin", hostPath = { path = "/opt/cni/bin" } },
            { name = "hostroot", hostPath = { path = "/" } },
            {
              name = "multus-daemon-config"
              configMap = {
                name  = local.config_map_name
                items = [{ key = "daemon-config.json", path = "daemon-config.json" }]
              }
            },
            { name = "host-run", hostPath = { path = "/run" } },
            { name = "host-var-lib-cni-multus", hostPath = { path = "/var/lib/cni/multus" } },
            { name = "host-var-lib-kubelet", hostPath = { path = "/var/lib/kubelet" } },
            { name = "host-run-k8s-cni-cncf-io", hostPath = { path = "/run/k8s.cni.cncf.io" } },
            { name = "host-run-netns", hostPath = { path = "/run/netns/" } },
          ]
        }
      }
    }
  })

  # The service account and the config map are named as literal strings in the pod spec, so nothing
  # else orders them (rules.md D-1). The CRD is not referenced at all and still has to exist first,
  # because the daemon lists NetworkAttachmentDefinitions as soon as it starts.
  depends_on = [
    kubectl_manifest.network_attachment_definition_crd,
    kubectl_manifest.cluster_role_binding,
    kubectl_manifest.daemon_config,
  ]
}
