# Argo CD with the argocd-vault-plugin, from the official argo-cd chart.
#
# The _monolithic template did this with raw kubectl against an unpinned URL:
#   kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
#   kubectl -n argocd annotate service argocd-server <three annotations>
#   kubectl -n argocd patch service argocd-server -p '{"spec":{"type":"LoadBalancer"}}'
#   kubectl -n argocd apply -f <a full argocd-repo-server Deployment with the AVP sidecar>
#   kubectl -n argocd rollout restart deployment argocd-repo-server argocd-redis
#
# Four things were wrong with that, and the chart fixes all of them (rules.md E-1):
#
#   1. "stable" is a moving target, so no two applies installed the same Argo CD.
#   2. annotate and patch are imperative edits to an object Terraform does not own, so the
#      Service's type and annotations were invisible to plan and lost on any reinstall.
#   3. Re-applying a whole argocd-repo-server Deployment means owning upstream's definition -
#      every field of it, forever. That is the failure rules.md E-8 describes at manifest scale:
#      the next Argo CD version changes its own Deployment and this copy silently overrides it.
#   4. The rollout restarts existed only to work around 2 and 3.
#
# Everything above becomes chart values below, so the Service type, the annotations and the
# sidecar are all declared, diffable and removed cleanly on destroy.
locals {
  # The plugin the sidecar runs. The chart renders this into the argocd-cmp-cm ConfigMap, which
  # is why no ConfigMap is declared by hand here.
  cmp_plugins = {
    (var.plugin_name) = {
      allowConcurrency = true
      discover = {
        find = {
          command = ["sh", "-c", "find . -name '*.yaml'"]
        }
      }
      generate = {
        command = ["argocd-vault-plugin", "generate", "-s", var.vault_secret_name, "."]
      }
      lockRepo = false
    }
  }
  values = {
    # Pins the Argo CD application version alongside the chart version, so the sidecar's
    # copyutil image and the repo-server image cannot drift apart.
    global = {
      image = {
        tag = var.argocd_image_tag
      }
    }
    configs = {
      cmp = {
        # Renders argocd-cmp-cm from cmp_plugins. Without create the ConfigMap does not exist and
        # the sidecar starts with no plugin definition, which presents as an application stuck
        # on "no matching config management plugin".
        create  = true
        plugins = local.cmp_plugins
      }
      # argocd-cmd-params-cm. server.insecure is what makes the UI reachable over the load
      # balancer's HTTP listener, and without it the dashboard simply does not open.
      #
      # argocd-server terminates TLS itself by default and answers plain HTTP with a redirect.
      # Through the NLB that is a dead end, measured against the deployed stack:
      #
      #   http://<nlb>   -> 307, Location: https://<nlb>/
      #   https://<nlb>  -> connection failed
      #
      # The redirect target fails because the frontend security group opens only the listener port
      # (rules.md G-1), so 443 is closed - and even opened it would serve a self-signed certificate.
      # insecure makes the server speak plain HTTP on 8080 and stop redirecting, which matches the
      # single port the security group opens and the http:// URL this project outputs.
      #
      # The _monolithic template hit the same wall and worked around it only for the CLI, with
      # "argocd login --insecure"; the browser was left with the redirect.
      params = {
        "server.insecure" = var.server_insecure
      }
    }
    server = {
      service = {
        # Declared, not patched. The _monolithic template created the Service as ClusterIP and
        # then edited it in place with kubectl patch.
        type = "LoadBalancer"
        # The switch that decides which controller handles this Service, plus the scheme, the
        # target type and the frontend security group. aws-load-balancer-type: external is the
        # one the _monolithic template omitted - without it the in-tree cloud provider claims the
        # Service and builds a Classic Load Balancer, ignoring every other annotation, so the
        # pre-created NLB is never adopted (rules.md G-1/G-3).
        annotations = var.service_annotations
      }
    }
    repoServer = {
      # The AVP sidecar. extraContainers rather than a replacement Deployment, so upstream keeps
      # ownership of everything else in the pod spec.
      extraContainers = [{
        name    = var.sidecar_name
        command = ["/var/run/argocd/argocd-cmp-server"]
        image   = var.sidecar_image
        securityContext = {
          runAsNonRoot = true
          runAsUser    = 999
        }
        volumeMounts = [
          { mountPath = "/var/run/argocd", name = "var-files" },
          { mountPath = "/home/argocd/cmp-server/plugins", name = "plugins" },
          { mountPath = "/tmp", name = "tmp" },
          # The chart keys each plugin in argocd-cmp-cm as "<name>.yaml", and the sidecar expects
          # exactly one plugin definition at this path - hence the subPath.
          {
            mountPath = "/home/argocd/cmp-server/config/plugin.yaml"
            subPath   = "${var.plugin_name}.yaml"
            name      = "argocd-cmp-cm"
          },
          # Puts the downloaded binary on the sidecar's PATH. The generate command above is just
          # "argocd-vault-plugin", so this mount is what makes it resolvable.
          {
            mountPath = "/usr/local/bin/argocd-vault-plugin"
            subPath   = "argocd-vault-plugin"
            name      = "custom-tools"
          },
        ]
      }]
      # Fetches the plugin binary into a shared emptyDir before the sidecar starts. Pinned,
      # because the _monolithic template's manifest hardcoded a version inline where nothing
      # surfaced it.
      initContainers = [{
        name    = "download-tools"
        image   = var.download_tools_image
        command = ["sh", "-c"]
        args = [join(" && ", [
          "curl -sSfL https://github.com/argoproj-labs/argocd-vault-plugin/releases/download/v${var.avp_version}/argocd-vault-plugin_${var.avp_version}_linux_amd64 -o argocd-vault-plugin",
          "chmod +x argocd-vault-plugin",
          "mv argocd-vault-plugin /custom-tools/",
        ])]
        volumeMounts = [{ mountPath = "/custom-tools", name = "custom-tools" }]
      }]
      volumes = [
        { name = "custom-tools", emptyDir = {} },
        { name = "argocd-cmp-cm", configMap = { name = "argocd-cmp-cm" } },
      ]
    }
  }
}
resource "helm_release" "argocd" {
  name             = var.release_name
  repository       = var.chart_repository
  chart            = "argo-cd"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = true
  wait             = true
  timeout          = var.timeout_seconds

  values = [yamlencode(local.values)]

  set = var.additional_set_values
}
# Lets the repo-server read the Secret holding Vault's address and token.
#
# The Secret itself is NOT created here: its VAULT_TOKEN comes from "vault operator init", which
# runs in an SSM Association because there is no Terraform resource for initialising Vault (see
# the root's aws_ssm_association.vault_bootstrap). The Role and RoleBinding do not depend on the
# token, so they belong in Terraform - and putting them here means they exist before the token
# does, which is the order that works: the repo-server only reads the Secret when it generates
# manifests, long after both.
resource "kubectl_manifest" "repo_server_secret_role" {
  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "Role"
    metadata = {
      name      = "${var.release_name}-repo-server-vault"
      namespace = var.namespace
    }
    rules = [{
      apiGroups = [""]
      resources = ["secrets"]
      # Scoped to the one Secret rather than every Secret in the namespace, which is what the
      # _monolithic template's Role also did - worth keeping, because the repo-server runs
      # plugin code from a Git repository.
      resourceNames = [var.vault_secret_name]
      verbs         = ["get"]
    }]
  })

  # The namespace is created by the Helm release above, and metadata.namespace is a literal
  # string rather than an attribute reference, so nothing else orders this after it
  # (rules.md D-1).
  depends_on = [helm_release.argocd]
}
resource "kubectl_manifest" "repo_server_secret_role_binding" {
  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "RoleBinding"
    metadata = {
      name      = "${var.release_name}-repo-server-vault"
      namespace = var.namespace
    }
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io"
      kind     = "Role"
      name     = "${var.release_name}-repo-server-vault"
    }
    subjects = [{
      kind      = "ServiceAccount"
      name      = "${var.release_name}-repo-server"
      namespace = var.namespace
    }]
  })

  # roleRef names the Role as a literal string rather than referencing the resource, so nothing
  # else orders this after it (rules.md D-1/E-2).
  depends_on = [
    helm_release.argocd,
    kubectl_manifest.repo_server_secret_role,
  ]
}
# The repository credential Argo CD clones the seed repository with.
#
# Needed because the seed repository is private. Argo CD finds credentials by matching a Secret
# labelled argocd.argoproj.io/secret-type: repository against the repository URL an Application names;
# with no match it tries an anonymous clone, and a private repository answers that with
# "authentication required". The Application is then Unknown with a connection error - the repository
# and its manifests exist, and nothing about the Application says the problem is a credential.
#
# Optional, so a caller pointing at a public repository can leave it out entirely rather than putting
# a token in the cluster for nothing (rules.md B-4).
#
# The switch is its own variable and not "repository_url != null", which is what it was first written
# as. count has to be decidable during plan, and repository_url is the clone URL of a repository this
# same apply creates - unknown until apply, so Terraform cannot tell whether this block is one
# instance or zero:
#
#   Error: Invalid count argument
#   The "count" value depends on resource attributes that cannot be determined until apply
#
# It is the same constraint rules.md B-8 describes for for_each keys, reached through count: the
# decision comes from configuration, the values may come from apply-time results. Worth noting how it
# hid - with the repository already in state its URL is known, so the error appears only on an apply
# that creates both, which is every apply from an empty state.
resource "kubectl_manifest" "repository_credentials" {
  count = var.create_repository_credentials ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = var.repository_secret_name
      namespace = var.namespace
      # The label is the whole mechanism. Without it this is an ordinary Secret that Argo CD never
      # looks at, and the failure is identical to having no credential at all.
      labels = {
        "argocd.argoproj.io/secret-type" = "repository"
      }
    }
    type = "Opaque"
    stringData = {
      type = "git"
      # Has to match the URL the Application names, character for character - Argo CD picks the
      # credential by longest URL prefix. It comes from the module that created the repository, so
      # both sides read the same value (rules.md B-5).
      url      = var.repository_url
      username = var.repository_username
      # A personal access token goes in the password field; GitHub stopped accepting passwords for
      # Git over HTTPS, and the username is not what authenticates.
      password = var.repository_token
    }
  })

  # Keeps the token out of plan output. yaml_body is already sensitive in this provider's schema, so
  # this is belt and braces for anything that reads the field back.
  sensitive_fields = ["stringData.password"]

  # The namespace comes from the Helm release, and metadata.namespace is a literal string rather than
  # an attribute reference, so nothing else orders this after it (rules.md D-1).
  depends_on = [helm_release.argocd]
}
