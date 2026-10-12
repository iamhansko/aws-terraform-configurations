locals {
  # The Serve application config. RayService carries it as a YAML string in
  # spec.serveConfigV2, so it is built as an HCL object and rendered with yamlencode -
  # which keeps the model ID, the replica bounds and the per-replica GPU count as typed
  # values in one place rather than as text inside text (rules.md E-3).
  serve_config = {
    applications = [{
      name         = var.serve_application_name
      import_path  = var.serve_import_path
      route_prefix = var.serve_route_prefix
      runtime_env = {
        env_vars = merge({ MODEL_ID = var.model_id }, var.extra_env_vars)
        pip      = var.serve_pip_packages
      }
      deployments = [{
        name = var.serve_deployment_name
        autoscaling_config = {
          min_replicas       = var.serve_min_replicas
          max_replicas       = var.serve_max_replicas
          metrics_interval_s = var.serve_metrics_interval_seconds
          look_back_period_s = var.serve_look_back_period_seconds
          upscale_delay_s    = var.serve_upscale_delay_seconds
          downscale_delay_s  = var.serve_downscale_delay_seconds
          # target_ongoing_requests, not target_num_ongoing_requests_per_replica. The
          # old name is what the _monolithic template used; Ray renamed it (and
          # max_concurrent_queries to max_ongoing_requests) and the defaults changed in
          # Ray 2.32, so on the 2.48 runtime this manifest declares, the old keys are
          # rejected by the config parser - which surfaces as a Serve application stuck
          # in DEPLOY_FAILED rather than as a bad manifest.
          target_ongoing_requests = var.serve_target_ongoing_requests
        }
        max_ongoing_requests        = var.serve_max_ongoing_requests
        graceful_shutdown_timeout_s = var.serve_graceful_shutdown_timeout_seconds
        ray_actor_options = {
          num_cpus = var.serve_actor_cpus
          num_gpus = var.serve_actor_gpus
        }
      }]
    }]
  }

  # Tolerations derived from the GPU pool's taints rather than restated. A toleration
  # that does not match the taint leaves the worker pods Pending on a cluster that has
  # the capacity for them, with nothing in the Ray status pointing at scheduling
  # (rules.md B-5).
  worker_tolerations = [
    for taint in var.worker_node_taints : {
      key      = taint.key
      operator = "Exists"
      effect   = taint.effect
    }
  ]
}

# The namespace, as its own manifest. The _monolithic template put it in the same
# multi-document file as the RayService, which meant kubectl had to create both in one
# apply and the ordering was whatever the file order happened to be.
resource "kubectl_manifest" "namespace" {
  count = var.create_namespace ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata   = { name = var.namespace }
  })
}

# The RayService: one object that the KubeRay operator turns into a Ray cluster, a Serve
# application on it, and a head Service the Ingress below points at.
resource "kubectl_manifest" "ray_service" {
  yaml_body = yamlencode({
    apiVersion = "ray.io/v1"
    kind       = "RayService"
    metadata = {
      name      = var.name
      namespace = var.namespace
    }
    spec = {
      # No serviceUnhealthySecondThreshold or deploymentUnhealthySecondThreshold, which
      # the _monolithic template set. KubeRay deprecated both and removed them from the
      # CRD schema; a structural schema prunes unknown fields silently, so they were
      # accepted and discarded - two settings that looked applied and were not.
      serveConfigV2 = yamlencode(local.serve_config)
      rayClusterConfig = {
        rayVersion = var.ray_version
        # The Ray autoscaler inside the cluster, which is what adds worker pods when
        # Serve asks for replicas. Karpenter then adds nodes for those pods - two
        # autoscalers in series, and this is the inner one.
        enableInTreeAutoscaling = var.enable_in_tree_autoscaling
        headGroupSpec = {
          headService = {
            metadata = { namespace = var.namespace }
          }
          rayStartParams = {
            # 0.0.0.0, so the dashboard is reachable from outside the pod - through a
            # port-forward, or through the Ingress if the caller routes to it.
            "dashboard-host" = "0.0.0.0"
          }
          template = {
            spec = {
              containers = [{
                name            = "head"
                image           = var.image
                imagePullPolicy = var.image_pull_policy
                lifecycle = {
                  preStop = {
                    # Lets Ray deregister the node before the container is killed, which
                    # is what keeps a rolling update from looking like a crash.
                    exec = { command = ["/bin/sh", "-c", "ray stop"] }
                  }
                }
                ports = [
                  { containerPort = 6379, name = "gcs-server" },
                  { containerPort = 8265, name = "dashboard" },
                  { containerPort = 10001, name = "client" },
                  { containerPort = var.serve_port, name = "serve" },
                ]
                volumeMounts = [{ mountPath = "/tmp/ray", name = "ray-logs" }]
                resources = {
                  requests = { cpu = var.head_cpu, memory = var.head_memory }
                  limits   = { cpu = var.head_cpu, memory = var.head_memory }
                }
              }]
              # The head belongs on CPU capacity. Without this selector it can land on a
              # GPU node and occupy an instance the workers need, which is expensive and
              # invisible - everything reports healthy.
              nodeSelector = var.head_node_selector
              volumes      = [{ name = "ray-logs", emptyDir = {} }]
            }
          }
        }
        workerGroupSpecs = [{
          groupName      = var.worker_group_name
          minReplicas    = var.worker_min_replicas
          maxReplicas    = var.worker_max_replicas
          rayStartParams = {}
          template = {
            spec = {
              containers = [{
                name            = "worker"
                image           = var.image
                imagePullPolicy = var.image_pull_policy
                lifecycle = {
                  preStop = {
                    exec = { command = ["/bin/sh", "-c", "ray stop"] }
                  }
                }
                resources = {
                  requests = {
                    cpu              = var.worker_cpu
                    memory           = var.worker_memory
                    "nvidia.com/gpu" = var.worker_gpus
                  }
                  limits = {
                    cpu    = var.worker_cpu
                    memory = var.worker_memory
                    # The GPU count has to appear in limits as well as requests.
                    # Kubernetes treats extended resources as limits-only, so a request
                    # without a matching limit is rejected.
                    "nvidia.com/gpu" = var.worker_gpus
                  }
                }
              }]
              nodeSelector = var.worker_node_selector
              tolerations  = local.worker_tolerations
            }
          }
        }]
      }
    }
  })

  # The namespace is named by a literal string, so nothing else orders this after it
  # (rules.md E-2).
  depends_on = [kubectl_manifest.namespace]
}

# The Ingress the AWS Load Balancer Controller turns into an ALB in front of the Ray
# Serve HTTP port.
#
# The backend Service is created by the operator, not here: KubeRay names it
# <rayservice>-head-svc. That is a literal name, so this Ingress can be applied before
# the Service exists - the controller reconciles it again when the Service appears.
resource "kubectl_manifest" "ingress" {
  count = var.create_ingress ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name        = var.ingress_name
      namespace   = var.namespace
      annotations = var.ingress_annotations
    }
    spec = {
      # Without this the Ingress is created and no controller ever looks at it
      # (rules.md G-1).
      ingressClassName = var.ingress_class_name
      rules = [{
        http = {
          paths = [{
            path = "/"
            # Prefix, not ImplementationSpecific. The AWS Load Balancer Controller hands an
            # ImplementationSpecific path to the ALB as a literal path pattern, so "/" became
            # a listener rule matching the single path "/" - and /imagine fell through to
            # the listener's default action, a fixed 404 that never reaches the target group.
            # Prefix "/" is the one path the controller turns into "/*" (rules.md G-1).
            pathType = "Prefix"
            backend = {
              service = {
                name = "${var.name}-head-svc"
                port = { number = var.serve_port }
              }
            }
          }]
        }
      }]
    }
  })

  depends_on = [kubectl_manifest.ray_service]
}
