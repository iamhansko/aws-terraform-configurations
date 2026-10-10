data "aws_region" "current" {}
# What the _monolithic template's dockerBuildandPush config set was for, as real Terraform.
#
# The template wrote nine files and ran three docker build/push pairs out of a resource's
# AWS::CloudFormation::Init metadata, invoked by two cfn-init calls in the bastion's userdata. There is no
# CloudFormation stack for cfn-init to read metadata from, so none of it ran, and the three ECS services
# referenced images that were never built. This module is where that work actually happens.
#
# Why SSM associations rather than userdata. Three reasons, in order of how much they matter:
#
#   1. Size. The nine source files are roughly 9 KB and EC2's user data limit is 16 KB for the whole script,
#      before the code-server bootstrap. They do not fit.
#   2. Reporting. A userdata script's exit status goes nowhere - the instance boots either way and the only
#      record is /var/log/cloud-init-output.log on a box somebody has to get onto. An association records a
#      Failed status and the command's stdout and stderr, which is what makes "the repository is empty"
#      answerable.
#   3. Re-running. Changing an application's source changes its image tag, which creates a new association
#      for it and runs the build again (see local.builds for why it is a new one rather than an update). A
#      changed userdata script does nothing until the instance is replaced.
#
# Why on the workbench rather than in CodeBuild: a docker build genuinely needs a daemon, which is the case
# rules.md H-1 leaves open for the EC2 workbench to do real work. The instance already has docker installed
# by its caller and an instance role that can reach ECR.
locals {
  # Build order, and the chain of marker files that enforces it.
  #
  # The builds are serialised rather than run in parallel, and that is the reason this module computes an
  # order at all. Three concurrent docker builds on one instance compete for memory, and the product
  # application's image links aws-sdk-go-v2's DynamoDB client - a compile large enough that two of these at
  # once is what gets the Go linker killed rather than a slow build.
  #
  # Each step waits for its predecessor's marker and writes its own, which is how this repository expresses
  # "the remote command finished" rather than trusting depends_on or a provider timeout to mean it
  # (rules.md D-5). depends_on between the associations would order their creation, not their execution.
  #
  # The order comes from the order field so the chain is derived rather than written out twice: a map from
  # zero-padded order to name, read back through sort(), which also means two applications sharing an order
  # would silently collapse - hence the distinctness validation on the variable.
  names_by_order = { for name, app in var.applications : format("%03d", app.order) => name }
  ordered_names  = [for key in sort(keys(local.names_by_order)) : local.names_by_order[key]]
  # The first step waits for the instance bootstrap; every later one waits for the step before it.
  wait_marker = {
    for index, name in local.ordered_names :
    name => index == 0 ? var.initial_marker_name : "image_${local.ordered_names[index - 1]}"
  }
  completion_marker_name = "image_${local.ordered_names[length(local.ordered_names) - 1]}"
  # The source files, written as a sequence of quoted heredocs rather than nested inside the script's own
  # heredoc. Built by join with explicit newlines because a heredoc inside a for inside a heredoc leaves the
  # delimiter's column ambiguous, and a delimiter that does not start the line is not a delimiter.
  #
  # Three parsers touch this text and knowing which owns what is the difference between editing it safely
  # and breaking a container:
  #
  #   1. Terraform expands ${...} and %{...} and nothing else. These files arrive as opaque strings from
  #      file() in the root, so nothing in them is expanded here.
  #   2. The instance's shell writes each file. The delimiter is quoted ('TFSOURCEFILE'), so the shell
  #      expands nothing - which is what keeps a Dockerfile's own $ and backtick characters intact.
  #   3. docker and go read the result. By then it is byte-for-byte what is in src/.
  #
  # The delimiter has to be a string that cannot appear at the start of a line in any source file. Go and
  # Dockerfile syntax will not produce TFSOURCEFILE; a short delimiter like EOF very much could.
  source_file_writes = {
    for name, app in var.applications : name => join("\n", flatten([
      for path, content in app.files : [
        "mkdir -p \"$(dirname ${var.build_root}/${name}/${path})\"",
        "cat > ${var.build_root}/${name}/${path} << 'TFSOURCEFILE'",
        content,
        "TFSOURCEFILE",
      ]
    ]))
  }
  # One association per application and image tag, keyed "<name>-<tag>", rather than one per application.
  #
  # The reason is that aws_ssm_association only waits on create. wait_for_success_timeout_seconds is read
  # in the provider's create function and nowhere else; an update returns as soon as UpdateAssociation is
  # accepted, while SSM is only starting the re-run. Keyed by name, a changed source is an in-place update,
  # so the services waiting on this module (the root's depends_on) would move on with the build still
  # running - and their new task definitions would name a tag not pushed yet, which ECS answers with
  # CannotPullContainerError until the push lands. Keyed by tag, the same change is a new instance: it is
  # created, the create waits for the build to report success, and only then does anything downstream
  # start. The previous revision's association is destroyed, which touches nothing on the instance.
  #
  # The caller makes the tag a digest of the source (the root's local.application_image_tags), so the key
  # changes exactly when something worth rebuilding does. It has to be known at plan, because it is a
  # for_each key (rules.md B-8) - a tag computed from an apply-time value fails plan with "Invalid for_each
  # argument".
  #
  # replace_triggered_by pointing at a terraform_data holding the tag looks like the shorter way to the same
  # thing, and is not: Terraform does not replace a resource when the resource its trigger names is itself
  # being created, so the first apply after introducing it - the very apply carrying the source change -
  # would still have been an unwaited update.
  builds = {
    for name, app in var.applications : "${name}-${app.image_tag}" => merge(app, { name = name })
  }
  build_keys = { for name, app in var.applications : name => "${name}-${app.image_tag}" }
}
resource "aws_ssm_association" "image_build" {
  for_each = local.builds

  name                             = "AWS-RunShellScript"
  association_name                 = "${var.association_name_prefix}-build-${each.value.name}"
  wait_for_success_timeout_seconds = var.build_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [var.instance_id]
  }
  parameters = {
    # AWS-RunShellScript's own timeout, which is separate from the Terraform-side wait above and defaults to
    # one hour. The last step in the chain spends most of its time waiting for the two before it, so the
    # default is reachable: the document would kill the command mid-build and report a timeout that looks
    # like a hung docker rather than an exhausted budget.
    executionTimeout = tostring(var.execution_timeout_seconds)
    commands         = <<-EOT
      set -u

      MARKER_DIR=${var.marker_file_path}
      BUILD_DIR=${var.build_root}/${each.value.name}

      # Phase one: wait for the step before this one.
      #
      # An until loop rather than a bare test, and the reason is rules.md D-5's shape: a failing test is a
      # non-zero statement at top level, so under a shell with -e set it would end the script on the first
      # pass with no output at all. A failing until condition never triggers -e.
      waited=0
      until [ -f "$MARKER_DIR/${local.wait_marker[each.value.name]}" ]; do
        waited=$((waited + 1))
        if [ "$waited" -gt ${var.wait_attempts} ]; then
          echo "timed out waiting for $MARKER_DIR/${local.wait_marker[each.value.name]}. The step that writes it either has not run or failed; read that association's output, or /var/log/cloud-init-output.log on this instance if the missing marker is ${var.initial_marker_name}." >&2
          exit 1
        fi
        sleep ${var.wait_interval_seconds}
      done

      # Then one build at a time on this instance, whatever the chain above did or did not order.
      #
      # The marker chain only orders the first run. The markers live in this boot's /run, so on any later
      # apply every one a step waits for is already there, and two applications whose sources changed in the
      # same apply - each a new association, created at once - would build side by side. That is the
      # concurrency the chain exists to prevent (see the order comment above). On a first run the chain has
      # already serialised the steps and this lock is never contended; it is released when the script exits,
      # however it exits.
      mkdir -p "$MARKER_DIR"
      exec 9> "$MARKER_DIR/image_build.lock"
      flock -w ${var.wait_attempts * var.wait_interval_seconds} 9 || { echo "timed out waiting for $MARKER_DIR/image_build.lock, which another build step on this instance is holding; read the other build associations' output." >&2; exit 1; }

      # Phase two: the application source, from the src/ tree in the repository.
      #
      # These files are read with file() in the root and travel through here as strings, rather than being
      # restated inline in this script. src/ is the extracted form of the template's cfn-init metadata, so
      # reading it is what keeps one copy of each application instead of two that drift (rules.md B-5).
      mkdir -p "$BUILD_DIR"
      ${local.source_file_writes[each.value.name]}
      chown -R ec2-user:ec2-user "$BUILD_DIR"

      # Phase three: log in, build, push.
      #
      # The login happens here rather than once in the instance bootstrap, where the template's
      # dockerInstallandLogin config set put it. An ECR authorization token lasts twelve hours, and a build
      # runs again whenever an application's source changes - which can be days later, against a token that
      # expired. The failure then is "no basic auth credentials" on the push, which reads as a
      # permissions problem.
      #
      # The registry host with no repository path. docker accepts a login carrying a path and then fails to
      # match it on push, with the same misleading message.
      aws ecr get-login-password --region ${data.aws_region.current.region} | docker login --username AWS --password-stdin ${split("/", each.value.image_uri)[0]} || { echo "docker login against ${split("/", each.value.image_uri)[0]} failed. The instance role needs ecr:GetAuthorizationToken, and the instance needs a route out - check its security group's egress rule." >&2; exit 1; }

      cd "$BUILD_DIR"
      # No --platform. This instance is x86_64 and so is the runtime_platform the task definitions declare;
      # an image built elsewhere for arm64 stops the task with "image manifest does not contain descriptor
      # matching platform".
      docker build -t ${each.value.image_uri} . || { echo "docker build failed for ${each.value.name}. A killed Go linker here means the instance ran out of memory - see the instance_type variable on the workbench module." >&2; exit 1; }
      docker push ${each.value.image_uri} || { echo "docker push failed for ${each.value.image_uri}." >&2; exit 1; }

      # Phase four: ask ECR rather than trusting the exit status above.
      #
      # This is what replaces the CloudFormation CreationPolicy the conversion dropped. The marker file only
      # says the script reached its end; the repository answering for the tag is what says an image exists
      # for the task definition to pull. Without this step a service starts against a missing image, its
      # tasks stop with CannotPullContainerError, and ECS keeps replacing them - so it recovers on its own
      # once a push eventually lands, which is worse than failing because the demo looks broken for ten
      # minutes and then silently is not.
      aws ecr describe-images --region ${data.aws_region.current.region} --repository-name ${each.value.repository_name} --image-ids imageTag=${each.value.image_tag} > /dev/null 2>&1 || { echo "${each.value.image_uri} is not in the repository although the build and push reported success." >&2; exit 1; }

      mkdir -p "$MARKER_DIR"
      # By application name, not by this association's key: the next step in the chain and the root's schema
      # step wait for image_<name>, and the tag in the key changes with every source change.
      touch "$MARKER_DIR/image_${each.value.name}"
      EOT
  }
}
