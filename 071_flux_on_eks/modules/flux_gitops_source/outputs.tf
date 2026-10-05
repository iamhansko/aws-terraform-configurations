output "name" {
  value       = var.name
  description = "Name shared by the GitRepository and the Kustomization"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace both objects live in, re-exposed so the caller's diagnostic commands read one value (rules.md B-5)"
}
output "target_namespace" {
  value       = var.target_namespace
  description = "Namespace the reconciled objects are rewritten into, or null when each manifest keeps its own. Re-exposed because it decides where a caller has to look for what arrived, which is not where the Kustomization itself lives (rules.md B-5)"
}
output "source_interval" {
  value       = var.source_interval
  description = "How often the repository is polled, re-exposed so a caller describing how long a push takes to arrive states the configured value"
}
output "git_source_check_command" {
  value       = "kubectl -n ${var.namespace} get gitrepository ${var.name} -o wide"
  description = "The repository's fetch status and the commit currently in hand. Ready=False here is a source problem - a wrong branch name, an unreachable URL - and everything downstream is blocked on it"
}
output "kustomization_check_command" {
  value       = "kubectl -n ${var.namespace} get kustomization ${var.name} -o wide"
  description = "What the Kustomization applied and whether it is healthy. With wait enabled, Ready=True means the applied objects are themselves ready rather than merely accepted"
}
output "reconcile_watch_command" {
  value       = "flux get kustomizations --watch"
  description = "The reconciliation loop as it runs. Uses the flux CLI, which the workbench instance has - the same command the _monolithic README suggested, and still the clearest view of the loop"
}
output "reconcile_now_command" {
  value       = "kubectl -n ${var.namespace} annotate --overwrite kustomization ${var.name} reconcile.fluxcd.io/requestedAt=\"$(date +%s)\""
  description = "Asks this Kustomization to reconcile immediately rather than waiting out its interval. The annotation is what the flux CLI's reconcile subcommand writes, and doing it with kubectl means the demo does not depend on the CLI being present"
}
# No output describing what the repository applies - no workload or drift command. This module
# points Flux at a repository and does not know what is in it: the objects could be a Deployment,
# or they could be more Flux custom resources that reconcile something else in turn. The caller
# knows, because the caller chose the repository, so those commands are built there (rules.md B-5).
output "url" {
  value       = var.url
  description = "Repository this source points at, re-exposed so the caller's outputs report the configured value rather than restating it (rules.md B-5)"
}
output "branch" {
  value       = var.branch
  description = "Branch tracked, re-exposed for the same reason as url"
}
output "path" {
  value       = var.path
  description = "Directory inside the repository the Kustomization applies, re-exposed for the same reason as url"
}
# No output for the credential Secret, in any form - not its name and not a command that reads it.
#
# The caller renders every output it has into a README on an instance whose code-server has no
# authentication in front of it (rules.md H-2), and the Secret is the one object here whose
# existence is only interesting to somebody trying to reach the credential. Where it matters
# operationally is a failed clone, and that is reported on the GitRepository rather than on the
# Secret - git_source_check_command above is where an authentication failure shows up.
