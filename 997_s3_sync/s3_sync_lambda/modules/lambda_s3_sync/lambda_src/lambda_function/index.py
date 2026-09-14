import base64
import hashlib
import json
import os
import boto3

s3 = boto3.client("s3")

TASK_ROOT = os.environ.get("LAMBDA_TASK_ROOT", "/var/task")
PAYLOAD_ROOT = os.path.join(TASK_ROOT, os.environ.get("PAYLOAD_DIRECTORY", "payload"))
DELETE_BATCH_SIZE = 1000

def _existing_objects(bucket, prefix):
  found = {}
  paginator = s3.get_paginator("list_objects_v2")
  for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
    for item in page.get("Contents", []):
      found[item["Key"]] = item["ETag"].strip('"')
  return found


def _is_unchanged(etag, digest):
  if etag is None or "-" in etag:
    return False
  return etag == digest


def _delete_keys(bucket, keys):
  deleted = sorted(keys)
  for start in range(0, len(deleted), DELETE_BATCH_SIZE):
    batch = deleted[start:start + DELETE_BATCH_SIZE]
    s3.delete_objects(
      Bucket=bucket,
      Delete={"Objects": [{"Key": key} for key in batch], "Quiet": True},
    )
  return deleted


def _read_payload(relative_path):
  """Read one bundled file and return its original bytes."""
  local_path = os.path.join(PAYLOAD_ROOT, relative_path)
  if not os.path.realpath(local_path).startswith(os.path.realpath(PAYLOAD_ROOT) + os.sep):
    raise ValueError(f"payload path escapes the payload directory: {relative_path}")
  with open(local_path, "rb") as handle:
    return base64.b64decode(handle.read())


def handler(event, context):
  print(f"Event : {json.dumps(event)}")

  lifecycle = event.get("tf") or {}
  action = lifecycle.get("action", "create")

  bucket = event["bucket"]
  key_prefix = event.get("key_prefix", "")
  objects = event.get("objects", [])
  delete_removed = event.get("delete_removed", True)
  delete_on_destroy = event.get("delete_on_destroy", True)

  if action == "delete":
    if not delete_on_destroy:
      return {"action": action, "skipped_cleanup": True, "deleted": []}
    previous = lifecycle.get("prev_input") or {}
    previous_keys = [entry["key"] for entry in previous.get("objects", [])]
    if not previous_keys:
      previous_keys = list(_existing_objects(bucket, key_prefix))
    deleted = _delete_keys(bucket, previous_keys)
    return {"action": action, "deleted": deleted, "deleted_count": len(deleted)}

  existing = _existing_objects(bucket, key_prefix)

  uploaded, unchanged = [], []
  for entry in objects:
    key = entry["key"]
    body = _read_payload(entry["path"])
    digest = hashlib.md5(body).hexdigest()

    if _is_unchanged(existing.get(key), digest):
      unchanged.append(key)
      continue

    s3.put_object(
      Bucket=bucket,
      Key=key,
      Body=body,
      ContentType=entry.get("content_type", "application/octet-stream"),
    )
    uploaded.append(key)

  deleted = []
  if delete_removed:
    wanted = {entry["key"] for entry in objects}
    deleted = _delete_keys(bucket, set(existing) - wanted)

  result = {
    "action": action,
    "bucket": bucket,
    "key_prefix": key_prefix,
    "uploaded": uploaded,
    "uploaded_count": len(uploaded),
    "unchanged": unchanged,
    "unchanged_count": len(unchanged),
    "deleted": deleted,
    "deleted_count": len(deleted),
    "object_count": len(objects),
  }
  print(f"Result : {json.dumps(result)}")
  return result
