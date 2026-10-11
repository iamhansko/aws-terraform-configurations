import json
import time
import boto3
import cfnresponse
def handler(event, context):
  print(f"Event : {json.dumps(event)}")
  request_type = event["RequestType"]
  ecs_cluster = event["ResourceProperties"]["EcsCluster"]
  ecs_services = event["ResourceProperties"]["EcsServices"]
  response_data = {}
  ecs = boto3.client("ecs")
  try:
    response = ecs.describe_clusters(clusters=[ecs_cluster])
    container_instances = response["clusters"][0]["registeredContainerInstancesCount"]
    response_data["ContainerInstancesCount"] = str(container_instances)
    if request_type == "Delete":
      for service in ecs_services:
        ecs.update_service(cluster=ecs_cluster,service=service,desiredCount=0)
      while True:
        response = ecs.describe_clusters(clusters=[ecs_cluster])
        container_instances = response["clusters"][0]["registeredContainerInstancesCount"]
        if container_instances == 0:
          response_data["ContainerInstancesCount"] = str(0)
          break
        time.sleep(10)
    # elif request_type == "Create":
    # elif request_type == "Update":
    cfnresponse.send(event, context, cfnresponse.SUCCESS, response_data)
  except Exception as e:
    response_data["Message"] = "Error"
    cfnresponse.send(event, context, cfnresponse.FAILED, response_data, reason=str(e))
