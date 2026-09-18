locals {
  # The address the stress pod requests. A Service DNS name, not a pod IP - which
  # is the whole reason a Service exists in this module.
  #
  # The _monolithic template staged two manifest files on the bastion and waited
  # for someone to paste the nginx pod's address into the second one, because a
  # pod IP is not knowable until the pod is scheduled. That is equally true for
  # Terraform: a pod's address is status.podIP, so no expression here could
  # produce it and no amount of depends_on would help. A Service name is decided
  # by configuration instead of by the scheduler, so it is known at plan time and
  # the substitution step disappears.
  #
  # This resolves only because these projects run CoreDNS on Fargate. The
  # _monolithic cluster left the CoreDNS pods Pending - they carry EKS's
  # compute-type: ec2 annotation and this cluster has no nodes - so DNS did not
  # work at all, which is why the original had to use an address in the first
  # place.
  web_service_fqdn = "${var.web_pod_name}.${var.namespace}.svc.cluster.local"
  # %% escapes the Terraform template directive so curl receives %{http_code}.
  # Written unescaped it is read as an HCL template and fails to parse.
  stress_command = "while true; do curl -s -o /dev/null -w '%%{http_code}\\n' http://${local.web_service_fqdn}:${var.container_port}; sleep ${var.request_interval_seconds}; done"
}
# Bare pods rather than Deployments, as the _monolithic template had them. The
# demo's point is that an individual pod gets its own Fargate node, which a
# listing shows directly for a pod named "web" and obscures behind a generated
# name for a Deployment's replica.
#
# Declared with alekc/kubectl because this module is applied in the same
# terraform apply as the cluster whose outputs configure the provider
# (rules.md E-2).
resource "kubectl_manifest" "web_pod" {
  count = var.create_pods ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Pod"
    metadata = {
      name      = var.web_pod_name
      namespace = var.namespace
      # Not decoration: the CloudWatch variant's Fluent Bit configuration runs a
      # rewrite_tag filter over kubernetes.labels.app and its OUTPUT blocks match
      # the tag that produces, so a pod without this label keeps its kube.* tag,
      # matches no output and has its logs dropped silently.
      labels = { app = var.web_pod_name }
    }
    spec = {
      restartPolicy = var.restart_policy
      containers = [{
        name  = var.web_pod_name
        image = var.web_image
        ports = [{ containerPort = var.container_port }]
      }]
    }
  })
}
# Gives the stress pod a name to request instead of an address to be told.
resource "kubectl_manifest" "web_service" {
  count = var.create_pods ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = var.web_pod_name
      namespace = var.namespace
    }
    spec = {
      type     = "ClusterIP"
      selector = { app = var.web_pod_name }
      ports = [{
        port       = var.container_port
        targetPort = var.container_port
        protocol   = "TCP"
      }]
    }
  })
}
resource "kubectl_manifest" "stress_pod" {
  count = var.create_pods ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Pod"
    metadata = {
      name      = var.stress_pod_name
      namespace = var.namespace
      # Same reason as the web pod: this label is what routes the records.
      labels = { app = var.stress_pod_name }
    }
    spec = {
      restartPolicy = var.restart_policy
      containers = [{
        name    = var.stress_pod_name
        image   = var.stress_image
        command = ["sh", "-c", local.stress_command]
      }]
    }
  })

  # The Service and the pod behind it are named in a string inside the container
  # command, not referenced as attributes, so nothing else tells Terraform they
  # have to exist first (rules.md D-1). The curl loop would survive being wrong
  # about this - it retries every few seconds - but the first records would be
  # connection failures rather than the 200s the demo is showing.
  depends_on = [kubectl_manifest.web_service, kubectl_manifest.web_pod]
}
