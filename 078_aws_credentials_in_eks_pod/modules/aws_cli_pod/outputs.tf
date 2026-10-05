output "name" {
  value       = var.name
  description = "Name of the pod"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace the pod and its service account live in, re-exposed so the caller's diagnostic commands read one value (rules.md B-5)"
}
output "service_account_name" {
  value       = var.service_account_name
  description = "Name of the service account, re-exposed because the IRSA trust policy's sub condition and the Pod Identity association both have to name exactly this - and a mismatch leaves the pod with the node's credentials rather than an error (rules.md B-5)"
}
output "credential_mechanism" {
  value       = var.credential_mechanism
  description = "Which mechanism this pod's cluster was built for, re-exposed so the caller can label the comparison with the same value the pod carries"
}
output "role_arn_annotation" {
  value       = var.role_arn_annotation
  description = "The role ARN written onto the service account, or null when there is none. Re-exposed because whether the annotation is present is the entire difference between the IRSA cluster and the other two on the Kubernetes side (rules.md B-5)"
}
output "identity_command" {
  value       = "kubectl -n ${var.namespace} exec ${var.name} -- aws sts get-caller-identity"
  description = "The demo, in one command. The ARN it prints says which role the pod actually got: the node's instance role means the credentials came from IMDS, and a role named after the cluster's mechanism means that mechanism worked. Nothing else in the cluster distinguishes the two"
}
output "credential_source_command" {
  value       = "kubectl -n ${var.namespace} exec ${var.name} -- env | grep -E 'AWS_ROLE_ARN|AWS_WEB_IDENTITY_TOKEN_FILE|AWS_CONTAINER_CREDENTIALS_FULL_URI|AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE'"
  description = "How the credentials arrive, rather than which ones. AWS_ROLE_ARN and AWS_WEB_IDENTITY_TOKEN_FILE are IRSA's, injected by the cluster's mutating webhook; AWS_CONTAINER_CREDENTIALS_FULL_URI is Pod Identity's, injected by EKS; no output at all means IMDS, because nothing is injected and the SDK simply falls through to the metadata service"
}
output "bucket_access_command" {
  value       = "kubectl -n ${var.namespace} exec ${var.name} -- aws s3 ls"
  description = "Whether the identity the pod got can actually do anything. On the IRSA and Pod Identity clusters this lists the demo bucket; on the IMDS cluster it is denied, because the credentials are the node's and the node role has no S3 permissions - which is the security argument for the other two rather than a fault"
}
output "shell_command" {
  value       = "kubectl -n ${var.namespace} exec -it ${var.name} -- sh"
  description = "A shell inside the pod, for trying anything else. The image is the AWS CLI, so every AWS command is available with whatever identity the pod was given"
}
