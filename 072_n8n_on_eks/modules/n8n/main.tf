# n8n and the Postgres it stores workflows in.
#
# These are the objects in n8n-io/n8n-hosting's kubernetes directory, declared as HCL rather than
# cloned and applied. The _monolithic template did:
#
#   git clone https://github.com/n8n-io/n8n-hosting.git
#   echo '<a whole Service manifest>' > n8n-hosting/kubernetes/n8n-service.yaml
#   kubectl create namespace n8n
#   kubectl apply -f n8n-hosting/kubernetes
#   kubectl -n n8n set image deployment n8n n8n=n8nio/n8n:1.119.2
#   kubectl -n n8n set env deployment n8n -c n8n N8N_SECURE_COOKIE=false
#
# Six things follow from that which declaring the objects fixes (rules.md E-1/E-2/E-3/E-5):
#
#   - "kubectl apply -f <directory>" applies whatever that repository contains on the day it is
#     cloned. The image tag, the resource requests and the 300Gi claim below all changed upstream
#     without anything here noticing.
#   - Nothing was in state, so nothing appeared in plan and nothing was removed on destroy.
#   - The Service was overwritten by echoing a manifest into the clone, so the file in the
#     repository and the object in the cluster differed with no record of the difference.
#   - "set image" and "set env" patched the Deployment after the fact. The cluster then held a
#     Deployment that matched neither the repository nor any file - and a re-apply of the
#     directory would have silently undone both patches.
#   - The upstream Secret ships literal credentials ("changeUser" / "changePassword"), which the
#     original applied as-is.
#   - The clone step needed git and github.com reachable from the instance at boot.
locals {
  # Upstream selects on a "service" label rather than the usual app label; kept, because the
  # Service in the caller's stack tag has to select the same pods.
  n8n_labels      = { service = var.name }
  postgres_labels = { service = "postgres-${var.name}" }
  postgres_name   = "postgres"
  # Headless Service, so this name resolves straight to the pod. n8n is given the fully qualified
  # form because it is also what a webhook worker in another namespace would need.
  postgres_service_name = "postgres-service"
  postgres_host         = "postgres-service.${var.namespace}.svc.cluster.local"
  postgres_port         = 5432
  postgres_secret_name  = "postgres-secret"
  init_config_map_name  = "init-data"
  n8n_claim_name        = "${var.name}-data"
  # Defaults to the workload's name, so the caller's adoption stack tag - which is
  # <namespace>/<ingress name> for an Ingress - needs no second value to agree with (rules.md B-5).
  ingress_name = coalesce(var.ingress_name, var.name)
  # The Job that reconciles the application role, and the label its pods carry so they can be
  # found without naming the Job - whose name changes, and is derived from a generated password.
  init_job_base_name = "${var.name}-db-init"
  # Why the name carries a digest instead of being fixed. A Job's pod template is immutable once
  # created, so a Job cannot be updated to run again - it has to be a different object. Keying the
  # name on what the run would do means exactly one re-run per change to the desired state of the
  # role: the script, the role name, its password, or a run id the caller bumps deliberately.
  #
  # The alternative, a name carrying timestamp(), would re-run on literally every apply - and
  # would also make every plan propose replacing it, so this project could never report "No
  # changes" again. db_init_run_id is the opt-in for that behaviour, for a caller who would rather
  # have the churn.
  #
  # The digest covers a generated password, so it is a sensitive value and so is this name. That
  # is why nothing exposes it: the diagnostic commands select on the label above instead
  # (rules.md H-2).
  init_job_name = "${local.init_job_base_name}-${substr(sha1(join("|", [
    local.init_script,
    var.postgres_app_user,
    random_password.postgres_app.result,
    # A conditional rather than coalesce(var.db_init_run_id, ""): coalesce rejects an empty string
    # as well as a null, so it has no usable fallback here and fails the plan outright with "no
    # non-null, non-empty-string arguments".
    var.db_init_run_id == null ? "" : var.db_init_run_id,
  ])), 0, 10)}"
  init_job_labels = { "app.kubernetes.io/name" = local.init_job_base_name }
  # Waits for Postgres to answer before running the script, because the Job is scheduled as soon
  # as it is created and Postgres may still be initialising its data directory. pg_isready reads
  # PGHOST and PGPORT from the environment below.
  #
  # The script itself is the same file the postgres entrypoint runs on a first start - mounted
  # from the same ConfigMap, so there is one copy of it (rules.md B-5). It works unchanged over
  # TCP because psql takes the host and the password from PGHOST and PGPASSWORD, which is all that
  # differs between being run here and being run beside the socket.
  init_job_command = join("\n", [
    "set -e",
    "until pg_isready -q; do echo 'waiting for postgres'; sleep 2; done",
    "bash /scripts/init-data.sh",
  ])
  # One rule, built once. The host is the only part that varies, and a rule carrying host = "" is
  # not the same as a rule with no host: the first matches nothing (rules.md B-4).
  ingress_rule = merge(
    {
      http = {
        paths = [{
          path     = var.ingress_path
          pathType = var.ingress_path_type
          backend = {
            service = {
              name = var.name
              # The Service port, not the container port. The ALB's target group sends traffic to
              # the pods on whatever that port maps to, which is the container port.
              port = { number = var.service_port }
            }
          }
        }]
      }
    },
    var.ingress_host == null ? {} : { host = var.ingress_host },
  )
  postgres_claim_name  = "postgres-data"
  n8n_volume_name      = "data"
  postgres_volume_name = "data"
  # The script upstream ships in a ConfigMap, run by the postgres image's entrypoint the first
  # time the data directory is initialised. It creates the non-superuser role n8n connects as,
  # which is why n8n never sees the superuser password.
  #
  # Rewritten rather than copied, for one reason that is easy to miss: upstream feeds the SQL to
  # psql through a "<<-'EOSQL'" heredoc, and bash's <<- strips leading tabs only. Carried into an
  # indented Terraform heredoc the terminator ends up indented with spaces, bash stops
  # recognising it, the heredoc runs to the end of the file and the script fails to parse - so
  # nothing runs at all, and the failure looks like Postgres ignoring the file (rules.md A-4). The
  # \gexec meta-commands the heredoc existed for are replaced by a plain existence check, which
  # needs no heredoc. Safe to interpolate because both values are validated: the role name matches
  # ^[a-z][a-z0-9_]*$ and the password is generated without special characters.
  #
  # On the dollar signs, because getting this wrong is what made every one of these lines a no-op.
  # Terraform's escape is "$${" for a literal "${" - it is about the brace, not the dollar. A "$"
  # followed by a letter is already literal and needs no escaping, so writing "$$RUN" does not
  # produce "$RUN": it produces "$$RUN", and bash expands "$$" to its own process ID. The script
  # then ran "134RUN" and "134POSTGRES_USER", failed with "command not found", and - because this
  # runs from the postgres entrypoint's init directory, whose output nobody reads unless a pod is
  # already crash-looping - the only visible symptom was n8n reporting "password authentication
  # failed for user n8napp" forever, because the role it names was never created.
  init_script = <<-SH
    #!/bin/bash
    set -e
    if [ -z "$${POSTGRES_NON_ROOT_USER:-}" ] || [ -z "$${POSTGRES_NON_ROOT_PASSWORD:-}" ]; then
      echo "SETUP INFO: no non-root user requested, skipping"
      exit 0
    fi
    RUN="psql -v ON_ERROR_STOP=1 --username=$POSTGRES_USER --dbname=$POSTGRES_DB"
    if $RUN -tAc "SELECT 1 FROM pg_roles WHERE rolname = '$POSTGRES_NON_ROOT_USER'" | grep -q 1; then
      echo "SETUP INFO: role $POSTGRES_NON_ROOT_USER exists, resetting its password"
      $RUN -c "ALTER ROLE \"$POSTGRES_NON_ROOT_USER\" WITH LOGIN PASSWORD '$POSTGRES_NON_ROOT_PASSWORD'"
    else
      echo "SETUP INFO: creating role $POSTGRES_NON_ROOT_USER"
      $RUN -c "CREATE ROLE \"$POSTGRES_NON_ROOT_USER\" WITH LOGIN PASSWORD '$POSTGRES_NON_ROOT_PASSWORD'"
    fi
    $RUN -c "GRANT ALL PRIVILEGES ON DATABASE \"$POSTGRES_DB\" TO \"$POSTGRES_NON_ROOT_USER\""
    $RUN -c "GRANT ALL ON SCHEMA public TO \"$POSTGRES_NON_ROOT_USER\""
    echo "SETUP INFO: done"
  SH
}
resource "kubectl_manifest" "namespace" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata   = { name = var.namespace }
  })
}
# Generated rather than the literals upstream ships. Two passwords because Postgres runs with a
# superuser that initialises the database and n8n connects as a separate role the init script
# creates - so a leak of n8n's credentials is not a leak of the superuser's.
#
# These end up in Terraform state and in a Kubernetes Secret in clear text, which is what any
# Kubernetes Secret is. Neither is exposed as an output: the caller's README says how to read
# them out of the cluster rather than carrying the values (rules.md H-2).
resource "random_password" "postgres_admin" {
  length  = var.postgres_password_length
  special = false
}
resource "random_password" "postgres_app" {
  length  = var.postgres_password_length
  special = false
}
resource "kubectl_manifest" "postgres_secret" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = local.postgres_secret_name
      namespace = var.namespace
    }
    type = "Opaque"
    stringData = {
      POSTGRES_USER              = var.postgres_admin_user
      POSTGRES_PASSWORD          = random_password.postgres_admin.result
      POSTGRES_DB                = var.postgres_database
      POSTGRES_NON_ROOT_USER     = var.postgres_app_user
      POSTGRES_NON_ROOT_PASSWORD = random_password.postgres_app.result
    }
  })

  # The manifest carries the generated passwords, so the provider's rendered-manifest attributes
  # would otherwise show them in plan output and in state as readable diffs.
  sensitive_fields = ["stringData"]

  depends_on = [kubectl_manifest.namespace]
}
resource "kubectl_manifest" "postgres_init_config_map" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = local.init_config_map_name
      namespace = var.namespace
    }
    data = {
      "init-data.sh" = local.init_script
    }
  })

  depends_on = [kubectl_manifest.namespace]
}
resource "kubectl_manifest" "postgres_claim" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "PersistentVolumeClaim"
    metadata = {
      name      = local.postgres_claim_name
      namespace = var.namespace
      labels    = local.postgres_labels
    }
    spec = {
      accessModes = ["ReadWriteOnce"]
      # Named explicitly, where the upstream manifest names no class and relies on whichever one
      # the cluster marks default (rules.md B-5).
      storageClassName = var.storage_class_name
      resources = {
        requests = {
          storage = var.postgres_storage_size
        }
      }
    }
  })

  depends_on = [kubectl_manifest.namespace]
}
resource "kubectl_manifest" "postgres_deployment" {
  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = local.postgres_name
      namespace = var.namespace
      labels    = local.postgres_labels
    }
    spec = {
      replicas = 1
      selector = { matchLabels = local.postgres_labels }
      # Recreate rather than upstream's RollingUpdate with maxSurge 1. A rolling update would
      # start a second Postgres pod while the first still holds the ReadWriteOnce volume, so the
      # new pod cannot attach it and the rollout stalls with the old pod already terminating.
      strategy = { type = "Recreate" }
      template = {
        metadata = { labels = local.postgres_labels }
        spec = {
          restartPolicy = "Always"
          containers = [{
            name  = local.postgres_name
            image = var.postgres_image
            ports = [{ containerPort = local.postgres_port }]
            resources = {
              requests = {
                cpu    = var.postgres_cpu_request
                memory = var.postgres_memory_request
              }
              limits = {
                cpu    = var.postgres_cpu_limit
                memory = var.postgres_memory_limit
              }
            }
            env = [
              # A subdirectory rather than the mount point itself: the EBS volume arrives with a
              # lost+found directory, and initdb refuses to initialise into a non-empty directory.
              { name = "PGDATA", value = "/var/lib/postgresql/data/pgdata" },
              { name = "POSTGRES_DB", value = var.postgres_database },
              {
                name      = "POSTGRES_USER"
                valueFrom = { secretKeyRef = { name = local.postgres_secret_name, key = "POSTGRES_USER" } }
              },
              {
                name      = "POSTGRES_PASSWORD"
                valueFrom = { secretKeyRef = { name = local.postgres_secret_name, key = "POSTGRES_PASSWORD" } }
              },
              {
                name      = "POSTGRES_NON_ROOT_USER"
                valueFrom = { secretKeyRef = { name = local.postgres_secret_name, key = "POSTGRES_NON_ROOT_USER" } }
              },
              {
                name      = "POSTGRES_NON_ROOT_PASSWORD"
                valueFrom = { secretKeyRef = { name = local.postgres_secret_name, key = "POSTGRES_NON_ROOT_PASSWORD" } }
              },
            ]
            volumeMounts = [
              {
                name      = local.postgres_volume_name
                mountPath = "/var/lib/postgresql/data"
              },
              {
                name      = local.init_config_map_name
                mountPath = "/docker-entrypoint-initdb.d/init-n8n-user.sh"
                subPath   = "init-data.sh"
              },
            ]
          }]
          # Upstream also declares a postgres-secret volume that no container mounts. Dropped: a
          # volume in a pod spec has to resolve before the pod starts whether or not anything
          # mounts it, so an unused one is a dependency with no purpose.
          volumes = [
            {
              name                  = local.postgres_volume_name
              persistentVolumeClaim = { claimName = local.postgres_claim_name }
            },
            {
              name = local.init_config_map_name
              configMap = {
                name        = local.init_config_map_name
                defaultMode = 484 # 0744, which yamlencode would render as a decimal anyway
              }
            },
          ]
        }
      }
    }
  })

  # The Secret, ConfigMap and claim are named as literal strings inside the pod spec rather than
  # referenced, so nothing else orders them (rules.md D-1). All three have to exist before the
  # pod is admitted.
  depends_on = [
    kubectl_manifest.postgres_secret,
    kubectl_manifest.postgres_init_config_map,
    kubectl_manifest.postgres_claim,
  ]
}
resource "kubectl_manifest" "postgres_service" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = local.postgres_service_name
      namespace = var.namespace
      labels    = local.postgres_labels
    }
    spec = {
      # Headless, as upstream has it: the name resolves to the pod's own address rather than to a
      # virtual IP, which for a single-replica database removes a hop and makes the DNS answer
      # change when the pod is replaced.
      clusterIP = "None"
      selector  = local.postgres_labels
      ports = [{
        name       = tostring(local.postgres_port)
        port       = local.postgres_port
        targetPort = local.postgres_port
        protocol   = "TCP"
      }]
    }
  })

  depends_on = [kubectl_manifest.postgres_deployment]
}
resource "kubectl_manifest" "n8n_claim" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "PersistentVolumeClaim"
    metadata = {
      name      = local.n8n_claim_name
      namespace = var.namespace
      labels    = local.n8n_labels
    }
    spec = {
      accessModes      = ["ReadWriteOnce"]
      storageClassName = var.storage_class_name
      resources = {
        requests = {
          storage = var.n8n_storage_size
        }
      }
    }
  })

  depends_on = [kubectl_manifest.namespace]
}
# Makes the application role match this configuration, on every apply that changes what it should
# be - rather than only on the one boot where Postgres happened to initialise an empty volume.
#
# The problem this closes. The postgres image runs everything in
# /docker-entrypoint-initdb.d exactly once, when it initialises an empty data directory, and the
# ConfigMap above is mounted there. So the role is created on a first start and never reconciled
# again: a volume that survives a rebuild, a regenerated password, or - as happened here - a
# script that was broken on that one run, all leave Postgres with no matching role and nothing
# saying so. The only symptom is n8n reporting "password authentication failed for user n8napp"
# forever, several layers away from the cause.
#
# The script is idempotent by construction: it ALTERs the role when it exists and CREATEs it when
# it does not, so running it again is always safe and is the whole point of running it from here.
resource "kubectl_manifest" "postgres_init_job" {
  yaml_body = yamlencode({
    apiVersion = "batch/v1"
    kind       = "Job"
    metadata = {
      name      = local.init_job_name
      namespace = var.namespace
      labels    = local.init_job_labels
    }
    spec = {
      backoffLimit = var.db_init_backoff_limit
      # Lets the API server clean the finished Job and its pod up on its own. Without it every
      # change to the role leaves another completed Job in the namespace for good.
      ttlSecondsAfterFinished = var.db_init_ttl_seconds
      template = {
        metadata = { labels = local.init_job_labels }
        spec = {
          # OnFailure rather than Never, so a pod that loses the race with Postgres is retried in
          # place instead of leaving a failed pod behind for the Job controller to replace.
          restartPolicy = "OnFailure"
          containers = [{
            name    = "db-init"
            image   = var.postgres_image
            command = ["bash", "-c", local.init_job_command]
            env = [
              # The script reaches Postgres over the Service here rather than over the local
              # socket it uses when the entrypoint runs it.
              { name = "PGHOST", value = local.postgres_host },
              { name = "PGPORT", value = tostring(local.postgres_port) },
              # Over TCP the superuser has to authenticate, which it does not have to do over the
              # socket - so this is the one value the entrypoint path never needs.
              {
                name      = "PGPASSWORD"
                valueFrom = { secretKeyRef = { name = local.postgres_secret_name, key = "POSTGRES_PASSWORD" } }
              },
            ]
            # The same Secret the Postgres container reads, so the role this creates and the
            # credentials n8n is given cannot disagree (rules.md B-5).
            envFrom = [{ secretRef = { name = local.postgres_secret_name } }]
            volumeMounts = [{
              name      = "init"
              mountPath = "/scripts"
            }]
          }]
          # A whole-volume mount, not the subPath the Postgres container uses. Kubernetes never
          # refreshes a subPath mount when its ConfigMap changes, so a pod mounting the script
          # that way keeps the version it started with - which is why fixing the script in place
          # required restarting Postgres. This mount gets the current content every run.
          volumes = [{
            name      = "init"
            configMap = { name = local.init_config_map_name }
          }]
        }
      }
    }
  })

  # Turns a failed reconciliation into a failed apply. Without this the Job is created and the
  # apply moves on, so a role that could not be created is reported nowhere - which is the exact
  # failure mode this resource exists to remove.
  wait_for {
    condition {
      type   = "Complete"
      status = "True"
    }
  }

  timeouts {
    create = var.db_init_timeout
  }

  # Everything the Job reads by name rather than by reference: the Secret for its credentials, the
  # ConfigMap for the script, and the Service and Deployment for something to connect to. None of
  # those names is an attribute reference, so nothing else orders them (rules.md D-1).
  depends_on = [
    kubectl_manifest.postgres_secret,
    kubectl_manifest.postgres_init_config_map,
    kubectl_manifest.postgres_service,
    kubectl_manifest.postgres_deployment,
  ]
}
resource "kubectl_manifest" "n8n_deployment" {
  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = var.name
      namespace = var.namespace
      labels    = local.n8n_labels
    }
    spec = {
      replicas = 1
      selector = { matchLabels = local.n8n_labels }
      # Recreate, as upstream has it, for the same ReadWriteOnce reason as Postgres.
      strategy = { type = "Recreate" }
      template = {
        metadata = { labels = local.n8n_labels }
        spec = {
          restartPolicy = "Always"
          # The n8n image runs as uid 1000 and an EBS volume arrives owned by root, so without
          # this the app cannot write to /home/node/.n8n and exits on start.
          initContainers = [{
            name    = "volume-permissions"
            image   = var.init_container_image
            command = ["sh", "-c", "chown 1000:1000 /data"]
            volumeMounts = [{
              name      = local.n8n_volume_name
              mountPath = "/data"
            }]
          }]
          containers = [{
            name  = var.name
            image = var.image
            # Upstream's "sleep 5; n8n start". The sleep is there because n8n exits rather than
            # retries if Postgres is not accepting connections yet - the restartPolicy would bring
            # it back anyway, so this only saves a restart or two on a cold start.
            command = ["/bin/sh"]
            args    = ["-c", "sleep 5; n8n start"]
            ports   = [{ containerPort = var.container_port }]
            resources = {
              requests = { memory = var.n8n_memory_request }
              limits   = { memory = var.n8n_memory_limit }
            }
            env = concat(
              [
                { name = "DB_TYPE", value = "postgresdb" },
                { name = "DB_POSTGRESDB_HOST", value = local.postgres_host },
                { name = "DB_POSTGRESDB_PORT", value = tostring(local.postgres_port) },
                { name = "DB_POSTGRESDB_DATABASE", value = var.postgres_database },
                {
                  name      = "DB_POSTGRESDB_USER"
                  valueFrom = { secretKeyRef = { name = local.postgres_secret_name, key = "POSTGRES_NON_ROOT_USER" } }
                },
                {
                  name      = "DB_POSTGRESDB_PASSWORD"
                  valueFrom = { secretKeyRef = { name = local.postgres_secret_name, key = "POSTGRES_NON_ROOT_PASSWORD" } }
                },
                { name = "N8N_PROTOCOL", value = "http" },
                { name = "N8N_PORT", value = tostring(var.container_port) },
                # What the _monolithic template patched in afterwards with kubectl set env. n8n
                # marks its session cookie Secure by default, and a browser will not send a Secure
                # cookie back over plain http - so the login succeeds and lands back on the login
                # page (rules.md E-5).
                { name = "N8N_SECURE_COOKIE", value = tostring(var.secure_cookie) },
              ],
              # Only when the caller knows the external address, which it does here because
              # Terraform created the load balancer (rules.md G-3). Without these n8n builds
              # webhook URLs from the pod's hostname, and every webhook it hands out is
              # unreachable - which is not obvious until somebody tries to call one
              # (rules.md B-4).
              var.external_url == null ? [] : [
                { name = "N8N_HOST", value = replace(replace(var.external_url, "https://", ""), "http://", "") },
                { name = "N8N_EDITOR_BASE_URL", value = var.external_url },
                { name = "WEBHOOK_URL", value = var.external_url },
              ],
            )
            volumeMounts = [{
              name      = local.n8n_volume_name
              mountPath = "/home/node/.n8n"
            }]
          }]
          # Upstream declares n8n-secret and postgres-secret volumes here that no container
          # mounts - and n8n-secret does not exist in that repository at all. A pod's volumes all
          # have to resolve before it starts, mounted or not, so the pod would sit in
          # ContainerCreating waiting for a Secret nobody creates. Both are dropped.
          volumes = [{
            name                  = local.n8n_volume_name
            persistentVolumeClaim = { claimName = local.n8n_claim_name }
          }]
        }
      }
    }
  })

  # The init Job is in the list so that n8n starts against a database that already has its role.
  # n8n would recover anyway - it exits and is restarted until the database answers - but the
  # first start is then clean rather than a short crash loop that reads exactly like the failure
  # this project spent a while chasing.
  depends_on = [
    kubectl_manifest.postgres_service,
    kubectl_manifest.postgres_secret,
    kubectl_manifest.postgres_init_job,
    kubectl_manifest.n8n_claim,
  ]
}
resource "kubectl_manifest" "n8n_service" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = var.name
      namespace = var.namespace
      labels    = local.n8n_labels
    }
    spec = {
      # ClusterIP, because the load balancer is now reached through the Ingress below rather than
      # through this Service. With an ALB and target-type ip the load balancer registers pod
      # addresses directly, so the Service only has to exist for the Ingress to name - it is never
      # in the data path, and a NodePort would be an open port on every node for nothing
      # (rules.md G-1).
      #
      # It used to be LoadBalancer, which is what made this an NLB. That shape needed the
      # aws-load-balancer-type annotation to keep the in-tree cloud provider from claiming the
      # Service and building a Classic Load Balancer; a ClusterIP Service is of no interest to
      # either controller, so that whole class of mistake is gone with it.
      type     = var.service_type
      selector = local.n8n_labels
      ports = [{
        name       = tostring(var.service_port)
        port       = var.service_port
        targetPort = var.container_port
        protocol   = "TCP"
      }]
    }
  })

  depends_on = [kubectl_manifest.n8n_deployment]
}
# What makes n8n reachable over http.
#
# The switch is spec.ingressClassName, and it is the one thing here that cannot be left out: the
# annotations below are read by the AWS Load Balancer Controller only once it has decided this
# Ingress is its to reconcile, and without the class it never does. An Ingress nobody reconciles
# is not an error - it sits with an empty ADDRESS forever (rules.md G-1).
#
# No host, so any Host header matches. That is what makes the load balancer's own DNS name a
# usable address, which matters here because that address is also what n8n is told to build its
# webhook URLs from - there is no domain in front of this.
#
# No TLS either, deliberately: http only, which is why the deployment above also sets
# N8N_SECURE_COOKIE false. A browser will not return a Secure session cookie over plain http, so
# with the default the login succeeds and lands straight back on the login page.
resource "kubectl_manifest" "n8n_ingress" {
  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = local.ingress_name
      namespace = var.namespace
      labels    = local.n8n_labels
      # Supplied by the caller, because the values name a security group and a load balancer this
      # module does not own (rules.md B-6).
      annotations = var.ingress_annotations
    }
    spec = {
      ingressClassName = var.ingress_class_name
      rules            = [local.ingress_rule]
    }
  })

  # The Service has to exist before the controller resolves this Ingress's backend, and the
  # backend names it by a literal string rather than by reference (rules.md D-1). Ordering it here
  # also means terraform destroy removes the Ingress before the Service, which is the order that
  # lets the controller clean up its listeners and target groups.
  depends_on = [kubectl_manifest.n8n_service]
}
