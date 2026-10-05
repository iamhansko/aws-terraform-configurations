variable "release_name" {
  type        = string
  default     = "karmada"
  description = "Helm release name. The chart's karmada.name helper is just .Release.Name, so this becomes the prefix on every object it creates - karmada-apiserver, karmada-cert, karmada-kubeconfig. The in-cluster certificate SANs are wildcards, so a different name still works, but every command in this project's outputs assumes karmada"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name))
    error_message = "release_name must be a valid lowercase RFC 1123 label - it prefixes the names of the Kubernetes objects the chart creates."
  }
}
variable "chart_repository" {
  type        = string
  default     = "https://raw.githubusercontent.com/karmada-io/karmada/master/charts"
  description = "Helm repository holding the Karmada chart, which is the one Karmada's own installation documentation names. The index there is served out of the master branch while each chart version is a release artifact, so pinning chart_version is what makes the install reproducible rather than pinning this"

  validation {
    condition     = can(regex("^(https://|oci://)", var.chart_repository))
    error_message = "chart_repository must be an https or oci URL."
  }
}
variable "chart_version" {
  type        = string
  default     = "v1.19.0"
  description = "Chart version, with the leading v the Karmada repository's index uses - unusually for a Helm chart, the versions there are v1.19.0 rather than 1.19.0, and omitting it fails to resolve. Pinned because the guidance installer pinned nothing: it cloned the repository's default branch and installed whatever Karmada that branch's script asked for"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must look like v1.19.0, including the leading v that the Karmada chart repository's index uses."
  }
}
variable "karmada_image_version" {
  type        = string
  default     = "v1.19.0"
  description = "Tag used for the Karmada component images. Normally the same as the chart's appVersion. The chart leaves these on :latest, so this is set per component rather than through karmadaImageVersion - see the note in main.tf, because the reason is a YAML anchor and the symptom is nothing at all until a reinstall months later picks up a different Karmada"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.karmada_image_version))
    error_message = "karmada_image_version must look like v1.19.0."
  }
}
variable "namespace" {
  type        = string
  default     = "karmada-system"
  description = "Namespace the control plane is installed into, which is also passed as the chart's systemNamespace. karmada-system, as karmada init used. It has to match the namespace the certificates were generated for, because the in-cluster SANs include it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 label."
  }
}
variable "cluster_domain" {
  type        = string
  default     = "cluster.local"
  description = "The host cluster's DNS suffix, used to build the service names the components reach each other on. Must match the value the certificates were generated with"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.cluster_domain))
    error_message = "cluster_domain must be a valid lowercase DNS name."
  }
}
variable "node_port" {
  type        = number
  default     = 32443
  description = "nodePort the Karmada API server Service is published on, which the load balancer forwards to. Supplied by the load balancer module's output rather than restated, so the two cannot drift - a mismatch leaves every target unhealthy and the endpoint timing out (rules.md B-5)"

  validation {
    condition     = var.node_port >= 30000 && var.node_port <= 32767
    error_message = "node_port must be between 30000 and 32767, the range Kubernetes allocates node ports from."
  }
}
variable "apiserver_replicas" {
  type        = number
  default     = 3
  description = <<-DESC
    Replicas of karmada-apiserver, three as the guidance installer asked for with
    --karmada-apiserver-replicas 3.

    Three needs three nodes: the chart puts a requiredDuringSchedulingIgnoredDuringExecution pod
    anti-affinity on this Deployment, so two replicas on one node will not schedule and the surplus pods stay
    Pending - which stalls the Helm release until its timeout rather than failing with an explanation. Keep
    this at or below the parent cluster's node count.
  DESC

  validation {
    condition     = var.apiserver_replicas >= 1
    error_message = "apiserver_replicas must be at least one."
  }
}
variable "etcd_replicas" {
  type        = number
  default     = 1
  description = <<-DESC
    Replicas of Karmada's etcd. One, which is the value this project's original template patched the
    installer down to with

      sed -i 's/--etcd-replicas 3/--etcd-replicas 1/' include/deploy-karmada-functions.sh

    and the reason it did is worth keeping: the chart puts the same required pod anti-affinity on the etcd
    StatefulSet as on the apiserver, and each replica claims its own volume, so three replicas need three
    nodes with volumes in three zones. The guidance's own default cluster is smaller than that, so the extra
    pods stay Pending and nothing says why.

    One replica is not highly available - losing that node loses the Karmada control plane, including every
    member cluster registration - which is acceptable for a demo and wrong for anything else.
  DESC

  validation {
    condition     = contains([1, 3, 5], var.etcd_replicas)
    error_message = "etcd_replicas must be 1, 3 or 5. etcd needs an odd number to establish a quorum."
  }
}
variable "etcd_storage_class_name" {
  type        = string
  default     = "ebs-sc"
  description = "StorageClass the etcd volume claim names, the installer's --storage-classes-name. Supplied by the storage class module's output rather than restated here (rules.md B-5): a claim naming a class that does not exist stays Pending, and because every other Karmada component waits on etcd the symptom is the entire control plane appearing not to start"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.etcd_storage_class_name))
    error_message = "etcd_storage_class_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "etcd_volume_size" {
  type        = string
  default     = "5Gi"
  description = "Size of each etcd volume, as a Kubernetes quantity. Five gibibytes, which is what karmada init requests"

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi|Ti)$", var.etcd_volume_size))
    error_message = "etcd_volume_size must be a Kubernetes quantity such as 5Gi."
  }
}
variable "hook_kubectl_image_registry" {
  type        = string
  default     = "docker.io"
  description = "Registry for the kubectl image the chart's pre-install and static-resource jobs run"

  validation {
    condition     = length(var.hook_kubectl_image_registry) > 0
    error_message = "hook_kubectl_image_registry must not be empty."
  }
}
variable "hook_kubectl_image_repository" {
  type        = string
  default     = "bitnamisecure/kubectl"
  description = "Repository for that image, the chart's own default. Worth knowing which one it is: Bitnami moved its Docker Hub images in 2025, and a chart version still pointing at the old bitnami/kubectl path produces a release whose CRD job cannot pull"

  validation {
    condition     = length(var.hook_kubectl_image_repository) > 0
    error_message = "hook_kubectl_image_repository must not be empty."
  }
}
variable "hook_kubectl_image_tag" {
  type        = string
  default     = "latest"
  description = "Tag for that image. latest, which is the chart's default - exposed here so it can be pinned, rather than left where nobody would find it"

  validation {
    condition     = length(var.hook_kubectl_image_tag) > 0
    error_message = "hook_kubectl_image_tag must not be empty."
  }
}
variable "wait_image_registry" {
  type        = string
  default     = "docker.io"
  description = "Registry for the image the chart runs as the etcd-wait init container on every component"

  validation {
    condition     = length(var.wait_image_registry) > 0
    error_message = "wait_image_registry must not be empty."
  }
}
variable "wait_image_repository" {
  type        = string
  default     = "cfssl/cfssl"
  description = "Repository for that image. The chart calls this value cfssl because the image is cfssl's, but with certs.mode = custom nothing here generates a certificate - the container only polls etcd with curl until it answers. Worth knowing the name is misleading, because it is otherwise easy to assume this image is unused in custom mode and leave it unpinned"

  validation {
    condition     = length(var.wait_image_repository) > 0
    error_message = "wait_image_repository must not be empty."
  }
}
variable "wait_image_tag" {
  type        = string
  default     = "latest"
  description = "Tag for that image, the chart's default. Pin it where the registry allows: if this image cannot be pulled, every component sits in Init and the release fails with no pod having started, which looks like a cluster problem rather than a missing tag"

  validation {
    condition     = length(var.wait_image_tag) > 0
    error_message = "wait_image_tag must not be empty."
  }
}
variable "timeout_seconds" {
  type        = number
  default     = 900
  description = "How long helm waits for the release to become ready. Generous because this release is not just Deployments: etcd has to get a volume provisioned and bound, and the static-resource Job has to pull an image and apply Karmada's CRDs into the new API server before helm considers the release done"

  validation {
    condition     = var.timeout_seconds > 0
    error_message = "timeout_seconds must be positive."
  }
}
variable "ca_cert_pem" {
  type        = string
  description = "Server CA certificate, the chart's certs.custom.caCrt"

  validation {
    condition     = can(regex("BEGIN CERTIFICATE", var.ca_cert_pem))
    error_message = "ca_cert_pem must be a PEM-encoded certificate."
  }
}
variable "ca_private_key_pem" {
  type        = string
  sensitive   = true
  description = "Server CA private key, the chart's certs.custom.caKey. The control plane needs it, not just its certificate: it issues certificates for the clusters it registers"

  validation {
    condition     = can(regex("PRIVATE KEY", var.ca_private_key_pem))
    error_message = "ca_private_key_pem must be a PEM-encoded private key."
  }
}
variable "cert_pem" {
  type        = string
  description = "The karmada certificate, the chart's certs.custom.crt. Serves as the API server's TLS certificate, etcd's, the webhook's, and the admin client certificate all at once - see modules/karmada_certificates"

  validation {
    condition     = can(regex("BEGIN CERTIFICATE", var.cert_pem))
    error_message = "cert_pem must be a PEM-encoded certificate."
  }
}
variable "private_key_pem" {
  type        = string
  sensitive   = true
  description = "Its private key, the chart's certs.custom.key. Also the key the Karmada API server signs service account tokens with, which is why it has to be RSA"

  validation {
    condition     = can(regex("PRIVATE KEY", var.private_key_pem))
    error_message = "private_key_pem must be a PEM-encoded private key."
  }
}
variable "front_proxy_ca_cert_pem" {
  type        = string
  description = "Aggregation layer CA certificate, the chart's certs.custom.frontProxyCaCrt"

  validation {
    condition     = can(regex("BEGIN CERTIFICATE", var.front_proxy_ca_cert_pem))
    error_message = "front_proxy_ca_cert_pem must be a PEM-encoded certificate."
  }
}
variable "front_proxy_cert_pem" {
  type        = string
  description = "Aggregation layer client certificate, the chart's certs.custom.frontProxyCrt. Its common name must be front-proxy-client, which modules/karmada_certificates enforces"

  validation {
    condition     = can(regex("BEGIN CERTIFICATE", var.front_proxy_cert_pem))
    error_message = "front_proxy_cert_pem must be a PEM-encoded certificate."
  }
}
variable "front_proxy_private_key_pem" {
  type        = string
  sensitive   = true
  description = "Its private key, the chart's certs.custom.frontProxyKey"

  validation {
    condition     = can(regex("PRIVATE KEY", var.front_proxy_private_key_pem))
    error_message = "front_proxy_private_key_pem must be a PEM-encoded private key."
  }
}
