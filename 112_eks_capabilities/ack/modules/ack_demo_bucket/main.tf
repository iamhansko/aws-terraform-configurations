# A single ACK custom resource, which is the only way to see whether the ACK capability actually
# works. The capability reaching ACTIVE means EKS installed the controllers and their CRDs; it says
# nothing about whether the role it assumes can reach an AWS API.
#
# Declared as a kubectl_manifest rather than applied from the workbench, so the object is in
# Terraform state and `terraform destroy` removes it. That ordering matters more here than usual:
# with the CRD's default deletion behaviour, deleting this object deletes the S3 bucket. Leaving it
# behind would leave a bucket nothing in this configuration owns (rules.md E-1/E-3).
resource "kubectl_manifest" "demo_bucket" {
  yaml_body = yamlencode({
    apiVersion = "s3.services.k8s.aws/v1alpha1"
    kind       = "Bucket"
    metadata = {
      name      = var.name
      namespace = var.namespace
    }
    spec = {
      # The bucket's own name, which is global to all of AWS and has nothing to do with the
      # Kubernetes object's name. Suffixed by the caller with the account and region so two
      # deployments of this project do not collide on it.
      name = var.bucket_name
    }
  })

  # The Bucket CRD does not exist until the capability has installed the ACK controllers, and a
  # manifest whose kind is unregistered fails with "no matches for kind" rather than waiting for it.
  #
  # This also makes `terraform destroy` run in the reverse order: the object is deleted while the
  # controller that reconciles it is still installed. Deleting the capability first would leave the
  # object with a finalizer and no controller to clear it, and the delete would hang
  # (rules.md D-4).
  depends_on = [var.capability_dependency]
}
