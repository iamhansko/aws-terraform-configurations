# The Karmada control plane on the parent cluster.
#
# This replaces `kubectl karmada init`, which is what the guidance installer ran. The two are different
# front ends onto the same components - etcd, karmada-apiserver, karmada-aggregated-apiserver,
# kube-controller-manager, karmada-controller-manager, karmada-scheduler, karmada-webhook and
# karmada-metrics-adapter - and the chart is the one that can be a Terraform resource, so it is the one used
# here (rules.md E-1).
#
# What the installer passed to karmada init, and where each of those lands here:
#
#   --karmada-apiserver-replicas 3        -> apiServer.replicaCount
#   --etcd-replicas 3                     -> etcd.internal.replicaCount. The installer's own template said 3
#                                            and the project then patched it to 1 with a sed on
#                                            deploy-karmada-functions.sh; see the etcd_replicas variable for
#                                            why, and note that the patch is now just a default.
#   --etcd-storage-mode PVC               -> etcd.internal.storageType = "pvc"
#   --storage-classes-name ebs-sc         -> etcd.internal.pvc.storageClass
#   --cert-external-dns "*.elb...."       -> a SAN on the certificate, in modules/karmada_certificates
#   --karmada-apiserver-advertise-address -> not needed. That flag existed because karmada init had to put
#                                            the load balancer's address into the certificate it was about
#                                            to generate, and the script resolved the address by running
#                                            `ping` on the load balancer's DNS name to scrape the IP out of
#                                            the first line of output. Here the certificate is generated
#                                            before the chart is installed and carries the name itself.
#   --karmada-data / --karmada-pki        -> nothing. Those were directories on the workbench's disk holding
#                                            the generated PKI and a kubeconfig. The PKI is in Terraform
#                                            state instead, and the kubeconfig is rendered as an output.
#
# hashicorp/helm needs no workaround for being pointed at a cluster created in the same apply: it does not
# contact the API server during plan, only during apply (rules.md E-2). That is why the control plane is a
# helm_release while the StorageClass next to it has to be a kubectl_manifest.
locals {
  # The image tags that cannot be set by setting karmadaImageVersion.
  #
  # The chart declares `karmadaImageVersion: &karmadaImageVersion latest` and then writes
  # `tag: *karmadaImageVersion` on each component. A YAML anchor is resolved when values.yaml is parsed, so
  # by the time user values are merged those tags are already the literal string "latest" - overriding
  # karmadaImageVersion alone changes nothing except the karmada-version ConfigMap the static-resource job
  # writes. Each component's tag has to be set individually, and a component missed here runs :latest: it
  # works today, and reinstalling months later silently installs a different Karmada.
  # These four and no more, because these are the Karmada components the chart actually installs in host
  # mode. The chart also has values for metricsAdapter, descheduler, search and schedulerEstimator, and all
  # four are gated on being listed in .Values.components, which this module leaves empty - tagging them
  # would render nothing and read as though they were deployed. Confirmed by rendering the chart rather than
  # by reading the values file, which lists them all without saying which are conditional.
  component_image_tags = {
    for component in [
      "scheduler",
      "webhook",
      "controllerManager",
      "aggregatedApiServer",
    ] : component => { image = { tag = var.karmada_image_version } }
  }
}
resource "helm_release" "karmada" {
  name             = var.release_name
  repository       = var.chart_repository
  chart            = "karmada"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = true
  # Blocks the apply until every object in the release is ready, which is what makes this resource a usable
  # ordering edge for the agents and the demo workload that follow it.
  wait = true
  # And this is the half that is easy to miss, because it defaults to false and `wait = true` reads as
  # though it covered everything. It does not cover Jobs - and the object that installs Karmada's CRDs into
  # the new API server is a Job, karmada-static-resource, declared as an ordinary chart resource rather than
  # as a hook. Without this, helm returns once the Deployments are Available while that Job is still
  # running, and the next module applies a PropagationPolicy against an API server whose CRDs do not exist
  # yet. The error that produces names the resource type as unknown, which points at the manifest rather
  # than at the race.
  wait_for_jobs = true
  timeout       = var.timeout_seconds
  # values rather than a list of set entries. Seven of the values below are multi-line PEM documents and the
  # rest are nested two or three deep; expressing that through set would mean one escaped string per leaf,
  # which is where a number or a bool arrives as a string and breaks a chart guard silently (rules.md E-7).
  # A single yamlencode keeps every value the type it is written as.
  values = [yamlencode(merge(local.component_image_tags, {
    installMode = "host"
    # Both, and they are different things. clusterDomain is the host cluster's DNS suffix, used to build the
    # in-cluster service names the components talk to each other on - it has to match the SANs in
    # modules/karmada_certificates. systemNamespace is the namespace the chart's static resources are
    # created in inside the Karmada API server, which is a different API server from the one this release
    # is installed into.
    clusterDomain   = var.cluster_domain
    systemNamespace = var.namespace
    # Only reaches the karmada-version ConfigMap; see local.component_image_tags above.
    karmadaImageVersion = var.karmada_image_version

    # The two images in this release that are not Karmada components, and that the chart therefore leaves on
    # :latest. Both are surfaced as variables rather than left at the chart's defaults, because both sit in
    # the critical path and neither failure says "image":
    #
    #   kubectl - runs the karmada-static-resource Job, which installs Karmada's CRDs. If it cannot be
    #             pulled, helm waits out its whole timeout and reports a Job that never completed.
    #   cfssl   - not a certificate generator here, despite the name and despite certs.mode being custom.
    #             The chart uses this image as the "wait" init container on every component, polling etcd
    #             until it answers. If it cannot be pulled, nothing in the release ever leaves Init.
    kubectl = {
      image = {
        registry   = var.hook_kubectl_image_registry
        repository = var.hook_kubectl_image_repository
        tag        = var.hook_kubectl_image_tag
      }
    }
    cfssl = {
      image = {
        registry   = var.wait_image_registry
        repository = var.wait_image_repository
        tag        = var.wait_image_tag
      }
    }

    # certs.mode custom, which is the decision modules/karmada_certificates exists for - in auto mode the
    # chart generates this material inside the cluster with a cfssl job and Terraform never learns the
    # client certificate, so neither the member agents nor a provider aimed at the Karmada API server could
    # be configured. The seven keys here are exactly what charts/karmada/templates/karmada-cert.yaml reads.
    certs = {
      mode = "custom"
      custom = {
        caCrt           = var.ca_cert_pem
        caKey           = var.ca_private_key_pem
        crt             = var.cert_pem
        key             = var.private_key_pem
        frontProxyCaCrt = var.front_proxy_ca_cert_pem
        frontProxyCrt   = var.front_proxy_cert_pem
        frontProxyKey   = var.front_proxy_private_key_pem
      }
    }

    apiServer = {
      replicaCount = var.apiserver_replicas
      # NodePort, so that a load balancer Terraform owns can forward to it. The chart's default is ClusterIP,
      # and LoadBalancer is the other option - but a LoadBalancer Service hands the load balancer's creation
      # to a controller in the cluster, which puts its DNS name outside Terraform's reach. See
      # modules/karmada_api_load_balancer for why that address has to be a value here.
      serviceType = "NodePort"
      nodePort    = var.node_port
      # No image override. The Karmada components are tagged above because the chart leaves them on
      # :latest; kube-apiserver and kube-controller-manager are not - the chart pins both to a specific
      # Kubernetes patch release already, and restating it here would mean keeping a variable in step with
      # the chart for no gain.
    }

    etcd = {
      mode = "internal"
      internal = {
        replicaCount = var.etcd_replicas
        # pvc, not the chart's default of hostPath. hostPath puts etcd's data on whichever node the pod
        # landed on, so replacing that node loses the Karmada control plane's entire state - every
        # registered cluster and every policy. This is what the installer's --etcd-storage-mode PVC asked
        # for, and it is why the parent cluster is the one cluster here that gets the EBS CSI driver.
        storageType = "pvc"
        pvc = {
          storageClass = var.etcd_storage_class_name
          size         = var.etcd_volume_size
        }
      }
    }
  }))]
}
