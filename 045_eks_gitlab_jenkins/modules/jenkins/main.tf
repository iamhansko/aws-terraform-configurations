# The Jenkins chart, as a Helm release rather than as a `helm upgrade --install`
# inside a shell script an SSM Association ran on the workbench (rules.md E-1).
# The _monolithic template wrote that script to /home/ec2-user/jenkins.sh, ran
# it, and then patched the Ingress afterwards with kubectl - so neither the
# release nor the Ingress class was in state.
resource "helm_release" "jenkins" {
  name             = var.release_name
  repository       = var.chart_repository
  chart            = "jenkins"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = var.create_namespace

  # Holds the apply until the controller StatefulSet is ready, which is what the
  # _monolithic script's --wait did. Worth keeping here, unlike the GitLab
  # release: this is one StatefulSet with one PersistentVolumeClaim, and if it
  # cannot bind a volume that is exactly what the caller needs to find out.
  wait    = var.wait
  timeout = var.timeout_seconds

  set = concat([
    {
      name  = "controller.admin.username"
      value = var.admin_username
      type  = "string"
    },
    {
      name  = "controller.jenkinsAdminEmail"
      value = var.admin_email
      type  = "string"
    },
    {
      name = "controller.ingress.enabled"
      # A boolean the chart tests with `if`, so it is left to auto inference
      # rather than forced to a string (rules.md E-7).
      value = "true"
    },
    {
      # Set here rather than patched in afterwards. The _monolithic script
      # installed the chart with ingress.enabled and then ran
      # `kubectl patch ingress jenkins` to put the class on it, which left the
      # Ingress unclaimed in between - and left the patch untracked, so the next
      # helm upgrade would drop it again (rules.md E-1).
      name  = "controller.ingress.ingressClassName"
      value = var.ingress_class_name
      type  = "string"
    },
    {
      name = "controller.serviceType"
      # ClusterIP: the ingress-nginx controller in front of this release is what
      # holds the load balancer. A LoadBalancer Service here would build a second
      # one for the same application.
      value = "ClusterIP"
      type  = "string"
    },
    ],
    # Only set when the caller gave a hostname. Left empty the chart emits an
    # Ingress rule with no host, which matches every request the controller
    # receives - fine for a single application behind its own controller, wrong
    # as soon as a second one shares it (rules.md B-4).
    var.ingress_hostname == null ? [] : [{
      name  = "controller.ingress.hostName"
      value = var.ingress_hostname
      type  = "string"
    }],
    var.persistence_storage_class == null ? [] : [{
      name  = "persistence.storageClass"
      value = var.persistence_storage_class
      type  = "string"
    }],
    var.additional_set_values,
  )

  # set_sensitive rather than set, so the password does not appear in plan output
  # or in the state's rendered value list. The chart still writes it into its own
  # Secret in the cluster, which is where Jenkins reads it from.
  set_sensitive = [
    {
      name  = "controller.admin.password"
      value = var.admin_password
      type  = "string"
    },
  ]
}
