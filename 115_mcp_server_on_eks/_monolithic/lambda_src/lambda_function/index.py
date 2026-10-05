import json
import time
import urllib.request
import boto3

codebuild = boto3.client("codebuild")

def handler(event, context):
  print(f"Event: {json.dumps(event)}")
  request_type = event["RequestType"]
  if request_type == "Delete":
    send(event, "SUCCESS", {})
    return

  props = event["ResourceProperties"]
  project_name = props["CodeBuildProject"]
  env_overrides = props.get("EnvironmentVariablesOverride", [])

  try:
    start = codebuild.start_build(
      projectName=project_name,
      environmentVariablesOverride=env_overrides,
    )
    build_id = start["build"]["id"]
    print(f"Started build {build_id} for project {project_name}")

    deadline = time.time() + 14 * 60
    status = "IN_PROGRESS"
    while time.time() < deadline:
      builds = codebuild.batch_get_builds(ids=[build_id])["builds"]
      status = builds[0]["buildStatus"]
      print(f"Build status: {status}")
      if status != "IN_PROGRESS":
        break
      time.sleep(20)
    if status == "SUCCEEDED":
      send(event, "SUCCESS", {"BuildId": build_id}, physical_id=build_id)
    else:
      send(event, "FAILED", {}, reason=f"Build {build_id} ended with status: {status}", physical_id=build_id)
  except Exception as error:
    print(f"Error: {error}")
    send(event, "FAILED", {}, reason=str(error))

def send(event, status, data, reason=None, physical_id=None):
  body = json.dumps(
    {
      "Status": status,
      "Reason": reason or "See CloudWatch Logs for details",
      "PhysicalResourceId": physical_id or event.get("PhysicalResourceId") or event["RequestId"],
      "StackId": event["StackId"],
      "RequestId": event["RequestId"],
      "LogicalResourceId": event["LogicalResourceId"],
      "Data": data,
    }
  ).encode("utf-8")

  request = urllib.request.Request(
    event["ResponseURL"],
    data=body,
    method="PUT",
    headers={"Content-Type": "", "Content-Length": str(len(body))},
  )
  urllib.request.urlopen(request)
