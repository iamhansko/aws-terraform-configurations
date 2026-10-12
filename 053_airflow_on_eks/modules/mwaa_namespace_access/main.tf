# Where the KubernetesPodOperator DAG runs its pods, and what the MWAA execution role may do there
# (mwaa.tf in the blueprint, "Create K8s Namespace and Role for mwaa access directly").
#
# The permissions are this Role and nothing else. The blueprint also mapped the execution role to
# system:masters through aws-auth, which made it cluster-admin - and that is why a bug in its
# RoleBinding never showed: roleRef named "mwaa", the namespace, rather than "mwaa-role", the Role,
# so the binding granted nothing and cluster-admin did all the work. Here the binding points at the
# Role, the root's access entry for the execution role carries no access policy, and the DAG gets
# exactly the namespace-scoped permissions the blueprint wrote down (rules.md A-5 - narrowing what
# the original granted is a change, and this is where it is recorded).
resource "kubectl_manifest" "namespace" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    # The blueprint also set an annotation "name: mwaa" on it, which nothing reads; not carried over.
    metadata = { name = var.namespace }
  })
}
resource "kubectl_manifest" "role" {
  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "Role"
    metadata = {
      name      = var.role_name
      namespace = var.namespace
    }
    # camelCase throughout, because these are the Kubernetes API's own field names - not the
    # snake_case the blueprint's typed kubernetes_role_v1 block used (rules.md E-2/E-3).
    rules = [
      # The blueprint's rule as it wrote it, which is also the Role AWS's MWAA-with-EKS guide uses.
      {
        apiGroups = ["", "apps", "batch", "extensions"]
        resources = ["jobs", "pods", "pods/attach", "pods/exec", "pods/log", "pods/portforward", "secrets", "services"]
        verbs     = ["create", "delete", "describe", "get", "list", "patch", "update"]
      },
      # Added, because the provider this environment installs needs it and the blueprint's Role
      # predates that. apache-airflow-providers-cncf-kubernetes 10.13.0, which the Airflow 2.11.2
      # constraints pin, lists the pod's events while it waits for the pod to start - on the success
      # path, not only after a failure. Without this the task fails with 403 Forbidden on
      # events before the pod has done anything. The blueprint would not have seen it either way,
      # because cluster-admin covered it.
      {
        apiGroups = [""]
        resources = ["events"]
        verbs     = ["get", "list", "watch"]
      },
    ]
  })
  depends_on = [kubectl_manifest.namespace]
}
resource "kubectl_manifest" "role_binding" {
  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "RoleBinding"
    metadata = {
      name      = var.role_binding_name
      namespace = var.namespace
    }
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io"
      kind     = "Role"
      # The Role above, by the same variable - not the namespace's name, which is what the blueprint's
      # roleRef pointed at.
      name = var.role_name
    }
    subjects = [{
      apiGroup = "rbac.authorization.k8s.io"
      kind     = "User"
      # The user name the root's access entry gives the MWAA execution role. One value on both sides,
      # so the binding cannot miss its subject (rules.md B-5).
      name = var.user_name
    }]
  })
  # roleRef.name is a literal string, so nothing else tells Terraform the Role must exist first
  # (rules.md E-2).
  depends_on = [kubectl_manifest.role]
}
