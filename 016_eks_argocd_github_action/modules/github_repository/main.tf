locals {
  # The GitHub Actions workflow. Three things about it:
  #
  # Every step is a "run" step or a JavaScript action, and the manifest rewrite in
  # particular is a run step rather than the mikefarah/yq action it used to be. That
  # action is a Docker container action - "runs: using: docker" - and a container
  # action cannot see the workspace on this runner. The job executes inside a
  # CodeBuild container, so when the runner starts the action with
  # "docker run -v $GITHUB_WORKSPACE:/github/workspace", that source path is resolved
  # by a Docker daemon that does not share the runner's filesystem. The container
  # comes up with an empty /github/workspace and yq fails on a file that is in the
  # repository:
  #
  #   Error: stat ./manifest/deployment.yaml: no such file or directory
  #
  # The run steps are unaffected, which is what makes this confusing to read: in the
  # failed run, "Check out the repo" succeeded and "Build and push" succeeded - the
  # latter having read ./version and sent the whole directory as a build context -
  # and then the step after them could not find a file in that same directory. Only
  # the bind mount is broken, not Docker: docker build streams its context from the
  # client rather than mounting it.
  #
  # So the rule for this workflow is that no step may be a container action. A
  # JavaScript action (actions/checkout, aws-actions/amazon-ecr-login) runs in the
  # runner's own process and is fine.
  #
  # Two things about the escaping here:
  #
  # "$${{ ... }}" is a literal ${{ }} after Terraform's interpolation - GitHub
  # expression syntax collides with Terraform's, so every one of them is doubled.
  # The _monolithic template had the same problem twice over, because the file was
  # produced by a shell heredoc inside a Terraform string inside an SSM parameter,
  # which is why its version carried \\$${{ and \\' sequences.
  #
  # The runner label is what routes the job to CodeBuild: GitHub matches the
  # "codebuild-<project>-${{ github.run_id }}-${{ github.run_attempt }}" label
  # against the project the webhook belongs to.
  workflow = <<-EOT
    name: ${var.workflow_name}
    permissions:
      contents: write
    on:
      push:
        branches: [ "${var.default_branch}" ]
        paths: [ "index.html" ]
    jobs:
      build:
        runs-on:
          - codebuild-${var.codebuild_project_name}-$${{ github.run_id }}-$${{ github.run_attempt }}
        steps:
          - name: Check out the repo
            uses: actions/checkout@v4
          - name: ECR login
            id: login-ecr
            uses: aws-actions/amazon-ecr-login@v2
          - name: Build and push
            env:
              REGISTRY: $${{ steps.login-ecr.outputs.registry }}
              REPOSITORY: ${var.ecr_repository_name}
            run: |
              IMAGE_TAG=$(cat version)
              docker build -t $REGISTRY/$REPOSITORY:$IMAGE_TAG .
              docker push $REGISTRY/$REPOSITORY:$IMAGE_TAG
              echo "IMAGE=$REGISTRY/$REPOSITORY:$IMAGE_TAG" >> $GITHUB_ENV
          - name: Update the manifest
            env:
              YQ_VERSION: ${var.yq_version}
            run: |
              curl -fsSL "https://github.com/mikefarah/yq/releases/download/$YQ_VERSION/yq_linux_amd64" -o "$RUNNER_TEMP/yq"
              chmod +x "$RUNNER_TEMP/yq"
              "$RUNNER_TEMP/yq" -i '.spec.template.spec.containers[0].image = strenv(IMAGE)' ./${var.manifest_path}/deployment.yaml
          - name: Commit and push
            run: |
              git config --global user.email "${var.commit_author_email}"
              git config --global user.name "${var.commit_author_name}"
              git add ./${var.manifest_path}
              git commit -m "Update deployment image"
              git push
  EOT
  # The Dockerfile the workflow builds. The _monolithic template wrote it inside the
  # workflow's run block with an echo, which meant the image definition lived in a
  # shell string inside a YAML string inside an SSM parameter. A file in the
  # repository is the same thing, readable.
  dockerfile = <<-EOT
    FROM public.ecr.aws/nginx/nginx:latest
    COPY index.html /usr/share/nginx/html/index.html
    CMD ["nginx", "-g", "daemon off;"]
  EOT
  index_html = <<-EOT
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <title>${var.app_name} - ${var.initial_version}</title>
    </head>
    <body style="font-family: Arial, sans-serif; text-align: center; padding-top: 100px">
      <h1>${var.app_name}</h1>
      <div>Version: ${var.initial_version}</div>
    </body>
    </html>
  EOT
  # The manifests Argo CD syncs. The workflow rewrites the image in deployment.yaml,
  # Argo CD notices the commit and applies it - that is the whole loop this project
  # demonstrates, and it only works because both sides agree on this path.
  deployment_yaml = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name   = var.app_name
      labels = { app = var.app_name }
    }
    spec = {
      replicas = var.replica_count
      selector = { matchLabels = { app = var.app_name } }
      template = {
        metadata = { labels = { app = var.app_name } }
        spec = {
          containers = [{
            name = var.app_name
            # The first image is the upstream nginx, not one from ECR: nothing has been
            # pushed yet when Argo CD first syncs. The workflow replaces it on the
            # first commit to index.html.
            image = var.initial_image
            ports = [{ containerPort = var.container_port }]
          }]
        }
      }
    }
  })
  service_yaml = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata   = { name = "${var.app_name}-service" }
    spec = {
      selector = { app = var.app_name }
      ports = [{
        protocol   = "TCP"
        port       = var.service_port
        targetPort = var.container_port
      }]
    }
  })
  ingress_yaml = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name = "${var.app_name}-ingress"
      annotations = {
        "alb.ingress.kubernetes.io/load-balancer-name" = var.ingress_load_balancer_name
        "alb.ingress.kubernetes.io/scheme"             = "internet-facing"
        # ip rather than instance: the ALB reaches pod IPs directly, which the VPC CNI
        # makes routable, and it means no NodePort has to be opened (rules.md G-1).
        "alb.ingress.kubernetes.io/target-type" = "ip"
      }
    }
    spec = {
      ingressClassName = "alb"
      rules = [{
        http = {
          paths = [{
            path     = "/"
            pathType = "Prefix"
            backend = {
              service = {
                name = "${var.app_name}-service"
                port = { number = var.service_port }
              }
            }
          }]
        }
      }]
    }
  })
  # Two maps rather than one, split by who writes the file after the first apply.
  # for_each over either is safe: the keys are literals in the configuration, so they
  # are known at plan time (rules.md B-8).
  #
  # The split exists because ignore_changes = [content] used to cover all seven files,
  # and the workflow was one of them. Nothing but Terraform ever writes the workflow,
  # so freezing it meant a correction to it could not be deployed: editing the heredoc
  # above produced no diff, apply reported no changes, and the repository kept running
  # the old job. That is how the container-action bug survived a fix - the fix was in
  # the configuration and never in the repository.
  #
  # So ignore_changes is now scoped to the files something outside Terraform rewrites,
  # which is the same reasoning as keeping the exclusion to the fields a controller
  # actually touches rather than freezing a whole manifest (rules.md E-8).

  # Written once by Terraform and never by anything else.
  managed_files = {
    ".github/workflows/${var.workflow_file_name}" = local.workflow
    "Dockerfile"                                  = local.dockerfile
    "${var.manifest_path}/service.yaml"           = local.service_yaml
    "${var.manifest_path}/ingress.yaml"           = local.ingress_yaml
  }
  # Seeded by Terraform, then owned by the demo: the workflow rewrites the image in
  # deployment.yaml and commits it, and index.html and version are what the operator
  # edits in the browser to start the pipeline. Terraform must not pull these back.
  seeded_files = {
    "index.html"                           = local.index_html
    "version"                              = "${var.initial_version}\n"
    "${var.manifest_path}/deployment.yaml" = local.deployment_yaml
  }
}
# The repository itself. This is what the _monolithic template could not express: it
# staged these files on the bastion over SSM, zipped them, uploaded the zip to S3, and
# handed the bucket to an AWS::CodeStar::GitHubRepository resource - which the AWS
# Terraform provider has no equivalent for, so the conversion left it commented out as
# NOT CONVERTED. The GitHub provider creates the repository directly, and the S3
# bucket, the zip and the SSM association all disappear with it.
resource "github_repository" "app" {
  name        = var.repository_name
  description = var.description
  visibility  = var.visibility
  # A repository with no commit has no default branch, and github_repository_file
  # cannot create the first file on a branch that does not exist. auto_init makes the
  # initial commit so the files below have somewhere to land.
  auto_init = true

  # The demo pushes to this repository from CodeBuild, so it must not be archived or
  # have pushes blocked.
  archived = false
}
# The files Terraform owns. No ignore_changes: a change to the workflow, the
# Dockerfile or the Service/Ingress manifests here is meant to reach the repository on
# the next apply.
resource "github_repository_file" "managed" {
  for_each = local.managed_files

  repository = github_repository.app.name
  branch     = var.default_branch
  file       = each.key
  content    = each.value

  commit_message = "${var.commit_message_prefix} ${each.key}"
  commit_author  = var.commit_author_name
  commit_email   = var.commit_author_email
  # auto_init already made a commit, and these land on top of it.
  overwrite_on_create = true
}
# These four moved out of github_repository_file.files when the map was split. Without
# the moved blocks Terraform would delete and recreate them, and a delete of
# service.yaml or ingress.yaml is a delete in the cluster too - the Argo CD Application
# syncs this path with prune enabled, so it would tear down the Service and the ALB
# behind the Ingress and then build them again.
#
# The addresses have to be literal, so they spell out the default workflow_file_name
# and manifest_path. A caller that overrode either needs these keys adjusted to match,
# and they can be dropped entirely once every state has been through one apply.
moved {
  from = github_repository_file.files[".github/workflows/codebuild.yaml"]
  to   = github_repository_file.managed[".github/workflows/codebuild.yaml"]
}
moved {
  from = github_repository_file.files["Dockerfile"]
  to   = github_repository_file.managed["Dockerfile"]
}
moved {
  from = github_repository_file.files["manifest/service.yaml"]
  to   = github_repository_file.managed["manifest/service.yaml"]
}
moved {
  from = github_repository_file.files["manifest/ingress.yaml"]
  to   = github_repository_file.managed["manifest/ingress.yaml"]
}
# The files the demo rewrites. The resource name is unchanged so these three keep their
# state addresses and need no moved block - recreating them would discard the image tag
# the pipeline committed and reset index.html and version to their seed values.
resource "github_repository_file" "files" {
  for_each = local.seeded_files

  repository = github_repository.app.name
  branch     = var.default_branch
  file       = each.key
  content    = each.value

  commit_message = "${var.commit_message_prefix} ${each.key}"
  commit_author  = var.commit_author_name
  commit_email   = var.commit_author_email
  # The workflow commits back to this repository - it rewrites the image in
  # deployment.yaml and pushes. Without this, the next terraform plan would want to
  # restore the file to what Terraform wrote and undo the pipeline's work, which is
  # the same reasoning that keeps Terraform out of a target group's membership.
  overwrite_on_create = true

  lifecycle {
    ignore_changes = [content]
  }
}
