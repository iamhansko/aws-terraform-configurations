# An HTTPRoute, which is what the AWS Gateway API Controller turns into a VPC Lattice service with
# listeners, rules and target groups.
#
# The controller writes the Lattice-assigned domain name back onto this object as the annotation
# application-networking.k8s.aws/lattice-assigned-domain-name. That is the address the demo curls, and
# it is not knowable at apply time - so this project's outputs carry the command that reads it rather
# than a value (rules.md G-1's reasoning, applied to Lattice rather than a load balancer).
resource "kubectl_manifest" "http_route" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = var.name
      namespace = var.namespace
    }
    spec = {
      parentRefs = [{
        name = var.gateway_name
        # Which listener on that Gateway. Named rather than left out, so adding a second listener later
        # does not silently attach this route to both.
        sectionName = var.listener_name
      }]
      rules = [
        for rule in var.rules : merge(
          {
            backendRefs = [
              for backend in rule.backends : merge(
                {
                  name = backend.name
                  kind = "Service"
                  port = backend.port
                },
                # Omitted rather than defaulted when no weight was given: a rule with one backend and no
                # weight is the plain case, and writing weight: 1 there would suggest a split that is not
                # happening (rules.md B-4).
                backend.weight == null ? {} : { weight = backend.weight },
              )
            ]
          },
          # Omitted for a rule that matches everything. The Gateway API treats a rule with no matches as
          # matching all paths, which is what the canary shape relies on.
          rule.path_prefix == null ? {} : {
            matches = [{
              path = {
                type  = "PathPrefix"
                value = rule.path_prefix
              }
            }]
          },
        )
      ]
    }
  })

  # The controller puts a httproute.k8s.aws/resources finalizer on this object, and clearing it is what
  # deletes the VPC Lattice service, its listeners and its target groups. Without wait the provider
  # issues the DELETE and returns while the object is still Terminating, so destroy goes on to uninstall
  # the controller seconds later - and then nothing is left to clear the finalizer. The object never goes
  # away, the CRD behind it blocks forever on customresourcecleanup, and the Lattice service survives the
  # destroy as an orphan. Ordering this module after the controller is necessary but not sufficient on its
  # own: the ordering only decides when the DELETE is sent, not when it finishes (rules.md D-4/D-7).
  wait = true
}
