# ComfyUI itself: the pod role and its Pod Identity association, and every Kubernetes object the blueprint's
# deploy_infra.sh applied with kubectl - the namespace labels, the two Mountpoint volumes, the Deployment, the
# Service, the Ingress, the disruption budget and the network policy (rules.md E-1).
#
# The blueprint created these from YAML files it rewrote with sed first (ACCOUNT_ID, REGION, the bucket
# names), and deleted the Deployment before re-applying it on every run. Here the values arrive as inputs and
# a change is an in-place update the plan shows.
#
# The role and the manifests are one module because they cannot exist apart: the association names the
# service account the Deployment runs as, in the namespace this module creates (rules.md C-2).
locals {
  labels     = merge(var.labels, { app = var.name })
  pod_labels = local.labels

  # The two buckets ComfyUI reads and writes through Mountpoint. Literal keys, because the bucket names are
  # another module's outputs and these keys become resource addresses (rules.md B-8).
  volumes = {
    inputs = {
      bucket_name = var.inputs_bucket_name
      mount_path  = "/app/ComfyUI/input"
    }
    outputs = {
      bucket_name = var.outputs_bucket_name
      mount_path  = "/app/ComfyUI/output"
    }
  }
  # allow-delete has to agree with the driver role's s3:DeleteObject, which is why the caller passes the
  # add-on module's own value. region is mandatory: the driver does not infer a bucket's region.
  mount_options = concat(var.allow_delete ? ["allow-delete"] : [], ["region ${var.region}"])
}

# --- The pod's AWS identity -------------------------------------------------------------------------------

resource "aws_iam_role" "pod" {
  name_prefix = "${substr(var.name, 0, 24)}-pod-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      # sts:TagSession is not optional: the Pod Identity agent tags the session, and a role that does not
      # allow tagging cannot be assumed at all.
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}
# The blueprint's ComfyUI-Bedrock-PodIdentity role, which deploy_infra.sh created with the AWS CLI and never
# removed. Its policies are reproduced and then corrected where they could not have worked:
#
#   - Bedrock foundation models in every region, not only this one. The image's Bedrock nodes default to
#     cross-region inference profiles (us.anthropic..., us.amazon.nova...), and an inference profile routes to
#     the foundation model in whichever region serves the request - which is denied when the policy names only
#     the caller's region.
#   - GetAsyncInvoke on async-invoke/*, the resource type that action is authorised against. The blueprint
#     granted it on models only, so the video nodes could start a job and never read its status.
#   - Write on the whole outputs bucket, not only video/. The image's auto model downloader moves ComfyUI's
#     output directory off the Mountpoint mount (which cannot seek) and uploads every result itself, with these
#     credentials - so with video/ alone every image upload failed with AccessDenied.
#   - Read and write on the models bucket, which the blueprint did not grant at all. The same custom node
#     looks for a missing model there first, and uploads what it had to fetch from HuggingFace so the sync
#     Lambda can copy it onto the other GPU nodes.
resource "aws_iam_role_policy" "pod" {
  name = "comfyui"
  role = aws_iam_role.pod.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BedrockInvoke"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock:StartAsyncInvoke",
          "bedrock:GetAsyncInvoke",
        ]
        Resource = [
          "arn:${var.partition}:bedrock:*::foundation-model/*",
          "arn:${var.partition}:bedrock:${var.region}:${var.account_id}:inference-profile/*",
          "arn:${var.partition}:bedrock:${var.region}:${var.account_id}:async-invoke/*",
        ]
      },
      {
        Sid      = "OutputsWrite"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:AbortMultipartUpload"]
        Resource = ["${var.outputs_bucket_arn}/*"]
      },
      {
        Sid      = "OutputsList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [var.outputs_bucket_arn]
      },
      {
        Sid      = "ModelsReadWrite"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:AbortMultipartUpload"]
        Resource = ["${var.models_bucket_arn}/*"]
      },
      {
        # ListBucket is what makes HeadObject on a missing model answer 404 instead of 403. The custom node
        # treats either as "not in S3", so this only changes what the logs say - which is the point.
        Sid      = "ModelsList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [var.models_bucket_arn]
      },
    ]
  })
}
resource "aws_eks_pod_identity_association" "pod" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account_name
  role_arn        = aws_iam_role.pod.arn
}

# --- Namespace and service account ------------------------------------------------------------------------

resource "kubectl_manifest" "namespace" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name   = var.namespace
      labels = merge(var.labels, var.pod_security_labels)
    }
  })

  # A namespace is deleted through the kubernetes finalizer, which waits for everything inside it to go.
  # Waiting here is what keeps destroy from removing the load balancer controller and the CSI driver while
  # this namespace's objects still need them (rules.md D-7).
  wait = true
}
resource "kubectl_manifest" "service_account" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ServiceAccount"
    metadata = {
      name      = var.service_account_name
      namespace = var.namespace
      labels    = var.labels
    }
  })

  depends_on = [kubectl_manifest.namespace]
}

# --- Mountpoint volumes -----------------------------------------------------------------------------------

# Statically provisioned, as the blueprint's manifests/PersistentVolume had them: Mountpoint has nothing to
# provision, because the bucket already exists. storageClassName is empty on both halves so the default
# StorageClass does not try to provision something else for the claim.
resource "kubectl_manifest" "persistent_volume" {
  for_each = local.volumes

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "PersistentVolume"
    metadata = {
      name   = "${var.name}-${each.key}-pv"
      labels = var.labels
    }
    spec = {
      capacity         = { storage = var.volume_capacity }
      accessModes      = ["ReadWriteMany"]
      storageClassName = ""
      # Pre-binds the volume to its own claim, so no other claim in the cluster can be bound to this bucket.
      claimRef = {
        namespace = var.namespace
        name      = "${var.name}-${each.key}-pvc"
      }
      mountOptions = local.mount_options
      csi = {
        driver = var.s3_csi_driver
        # Has to be unique per volume in the cluster; two volumes sharing a handle mount the same thing.
        volumeHandle     = "s3-csi-driver-volume-${each.key}"
        volumeAttributes = { bucketName = each.value.bucket_name }
      }
    }
  })

  # The kubernetes.io/pv-protection finalizer holds a bound volume until its claim is gone (rules.md D-7).
  wait = true
}
resource "kubectl_manifest" "persistent_volume_claim" {
  for_each = local.volumes

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "PersistentVolumeClaim"
    metadata = {
      name      = "${var.name}-${each.key}-pvc"
      namespace = var.namespace
      labels    = var.labels
    }
    spec = {
      accessModes      = ["ReadWriteMany"]
      storageClassName = ""
      resources        = { requests = { storage = var.volume_capacity } }
      volumeName       = "${var.name}-${each.key}-pv"
    }
  })

  # The Deployment below names these claims, and a claim is created Pending. On a node group the scheduler
  # retries until it is Bound, so this only removes a race - but it removes it (rules.md D-8).
  wait_for {
    field {
      key   = "status.phase"
      value = "Bound"
    }
  }

  # kubernetes.io/pvc-protection holds the claim while a pod still uses it (rules.md D-7).
  wait = true

  # volumeName is a plain string, so nothing else tells Terraform the volume must exist first (rules.md E-2).
  depends_on = [kubectl_manifest.namespace, kubectl_manifest.persistent_volume]
}

# --- The Deployment ---------------------------------------------------------------------------------------

resource "kubectl_manifest" "deployment" {
  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = var.name
      namespace = var.namespace
      labels    = local.labels
    }
    spec = {
      replicas = var.replicas
      selector = { matchLabels = { app = var.name } }
      template = {
        metadata = {
          labels = local.pod_labels
          annotations = {
            # What rolls the pods when the image is rebuilt. The tag does not change, so nothing else in this
            # manifest would.
            "comfyui-on-eks/image-revision" = var.image_revision
          }
        }
        spec = {
          serviceAccountName = var.service_account_name
          nodeSelector       = var.node_selector
          volumes = [
            {
              # The node's instance-store mount, which its user data fills with models at boot and the sync
              # Lambda keeps filling afterwards.
              name     = "stable-diffusion-models"
              hostPath = { path = var.models_host_path }
            },
            {
              name                  = "comfyui-inputs"
              persistentVolumeClaim = { claimName = "${var.name}-inputs-pvc" }
            },
            {
              name                  = "comfyui-outputs"
              persistentVolumeClaim = { claimName = "${var.name}-outputs-pvc" }
            },
            {
              # Local scratch for video output. Mountpoint only supports sequential writes to new objects,
              # and ffmpeg's .mp4 muxing seeks - so video is written here and the sidecar copies it out.
              name     = "comfyui-video-scratch"
              emptyDir = {}
            },
          ]
          containers = [
            {
              name            = "comfyui"
              image           = var.image
              imagePullPolicy = "Always"
              ports           = [{ containerPort = var.container_port }]
              env = [
                { name = "AWS_REGION", value = var.region },
                { name = "AWS_DEFAULT_REGION", value = var.region },
                { name = "AWS_ACCOUNT_ID", value = var.account_id },
              ]
              securityContext = {
                allowPrivilegeEscalation = false
                capabilities             = { drop = ["ALL"] }
              }
              volumeMounts = [
                { mountPath = "/app/ComfyUI/models", name = "stable-diffusion-models" },
                { mountPath = local.volumes.inputs.mount_path, name = "comfyui-inputs" },
                { mountPath = local.volumes.outputs.mount_path, name = "comfyui-outputs" },
                { mountPath = "${local.volumes.outputs.mount_path}/video", name = "comfyui-video-scratch" },
              ]
              resources = {
                requests = { "nvidia.com/gpu" = var.gpu_count }
                limits   = { "nvidia.com/gpu" = var.gpu_count }
              }
            },
            {
              name    = "video-s3-sync"
              image   = var.video_sync_image
              command = ["/bin/sh", "-c"]
              args = [join("\n", [
                "while true; do",
                "  aws s3 sync /video \"s3://${var.outputs_bucket_name}/video/\" --region ${var.region} --no-progress --only-show-errors || true",
                "  sleep ${var.video_sync_interval_seconds}",
                "done",
              ])]
              securityContext = {
                allowPrivilegeEscalation = false
                capabilities             = { drop = ["ALL"] }
              }
              volumeMounts = [{ mountPath = "/video", name = "comfyui-video-scratch" }]
              resources = {
                requests = { cpu = "50m", memory = "64Mi" }
                limits   = { memory = "128Mi" }
              }
            },
          ]
        }
      }
    }
  })

  # Waits for the rollout, as deploy_infra.sh's wait_for_comfyui_ready did - which is what makes the apply's
  # success mean ComfyUI is serving, and turns "no GPU capacity" into an apply error naming this Deployment
  # rather than a pod that stays Pending with nothing reporting it.
  wait_for_rollout = true

  # With wait, deletion runs in the foreground: the Deployment is gone only once its pods are. Without it,
  # destroy would move on to the claims, the volumes and the CSI driver while ComfyUI was still unmounting
  # them (rules.md D-7).
  wait = true

  timeouts {
    create = var.rollout_timeout
    update = var.rollout_timeout
    delete = "10m"
  }

  # The claims have to be Bound and the service account present before a pod can start, and the Pod Identity
  # association has to exist before the pod is admitted - the pod is only given credentials if the association
  # is there when it is created (rules.md D-1).
  depends_on = [
    kubectl_manifest.service_account,
    kubectl_manifest.persistent_volume_claim,
    aws_eks_pod_identity_association.pod,
    aws_iam_role_policy.pod,
  ]
}

# --- Service, Ingress and the rest ------------------------------------------------------------------------

# ClusterIP rather than the blueprint's NodePort. The Ingress uses target-type ip, so the ALB registers pod
# addresses and sends traffic to the container port directly - a NodePort would only open a port on every
# node that nothing uses (rules.md G-1).
resource "kubectl_manifest" "service" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = var.service_name
      namespace = var.namespace
      labels    = var.labels
    }
    spec = {
      type     = "ClusterIP"
      selector = { app = var.name }
      ports = [{
        port       = var.container_port
        protocol   = "TCP"
        targetPort = var.container_port
      }]
    }
  })

  depends_on = [kubectl_manifest.namespace]
}
resource "kubectl_manifest" "ingress" {
  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name        = var.ingress_name
      namespace   = var.namespace
      labels      = var.labels
      annotations = var.ingress_annotations
    }
    spec = {
      ingressClassName = var.ingress_class_name
      rules = [{
        http = {
          paths = [{
            path     = "/"
            pathType = "Prefix"
            backend = {
              service = {
                name = var.service_name
                port = { number = var.container_port }
              }
            }
          }]
        }
      }]
    }
  })

  # The controller puts ingress.k8s.aws/resources on the Ingress and removes it once it has deleted the
  # listener, the target group and - because the adopted ALB belongs to this Ingress's stack - the ALB itself.
  # Waiting for that is what keeps destroy from uninstalling the controller first (rules.md D-7/G-3).
  wait = true

  depends_on = [kubectl_manifest.service]
}
resource "kubectl_manifest" "pod_disruption_budget" {
  yaml_body = yamlencode({
    apiVersion = "policy/v1"
    kind       = "PodDisruptionBudget"
    metadata = {
      name      = "${var.name}-pdb"
      namespace = var.namespace
      labels    = var.labels
    }
    spec = {
      maxUnavailable = 1
      selector       = { matchLabels = { app = var.name } }
    }
  })

  depends_on = [kubectl_manifest.namespace]
}
# The blueprint's comfyui-allow-ingress policy, with its ingress sources corrected.
#
# The blueprint admitted port 8848 from 10.2.0.0/20, 10.2.16.0/20 and 10.2.32.0/20 - the public subnets - while
# the Ingress it shipped built an internal ALB, which the controller places in the private subnets. Enforced,
# that policy would have dropped every request the ALB sent; it never was, because the VPC CNI's network
# policy agent was not turned on. The sources here are the subnets the ALB is actually given (rules.md B-5).
#
# One egress rule is added for the same reason: the Pod Identity agent answers on 169.254.170.23:80, and a pod
# whose egress is limited to DNS and 443 could not fetch its credentials once this is enforced.
resource "kubectl_manifest" "network_policy" {
  count = var.create_network_policy ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata = {
      name      = "${var.name}-allow-ingress"
      namespace = var.namespace
      labels    = var.labels
    }
    spec = {
      podSelector = { matchLabels = { app = var.name } }
      policyTypes = ["Ingress", "Egress"]
      ingress = [{
        from  = [for cidr in var.network_policy_ingress_cidr_blocks : { ipBlock = { cidr = cidr } }]
        ports = [{ port = var.container_port }]
      }]
      egress = [
        {
          to    = [{ ipBlock = { cidr = var.network_policy_dns_cidr_block } }]
          ports = [{ port = 53, protocol = "UDP" }, { port = 53, protocol = "TCP" }]
        },
        {
          to    = [{ ipBlock = { cidr = "0.0.0.0/0" } }]
          ports = [{ port = 443, protocol = "TCP" }]
        },
        {
          to    = [{ ipBlock = { cidr = "169.254.170.23/32" } }]
          ports = [{ port = 80, protocol = "TCP" }]
        },
      ]
    }
  })

  depends_on = [kubectl_manifest.namespace]
}
