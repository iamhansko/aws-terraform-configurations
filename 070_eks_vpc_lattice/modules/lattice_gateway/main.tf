# The GatewayClass and the Gateway: the two objects that make the AWS Gateway API Controller build a
# VPC Lattice service network.
#
# Both are instances of CRDs installed by another module in this same apply, which is why the caller
# has to order this after them - and why they are declared through alekc/kubectl rather than
# hashicorp/kubernetes, whose plan-time schema lookup cannot work for a CRD created in the same run
# (rules.md E-2/E-3/D-2).
#
# The _monolithic template echoed both into a file on the bastion and applied them with kubectl, after
# an "exec bash" line that discards everything following it - so on a real boot neither reached the
# cluster (rules.md E-1).
resource "kubectl_manifest" "gateway_class" {
  yaml_body = yamlencode({
    # v1beta1 for the class, as the _monolithic template and AWS's own documentation have it. The
    # Gateway below is v1: the Gateway API promoted Gateway and HTTPRoute to v1 while GatewayClass
    # examples are still commonly written against v1beta1, and both are served by the same CRD. Kept as
    # the original had them rather than normalised, so the objects match what AWS documents.
    apiVersion = "gateway.networking.k8s.io/v1beta1"
    kind       = "GatewayClass"
    metadata = {
      name = var.gateway_class_name
    }
    spec = {
      # The string the controller watches for. A class naming anything else is created successfully and
      # claimed by nobody.
      controllerName = var.controller_name
    }
  })
}
resource "kubectl_manifest" "gateway" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = var.name
      namespace = var.namespace
    }
    spec = {
      gatewayClassName = var.gateway_class_name
      listeners = [{
        name     = var.listener_name
        protocol = var.listener_protocol
        port     = var.listener_port
      }]
    }
  })

  # The controller puts a gateway.k8s.aws/resources finalizer on this object, and clearing it is what
  # deletes the VPC Lattice service network and its VPC association. Without wait the DELETE returns
  # while the object is still Terminating, the controller is uninstalled moments later, and the finalizer
  # is left with nobody to clear it - which strands the service network and blocks the Gateway CRD on
  # customresourcecleanup for good (rules.md D-7).
  wait = true

  # gatewayClassName is a literal string rather than a reference, so nothing else tells Terraform the
  # class has to exist first (rules.md D-1). A Gateway whose class is missing is accepted and stays
  # without an address.
  depends_on = [kubectl_manifest.gateway_class]
}
