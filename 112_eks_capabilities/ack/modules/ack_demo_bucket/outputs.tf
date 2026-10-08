output "name" {
  value       = var.name
  description = "Name of the Kubernetes Bucket object, re-exposed so the verification commands and the caller read one value (rules.md B-5)"
}

output "namespace" {
  value       = var.namespace
  description = "Namespace the Bucket object is in"
}

output "bucket_name" {
  value       = var.bucket_name
  description = "Name of the S3 bucket ACK creates from this object"
}

output "custom_resource_status_command" {
  # ACK writes the outcome into status.conditions, and ACK.ResourceSynced is the one that answers
  # "did the AWS call succeed". A denial from IAM shows up there as a message, not as a Kubernetes
  # event, which is why this is the first thing to read.
  value       = "kubectl -n ${var.namespace} get bucket ${var.name} -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.message}{\"\\n\"}{end}'"
  description = "Reads the ACK reconciliation status of the Bucket object, including the message an AWS API denial leaves behind"
}

output "bucket_check_command" {
  value       = "aws s3api head-bucket --bucket ${var.bucket_name}"
  description = "Confirms the S3 bucket exists in the account. Succeeding here is the proof that the capability's IAM role reached the S3 API"
}

output "crd_check_command" {
  value       = "kubectl get crd bucket.s3.services.k8s.aws"
  description = "Confirms the ACK capability installed the S3 controller's CRD. NotFound means the capability is not ACTIVE yet, which is what makes the manifest fail with \"no matches for kind\""
}
