# The demo workload, created on the Karmada API server rather than on any member cluster.
#
# This is what the guidance installer's -t flag produced, in eks_karmada_demo_deploy: a PropagationPolicy
# named sample-propagation, and a Deployment named karmada-demo-nginx with four replicas, both applied with
# `kubectl --kubeconfig ~/.karmada/karmada-apiserver.config`. It is also the only part of that script whose
# output proves the whole thing worked - a Karmada control plane with members registered and nothing
# propagated looks identical to one that cannot schedule.
#
# Both objects go to the Karmada API server, which is a different API server from the parent cluster's. That
# is the whole point and it is easy to misread: the Deployment below creates no pods where it is submitted.
# Karmada's scheduler reads it, divides its replicas between the member clusters named in the policy, and
# the agent in each member creates the real Deployment there. So:
#
#   kubectl --kubeconfig <karmada> get deployments   -> one Deployment, 4 replicas, an aggregate status
#   kubectl --context <member-1> get pods            -> 2 nginx pods
#   kubectl --context <member-2> get pods            -> 2 nginx pods
#
# Declared through alekc/kubectl: a PropagationPolicy is a custom resource whose CRD is installed by the
# Helm release in this same apply, so hashicorp/kubernetes could not resolve its schema at plan time even if
# its provider could be configured here at all (rules.md E-2/E-3).
resource "kubectl_manifest" "propagation_policy" {
  yaml_body = yamlencode({
    apiVersion = "policy.karmada.io/v1alpha1"
    kind       = "PropagationPolicy"
    metadata = {
      name      = var.propagation_policy_name
      namespace = var.namespace
    }
    spec = {
      # Selects by kind and name, as the installer's policy did. A PropagationPolicy only governs resources
      # in its own namespace, which is why both objects are in the same one - and why a policy that names a
      # Deployment in another namespace is accepted and then governs nothing.
      resourceSelectors = [{
        apiVersion = "apps/v1"
        kind       = "Deployment"
        name       = var.deployment_name
      }]
      placement = {
        clusterAffinity = {
          clusterNames = var.member_cluster_names
        }
        replicaScheduling = {
          # Divided with a Weighted preference and equal static weights, as the installer's policy had it:
          # the Deployment's four replicas are split between the member clusters rather than four being run
          # in each. The alternative, Duplicated, would run the full replica count in every cluster - which
          # is a different demo, and one where a misconfigured policy is much harder to notice.
          replicaDivisionPreference = "Weighted"
          replicaSchedulingType     = "Divided"
          weightPreference = {
            # One entry naming every cluster with weight 1, which is how the installer expressed "equal
            # shares". A list of one entry per cluster would say the same thing; this is the original's
            # shape, and it keeps the weights equal by construction rather than by all the numbers
            # happening to match.
            staticWeightList = [{
              targetCluster = {
                clusterNames = var.member_cluster_names
              }
              weight = var.cluster_weight
            }]
          }
        }
      }
    }
  })
  # The karmada-controller-manager adds karmada.io/propagation-policy-controller to this object, and removing
  # that finalizer is how it unbinds the resources the policy governs. kubectl_manifest's delete returns as
  # soon as the API server accepts the request unless this is set, which would let the destroy move on to
  # uninstalling the control plane while the policy is still Terminating - leaving nothing to remove the
  # finalizer (rules.md D-7).
  wait = true
}
resource "kubectl_manifest" "demo_deployment" {
  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = var.deployment_name
      namespace = var.namespace
      labels    = { app = var.deployment_name }
    }
    spec = {
      replicas = var.replicas
      selector = {
        matchLabels = { app = var.deployment_name }
      }
      template = {
        metadata = {
          labels = { app = var.deployment_name }
        }
        spec = {
          containers = [{
            name  = var.container_name
            image = "${var.image_repository}:${var.image_tag}"
            ports = [{ containerPort = var.container_port }]
          }]
        }
      }
    }
  })
  # Off, and this one has to be set explicitly because the provider defaults it to true.
  #
  # wait_for_rollout works by watching the Deployment's status the way `kubectl rollout status` does, and
  # that status is produced by a Deployment controller. The Karmada API server has no Deployment controller:
  # the kube-controller-manager the chart deploys alongside it runs only the namespace and garbage
  # collection controllers. What fills in this object's status instead is Karmada, aggregating the real
  # Deployments' status back from the member clusters - which is a different thing arriving by a different
  # route, and not something `rollout status` logic can be relied on to accept.
  #
  # Left at the default, the likely outcome is an apply that hangs until the resource's timeout on a
  # workload that is in fact running, with the pods visible in both member clusters the whole time. The
  # outputs' check commands are the signal instead; see scheduling_decision_command, which reads the
  # scheduler's actual per-cluster decision.
  wait_for_rollout = false
  # No wait here either, unlike the policy above. Karmada attaches its finalizers to the ResourceBinding and
  # the Work objects it derives from this Deployment, not to the Deployment itself, so there is nothing for
  # a foreground delete to wait on (rules.md D-7's test is whether a controller attaches a finalizer to this
  # object, and here it does not).
  #
  # Created after the policy, which is the order the installer used. Either order ends up in the same place -
  # Karmada picks up a resource when a matching policy appears - but a Deployment created first sits
  # unscheduled with no status for as long as that takes, which reads like a failure.
  depends_on = [kubectl_manifest.propagation_policy]
}
