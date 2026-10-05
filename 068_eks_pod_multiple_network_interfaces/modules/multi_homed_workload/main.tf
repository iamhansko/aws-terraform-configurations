# The pod that gets two network interfaces.
#
# Everything about this Deployment is ordinary except one annotation on the pod template. The VPC
# CNI, with ENABLE_MULTI_NIC set, gives a pod carrying k8s.amazonaws.com/nicConfig an interface
# from a second network card on the node instead of the usual single one.
#
# Three preconditions have to hold, and none of them is visible from this manifest
# (rules.md D-2):
#
#   - the VPC CNI is 1.20.0 or later and has ENABLE_MULTI_NIC=true, which the addon module sets
#     through configuration_values rather than a "kubectl set env daemonset aws-node" call
#     (rules.md E-5);
#   - the node's instance type has more than one network card. Not more than one ENI - every
#     instance type has several of those - but more than one card, which only the largest sizes of
#     a few families have;
#   - the pod is scheduled onto such a node.
#
# When any of them fails the pod starts normally with one interface and nothing reports a problem.
# That is what makes this demo worth having in state rather than in a shell script: the failure
# mode is silence, so the only way to know is to look inside the pod.
#
# The _monolithic template echoed this manifest into a file on the bastion and applied it with
# kubectl, so it was not in state - and the kubectl call sat after an "exec bash" line that
# discards every following line, so on a real boot it never ran (rules.md E-1/E-2).
resource "kubectl_manifest" "deployment" {
  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = var.name
      namespace = var.namespace
      labels    = { app = var.name }
    }
    spec = {
      replicas = var.replicas
      selector = {
        matchLabels = { app = var.name }
      }
      template = {
        metadata = merge(
          { labels = { app = var.name } },
          # Omitted entirely rather than set to an empty value when the comparison case is wanted:
          # an annotation with a value the feature does not recognise behaves exactly like no
          # annotation, so leaving it out is the honest way to express "without" (rules.md B-4).
          var.enable_multi_nic_annotation ? {
            annotations = {
              "k8s.amazonaws.com/nicConfig" = var.nic_config_annotation_value
            }
          } : {},
        )
        spec = {
          restartPolicy = "Always"
          containers = [{
            name            = "dnsutils"
            image           = var.image
            imagePullPolicy = var.image_pull_policy
          }]
        }
      }
    }
  })
}
