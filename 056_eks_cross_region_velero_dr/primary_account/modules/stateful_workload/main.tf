# The workload the backup is taken of: a StatefulSet with a PersistentVolumeClaim, and a Service in
# front of it.
#
# It has to have a volume, because that is the whole subject. A Deployment with no storage would be
# backed up and restored by Velero without any of the CSI snapshot machinery being exercised, and the
# demo would pass while proving nothing about the part that is hard.
#
# The _monolithic template wrote both objects as single-quoted shell strings inside user data and
# applied them with kubectl, so neither was in state: no diff in plan, nothing removed on destroy,
# and a YAML indentation error would have appeared only in cloud-init's log (rules.md E-1/E-2).
resource "kubectl_manifest" "service" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = var.service_name
      namespace = var.namespace
      labels    = { app = var.name }
      # Without aws-load-balancer-type: external the in-tree cloud provider claims this Service and
      # builds a Classic Load Balancer, ignoring the AWS Load Balancer Controller entirely - and the
      # Service still gets an EXTERNAL-IP, so it looks like it worked. The _monolithic template's
      # Service had no annotations at all while its bootstrap carefully installed the controller
      # (rules.md G-1).
      annotations = merge(
        {
          "service.beta.kubernetes.io/aws-load-balancer-type"            = "external"
          "service.beta.kubernetes.io/aws-load-balancer-scheme"          = var.load_balancer_scheme
          "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = var.nlb_target_type
        },
        var.service_annotations,
      )
    }
    spec = {
      type = "LoadBalancer"
      ports = [{
        name       = "web"
        port       = var.service_port
        targetPort = var.container_port
        protocol   = "TCP"
      }]
      selector = { app = var.name }
    }
  })
}
resource "kubectl_manifest" "statefulset" {
  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "StatefulSet"
    metadata = {
      name      = var.name
      namespace = var.namespace
      labels    = { app = var.name }
    }
    spec = {
      # The headless-service name a StatefulSet uses for its pods' stable DNS names. Pointed at the
      # Service above, as the _monolithic template did - which is not strictly correct, because that
      # Service is type LoadBalancer rather than headless, and per-pod DNS therefore does not resolve.
      # Kept because it is what the original had and the demo does not use per-pod DNS; a real
      # StatefulSet needs a second, headless Service for this field.
      serviceName = var.service_name
      replicas    = var.replicas
      selector = {
        matchLabels = { app = var.name }
      }
      template = {
        metadata = {
          labels = { app = var.name }
        }
        spec = {
          containers = [{
            name  = var.name
            image = var.image
            ports = [{
              name          = "web"
              containerPort = var.container_port
            }]
            volumeMounts = [{
              name      = var.volume_name
              mountPath = var.mount_path
            }]
            resources = {
              requests = {
                cpu    = var.cpu_request
                memory = var.memory_request
              }
            }
          }]
        }
      }
      volumeClaimTemplates = [{
        metadata = { name = var.volume_name }
        spec = {
          accessModes = ["ReadWriteOnce"]
          # The class the storage module created, taken from its output rather than restated. A claim
          # naming a class that does not exist stays Pending, and the StatefulSet reports nothing
          # about why (rules.md B-5).
          storageClassName = var.storage_class_name
          resources = {
            requests = { storage = var.volume_size }
          }
        }
      }]
    }
  })

  # The Service's selector matches this StatefulSet's pods by a literal label rather than a
  # reference, so nothing else orders the two (rules.md D-1). Creating the Service first means the
  # controller has an empty target group briefly rather than the pods having nowhere to be
  # registered.
  depends_on = [kubectl_manifest.service]
}
