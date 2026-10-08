# One instance of the API the ResourceGraphDefinition created. Four lines of spec that kro expands
# into a Deployment and a Service, which is the only way to see that the definition works.
#
# A separate module from the definition on purpose. The kind this manifest uses does not exist when
# the definition is applied - kro has to process the definition and generate the CRD first - so the
# caller puts a wait between the two. Keeping both in one module would make that impossible: the
# wait would have to depend on the module and the module on the wait.
resource "kubectl_manifest" "instance" {
  yaml_body = yamlencode({
    apiVersion = var.api_version
    kind       = var.kind
    metadata = {
      name      = var.name
      namespace = var.namespace
    }
    # Only what the definition's schema exposes. image and replicas are left out so the defaults
    # declared there apply - which is what makes this a demonstration of the abstraction rather
    # than of a Deployment written in a different shape.
    spec = {
      name = var.workload_name
    }
  })

  # Ordered after whatever the caller uses to confirm the generated CRD is being served. Without it
  # this fails with "no matches for kind", because kro's work happens between the two applies
  # (rules.md D-4/D-5).
  depends_on = [var.api_dependency]
}
