# Keycloak and the PostgreSQL it stores realms in, plus the Ingress the ALB is adopted from.
#
# The _monolithic template ran, from an SSM Association on the bastion:
#   kubectl create namespace keycloak
#   kubectl apply -n keycloak -f https://raw.githubusercontent.com/keycloak/keycloak-quickstarts/refs/heads/main/kubernetes/keycloak.yaml
#   echo '<Ingress yaml>' > manifests/keycloak_ingress.yaml && kubectl apply -f ...
#
# The objects below are that quickstart, transcribed as HCL keeping the original camelCase field
# names rather than rewritten YAML (rules.md E-3), applied through alekc/kubectl so the cluster can
# be created in the same apply (rules.md E-2). Transcribing rather than curling matters for more
# than tidiness: that URL points at a branch, so the manifest it returns changes without notice -
# including the Keycloak image tag and the admin credentials baked into it.
#
# Three things are parameterised that the upstream manifest hardcodes, because it is explicit that
# they are not production values: the bootstrap admin password, the database password, and the
# image tags.
locals {
  keycloak_labels = { app = "keycloak" }
  postgres_labels = { app = "postgres" }
}
resource "kubectl_manifest" "namespace" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata   = { name = var.namespace }
  })
}
# Both passwords, in a Secret rather than inline env values on the pods.
#
# Upstream's quickstart puts them straight into the container env and says so in a comment: "In a
# production environment, use a secret to store username and password to the database". There is a
# second reason to do it here, specific to how this is applied: kubectl_manifest marks yaml_body
# sensitive, but it also exposes yaml_body_parsed, which is computed and NOT sensitive - so a
# password written into a StatefulSet's env renders in full in every terraform plan. The provider
# does redact the body of a Secret in that attribute, so moving the values here is what actually
# keeps them out of plan output.
resource "kubectl_manifest" "credentials" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    type       = "Opaque"
    metadata = {
      name      = var.credentials_secret_name
      namespace = var.namespace
    }
    # stringData, not data: it takes the raw value. base64-encoding by hand produces a valid Secret
    # that decodes into nonsense, which presents as a wrong password rather than a malformed one.
    stringData = {
      admin-password    = var.admin_password
      database-password = var.database_password
    }
  })

  depends_on = [kubectl_manifest.namespace]
}
# PostgreSQL first: Keycloak's startup probe allows ten minutes, but it cannot finish starting until
# the database answers, so bringing the database up first shortens the window where Keycloak is
# restarting.
#
# emptyDir, as upstream has it - the data is lost when the pod stops. That is a deliberate property
# of the quickstart rather than an oversight, and it is why this project needs no CSI driver.
resource "kubectl_manifest" "postgres_deployment" {
  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "postgres"
      namespace = var.namespace
      labels    = local.postgres_labels
    }
    spec = {
      replicas = 1
      selector = { matchLabels = local.postgres_labels }
      template = {
        metadata = { labels = local.postgres_labels }
        spec = {
          containers = [{
            name  = "postgres"
            image = var.postgres_image
            env = [
              { name = "POSTGRES_USER", value = var.database_user },
              {
                name = "POSTGRES_PASSWORD"
                valueFrom = {
                  secretKeyRef = {
                    name = var.credentials_secret_name
                    key  = "database-password"
                  }
                }
              },
              { name = "POSTGRES_DB", value = var.database_name },
              { name = "POSTGRES_LOG_STATEMENT", value = "all" },
            ]
            ports = [{ name = "postgres", containerPort = 5432 }]
            volumeMounts = [{
              # PostgreSQL's data directory is not writable in this image without a mount.
              name      = "postgres-data"
              mountPath = "/var/lib/postgresql/data"
            }]
          }]
          volumes = [{ name = "postgres-data", emptyDir = {} }]
        }
      }
    }
  })

  # secretKeyRef names the Secret as a literal string rather than referencing the resource, so
  # nothing else orders this after it (rules.md D-1).
  depends_on = [kubectl_manifest.namespace, kubectl_manifest.credentials]
}
resource "kubectl_manifest" "postgres_service" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "postgres"
      namespace = var.namespace
      labels    = local.postgres_labels
    }
    spec = {
      type     = "ClusterIP"
      selector = local.postgres_labels
      ports    = [{ protocol = "TCP", port = 5432, targetPort = 5432 }]
    }
  })

  depends_on = [kubectl_manifest.namespace]
}
# The Service the Ingress routes to. Named "keycloak", which with the namespace makes the adoption
# stack tag <namespace>/keycloak - except the tag is built from the Ingress name, not this one
# (rules.md G-3).
resource "kubectl_manifest" "keycloak_service" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = var.service_name
      namespace = var.namespace
      labels    = local.keycloak_labels
    }
    spec = {
      type     = "ClusterIP"
      selector = local.keycloak_labels
      ports = [{
        name = "http", protocol = "TCP", port = var.service_port, targetPort = "http"
      }]
    }
  })

  depends_on = [kubectl_manifest.namespace]
}
# The headless Service JGroups uses to find the other Keycloak pods. clusterIP: None is what makes
# it headless - with a cluster IP the cache members discover one address instead of each other, and
# a two-replica cluster silently runs as two independent caches.
resource "kubectl_manifest" "keycloak_discovery_service" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "${var.service_name}-discovery"
      namespace = var.namespace
      labels    = local.keycloak_labels
    }
    spec = {
      type      = "ClusterIP"
      clusterIP = "None"
      selector  = local.keycloak_labels
    }
  })

  depends_on = [kubectl_manifest.namespace]
}
# A StatefulSet rather than a Deployment, as upstream explains: a rolling update then restarts pods
# one at a time, which keeps the in-memory session cache that is only held in two copies.
resource "kubectl_manifest" "keycloak_statefulset" {
  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "StatefulSet"
    metadata = {
      name      = var.service_name
      namespace = var.namespace
      labels    = local.keycloak_labels
    }
    spec = {
      serviceName = "${var.service_name}-discovery"
      replicas    = var.replicas
      selector    = { matchLabels = local.keycloak_labels }
      template = {
        metadata = { labels = local.keycloak_labels }
        spec = {
          containers = [{
            name  = "keycloak"
            image = var.keycloak_image
            args  = ["start"]
            env = [
              { name = "KC_BOOTSTRAP_ADMIN_USERNAME", value = var.admin_username },
              {
                name = "KC_BOOTSTRAP_ADMIN_PASSWORD"
                valueFrom = {
                  secretKeyRef = {
                    name = var.credentials_secret_name
                    key  = "admin-password"
                  }
                }
              },
              # The ALB terminates TLS and forwards X-Forwarded-*, so Keycloak has to trust those
              # headers or every redirect it issues points at http on the wrong host.
              { name = "KC_PROXY_HEADERS", value = "xforwarded" },
              { name = "KC_HTTP_ENABLED", value = "true" },
              # Upstream leaves hostname checking off for an exploratory setup. Turning it on is the
              # production move, and it requires KC_HOSTNAME to match the Ingress host exactly.
              { name = "KC_HOSTNAME_STRICT", value = tostring(var.hostname_strict) },
              { name = "KC_HEALTH_ENABLED", value = "true" },
              { name = "KC_CACHE", value = "ispn" },
              {
                name = "POD_IP"
                valueFrom = {
                  fieldRef = { fieldPath = "status.podIP" }
                }
              },
              # JGroups needs an explicit bind address to work in IPv6-only setups, and takes it
              # from the pod IP above.
              { name = "KC_CACHE_EMBEDDED_NETWORK_BIND_ADDRESS", value = "$(POD_IP)" },
              { name = "KC_DB", value = "postgres" },
              { name = "KC_DB_URL_HOST", value = "postgres" },
              { name = "KC_DB_URL_DATABASE", value = var.database_name },
              { name = "KC_DB_USERNAME", value = var.database_user },
              {
                name = "KC_DB_PASSWORD"
                valueFrom = {
                  secretKeyRef = {
                    name = var.credentials_secret_name
                    key  = "database-password"
                  }
                }
              },
            ]
            ports = [
              { name = "http", containerPort = var.container_port },
              { name = "jgroups", containerPort = 7800 },
              { name = "jgroups-fd", containerPort = 57800 },
            ]
            # Port 9000 is Keycloak's management port, separate from http. The probes have to use it
            # or they poll the application port for paths that are not served there.
            startupProbe = {
              httpGet          = { path = "/health/started", port = 9000 }
              periodSeconds    = 1
              failureThreshold = 600
            }
            readinessProbe = {
              httpGet          = { path = "/health/ready", port = 9000 }
              periodSeconds    = 10
              failureThreshold = 3
            }
            livenessProbe = {
              httpGet          = { path = "/health/live", port = 9000 }
              periodSeconds    = 10
              failureThreshold = 3
            }
            resources = {
              limits   = { cpu = var.cpu_limit, memory = var.memory_limit }
              requests = { cpu = var.cpu_request, memory = var.memory_request }
            }
          }]
        }
      }
    }
  })

  # The database has to be reachable before Keycloak finishes starting. Not strictly required -
  # Keycloak retries - but it keeps the startup probe from burning through its window. The Secret is
  # named by secretKeyRef as a literal string rather than referenced, so nothing else orders this
  # after it (rules.md D-1).
  depends_on = [
    kubectl_manifest.namespace,
    kubectl_manifest.credentials,
    kubectl_manifest.postgres_service,
    kubectl_manifest.postgres_deployment,
    kubectl_manifest.keycloak_discovery_service,
  ]
}
# The object the AWS Load Balancer Controller reconciles, and the one the pre-created ALB is adopted
# from. Its namespace and name are the stack tag (rules.md G-3).
resource "kubectl_manifest" "ingress" {
  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name        = var.ingress_name
      namespace   = var.namespace
      annotations = var.ingress_annotations
    }
    spec = {
      # alb, the class the AWS Load Balancer Controller owns. An Ingress naming a class no controller
      # reconciles is created successfully and then never gets an address (rules.md G-1).
      ingressClassName = var.ingress_class_name
      # The tls block carries no secretName on purpose: the ALB terminates TLS with the ACM
      # certificate named in the annotations, so there is no Kubernetes Secret involved. It is here
      # because the controller reads the host list from it.
      tls = [{ hosts = [var.hostname] }]
      rules = [{
        host = var.hostname
        http = {
          paths = [{
            path     = "/"
            pathType = "Prefix"
            backend = {
              service = {
                name = var.service_name
                port = { number = var.service_port }
              }
            }
          }]
        }
      }]
    }
  })

  depends_on = [
    kubectl_manifest.namespace,
    kubectl_manifest.keycloak_service,
    kubectl_manifest.keycloak_statefulset,
  ]
}
