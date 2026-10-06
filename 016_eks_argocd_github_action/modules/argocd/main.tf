# Argo CD, installed with helm_release rather than by the
# "kubectl apply -n argocd -f .../install.yaml" the _monolithic template ran over SSM
# and then patched with "kubectl patch svc argocd-server -p '{...LoadBalancer}'"
# (rules.md E-1). The Service type is a chart value here, so the patch step is gone -
# and with it the "sleep 10; patch; sleep 120" sequence that made the install a matter
# of timing rather than of ordering.
#
# helm rather than kubectl_manifest for the install: the helm provider needs no API
# server access at plan time, only at apply time, so it works even though its
# configuration comes from a cluster created in the same apply (rules.md E-2).
resource "helm_release" "argocd" {
  name             = var.release_name
  repository       = var.chart_repository
  chart            = var.chart_name
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = true
  # Holds the apply until the server Deployment reports Available, which is what the
  # _monolithic template's three retried "argocd login" calls were working around.
  wait    = true
  timeout = var.timeout_seconds

  set = concat([
    {
      # What the _monolithic template achieved with kubectl patch. The AWS Load
      # Balancer Controller turns this into an NLB, so the dashboard is reachable
      # without a port-forward - but only with the two annotations below, which is
      # what this release was missing.
      name  = "server.service.type"
      value = var.server_service_type
    },
    {
      # The switch that hands this Service to the AWS Load Balancer Controller
      # (rules.md G-1). Without it the Service is claimed by the legacy cloud
      # provider instead, which builds a Classic Load Balancer and ignores every
      # annotation here - including the scheme below.
      #
      # It worked without this only because the controller's chart installs a
      # mutating webhook that injects spec.loadBalancerClass into every
      # type: LoadBalancer Service. That is a cluster-wide webhook this repository
      # turns off elsewhere (rules.md G-4), so depending on it makes the dashboard's
      # reachability a property of another module's chart defaults.
      name  = "server.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
      value = "external"
      # Annotation values must be strings (rules.md E-7).
      type = "string"
    },
    {
      # internet-facing, because the controller's default for a Service is
      # internal - not what the in-tree provider defaulted to, and not what the
      # _monolithic template's kubectl patch produced either.
      #
      # This is the annotation whose absence is invisible. An internal NLB is
      # created successfully, the Service gets an EXTERNAL-IP, kubectl looks
      # perfect, and the hostname resolves only inside the VPC - so the dashboard
      # is unreachable from a browser with nothing reporting an error. Placing it
      # needs the kubernetes.io/role/elb tag on the public subnets, which the root
      # passes to the network module (rules.md G-1).
      name  = "server.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-scheme"
      value = var.server_service_scheme
      type  = "string"
    },
    {
      # Argo CD terminates TLS itself by default, which means an ELB in front of it
      # speaks HTTP to a server expecting HTTPS and every request 307-redirects in a
      # loop. Running the server insecure moves TLS termination to the load balancer.
      name  = "configs.params.server\\.insecure"
      value = "true"
      # Chart values under configs.params become ConfigMap entries, and a ConfigMap
      # value has to be a string - an inferred bool renders unquoted and the API
      # server rejects it (rules.md E-7).
      type = "string"
    },
    ],
    var.additional_set_values,
  )
}
# The Application that makes this GitOps rather than a one-off deployment: Argo CD
# watches the repository path and applies whatever is committed there. The
# _monolithic template created it by running "argocd app create" from a shell script
# on the bastion, after logging in with a password scraped out of a secret - so the
# application existed nowhere in any configuration (rules.md E-1).
resource "kubectl_manifest" "application" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = var.application_name
      namespace = var.namespace
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.repository_url
        targetRevision = var.target_revision
        path           = var.manifest_path
      }
      destination = {
        # The cluster Argo CD runs in. The _monolithic template ran
        # "argocd cluster add" to register the current context, which for an
        # in-cluster deployment is what this built-in address already means.
        server    = "https://kubernetes.default.svc"
        namespace = var.destination_namespace
      }
      syncPolicy = {
        automated = {
          prune    = var.sync_prune
          selfHeal = var.sync_self_heal
        }
      }
    }
  })

  # The Application CRD is installed by the chart above, so the manifest cannot be
  # applied before the release exists. Ordering it here also makes terraform destroy
  # delete the Application while the controller is still running to prune what it
  # created (rules.md D-4).
  depends_on = [helm_release.argocd]
}
