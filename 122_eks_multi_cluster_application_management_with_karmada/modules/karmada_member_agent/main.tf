# Registers one member cluster with Karmada, by installing karmada-agent onto it.
#
# This replaces `kubectl karmada join`, which is what the guidance installer ran once per member. The two
# produce the same thing - a Cluster object on the Karmada API server, which is what `kubectl get clusters`
# lists and what a PropagationPolicy's clusterNames refer to - but they get there from opposite directions,
# and the difference shows up in one column:
#
#   karmada join  -> syncMode Push. The control plane connects out to the member's API server. To set that
#                    up, karmada join creates a ServiceAccount in the member cluster, reads the token
#                    Kubernetes issues for it, and writes that token into a Secret on the control plane
#                    alongside the Cluster object.
#   this module    -> syncMode Pull. The agent runs inside the member cluster, uses its own ServiceAccount
#                    for local access, and dials out to the Karmada API server. It creates its own Cluster
#                    object on arrival.
#
# Pull mode is used here because push mode is not expressible in Terraform in this root. It requires reading
# a ServiceAccount token back out of each member cluster, and there is no way to do that: alekc/kubectl has
# no data source for an arbitrary object, and hashicorp/kubernetes - which has kubernetes_secret - cannot be
# configured at all here, because the clusters it would read from are created in the same apply
# (rules.md E-2). A shell step on the workbench could do it, which is what the installer was.
#
# What that costs, stated rather than buried: the member clusters appear as Pull rather than Push in
# `kubectl get clusters`, and each one runs an extra Deployment. Scheduling, propagation, status collection
# and the demo workload all behave the same way - Karmada supports both modes as equals, and a
# PropagationPolicy cannot tell them apart.
#
# The chart is the same chart as the control plane's, with installMode flipped. Everything under certs is
# gated on installMode == host, so none of it renders here; the agent's only credential is the kubeconfig
# built from the values below.
resource "helm_release" "karmada_agent" {
  name             = var.release_name
  repository       = var.chart_repository
  chart            = "karmada"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = true
  # Waits for the agent Deployment to be Available. That is not the same as the cluster being registered -
  # the agent creates its Cluster object after it starts, and marks it Ready once it has reported status -
  # so a caller that needs the registration to exist has to order itself after this and still allow for the
  # agent's first status cycle. See the root's wait before the demo workload.
  wait    = true
  timeout = var.timeout_seconds
  values = [yamlencode({
    installMode     = "agent"
    systemNamespace = var.namespace
    # Reaches only the karmada-version ConfigMap, not the agent's image tag; the tag is set below for the
    # reason spelled out in modules/karmada_control_plane/main.tf.
    karmadaImageVersion = var.karmada_image_version

    agent = {
      # Becomes --cluster-name, and therefore the name of the Cluster object on the control plane. This is
      # the string a PropagationPolicy's clusterAffinity.clusterNames has to match, which is why the root
      # passes the member cluster's own name here and uses the same value in the policy (rules.md B-5).
      clusterName = var.cluster_name
      # Becomes --cluster-api-endpoint, recorded as spec.apiEndpoint on the Cluster object. In pull mode
      # nothing connects to it - the agent dials out - so this is descriptive, but without it the Cluster
      # object has an empty endpoint and `kubectl get clusters -o wide` says nothing about where the member
      # actually is.
      clusterEndpoint = var.cluster_endpoint
      replicaCount    = var.replica_count
      image           = { tag = var.karmada_image_version }
      # The kubeconfig the agent uses to reach the Karmada API server, rendered by the chart into a Secret.
      # Every field here is a value Terraform knows only because the control plane was installed with
      # certs.mode custom - this is the half of that decision that pays for itself (see
      # modules/karmada_certificates).
      kubeconfig = {
        caCrt = var.karmada_ca_cert_pem
        crt   = var.karmada_cert_pem
        key   = var.karmada_private_key_pem
        # The load balancer's address, with scheme and port. Not the in-cluster Service name: this pod runs
        # in a different cluster, so the only name that resolves for it is the external one - and the
        # certificate has to carry that name as a SAN or the agent fails the TLS handshake and logs a
        # certificate error in a loop while the Cluster object never appears.
        server = var.karmada_api_endpoint
      }
    }
  })]
}
