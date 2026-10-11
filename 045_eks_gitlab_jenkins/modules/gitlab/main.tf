locals {
  # Annotation keys have to be escaped for helm's --set, which reads an unescaped
  # dot as a path separator.
  service_annotation_prefix = "nginx-ingress.controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer"
}

# The GitLab chart, as a Helm release rather than as a `helm install` inside a
# shell script an SSM Association ran on the workbench (rules.md E-1). The
# _monolithic template wrote that script to /home/ec2-user/gitlab.sh and executed
# it, so the release was invisible to Terraform: no plan, no version pin, no way
# to see that it had failed.
#
# The release carries its own datastores - PostgreSQL, Redis and MinIO all come
# from subcharts - which is why chart_version is capped below 10.0.0, the version
# that removed them. Nothing else in this project provisions a database, a cache
# or a bucket, so a chart above that cap has nothing to connect to.
resource "helm_release" "gitlab" {
  name             = var.release_name
  repository       = var.chart_repository
  chart            = "gitlab"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = var.create_namespace

  # Off by default, unlike most releases in this repository. This chart installs
  # around thirty workloads plus migration Jobs, and a first install regularly
  # takes fifteen minutes or more; holding the apply open for it makes a timeout
  # the likely outcome and the timeout tells you nothing. The _monolithic script
  # did not wait either. Turn it on when the apply is expected to sit still.
  wait    = var.wait
  timeout = var.timeout_seconds

  set = concat([
    {
      name = "global.hosts.domain"
      # Every GitLab hostname is derived from this: gitlab.<domain>,
      # registry.<domain>, minio.<domain>. The wildcard DNS record the caller
      # points at the load balancer is what makes them resolve.
      value = var.domain
      type  = "string"
    },
    {
      name  = "certmanager-issuer.email"
      value = var.issuer_email
      type  = "string"
    },
    {
      # Redundant on the pinned 9.x chart, where this already defaults to true,
      # and set anyway because the default is not stable across majors: 10.0.0
      # flipped it to false in the same release that dropped the bundled
      # datastores. With it false the chart installs no ingress controller, so
      # the Service the pre-created NLB is tagged for
      # (gitlab-nginx-ingress-controller) never exists, and the AWS Load Balancer
      # Controller has nothing to reconcile and never adopts the load balancer -
      # which produces no error anywhere, just an address that answers nothing
      # (rules.md G-3).
      name  = "nginx-ingress.enabled"
      value = "true"
      # No type = "string": the condition is evaluated as a boolean, and a
      # string "true" would not satisfy it (rules.md E-7 is the same argument in
      # the other direction).
    },
    {
      # The switch that decides which controller owns the Service, and the other
      # thing the _monolithic script omitted. Without it the in-tree AWS cloud
      # provider claims the Service and builds a Classic Load Balancer, ignoring
      # every annotation below - the target type, the security groups, and the
      # adoption the pre-created NLB is waiting for (rules.md G-1).
      name  = "${local.service_annotation_prefix}-type"
      value = "external"
      # Annotation values must be strings; helm would otherwise infer a type and
      # the API server rejects a non-string annotation (rules.md E-7).
      type = "string"
    },
    {
      name  = "${local.service_annotation_prefix}-scheme"
      value = var.scheme
      type  = "string"
    },
    {
      # nlb-target-type, not target-type: the Service spelling carries the nlb-
      # prefix while the Ingress spelling does not, and the wrong one is ignored
      # rather than rejected (rules.md G-1).
      name  = "${local.service_annotation_prefix}-nlb-target-type"
      value = var.nlb_target_type
      type  = "string"
    },
    {
      # Naming the groups here is what keeps the controller from replacing them.
      # An NLB can only be given security groups at creation time, so the
      # pre-created load balancer is built with this same list (rules.md G-3).
      name  = "${local.service_annotation_prefix}-security-groups"
      value = join(",", var.frontend_security_group_ids)
      type  = "string"
    },
    ],
    var.additional_set_values,
  )
}
