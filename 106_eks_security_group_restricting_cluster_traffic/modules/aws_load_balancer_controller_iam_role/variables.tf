variable "cluster_name" {
  type        = string
  description = "Cluster the Pod Identity association is created on. This is the only cluster binding the role has - the trust policy itself names no cluster and no OIDC issuer, which is why nothing in the role has to be rebuilt when the cluster is replaced"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "namespace" {
  type        = string
  default     = "kube-system"
  description = "Namespace the controller and its service account are installed into. The Pod Identity association names it, so it must match the namespace the chart is installed into"

  validation {
    condition     = length(var.namespace) > 0
    error_message = "namespace must not be empty."
  }
}
variable "service_account_name" {
  type        = string
  default     = "aws-load-balancer-controller"
  description = "Kubernetes service account name the controller runs as. The Pod Identity association binds this account to the role - and unlike IRSA there is no annotation on the account to get right, which is the step the _monolithic template had to do by hand"

  validation {
    condition     = length(var.service_account_name) > 0
    error_message = "service_account_name must not be empty."
  }
}
