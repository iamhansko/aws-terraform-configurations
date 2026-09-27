resource "helm_release" "kube_prometheus_stack" {
  name = var.release_name
  # No repository argument: an oci:// reference carries the registry itself, and
  # setting both makes helm treat the chart name as a path under the repository.
  chart            = var.chart
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = var.create_namespace
  wait             = true
  timeout          = var.timeout_seconds

  set = concat([
    # Each component gets an Ingress on its own class, which is what puts the
    # three UIs behind three separate load balancers. The class names come from
    # the controller modules that own them rather than being spelled again here
    # (rules.md B-5) - an Ingress naming a class no controller owns is created
    # successfully and then simply never gets an address.
    {
      name  = "grafana.ingress.enabled"
      value = "true"
    },
    {
      name  = "grafana.ingress.ingressClassName"
      value = var.grafana_ingress_class_name
    },
    {
      name  = "prometheus.ingress.enabled"
      value = "true"
    },
    {
      name  = "prometheus.ingress.ingressClassName"
      value = var.prometheus_ingress_class_name
    },
    {
      name  = "alertmanager.ingress.enabled"
      value = "true"
    },
    {
      name  = "alertmanager.ingress.ingressClassName"
      value = var.alertmanager_ingress_class_name
    },
    {
      name  = "grafana.adminUser"
      value = var.grafana_admin_user
    },
    {
      name  = "grafana.adminPassword"
      value = var.grafana_admin_password
    },
    ],
    # Prometheus and Alertmanager both keep their data on a persistent volume, so
    # each gets a volumeClaimTemplate. The chart's storageSpec default is {} and it
    # supplies no defaults underneath it, so every field the PVC needs has to be set
    # here - naming only the StorageClass produces a claim template with nothing but
    # spec.storageClassName, which the API server rejects:
    #
    #   PersistentVolumeClaim "..." is invalid: spec.resources[storage]: Required value
    #
    # and that rejection surfaces in a way that hides the cause. helm reports the
    # release as deployed, because the CRs it created are valid; the operator turns
    # them into StatefulSets, also successfully; and then the StatefulSet controller
    # cannot create pod 0. So the release looks healthy while Prometheus and
    # Alertmanager have no pods at all, their Services have no endpoints, and Grafana
    # answers "no data" for a reason nothing in the release reports.
    var.storage_class_name == null ? [] : [
      {
        name  = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName"
        value = var.storage_class_name
      },
      # ReadWriteOnce because the volume is an EBS one, which attaches to a single
      # node. It is required rather than defaulted by the chart.
      {
        name  = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.accessModes[0]"
        value = "ReadWriteOnce"
      },
      {
        name  = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage"
        value = var.prometheus_storage_size
      },
      {
        name  = "alertmanager.alertmanagerSpec.storage.volumeClaimTemplate.spec.storageClassName"
        value = var.storage_class_name
      },
      {
        name  = "alertmanager.alertmanagerSpec.storage.volumeClaimTemplate.spec.accessModes[0]"
        value = "ReadWriteOnce"
      },
      {
        name  = "alertmanager.alertmanagerSpec.storage.volumeClaimTemplate.spec.resources.requests.storage"
        value = var.alertmanager_storage_size
      },
    ],
    var.additional_set_values,
  )
}
