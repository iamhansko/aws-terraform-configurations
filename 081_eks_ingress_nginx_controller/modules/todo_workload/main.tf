locals {
  # Names derived from var.name rather than taken as separate variables, so they cannot be
  # set to a set that does not hang together (rules.md B-1). The _monolithic template named
  # these gp3-pvc and ingress: the first tied the claim's name to the storage class it
  # happened to use, and the second was generic enough to collide with anything else in the
  # namespace.
  service_name = "${var.name}-service"
  claim_name   = "${var.name}-data"
  volume_name  = "data"
  # The prefix reaches three places that have to agree, so it is expanded once here. The app
  # is told it lives under path_prefix, the Ingress matches that prefix with a capture group,
  # and the rewrite hands the capture to the app without the prefix. Change any one of the
  # three alone and the app answers 404 while every resource reports success.
  ingress_path    = "${var.path_prefix}/(.*)"
  rewrite_target  = "/$1"
  app_entrypoint  = "poetry run python -m api.migrate_db && poetry run uvicorn api.main:app --host 0.0.0.0 --root-path ${var.path_prefix}"
  app_labels      = { app = "${var.name}-app" }
  mysql_data_path = "/var/lib/mysql"
}
# Where MySQL's data directory lives.
#
# The claim is the reason this project needs the EBS CSI driver addon at all: without it
# nothing provisions a volume for this claim, the claim stays Pending, and the pod never
# starts - with the pod's events, not the Deployment's, being the only place that says so.
resource "kubectl_manifest" "persistent_volume_claim" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "PersistentVolumeClaim"
    metadata = {
      name      = local.claim_name
      namespace = var.namespace
    }
    spec = {
      accessModes = ["ReadWriteOnce"]
      # Named explicitly rather than left to the cluster's default class, and taken from the
      # module that created it (rules.md B-5).
      storageClassName = var.storage_class_name
      resources = {
        requests = {
          storage = var.volume_size
        }
      }
    }
  })
}
# The app the two ingress controllers front.
#
# Three containers in one pod, as the _monolithic template had them: the FastAPI app, a
# MySQL it reaches over localhost, and a shell for poking at DNS from inside the pod. That
# is not how you would run a database, and the shape is worth keeping anyway - it makes the
# demo one object rather than three, and it is why the claim is ReadWriteOnce and the
# replica count is pinned to one.
#
# The _monolithic template wrote all of this as a single-quoted shell string inside an SSM
# Association and applied it with kubectl, so none of it was in state: no diff in plan,
# nothing removed on destroy, and a YAML indentation error would have surfaced only in the
# association's output (rules.md E-1/E-2).
resource "kubectl_manifest" "deployment" {
  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = var.name
      namespace = var.namespace
      labels    = local.app_labels
    }
    spec = {
      replicas = var.replicas
      selector = {
        matchLabels = local.app_labels
      }
      template = {
        metadata = {
          labels = local.app_labels
        }
        spec = {
          restartPolicy = "Always"
          containers = concat(
            [
              {
                name  = "fastapi"
                image = var.app_image
                ports = [{
                  name          = "http"
                  containerPort = var.app_container_port
                }]
                # Migrations first, then the server. The two are chained with && in one shell
                # so a failed migration does not leave a server answering against an empty
                # schema - and because MySQL takes a while to initialise on first boot, this
                # container is expected to fail and be restarted a few times before it comes
                # up. That is the pod healing itself rather than something being wrong.
                command = ["bash", "-c", local.app_entrypoint]
                env = [
                  { name = "WATCHFILES_FORCE_POLLING", value = "true" },
                  # localhost, because both containers share the pod's network namespace.
                  { name = "DB_HOST", value = "localhost" },
                  { name = "DB_PORT", value = tostring(var.mysql_port) },
                ]
              },
              {
                name  = "mysql"
                image = var.mysql_image
                ports = [{
                  name          = "mysql"
                  containerPort = var.mysql_port
                }]
                env = [
                  # As the _monolithic template had it. Nothing publishes this port - the app
                  # reaches it over localhost and no Service names it - but any pod in the
                  # cluster can still reach it at this pod's own address, so this is a demo
                  # setting rather than a pattern to copy.
                  { name = "MYSQL_ALLOW_EMPTY_PASSWORD", value = "yes" },
                  { name = "MYSQL_DATABASE", value = var.mysql_database },
                  { name = "TZ", value = var.mysql_timezone },
                ]
                volumeMounts = [{
                  name      = local.volume_name
                  mountPath = local.mysql_data_path
                }]
              },
            ],
            # No command on purpose: the image's own CMD is "pause", so it sleeps. Giving it
            # nothing to run would make it exit, restart and end up in CrashLoopBackOff -
            # which would keep the whole pod NotReady and pull the Service's endpoint out
            # from under the ingress controller (rules.md B-4).
            var.create_dnsutils_container ? [{
              name  = "dnsutils"
              image = var.dnsutils_image
            }] : [],
          )
          volumes = [{
            name = local.volume_name
            persistentVolumeClaim = {
              claimName = local.claim_name
            }
          }]
        }
      }
    }
  })

  # The claim is named as a literal string inside the pod spec rather than referenced, so
  # nothing else orders these two (rules.md D-1). The volumeBindingMode on the class is
  # WaitForFirstConsumer, so the claim does not actually provision until this pod is
  # scheduled - but the claim still has to exist for the pod to be admitted.
  depends_on = [kubectl_manifest.persistent_volume_claim]
}
resource "kubectl_manifest" "service" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = local.service_name
      namespace = var.namespace
    }
    spec = {
      # ClusterIP, left implicit by the _monolithic template and stated here. It matters that
      # it is not a LoadBalancer: the ingress controllers are what face the internet, and a
      # second Service of type LoadBalancer here would quietly add a third load balancer to
      # the account.
      type     = "ClusterIP"
      selector = local.app_labels
      ports = [{
        port       = var.service_port
        targetPort = var.app_container_port
      }]
    }
  })

  depends_on = [kubectl_manifest.deployment]
}
# The object that picks which of the two controllers serves this app.
#
# spec.ingressClassName is the whole subject of this project. Point it at the other class and
# the same Ingress is served by the other controller, through the other load balancer, with
# no other change anywhere - and point it at a class that does not exist and the Ingress is
# created successfully, gets no address, and nothing reports an error.
resource "kubectl_manifest" "ingress" {
  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = var.name
      namespace = var.namespace
      annotations = {
        # Hands the regex capture to the app with the prefix stripped, so the app sees / while
        # the client asked for <prefix>/. uvicorn is told the prefix separately through
        # --root-path, which is what makes the links it generates point back at <prefix>.
        "nginx.ingress.kubernetes.io/rewrite-target" = local.rewrite_target
      }
    }
    spec = {
      ingressClassName = var.ingress_class_name
      rules = [{
        http = {
          paths = [{
            path = local.ingress_path
            # ImplementationSpecific, because the path is a regex rather than a literal
            # prefix. Prefix or Exact would make nginx match the characters "(.*)" literally.
            pathType = "ImplementationSpecific"
            backend = {
              service = {
                name = local.service_name
                port = {
                  number = var.service_port
                }
              }
            }
          }]
        }
      }]
    }
  })

  # The Service is named as a literal string in the backend, so nothing else orders these
  # (rules.md D-1). Order matters on the way out too: an Ingress deleted after its controller
  # is gone leaves the load balancer's listener rules behind.
  depends_on = [kubectl_manifest.service]
}
