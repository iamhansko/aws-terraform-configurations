variable "namespace" {
  type        = string
  default     = "default"
  description = "Namespace the sample application and its traffic generator run in, as the _monolithic template had it. Part of the IRSA trust policy's sub condition, so it has to match where the service account actually is. Unlike most namespaces in this repository this module does not create it - default already exists, and a module that created it would delete it on destroy"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "service_account_name" {
  type        = string
  default     = "sample-sa"
  description = "Service account the sample application runs as, annotated with the IRSA role ARN. Named in the role's trust policy, so the two move together - a mismatch leaves the application unable to assume the role, and the AWS SDK call it makes fails while the HTTP call beside it succeeds"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.service_account_name))
    error_message = "service_account_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "sample_app_name" {
  type        = string
  default     = "sample-app"
  description = "Name of the sample application's Deployment and Service. Also the host the traffic generator calls, so it is read in two places from here (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.sample_app_name))
    error_message = "sample_app_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "sample_app_image" {
  type        = string
  default     = "public.ecr.aws/aws-otel-test/aws-otel-java-spark:1.17.0"
  description = "Image for the sample application, as the _monolithic template had it. An AWS-published sample already instrumented with the OpenTelemetry Java SDK: it exposes /outgoing-http-call and /aws-sdk-call, and emits a trace for each - which is why nothing here has to instrument anything"

  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$", var.sample_app_image))
    error_message = "sample_app_image must carry an explicit tag."
  }
}
variable "sample_app_port" {
  type        = number
  default     = 4567
  description = "Port the sample application listens on, and the port its Service publishes"

  validation {
    condition     = var.sample_app_port > 0 && var.sample_app_port <= 65535
    error_message = "sample_app_port must be a valid TCP port."
  }
}
variable "traffic_generator_name" {
  type        = string
  default     = "traffic-generator"
  description = "Name of the traffic generator's Deployment"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.traffic_generator_name))
    error_message = "traffic_generator_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "traffic_generator_image" {
  type        = string
  default     = "public.ecr.aws/docker/library/alpine:3.24.2"
  description = "Image for the traffic generator. Alpine from ECR Public, where the _monolithic template used ellerbrock/alpine-bash-curl-ssl:latest from Docker Hub - which is both a floating tag and a rate-limited registry, and every node here shares one NAT gateway address per zone. Alpine has no curl and no bash, so the loop below uses busybox wget and /bin/sh"

  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$", var.traffic_generator_image))
    error_message = "traffic_generator_image must carry an explicit tag; a floating latest makes a re-apply run something different with no diff in plan."
  }
}
variable "otlp_endpoint" {
  type        = string
  description = "Where the sample application sends its traces. Passed in from the add-on module rather than restated, because the collector's Service name is the add-on's to choose - a wrong value leaves the application running and exporting into nothing, with the failure only in its own log (rules.md B-5)"

  validation {
    condition     = can(regex("^https?://", var.otlp_endpoint))
    error_message = "otlp_endpoint must be an http:// or https:// URL, e.g. http://adot-col-otlp-ingest-collector.opentelemetry-operator-system.svc.cluster.local:4317."
  }
}
variable "otel_service_namespace" {
  type        = string
  default     = "GettingStarted"
  description = "OpenTelemetry service.namespace attribute, as the _monolithic template had it. Not a Kubernetes namespace: it is how the traces group themselves in the X-Ray console, so this is the name to look for there"

  validation {
    condition     = length(var.otel_service_namespace) > 0
    error_message = "otel_service_namespace must not be empty."
  }
}
variable "otel_service_name" {
  type        = string
  default     = "GettingStartedService"
  description = "OpenTelemetry service.name attribute. The name each trace is filed under in X-Ray, so it is what the service map's node is called"

  validation {
    condition     = length(var.otel_service_name) > 0
    error_message = "otel_service_name must not be empty."
  }
}
variable "aws_region" {
  type        = string
  description = "Region the sample application makes its AWS SDK call in"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region name."
  }
}
variable "oidc_provider_arn" {
  type        = string
  description = "ARN of the cluster's IAM OIDC provider, used as the Federated principal in the application's IRSA trust policy"

  validation {
    condition     = can(regex("^arn:aws:iam::", var.oidc_provider_arn))
    error_message = "oidc_provider_arn must be a valid IAM OIDC provider ARN."
  }
}
variable "oidc_issuer_host" {
  type        = string
  description = "Cluster OIDC issuer URL without the https:// scheme, used in the trust policy's sub/aud condition keys"

  validation {
    condition     = length(var.oidc_issuer_host) > 0 && !can(regex("^https://", var.oidc_issuer_host))
    error_message = "oidc_issuer_host must be non-empty and must not include the https:// scheme."
  }
}
variable "replicas" {
  type        = number
  default     = 1
  description = "Replicas for both Deployments, one as the _monolithic template had it. The point is a steady trickle of traces rather than load"

  validation {
    condition     = var.replicas >= 1
    error_message = "replicas must be at least 1."
  }
}
variable "cpu_request" {
  type        = string
  default     = "100m"
  description = "CPU request per pod. The sample application is a JVM, so it is the one thing on this cluster with a real footprint"

  validation {
    condition     = can(regex("^[0-9]+m?$", var.cpu_request))
    error_message = "cpu_request must be a Kubernetes CPU quantity such as 100m or 1."
  }
}
variable "memory_request" {
  type        = string
  default     = "512Mi"
  description = "Memory request per pod. A JVM with the OpenTelemetry agent attached does not fit comfortably in less, and a pod evicted under memory pressure looks like a tracing failure"

  validation {
    condition     = can(regex("^[0-9]+(Ki|Mi|Gi)?$", var.memory_request))
    error_message = "memory_request must be a Kubernetes memory quantity such as 512Mi."
  }
}
