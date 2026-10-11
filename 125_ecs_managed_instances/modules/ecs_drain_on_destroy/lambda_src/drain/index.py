"""Drains an ECS Managed Instances cluster before Terraform destroys what the instances depend on.

Invoked by Terraform's aws_lambda_invocation with lifecycle_scope = "CRUD", so the event is the invocation's
input with a "tf" key added - tf.action is "create", "update" or "delete". Only delete does anything.

On delete it scales every named service to zero and waits until the cluster reports no registered container
instances. With the capacity provider's scale_in_after at 0, ECS terminates each instance as soon as it is
idle, so this usually takes a couple of minutes. It has to finish before the capacity provider, its
infrastructure role, the instances' security group and the subnets are destroyed: ECS uses that role to
terminate the instances, and their ENIs hold the group and the subnets.

The _monolithic source this replaces did the same work as a CloudFormation custom resource and could not run
under aws_lambda_invocation: it read event["RequestType"] and event["ResourceProperties"], which only
CloudFormation sends, and reported back through cfnresponse, which exists only in CloudFormation's
inline-code runtime.
"""
import json
import time

import boto3

ecs = boto3.client("ecs")
POLL_SECONDS = 10


def registered_instances(cluster):
    clusters = ecs.describe_clusters(clusters=[cluster])["clusters"]
    return clusters[0]["registeredContainerInstancesCount"] if clusters else 0


def handler(event, context):
    print(json.dumps(event))
    action = event.get("tf", {}).get("action", "create")
    cluster = event["EcsCluster"]
    services = event["EcsServices"]

    if action != "delete":
        return {"Action": action, "ContainerInstancesCount": registered_instances(cluster)}

    for service in services:
        try:
            ecs.update_service(cluster=cluster, service=service, desiredCount=0)
        except (ecs.exceptions.ServiceNotFoundException, ecs.exceptions.ServiceNotActiveException):
            # Already gone, which is the state this is trying to reach.
            pass

    while True:
        count = registered_instances(cluster)
        if count == 0:
            return {"Action": action, "ContainerInstancesCount": 0}
        # Fail loudly rather than return early. A destroy that continues with instances still running is the
        # failure this function exists to prevent.
        if context.get_remaining_time_in_millis() < (POLL_SECONDS + 5) * 1000:
            raise TimeoutError(
                f"{count} container instances are still registered in {cluster}. "
                "Check the capacity provider's instances in the EC2 console before destroying further."
            )
        time.sleep(POLL_SECONDS)
