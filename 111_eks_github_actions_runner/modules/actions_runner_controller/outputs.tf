output "controller_namespace" {
  value       = var.controller_namespace
  description = "Namespace the controller runs in, re-exposed so the caller's diagnostic commands name the same one (rules.md B-5)"
}
output "runner_namespace" {
  value       = var.runner_namespace
  description = "Namespace the runner pods appear in"
}
output "runner_set_name" {
  value       = var.runner_set_name
  description = "Name of the runner scale set, which is also the value a workflow has to put in runs-on. A workflow naming anything else queues forever with no error (rules.md B-5)"
}
output "chart_version" {
  value       = var.chart_version
  description = "Version both charts were installed at, pinned where the original took whatever the registry served"
}
output "github_config_url" {
  value       = var.github_config_url
  description = "What the runners registered against. The _monolithic template's value contained a literal UNSUPPORTED_REF_GitHubRepository, left behind by the CloudFormation resource that did not convert - and that same failure meant the repository was never created either, which the caller now does"
}
output "min_runners" {
  value       = var.min_runners
  description = "Runners kept warm with nothing queued. Zero is the point of ARC - nothing runs until a workflow asks"
}
output "max_runners" {
  value       = var.max_runners
  description = "Ceiling on concurrent runners. The real ceiling is node capacity, which nothing here scales"
}
output "workflow_runs_on_snippet" {
  value       = "runs-on: ${var.runner_set_name}"
  description = "What a workflow has to say to land on these runners. This is the one string that connects a repository's workflow to this cluster, and getting it wrong produces a queued job rather than an error"
}
output "runner_scale_set_command" {
  value       = "kubectl -n ${var.runner_namespace} get autoscalingrunnersets,ephemeralrunnersets,pods -o wide"
  description = "The scale set, the ephemeral runner set it manages, and any runner pods. With minRunners at zero the expected state is both custom resources present and no pods. The listener is deliberately not in this command: it lives in the controller's namespace, not this one"
}
output "listener_command" {
  value       = "kubectl -n ${var.controller_namespace} get autoscalinglisteners,pods -o wide"
  description = <<-DESC
    The listener, which is in the controller's namespace rather than the runners' - and knowing that is the
    whole value of this output. A reader looking for it beside the runner pods finds nothing and concludes the
    scale set never registered, which is the same symptom as a real failure.

    No AutoscalingListener anywhere means the controller never got a registration token from GitHub. One that
    exists but whose pod is in CrashLoopBackOff means it got the token and cannot hold the connection.
  DESC
}
output "controller_logs_command" {
  value       = "kubectl -n ${var.controller_namespace} logs deploy/${var.controller_release_name}-gha-rs-controller --tail 100"
  description = "The controller's log, which is where a failure to reach GitHub is reported. A 401 here is the token; a 404 is the URL"
}
output "listener_logs_command" {
  # The controller's namespace, not the runners'. ARC creates the listener next to the controller - the pod
  # carries actions.github.com/scale-set-namespace to record which runner namespace it serves, which is the
  # relationship that makes it easy to assume the wrong way round. This command named var.runner_namespace
  # until the listener was looked for and found elsewhere, and it returned "No resources found" there.
  value       = "kubectl -n ${var.controller_namespace} logs -l app.kubernetes.io/component=runner-scale-set-listener --tail 100"
  description = "The listener's log. It records each job assignment, so this is where to look when a workflow queues and no runner appears - and it is in the controller's namespace, not the runners'"
}
