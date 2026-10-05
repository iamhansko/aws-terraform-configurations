# whereabouts, the IPAM plugin Multus calls to hand addresses to the secondary interfaces.
#
# What it replaces and why. host-local, which this project used before, keeps its allocation store
# in a directory on the node - /var/lib/cni/networks/<network>/. That store is per node, and nothing
# reconciles one node's copy with another's, so every node starts allocating at the bottom of the
# range. With one node that is invisible; with two, both nodes hand out the same first address and
# two pods end up with the same address on the same subnet. whereabouts keeps the store in the
# cluster instead, as IPPool custom resources, so the range is shared and an address is handed out
# once.
#
# Declared as objects through alekc/kubectl rather than applied from the upstream URL, for the
# reasons rules.md E-1/E-2/E-3 give: the version is pinned here rather than being whatever the
# default branch held on the day the node booted, the objects are in state so they appear in a plan
# and are removed by a destroy, and the CRDs below are created in the same apply as the cluster.
#
# The CRD schemas are transcribed from doc/crds/ at the pinned tag. The kubebuilder boilerplate
# describing apiVersion, kind and metadata is left out: it is documentation, carries no validation,
# and the API server handles those fields regardless.
locals {
  labels = {
    tier = "node"
    app  = var.name
  }
  pod_labels = merge(local.labels, { name = var.name })
  crd_group  = "whereabouts.cni.cncf.io"
  # Upstream names the ClusterRole "whereabouts-cni" while the ServiceAccount and the binding are
  # "whereabouts". Kept as upstream has it rather than tidied, because the role is the object a
  # reader is most likely to compare against the published manifest.
  cluster_role_name = "${var.name}-cni"
  config_map_name   = "${var.name}-config"
}
resource "kubectl_manifest" "ippool_crd" {
  yaml_body = yamlencode({
    apiVersion = "apiextensions.k8s.io/v1"
    kind       = "CustomResourceDefinition"
    metadata   = { name = "ippools.${local.crd_group}" }
    spec = {
      group = local.crd_group
      names = {
        kind     = "IPPool"
        listKind = "IPPoolList"
        plural   = "ippools"
        singular = "ippool"
      }
      scope = "Namespaced"
      versions = [{
        name    = "v1alpha1"
        served  = true
        storage = true
        schema = {
          openAPIV3Schema = {
            description = "IPPool is the Schema for the ippools API"
            type        = "object"
            properties = {
              spec = {
                description = "IPPoolSpec defines the desired state of IPPool"
                type        = "object"
                required    = ["allocations", "range"]
                properties = {
                  # The map that makes this cluster-wide: one entry per allocated address, keyed by
                  # the offset of that address into the pool's range. This is the object two nodes
                  # would have had to agree on and could not, with host-local.
                  allocations = {
                    description = "Allocations is the set of allocated IPs for the given range, indexed by offset into it"
                    type        = "object"
                    additionalProperties = {
                      description = "IPAllocation represents metadata about the pod or container owner of a specific IP"
                      type        = "object"
                      required    = ["id", "podref"]
                      properties = {
                        id     = { type = "string" }
                        ifname = { type = "string" }
                        podref = { type = "string" }
                      }
                    }
                  }
                  range = {
                    description = "Range is a RFC 4632/4291-style string that represents an IP address and prefix length in CIDR notation"
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
resource "kubectl_manifest" "overlappingrangeipreservation_crd" {
  yaml_body = yamlencode({
    apiVersion = "apiextensions.k8s.io/v1"
    kind       = "CustomResourceDefinition"
    metadata   = { name = "overlappingrangeipreservations.${local.crd_group}" }
    spec = {
      group = local.crd_group
      names = {
        kind     = "OverlappingRangeIPReservation"
        listKind = "OverlappingRangeIPReservationList"
        plural   = "overlappingrangeipreservations"
        singular = "overlappingrangeipreservation"
      }
      scope = "Namespaced"
      versions = [{
        name    = "v1alpha1"
        served  = true
        storage = true
        schema = {
          openAPIV3Schema = {
            description = "OverlappingRangeIPReservation is the Schema for the OverlappingRangeIPReservations API"
            type        = "object"
            required    = ["spec"]
            properties = {
              spec = {
                description = "OverlappingRangeIPReservationSpec defines the desired state of OverlappingRangeIPReservation"
                type        = "object"
                required    = ["podref"]
                properties = {
                  containerid = { type = "string" }
                  ifname      = { type = "string" }
                  podref      = { type = "string" }
                }
              }
            }
          }
        }
      }]
    }
  })
}
# Not used by this project's attachments, which give each interface a range of its own, but the
# controller's ClusterRole below lists it and the ip-control-loop watches for it - a missing CRD
# leaves it logging errors about a resource it cannot list.
resource "kubectl_manifest" "nodeslicepool_crd" {
  yaml_body = yamlencode({
    apiVersion = "apiextensions.k8s.io/v1"
    kind       = "CustomResourceDefinition"
    metadata   = { name = "nodeslicepools.${local.crd_group}" }
    spec = {
      group = local.crd_group
      names = {
        kind     = "NodeSlicePool"
        listKind = "NodeSlicePoolList"
        plural   = "nodeslicepools"
        singular = "nodeslicepool"
      }
      scope = "Namespaced"
      versions = [{
        name    = "v1alpha1"
        served  = true
        storage = true
        schema = {
          openAPIV3Schema = {
            description = "NodeSlicePool is the Schema for the nodesliceippools API"
            type        = "object"
            properties = {
              spec = {
                description = "NodeSlicePoolSpec defines the desired state of NodeSlicePool"
                type        = "object"
                required    = ["range", "sliceSize"]
                properties = {
                  range     = { type = "string" }
                  sliceSize = { type = "string" }
                }
              }
              status = {
                description = "NodeSlicePoolStatus defines the observed state of NodeSlicePool"
                type        = "object"
                required    = ["allocations"]
                properties = {
                  allocations = {
                    type = "array"
                    items = {
                      type     = "object"
                      required = ["nodeName", "sliceRange"]
                      properties = {
                        nodeName   = { type = "string" }
                        sliceRange = { type = "string" }
                      }
                    }
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
    metadata   = { name = local.cluster_role_name }
    rules = [
      {
        # The three CRDs above. This is where the allocation store lives, so write access to it is
        # the whole point of the plugin.
        apiGroups = [local.crd_group]
        resources = ["ippools", "overlappingrangeipreservations", "nodeslicepools"]
        verbs     = ["get", "list", "watch", "create", "update", "patch", "delete"]
      },
      {
        # Leases, which is how concurrent allocations on different nodes are serialised. Without
        # this the cluster-wide store would be read and written without coordination and two nodes
        # could still pick the same address - the problem host-local had, one layer up.
        apiGroups = ["coordination.k8s.io"]
        resources = ["leases"]
        verbs     = ["*"]
      },
      {
        apiGroups = [""]
        resources = ["pods"]
        verbs     = ["list", "watch", "get"]
      },
      {
        apiGroups = [""]
        resources = ["nodes"]
        verbs     = ["get", "list", "watch"]
      },
      {
        # The ip-control-loop reads attachments to find which ranges it is responsible for, and to
        # reclaim addresses whose pod is gone.
        apiGroups = ["k8s.cni.cncf.io"]
        resources = ["network-attachment-definitions"]
        verbs     = ["get", "list", "watch"]
      },
      {
        apiGroups = ["", "events.k8s.io"]
        resources = ["events"]
        verbs     = ["create", "patch", "update", "get"]
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
      name     = local.cluster_role_name
    }
    subjects = [{
      kind      = "ServiceAccount"
      name      = var.name
      namespace = var.namespace
    }]
  })

  # Both names are literal strings in the object above, so nothing else orders these
  # (rules.md D-1).
  depends_on = [
    kubectl_manifest.cluster_role,
    kubectl_manifest.service_account,
  ]
}
resource "kubectl_manifest" "config_map" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = local.config_map_name
      namespace = var.namespace
    }
    data = {
      # How often the reconciler sweeps the store for addresses whose pod no longer exists. Upstream
      # defaults to once a day; a demo that creates and destroys pods repeatedly wants it sooner,
      # which is why this is a variable rather than the upstream literal.
      "cron-expression" = var.reconciler_cron_expression
    }
  })
}
resource "kubectl_manifest" "daemon_set" {
  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "DaemonSet"
    metadata = {
      name      = var.name
      namespace = var.namespace
      labels    = local.labels
    }
    spec = {
      selector       = { matchLabels = { name = var.name } }
      updateStrategy = { type = "RollingUpdate" }
      template = {
        metadata = { labels = local.pod_labels }
        spec = {
          # Required: the container installs the plugin binary and its configuration onto the host,
          # and talks to the API server from the node's own network.
          hostNetwork        = true
          serviceAccountName = var.name
          tolerations = [
            { operator = "Exists", effect = "NoSchedule" },
          ]
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
                      # Not in the upstream manifest. Added for the same reason the Multus DaemonSet
                      # carries it: a Fargate node has no host filesystem to install a CNI binary
                      # onto, and the pod would sit Pending there forever.
                      key      = "eks.amazonaws.com/compute-type"
                      operator = "NotIn"
                      values   = ["fargate"]
                    },
                  ]
                }]
              }
            }
          }
          containers = [{
            name    = var.name
            image   = var.image
            command = ["/bin/sh"]
            args = [
              "-c",
              # Upstream's own entrypoint, verbatim in effect: install the binary and config onto
              # the host, keep the service account token fresh, then run the reconciler.
              join("\n", [
                "SLEEP=false source /install-cni.sh",
                "/token-watcher.sh &",
                "/ip-control-loop -log-level ${var.log_level}",
              ]),
            ]
            env = [
              {
                name = "NODENAME"
                valueFrom = {
                  fieldRef = {
                    apiVersion = "v1"
                    fieldPath  = "spec.nodeName"
                  }
                }
              },
              {
                name      = "WHEREABOUTS_NAMESPACE"
                valueFrom = { fieldRef = { fieldPath = "metadata.namespace" } }
              },
            ]
            resources = {
              requests = {
                cpu    = var.cpu_request
                memory = var.memory_request
              }
              limits = {
                cpu    = var.cpu_request
                memory = var.memory_limit
              }
            }
            securityContext = { privileged = true }
            volumeMounts = [
              { name = "cnibin", mountPath = "/host/opt/cni/bin" },
              { name = "cni-net-dir", mountPath = "/host/etc/cni/net.d" },
            ]
          }]
          volumes = [
            { name = "cnibin", hostPath = { path = "/opt/cni/bin" } },
            { name = "cni-net-dir", hostPath = { path = "/etc/cni/net.d" } },
          ]
        }
      }
    }
  })

  # The service account and the config map are named as literal strings in the pod spec, and the
  # CRDs are not referenced at all and still have to exist first - the reconciler lists them as soon
  # as it starts (rules.md D-1).
  depends_on = [
    kubectl_manifest.ippool_crd,
    kubectl_manifest.overlappingrangeipreservation_crd,
    kubectl_manifest.nodeslicepool_crd,
    kubectl_manifest.cluster_role_binding,
    kubectl_manifest.config_map,
  ]
}
