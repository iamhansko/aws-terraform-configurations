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
locals {
  # The command that writes a recognisable line into each pod's volume, one per replica in ordinal
  # order, and the single place it is written down - write_test_data_command is the first of them, so
  # what a caller prints and what a caller runs cannot drift apart (rules.md B-5).
  #
  # The claim is mounted over the directory nginx serves, and a new EBS volume is an empty ext4
  # filesystem. The mount hides the index.html the image put there, so until a file is written nginx -
  # asked for a directory, finding no index file, with autoindex off - answers every GET / with 403
  # and logs
  #
  #   directory index of "/usr/share/nginx/html/" is forbidden
  #
  # Every replica has its own volume, so writing to the first leaves the rest empty, and the Service
  # spreads requests across all of them: some are served and some are refused, which reads as a flaky
  # load balancer rather than as an empty volume. Hence one command per pod.
  #
  # var.name, var.namespace and var.mount_path go into a shell command, which is why each is
  # restricted by a validation rather than escaped here.
  write_test_data_commands = [
    for ordinal in range(var.replicas) :
    "kubectl -n ${var.namespace} exec ${var.name}-${ordinal} -- sh -c 'echo \"hello from ${var.name}-${ordinal} at $(date -u)\" > ${var.mount_path}/index.html'"
  ]
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
