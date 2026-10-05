# The seven PEMs the chart's certs.custom block takes, plus the three the agents and the kubectl provider
# need. They are the same material under different names - see the table in main.tf - and they are exposed
# separately so each consumer asks for what it uses rather than for a bundle.
output "ca_cert_pem" {
  value       = tls_self_signed_cert.ca.cert_pem
  description = "Server CA certificate. Goes to certs.custom.caCrt, to the agents' kubeconfig as certificate-authority-data, and to the kubectl provider's cluster_ca_certificate"
}
output "ca_private_key_pem" {
  value       = tls_private_key.ca.private_key_pem
  sensitive   = true
  description = "Server CA private key. Goes to certs.custom.caKey, which the chart stores as server-ca.key - the Karmada control plane needs it to issue certificates for clusters it registers"
}
output "cert_pem" {
  value       = tls_locally_signed_cert.karmada.cert_pem
  description = "The karmada certificate. Goes to certs.custom.crt, to the agents' kubeconfig as client-certificate-data, and to the kubectl provider's client_certificate. Not marked sensitive: a certificate is public, and seeing it in a plan is how a wrong SAN or subject gets noticed"
}
output "private_key_pem" {
  value       = tls_private_key.karmada.private_key_pem
  sensitive   = true
  description = "Its private key. Goes to certs.custom.key, to the agents' kubeconfig as client-key-data, and to the kubectl provider's client_key. This is the Karmada cluster-admin credential and also the key its service account tokens are signed with"
}
output "front_proxy_ca_cert_pem" {
  value       = tls_self_signed_cert.front_proxy_ca.cert_pem
  description = "Aggregation layer CA certificate, for certs.custom.frontProxyCaCrt"
}
output "front_proxy_cert_pem" {
  value       = tls_locally_signed_cert.front_proxy_client.cert_pem
  description = "Aggregation layer client certificate, for certs.custom.frontProxyCrt"
}
output "front_proxy_private_key_pem" {
  value       = tls_private_key.front_proxy_client.private_key_pem
  sensitive   = true
  description = "Its private key, for certs.custom.frontProxyKey"
}
output "dns_names" {
  value       = local.karmada_dns_names
  description = "Every DNS name the karmada certificate is valid for, including whatever the caller passed as external_dns_names (rules.md B-5). Worth reading when a client fails verification against the load balancer: if the address it used is not in this list, the certificate is the problem rather than the connection"
}
output "inspect_command" {
  value       = "kubectl -n ${var.namespace} get secret karmada-cert -o jsonpath='{.data.karmada\\.crt}' | base64 -d | openssl x509 -noout -subject -ext subjectAltName"
  description = "Reads the certificate back out of the cluster and prints its subject and SANs. This is the check that the chart received what this module generated - in certs.mode custom the Secret is rendered from Helm values, so a mismatch here means the values were wired wrong rather than that something regenerated them"
}
