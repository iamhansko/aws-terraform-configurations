# The PKI the Karmada control plane runs on.
#
# This module exists because of one decision: the Karmada chart is installed with certs.mode = "custom"
# rather than "auto". Both produce a working control plane, and only one of them leaves Terraform able to
# talk to it.
#
# In "auto" mode the chart runs a cfssl job as a pre-install hook, which generates a CA and a leaf
# certificate inside the cluster and stores them in the karmada-cert Secret. The admin client certificate
# in the karmada-kubeconfig Secret is that same leaf. So the credential needed to reach the Karmada API
# server is created inside the cluster and never leaves it - which means:
#
#   nothing can configure a provider against the Karmada API server, so the PropagationPolicy and the demo
#   Deployment cannot be Terraform resources at all;
#
#   the karmada-agent on each member cluster cannot be given a kubeconfig, because its Helm values need
#   that client certificate as a literal.
#
# Reading the Secret back out is not a way around it. alekc/kubectl has no data source for an arbitrary
# object, and hashicorp/kubernetes - which has kubernetes_secret - cannot be configured at all in this root
# because the cluster it would read from is created in the same apply (rules.md E-2).
#
# Generating the PKI here inverts that: Terraform owns the CA, so it knows the client certificate before
# the chart is installed, and both problems disappear. The cost is that the CA private key is in Terraform
# state, which is worth saying plainly - state for this project should be treated as a secret.
#
# The guidance installer did neither: `kubectl karmada init` generated the PKI on the workbench's disk
# under /home/ec2-user/.karmada/pki and wrote a kubeconfig next to it. That is the same shape as "auto" from
# Terraform's point of view - a credential it cannot see.
#
# ---------------------------------------------------------------------------------------------------------
# What the chart does with each of these, from charts/karmada/templates/karmada-cert.yaml. Worth reading
# before changing a subject or a SAN, because one key pair is used for five different things:
#
#   ca_cert_pem / ca_key_pem   -> server-ca.crt / server-ca.key
#                                 The apiserver's --client-ca-file, and etcd's --trusted-ca-file. Also the
#                                 caBundle in the webhook configurations.
#   karmada cert / key         -> karmada.crt / karmada.key, and the karmada-webhook-cert Secret, and the
#                                 client-certificate-data in the karmada-kubeconfig Secret. It is at once:
#                                   the apiserver's --tls-cert-file (a server certificate),
#                                   the apiserver's --service-account-key-file (so the key must be RSA),
#                                   etcd's --cert-file (another server certificate, different names),
#                                   the apiserver's etcd client certificate,
#                                   the webhook's serving certificate,
#                                   and the admin client certificate.
#                                 That is why it carries both server_auth and client_auth, and why its
#                                 subject matters: the apiserver runs --authorization-mode=Node,RBAC, and
#                                 the only thing granting this credential cluster-admin is the
#                                 system:masters group in its Organization.
#   front proxy CA / client    -> front-proxy-ca.crt / front-proxy-client.crt / front-proxy-client.key
#                                 The aggregation layer, used when the apiserver proxies to
#                                 karmada-aggregated-apiserver. The apiserver runs
#                                 --requestheader-allowed-names=front-proxy-client, so that common name is
#                                 not decorative - a different one makes the aggregated API 403 while
#                                 everything else works.
#
# The subjects below are the ones `karmada init` uses (pkg/karmadactl/cmdinit/kubernetes/deploy.go), so a
# control plane installed this way is indistinguishable from one the guidance installer produced.
# ---------------------------------------------------------------------------------------------------------
locals {
  # The in-cluster names the chart's own certs.auto.hosts list covers, rendered here instead. Kept in the
  # same order as the chart's list so the two can be diffed by eye when the chart changes.
  #
  # The etcd entry is not optional even though etcd is internal: the chart points etcd at this same
  # certificate, and the StatefulSet's pods answer on etcd-<n>.etcd.<namespace>.svc.<domain>. Leaving it out
  # produces an etcd that refuses its own peers, which surfaces as the apiserver stuck in its wait-for-etcd
  # init container rather than as a certificate error.
  in_cluster_dns_names = [
    "kubernetes.default.svc",
    "*.etcd.${var.namespace}.svc.${var.cluster_domain}",
    "*.${var.namespace}.svc.${var.cluster_domain}",
    "*.${var.namespace}.svc",
    "localhost",
  ]
  karmada_dns_names = distinct(concat(local.in_cluster_dns_names, var.external_dns_names))
}
# ---------------------------------------------------------------------------------------------------------
# Server CA
# ---------------------------------------------------------------------------------------------------------
resource "tls_private_key" "ca" {
  algorithm = "RSA"
  # 3072, matching the chart's certs.auto.rsaSize. Not 2048: this key also ends up signing the service
  # account tokens the Karmada apiserver issues.
  rsa_bits = var.rsa_bits
}
resource "tls_self_signed_cert" "ca" {
  private_key_pem = tls_private_key.ca.private_key_pem
  subject {
    common_name = var.ca_common_name
  }
  is_ca_certificate     = true
  validity_period_hours = var.ca_validity_period_hours
  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "digital_signature",
    "key_encipherment",
  ]
}
# ---------------------------------------------------------------------------------------------------------
# The karmada certificate - server and client at the same time, see the note above
# ---------------------------------------------------------------------------------------------------------
resource "tls_private_key" "karmada" {
  algorithm = "RSA"
  rsa_bits  = var.rsa_bits
}
resource "tls_cert_request" "karmada" {
  private_key_pem = tls_private_key.karmada.private_key_pem
  subject {
    # system:admin in system:masters, as karmada init sets it. The group is what makes this credential a
    # cluster administrator on the Karmada API server - RBAC grants system:masters everything without any
    # ClusterRoleBinding existing for it. Changing it leaves a certificate that authenticates and then
    # cannot read anything, which reads as an empty cluster rather than as a permissions problem.
    common_name  = var.client_common_name
    organization = var.client_organization
  }
  dns_names = local.karmada_dns_names
  ip_addresses = concat(
    ["127.0.0.1"],
    var.external_ip_addresses,
  )
}
resource "tls_locally_signed_cert" "karmada" {
  cert_request_pem      = tls_cert_request.karmada.cert_request_pem
  ca_private_key_pem    = tls_private_key.ca.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.ca.cert_pem
  validity_period_hours = var.validity_period_hours
  # Both, because this one certificate is presented by the apiserver, by etcd and by the webhook, and is
  # also sent as a client certificate to etcd and by Terraform to the apiserver. karmada init's
  # NewCertConfig sets exactly this pair for the same reason.
  allowed_uses = [
    "server_auth",
    "client_auth",
    "digital_signature",
    "key_encipherment",
  ]
}
# ---------------------------------------------------------------------------------------------------------
# Front proxy CA and client, for the aggregation layer
# ---------------------------------------------------------------------------------------------------------
# A separate CA from the server one, deliberately. The apiserver trusts whatever this CA signs to assert a
# username through the X-Remote-User header, so anything it signs can impersonate any user. Keeping it apart
# from the CA that signs ordinary client certificates is what stops an ordinary client certificate from
# being usable that way.
resource "tls_private_key" "front_proxy_ca" {
  algorithm = "RSA"
  rsa_bits  = var.rsa_bits
}
resource "tls_self_signed_cert" "front_proxy_ca" {
  private_key_pem = tls_private_key.front_proxy_ca.private_key_pem
  subject {
    common_name = var.front_proxy_ca_common_name
  }
  is_ca_certificate     = true
  validity_period_hours = var.ca_validity_period_hours
  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "digital_signature",
    "key_encipherment",
  ]
}
resource "tls_private_key" "front_proxy_client" {
  algorithm = "RSA"
  rsa_bits  = var.rsa_bits
}
resource "tls_cert_request" "front_proxy_client" {
  private_key_pem = tls_private_key.front_proxy_client.private_key_pem
  subject {
    # front-proxy-client, and it has to be exactly that: the apiserver is started with
    # --requestheader-allowed-names=front-proxy-client and rejects any other name presented on the
    # aggregation path.
    common_name = var.front_proxy_client_common_name
  }
}
resource "tls_locally_signed_cert" "front_proxy_client" {
  cert_request_pem      = tls_cert_request.front_proxy_client.cert_request_pem
  ca_private_key_pem    = tls_private_key.front_proxy_ca.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.front_proxy_ca.cert_pem
  validity_period_hours = var.validity_period_hours
  allowed_uses = [
    "client_auth",
    "digital_signature",
    "key_encipherment",
  ]
}
