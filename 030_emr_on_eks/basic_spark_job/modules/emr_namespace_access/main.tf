data "aws_caller_identity" "current" {}

# What makes EMR on EKS able to use a namespace at all - and the whole of it is missing from the
# _monolithic template, which declared an aws_emrcontainers_virtual_cluster pointed at a
# namespace nothing created and left it at that. CreateVirtualCluster fails with
#
#   ValidationException: Unauthorized to perform read namespace on (big-data)
#
# AWS documents three steps, and `eksctl create iamidentitymapping --service-name emr-containers`
# is the one command that does all three. Declared here instead:
#
#   1. the namespace itself;
#   2. a Role in it, plus a RoleBinding to a Kubernetes user;
#   3. that user mapped to the AWSServiceRoleForAmazonEMRContainers service-linked role.
#
# Step 3 is the interesting one. A service-linked role cannot be the principal of an
# aws_eks_access_entry - EKS rejects it with "The specified principalArn is invalid: invalid
# principal" - so the mapping has to go through the aws-auth ConfigMap (rules.md E-6).
resource "kubectl_manifest" "namespace" {
  count = var.create_namespace ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata   = { name = var.namespace }
  })
}

# The permissions EMR on EKS needs inside the namespace, as AWS documents them for the manual
# path. Namespace-scoped: a Role rather than a ClusterRole, so nothing here reaches outside the
# one namespace the virtual cluster is bound to.
resource "kubectl_manifest" "role" {
  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "Role"
    metadata = {
      name      = var.role_name
      namespace = var.namespace
    }
    # camelCase throughout, because these are the Kubernetes API's own field names - not the
    # snake_case a typed provider's HCL block would use (rules.md E-2/E-3).
    rules = [
      {
        apiGroups = [""]
        resources = ["namespaces"]
        verbs     = ["get"]
      },
      {
        apiGroups = [""]
        resources = ["serviceaccounts", "services", "configmaps", "events", "pods", "pods/log"]
        verbs     = ["get", "list", "watch", "describe", "create", "edit", "delete", "deletecollection", "annotate", "patch", "label"]
      },
      {
        apiGroups = [""]
        resources = ["secrets"]
        verbs     = ["create", "patch", "delete", "watch"]
      },
      {
        apiGroups = ["apps"]
        resources = ["statefulsets", "deployments"]
        verbs     = ["get", "list", "watch", "describe", "create", "edit", "delete", "annotate", "patch", "label"]
      },
      {
        apiGroups = ["batch"]
        resources = ["jobs"]
        verbs     = ["get", "list", "watch", "describe", "create", "edit", "delete", "annotate", "patch", "label"]
      },
      {
        apiGroups = ["extensions", "networking.k8s.io"]
        resources = ["ingresses"]
        verbs     = ["get", "list", "watch", "describe", "create", "edit", "delete", "annotate", "patch", "label"]
      },
      {
        apiGroups = ["rbac.authorization.k8s.io"]
        resources = ["roles", "rolebindings"]
        verbs     = ["get", "list", "watch", "describe", "create", "edit", "delete", "deletecollection", "annotate", "patch", "label"]
      },
      {
        apiGroups = ["", "apps", "batch", "extensions"]
        resources = ["persistentvolumeclaims"]
        verbs     = ["get", "list", "watch", "describe", "create", "edit", "delete", "deletecollection", "annotate", "patch", "label"]
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
      name     = var.role_name
    }
    subjects = [{
      apiGroup = "rbac.authorization.k8s.io"
      kind     = "User"
      # The same user name the aws-auth mapping below uses. One value on both sides, so the
      # binding cannot miss its subject (rules.md B-5).
      name = var.emr_user_name
    }]
  })

  # roleRef.name is a literal string, so nothing else tells Terraform the Role must exist first
  # (rules.md E-2).
  depends_on = [kubectl_manifest.role]
}

locals {
  # The ARN as the AWS IAM Authenticator will accept it, which is not the role's real ARN.
  #
  # AWSServiceRoleForAmazonEMRContainers actually lives at
  # role/aws-service-role/emr-containers.amazonaws.com/AWSServiceRoleForAmazonEMRContainers, but
  # the authenticator does not permit a path in a rolearn - so the ConfigMap entry has to name it
  # without one. This is the exact opposite of what aws_eks_access_entry wants, and it only comes
  # up on the ConfigMap path - which is the only path available for a service-linked role
  # (rules.md E-6).
  emr_service_linked_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.service_linked_role_name}"
}

# server_side_apply with force_conflicts, so only the mapRoles field is merged rather than the
# whole ConfigMap being replaced. EKS and the managed node group have already written their own
# entries into this object - the node instance role's mapping among them - and overwriting it
# would take every node out of the cluster (rules.md E-6).
resource "kubectl_manifest" "aws_auth" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "aws-auth"
      namespace = "kube-system"
    }
    data = {
      # A YAML string inside a YAML document, which is how aws-auth stores it.
      mapRoles = yamlencode([{
        rolearn  = local.emr_service_linked_role_arn
        username = var.emr_user_name
        groups   = []
      }])
    }
  })

  force_conflicts   = true
  server_side_apply = true

  # The RoleBinding names this user, so the mapping is only meaningful once the binding exists -
  # and the binding is what the authenticated user gets its permissions from.
  depends_on = [kubectl_manifest.role_binding]
}
