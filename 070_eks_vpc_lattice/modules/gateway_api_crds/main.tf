# The Kubernetes Gateway API CRDs: GatewayClass, Gateway, HTTPRoute, GRPCRoute and ReferenceGrant.
#
# The _monolithic template installed them with
#
#   kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml
#
# from a shell on the bastion, which left them out of state entirely - and everything else in this
# project is an instance of one of them, so a destroy removed the Gateways and HTTPRoutes and left
# the CRDs behind.
#
# Declaring ten thousand lines of upstream CRD as HCL is not the answer either. Instead the bundle is
# fetched by the root at plan time and split into its documents here, and each document becomes a
# kubectl_manifest - so every CRD is in state, appears in plan, and is removed on destroy, while the
# content stays upstream's (rules.md E-1/E-2).
#
# ---------------------------------------------------------------------------------------------------
# Why the fetch is in the root and not here
# ---------------------------------------------------------------------------------------------------
#
# This module was first written with its own data "http", which reads as the obvious shape: the module
# owns its input. It cannot work, and the reason is worth keeping.
#
# The for_each below is keyed by the documents, because a resource address should name the CRD it is
# about. That means the documents have to be known at plan time - for_each keys become resource
# addresses (rules.md B-8). data "http" is an ordinary HTTP read with no dependency on the cluster, so
# on its own it is read during plan and the keys would be known.
#
# But the root orders this module after the node group with depends_on, and a depends_on on a module
# block applies to every data source inside that module as well as to its resources. Deferred data
# sources are not read during plan, so response_body was unknown, and the split derived from it was
# unknown, and the plan failed with
#
#   local.keyed_documents will be known only after apply
#
# which reads like a problem with the split rather than with the module's ordering (rules.md D-6).
#
# Moving the fetch to the root fixes it because the root's own data source carries no depends_on. The
# module keeps its ordering, because that ordering is about when the CRDs are *applied*.
# ---------------------------------------------------------------------------------------------------
locals {
  # A leading newline is prepended so that a bundle whose very first line is the separator splits the
  # same way as one that starts straight into a document.
  #
  # Splitting on a newline-fenced "---" rather than on the bare string is what makes this safe: a "---"
  # inside a CRD description - upstream has plenty of prose - is inside an indented block scalar, so it
  # can never sit at column 0 the way a real document separator does.
  raw_documents = split("\n---\n", "\n${var.bundle_yaml}")
  # The license header at the top of the bundle is comments only and decodes to null, so the filter drops
  # it as well as any trailing empty document.
  documents = [
    for document in local.raw_documents : document
    if try(yamldecode(document).kind, null) != null && try(yamldecode(document).metadata.name, null) != null
  ]
  # Keyed by kind and name, so a plan names the CRD it is about rather than an index - and so a CRD
  # inserted upstream does not renumber every resource after it.
  keyed_documents = {
    for document in local.documents :
    "${yamldecode(document).kind}/${yamldecode(document).metadata.name}" => document
  }
}
resource "kubectl_manifest" "crd" {
  for_each  = local.keyed_documents
  yaml_body = each.value
  # wait is a delete-side flag, not a create-side one. The provider documents it as "wait for finalizers
  # to complete on deleted objects before returning" and its schema description says the same - it does
  # nothing on create, so it is not what makes a newly applied CRD start serving its kind. An earlier
  # comment here claimed that, and it was wrong; the apply ordering is what gives establishment its slack.
  #
  # It is kept because of what it does on destroy. Deleting a CRD leaves the apiextensions controller
  # holding a customresourcecleanup finalizer until every instance of the kind is gone, so this delete has
  # to block on that rather than return and let the cluster be torn down around it. Removing this flag
  # would not fix a slow destroy - it would turn a visible failure into CRDs that look deleted while their
  # instances, and the AWS resources behind them, quietly survive (rules.md D-7).
  wait = true
}
