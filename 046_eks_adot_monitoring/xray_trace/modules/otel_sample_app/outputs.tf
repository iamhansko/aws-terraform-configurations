output "namespace" {
  value       = var.namespace
  description = "Namespace both Deployments run in, re-exposed so the caller's diagnostic commands read one value (rules.md B-5)"
}
output "sample_app_name" {
  value       = var.sample_app_name
  description = "Name of the sample application's Deployment and Service"
}
output "iam_role_arn" {
  value       = aws_iam_role.sample_app_iam_role.arn
  description = "IRSA role the sample application assumes for its AWS SDK call. Scoped to s3:ListAllMyBuckets, where the _monolithic template attached AmazonS3FullAccess for the same one call"
}
output "otel_service_name" {
  value       = "${var.otel_service_namespace}/${var.otel_service_name}"
  description = "How the traces are labelled in X-Ray, which is what to search for in the console. Neither half is a Kubernetes namespace (rules.md B-5)"
}
output "rollout_status_command" {
  value       = "kubectl -n ${var.namespace} rollout status deployment ${var.sample_app_name} --timeout=5m && kubectl -n ${var.namespace} rollout status deployment ${var.traffic_generator_name} --timeout=5m"
  description = "Waits for both. The sample application is a JVM and takes the longer of the two; until it is up the generator's requests fail and no traces are produced"
}
output "sample_app_log_command" {
  value       = "kubectl -n ${var.namespace} logs deploy/${var.sample_app_name} --tail 50"
  description = "Where the exporter's own failures appear. A wrong OTLP endpoint leaves the application running and healthy while every export fails here, and nothing else reports it"
}
output "traffic_generator_log_command" {
  value       = "kubectl -n ${var.namespace} logs deploy/${var.traffic_generator_name} --tail 20"
  description = "Whether requests are being made at all. wget is quiet on success, so steady silence here is the expected result and a stream of errors means the Service is not resolving"
}
output "manual_call_command" {
  value       = "kubectl -n ${var.namespace} exec deploy/${var.traffic_generator_name} -- wget -q -O - http://${var.sample_app_name}.${var.namespace}.svc.cluster.local:${var.sample_app_port}/aws-sdk-call"
  description = "Makes one call by hand, which is the fastest way to produce a single trace and then look for it. This endpoint is the one that uses the IRSA role, so a failure here is a permissions problem rather than a tracing one"
}
