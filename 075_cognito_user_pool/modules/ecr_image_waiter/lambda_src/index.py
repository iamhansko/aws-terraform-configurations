"""Waits until the image tags an SSM association pushes are in ECR, and fails early if that association fails.

The caller reads the images back once this returns - data "aws_ecr_image" lookups named through this
function's result - and something has to hold those reads until the pushes have happened. The association's
own wait_for_success_timeout_seconds does not. An association whose target instance has not registered with
Systems Manager yet reports Overview.Status Success with an empty AssociationStatusAggregatedCount, and the
provider's waiter accepts that Success and returns. On a first apply the association is created seconds after
the instance launches, before its SSM agent has registered. And when the association's commands change it is
updated in place, which the provider does not wait on at all - so a new commit's tag was looked up before the
build had pushed it.

So the wait lives here, against the thing the reader actually needs: DescribeImages on each tag, until every
one answers. A tag is set only once its manifest is pushed, so a tag that answers is a complete image. The
association is consulted only for the opposite answer - an execution of its current version that has failed -
so a build that cannot succeed fails the apply within one poll, with the command that shows its output,
instead of at this function's timeout. Its Success is never trusted, for the reason above.
"""

import json
import time

import boto3
from botocore.exceptions import BotoCoreError, ClientError

POLL_SECONDS = 10
# Held back from the function's timeout so the wait ends in this function's own TimeoutError, which names the
# missing tags and the association, rather than Lambda's bare "Task timed out after N seconds".
RESERVE_MILLIS = 15_000
# Execution statuses that end a run without the pushes. Success is deliberately absent: see the docstring.
FAILED_EXECUTION_STATES = ("Failed", "TimedOut", "Cancelled")


def lambda_handler(event, context):
    print(json.dumps(event))

    images = event.get("images") or {}
    association_id = event.get("association_id")
    if not images or not association_id:
        raise ValueError("event must carry a non-empty images map and association_id")
    for label, image in images.items():
        if not image.get("repository_name") or not image.get("image_tag"):
            raise ValueError(f"images[{label}] must carry repository_name and image_tag")

    ecr = boto3.client("ecr")
    ssm = boto3.client("ssm")
    started = time.monotonic()
    last_error = None
    while True:
        found = {}
        missing = []
        for label, image in images.items():
            repository, tag = image["repository_name"], image["image_tag"]
            try:
                detail = ecr.describe_images(repositoryName=repository, imageIds=[{"imageTag": tag}])["imageDetails"][0]
                found[label] = {
                    "repository_name": repository,
                    "image_tag": tag,
                    "image_digest": detail["imageDigest"],
                    "pushed_at": detail["imagePushedAt"].isoformat(),
                }
            except ClientError as error:
                missing.append(f"{repository}:{tag}")
                if error.response.get("Error", {}).get("Code") != "ImageNotFoundException":
                    # Retried rather than raised: a role policy created in the same apply can take a few seconds
                    # to reach this function. A permanent error still ends the wait, at the deadline below, with
                    # this message attached.
                    last_error = error
                    print(f"retrying {repository}:{tag} after {error}")
            except BotoCoreError as error:
                missing.append(f"{repository}:{tag}")
                last_error = error
                print(f"retrying {repository}:{tag} after {error}")

        if not missing:
            waited_seconds = round(time.monotonic() - started)
            print(f"every image found after {waited_seconds}s: {json.dumps(found)}")
            # repository_name and image_tag are echoed back so the caller can name each image through this
            # result, which is what orders its lookup after this function. The digests are here for the
            # invocation's record only: this result is fixed at the invoke, while a tag can be pushed over later.
            return {"images": found, "waited_seconds": waited_seconds}
        print(f"waiting for {missing}")

        failure = _failed_execution(ssm, association_id)
        if failure is not None:
            raise RuntimeError(_failure_message(missing, association_id, failure))

        if context.get_remaining_time_in_millis() < RESERVE_MILLIS + POLL_SECONDS * 1000:
            raise TimeoutError(_timeout_message(missing, association_id, last_error))
        time.sleep(POLL_SECONDS)


def _failed_execution(ssm, association_id):
    """The newest execution of the association's current version if it has failed, otherwise None.

    Only the current version, because the association is updated in place when its commands change, and until
    the new version's run starts the newest execution is the previous version's - which can be the very failure
    the update is meant to fix.
    """
    try:
        description = ssm.describe_association(AssociationId=association_id)["AssociationDescription"]
        version = description.get("AssociationVersion")
        executions = []
        kwargs = {"AssociationId": association_id}
        while True:
            page = ssm.describe_association_executions(**kwargs)
            executions.extend(page.get("AssociationExecutions", []))
            if not page.get("NextToken"):
                break
            kwargs["NextToken"] = page["NextToken"]
    except (ClientError, BotoCoreError) as error:
        # Not fatal. Without these calls the function still waits on ECR; it only loses the early exit.
        print(f"could not read the association's executions, waiting on ECR alone: {error}")
        return None

    current = [e for e in executions if e.get("AssociationVersion") == version]
    if not current:
        return None
    latest = max(current, key=lambda e: e["CreatedTime"])
    if latest.get("Status") not in FAILED_EXECUTION_STATES:
        return None

    try:
        targets = ssm.describe_association_execution_targets(
            AssociationId=association_id, ExecutionId=latest["ExecutionId"]
        ).get("AssociationExecutionTargets", [])
    except (ClientError, BotoCoreError) as error:
        # The failure is known either way; only the pointer to its output is lost.
        print(f"could not read the failed execution's targets: {error}")
        targets = []
    return {"execution": latest, "targets": targets}


def _failure_message(missing, association_id, failure):
    execution = failure["execution"]
    parts = [
        f"SSM association {association_id} failed (execution {execution['ExecutionId']}:"
        f" {execution.get('Status')}/{execution.get('DetailedStatus')}) with {', '.join(missing)} still not in ECR,"
        " so there is nothing to wait for."
    ]
    for target in failure["targets"]:
        command_id = (target.get("OutputSource") or {}).get("OutputSourceId")
        if command_id:
            parts.append(
                f"Its output on {target['ResourceId']}: aws ssm get-command-invocation --command-id {command_id}"
                f" --instance-id {target['ResourceId']} --query '[StatusDetails,StandardErrorContent]' --output text."
            )
    parts.append(
        "Once the cause is fixed: if the fix changes the association's commands, the next terraform apply re-runs"
        f" it; otherwise re-run it with aws ssm start-associations-once --association-ids {association_id}."
        " Either way, the next terraform apply waits again."
    )
    return " ".join(parts)


def _timeout_message(missing, association_id, last_error):
    message = (
        f"{', '.join(missing)} did not appear in ECR before this function's timeout, and association"
        f" {association_id} has not failed either. aws ssm describe-association-executions --association-id"
        f" {association_id} shows which case this is. An execution still InProgress is only slow, and running"
        " terraform apply again waits again. Success with ResourceCountByStatus empty means the instance never"
        " registered with Systems Manager, so the build never ran. Success with the instance counted means the"
        " script finished without pushing these tags."
    )
    if last_error is not None:
        message += f" Last AWS error: {last_error}"
    return message
