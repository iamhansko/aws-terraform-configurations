# Sentry, from helm_release rather than the "helm upgrade --install sentry ..." line an SSM
# Association ran on the bastion (rules.md E-1). The admin credentials went through that
# command's arguments, which left them readable in the association's parameters with
# "aws ssm describe-association"; passing them as chart values from Terraform removes that
# copy, though the values still land in the release's own Secret in the cluster.
#
# This chart is not one application. It brings PostgreSQL, Redis, Kafka, ZooKeeper and
# ClickHouse as subcharts, each wanting a PersistentVolumeClaim, so it cannot become ready
# until the EBS CSI driver can provision volumes - see modules/eks_ebs_csi_driver_addon. A
# release that sits waiting on Pending pods is almost always that, not the chart.
locals {
  # Annotation keys have to be escaped for helm's --set, which treats an unescaped dot as a
  # path separator. Building the entries here keeps the escaping in one place rather than
  # repeated per annotation.
  ingress_annotation_entries = [
    for key, value in var.ingress_annotations : {
      name  = "ingress.annotations.${replace(key, ".", "\\.")}"
      value = value
      # Annotation values must be strings. helm's --set would infer a type otherwise, and the
      # API server rejects a non-string annotation - "true" here would arrive as a boolean
      # and fail the Ingress (rules.md E-7).
      type = "string"
    }
  ]
  # Every Bitnami-based subchart, repointed at a namespace that still has the tags this chart pins.
  #
  # Bitnami moved its versioned tags out of docker.io/bitnami into docker.io/bitnamilegacy, so every
  # image this chart's subcharts name is simply gone. The pull fails as NotFound rather than as an
  # auth or rate-limit error:
  #
  #   Failed to pull image "docker.io/bitnami/postgresql:15.3.0-debian-11-r0":
  #     ... failed to resolve reference: not found
  #
  # What that does to the install is worth following, because the error Terraform reports names
  # neither images nor the registry. PostgreSQL never starts, so the chart's db-check hook at weight
  # -1 - a netcat waiting for port 5432 - runs out its 600s activeDeadlineSeconds, and helm reports:
  #
  #   failed post-install: 1 error occurred: * job sentry-db-check failed: DeadlineExceeded
  #
  # Six images are affected in the default configuration (postgresql, redis, kafka, zookeeper,
  # rabbitmq, nginx) and two more in subcharts this project leaves off (memcached behind
  # sourcemaps.enabled, pgbouncer behind pgbouncer.enabled). All eight are listed, so turning either
  # of those on does not walk into the same wall. Counted by rendering the chart rather than guessed,
  # and each tag confirmed to exist under the legacy namespace.
  #
  # The subchart key and the image name coincide for all eight, which is why one list is enough.
  bitnami_subcharts = ["postgresql", "redis", "kafka", "zookeeper", "rabbitmq", "nginx", "memcached", "pgbouncer"]
  values = {
    for name in local.bitnami_subcharts :
    name => { image = { repository = "${var.bitnami_image_namespace}/${name}" } }
  }
}
resource "helm_release" "sentry" {
  name             = var.release_name
  repository       = var.chart_repository
  chart            = "sentry"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = var.create_namespace
  # Holds the apply until every subchart is ready, which is what the _monolithic script's
  # "--wait --timeout=3000s" did.
  #
  # Worth knowing what the timeout is actually spent on, because when it expires helm reports one
  # line - "context deadline exceeded" - and nothing about where it got to. Rendering this chart
  # shows 45 resources carrying a helm.sh/hook annotation: 5 Jobs and 40 Deployments, across 12
  # distinct hook weights. Helm runs hook weights strictly in order and waits for each group to
  # become ready before starting the next, so the install is a serial chain of twelve waves:
  #
  #   -1   db-check             waits for PostgreSQL to answer
  #    3   snuba-db-init        creates the ClickHouse schemas
  #    5   snuba-migrate        runs the ClickHouse migrations - minutes on its own
  #    6   db-init              Sentry's own migrations
  #    9   user-create          the admin account
  #   10   19 consumers         first wave of Deployments
  #   12   12 snuba consumers   second wave
  #   16-25                     four more waves, ending with relay
  #
  # Each wave pulls the getsentry/sentry image onto nodes that have never cached it, through the NAT
  # gateway, so the chain is genuinely slow and the timeout has to be generous.
  #
  # But slow was not the whole story, and an earlier version of this comment drew the wrong conclusion
  # from it - it said wait = false would not help. It does, and for a reason that has nothing to do
  # with how long anything takes. See var.wait_for_release: --wait blocks on the main manifest before
  # any post-install hook runs, and two of the main manifest's Deployments cannot become healthy until
  # the hooks have migrated the database. That is a deadlock, and raising the timeout from 3000 to
  # 5400 simply took longer to reach it.
  wait    = var.wait_for_release
  timeout = var.timeout_seconds

  # Nested image.repository values, so yamlencode rather than escaped set entries - the keys contain
  # no dots to escape, but the nesting is what the subcharts read.
  values = [yamlencode(local.values)]

  set = concat([
    {
      name = "ingress.enabled"
      # The chart defaults this to false, so without it no Ingress object is created at all and the
      # class name and annotations below are applied to nothing. Silent: the release succeeds and the
      # dashboard simply never gets an address (rules.md G-1).
      value = tostring(var.ingress_enabled)
    },
    {
      name = "ingress.ingressClassName"
      # A class name, so a string - but left to auto inference because no chart template
      # type-checks it and the value is never all digits.
      value = var.ingress_class_name
    },
    {
      name  = "user.email"
      value = var.admin_email
      # The login name. type = "string" because an address is a string and helm's inference
      # has no reason to be trusted with it (rules.md E-7).
      type = "string"
    },
    ],
    local.ingress_annotation_entries,
    var.additional_set_values,
  )
  # set_sensitive rather than set, so the password is not written into the plan output or the
  # state's rendered value list the way a plain set entry is. The chart still stores it in its
  # own Secret in the cluster, which is where Sentry reads it from.
  set_sensitive = [
    {
      name  = "user.password"
      value = var.admin_password
      type  = "string"
    },
  ]
}
