output "url" {
  value       = var.bundle_url
  description = "The bundle that was fetched, re-exposed because it is built from a version and a channel and the combination is easy to get wrong - a 404 shows up as a parse failure (rules.md B-5)"
}
output "version_tag" {
  value       = var.version_tag
  description = "The Gateway API release installed, re-exposed so a caller can check it against what the VPC Lattice controller version supports"
}
output "crd_names" {
  value       = sort(keys(local.keyed_documents))
  description = "The documents this module manages, by kind and name. These are the resource addresses as well, so this is also what a plan will talk about. Worth reading once after a version change: a bundle that suddenly contains far fewer documents is a redirect or an error page that happened to parse"
}
output "document_count" {
  value       = length(local.keyed_documents)
  description = "How many documents the bundle contained, and therefore how many resources this module manages"
}
output "check_command" {
  value       = "kubectl get crd -o name | grep gateway.networking.k8s.io"
  description = "The Gateway API kinds the cluster serves. A Gateway or HTTPRoute applied before these are established fails with \"no matches for kind\", which is a timing problem rather than a manifest problem"
}
