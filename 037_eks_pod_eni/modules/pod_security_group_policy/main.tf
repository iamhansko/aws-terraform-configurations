resource "aws_security_group" "default_pod_security_group" {
  description = "Security group assigned directly to pods via SecurityGroupPolicy (Security Groups for Pods)"
  name        = var.security_group_name
  vpc_id      = var.vpc_id

  tags = {
    Name = var.security_group_name
  }
}

resource "aws_vpc_security_group_egress_rule" "security_group_egress" {
  security_group_id = aws_security_group.default_pod_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# Declared as a raw manifest via the alekc/kubectl provider (kubectl_manifest)
# instead of hashicorp/kubernetes's kubernetes_manifest, because this module
# is applied in the same `terraform apply` as the EKS cluster that creates
# it, and kubernetes_manifest needs a live API server at plan time to
# resolve the CRD's schema (rules.md E-2).
resource "kubectl_manifest" "default_sgp" {
  yaml_body = yamlencode({
    apiVersion = "vpcresources.k8s.aws/v1beta1"
    kind       = "SecurityGroupPolicy"
    metadata = {
      name      = var.policy_name
      namespace = var.namespace
    }
    spec = {
      podSelector = {}
      securityGroups = {
        groupIds = [aws_security_group.default_pod_security_group.id]
      }
    }
  })
}

resource "kubectl_manifest" "demo_pod" {
  count = var.create_demo_pod ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Pod"
    metadata = {
      name      = var.demo_pod_name
      namespace = var.namespace
    }
    spec = {
      containers = [
        { name = var.demo_pod_name, image = var.demo_pod_image },
      ]
    }
  })

  depends_on = [kubectl_manifest.default_sgp]
}
