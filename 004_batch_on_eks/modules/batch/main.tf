data "aws_caller_identity" "current" {}

resource "aws_iam_role" "batch_node_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["ec2.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "batch_node_iam_role" {
  for_each   = toset(var.node_iam_policy_arns)
  role       = aws_iam_role.batch_node_iam_role.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "batch_node_instance_profile" {
  role = aws_iam_role.batch_node_iam_role.name
}

resource "aws_eks_access_entry" "batch_node_iam_access_entry" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.batch_node_iam_role.arn
  type          = "EC2_LINUX"
}

locals {
  # The AWS IAM Authenticator used by the aws-auth ConfigMap does not permit
  # a path in rolearn (docs.aws.amazon.com/eks/latest/userguide/security-iam-troubleshoot.html:
  # "The AWS IAM Authenticator doesn't permit a path in the role ARN used in
  # the ConfigMap"), so even though AWSServiceRoleForBatch's real ARN
  # contains the aws-service-role/batch.amazonaws.com/ path segment, the
  # ConfigMap mapping must use the path-less form below. This is the
  # opposite requirement from aws_eks_access_entry, which needs the full
  # ARN including the service-linked-role path (but doesn't accept
  # service-linked roles as a principal at all - see the comment below).
  batch_service_linked_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/AWSServiceRoleForBatch"
  all_namespaces                = concat([var.kubernetes_namespace], var.additional_kubernetes_namespaces)
}

# aws_eks_access_entry does not support service-linked role principals
# ("The caller is not allowed to modify access entries with a principalArn
# value of a Service Linked Role"), so AWSServiceRoleForBatch cannot be
# granted access the way modules/vscode_ec2 and modules/karpenter's node
# role are (rules.md E-6 does not apply here). It must instead be mapped
# through the aws-auth ConfigMap, which this cluster's
# authentication_mode = "API_AND_CONFIG_MAP" still supports alongside
# access entries.
resource "kubectl_manifest" "batch_service_aws_auth_mapping" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "aws-auth"
      namespace = "kube-system"
    }
    data = {
      mapRoles = yamlencode([
        {
          rolearn  = local.batch_service_linked_role_arn
          username = var.batch_username
          groups   = []
        },
      ])
    }
  })

  # aws-auth is created automatically by EKS; this resource must only patch
  # mapRoles onto it, not fight over ownership of the whole ConfigMap
  # (e.g. entries added by managed node groups for their own instance role).
  force_conflicts   = true
  server_side_apply = true
}

# Kubernetes RBAC objects are declared as raw manifests via the alekc/kubectl
# provider (kubectl_manifest) instead of the hashicorp/kubernetes typed
# resources, so the whole root module (EKS cluster + these RBAC objects) can
# be applied in a single `terraform apply` (rules.md E-2). yamlencode()
# converts the HCL object below into the manifest's exact camelCase
# Kubernetes API field names (apiGroups, roleRef, apiGroup, ...).
resource "kubectl_manifest" "batch_namespace" {
  for_each = toset(local.all_namespaces)

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name   = each.value
      labels = { name = each.value }
    }
  })
}

resource "kubectl_manifest" "aws_batch_cluster_role" {
  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "ClusterRole"
    metadata = {
      name = "aws-batch-cluster-role"
    }
    rules = [
      { apiGroups = [""], resources = ["namespaces"], verbs = ["get"] },
      { apiGroups = [""], resources = ["nodes"], verbs = ["get", "list", "watch"] },
      { apiGroups = [""], resources = ["pods"], verbs = ["get", "list", "watch"] },
      { apiGroups = [""], resources = ["events"], verbs = ["list"] },
      { apiGroups = [""], resources = ["configmaps"], verbs = ["get", "list", "watch"] },
      { apiGroups = ["apps"], resources = ["daemonsets", "deployments", "statefulsets", "replicasets"], verbs = ["get", "list", "watch"] },
      { apiGroups = ["rbac.authorization.k8s.io"], resources = ["clusterroles", "clusterrolebindings"], verbs = ["get", "list"] },
    ]
  })
}

resource "kubectl_manifest" "aws_batch_cluster_role_binding" {
  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "ClusterRoleBinding"
    metadata = {
      name = "aws-batch-cluster-role-binding"
    }
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io"
      kind     = "ClusterRole"
      name     = "aws-batch-cluster-role"
    }
    subjects = [
      { kind = "User", name = var.batch_username, apiGroup = "rbac.authorization.k8s.io" },
    ]
  })

  # roleRef.name above is a literal string, not an attribute reference, so
  # Terraform's graph would not otherwise know the ClusterRole must exist
  # first (rules.md D-1's reasoning, applied to a naming rather than an ARN
  # reference).
  depends_on = [kubectl_manifest.aws_batch_cluster_role]
}

resource "kubectl_manifest" "aws_batch_compute_environment_role" {
  # Iterating over the namespace *resource* map (rather than
  # toset(local.all_namespaces)) makes the namespace's existence an actual
  # Terraform dependency, since each.value.name is an attribute of the
  # Namespace manifest rather than a plain string.
  for_each = kubectl_manifest.batch_namespace

  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "Role"
    metadata = {
      name      = "aws-batch-compute-environment-role"
      namespace = each.value.name
    }
    rules = [
      { apiGroups = [""], resources = ["pods"], verbs = ["create", "get", "list", "watch", "delete", "patch"] },
      { apiGroups = [""], resources = ["serviceaccounts"], verbs = ["get", "list"] },
      { apiGroups = ["rbac.authorization.k8s.io"], resources = ["roles", "rolebindings"], verbs = ["get", "list"] },
    ]
  })
}

resource "kubectl_manifest" "aws_batch_compute_environment_role_binding" {
  for_each = kubectl_manifest.batch_namespace

  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "RoleBinding"
    metadata = {
      name      = "aws-batch-compute-environment-role-binding"
      namespace = each.value.name
    }
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io"
      kind     = "Role"
      name     = "aws-batch-compute-environment-role"
    }
    subjects = [
      { kind = "User", name = var.batch_username, apiGroup = "rbac.authorization.k8s.io" },
    ]
  })

  # roleRef.name is a literal string matching the Role created above; make
  # the dependency explicit since there is no attribute reference.
  depends_on = [kubectl_manifest.aws_batch_compute_environment_role]
}

resource "aws_batch_compute_environment" "batch_compute_environment" {
  type  = "MANAGED"
  state = "ENABLED"
  eks_configuration {
    eks_cluster_arn      = var.cluster_arn
    kubernetes_namespace = var.kubernetes_namespace
  }
  compute_resources {
    type                = "EC2"
    allocation_strategy = var.allocation_strategy
    min_vcpus           = var.min_vcpus
    max_vcpus           = var.max_vcpus
    instance_type       = ["optimal"]
    subnets             = var.subnet_ids
    security_group_ids  = var.security_group_ids
    ec2_key_pair        = var.key_name
    instance_role       = aws_iam_instance_profile.batch_node_instance_profile.arn
    tags = {
      Name = "batch-node"
    }
  }
  update_policy {
    job_execution_timeout_minutes = 30
    terminate_jobs_on_update      = false
  }

  depends_on = [
    aws_iam_role_policy_attachment.batch_node_iam_role,
    aws_eks_access_entry.batch_node_iam_access_entry,
    kubectl_manifest.batch_service_aws_auth_mapping,
    kubectl_manifest.aws_batch_cluster_role_binding,
    kubectl_manifest.aws_batch_compute_environment_role_binding,
  ]
}

resource "aws_batch_job_definition" "batch_job_definition" {
  type = "container"
  name = "${var.name_prefix}-batch-job-definition"
  eks_properties {
    pod_properties {
      containers {
        name    = "sleep30s"
        image   = var.job_container_image
        command = var.job_command
        resources {
          limits = {
            cpu    = var.job_cpu
            memory = var.job_memory
          }
          requests = {
            cpu    = var.job_cpu
            memory = var.job_memory
          }
        }
      }
    }
  }
  platform_capabilities = ["EC2"]
  timeout {
    attempt_duration_seconds = var.job_timeout_seconds
  }
}

resource "aws_batch_job_queue" "batch_job_queue" {
  name     = "${var.name_prefix}-batch-job-queue"
  state    = "ENABLED"
  priority = 1
  compute_environment_order {
    order               = 1
    compute_environment = aws_batch_compute_environment.batch_compute_environment.arn
  }
}
