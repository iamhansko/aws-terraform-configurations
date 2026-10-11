# Copies a model onto every running GPU node when it lands in the models bucket, and removes it when it is
# deleted.
#
# Taken from the blueprint's lib/ComfyModelsSyncLambda/model_sync.py, with four changes:
#
#   - The GPU nodes are found by eks:eks-cluster-name, not aws:eks:cluster-name. The aws: prefix is reserved
#     for tags AWS itself writes - EKS writes that one onto managed node group instances - and Karpenter,
#     which launches every GPU node here, cannot write it. It writes eks:eks-cluster-name instead. Filtering
#     on the aws: tag together with karpenter.sh/nodepool matched no instance at all, so the original synced
#     nothing to the nodes it was written for.
#   - The bucket, the node directory, the cluster and the pool come from the environment the Terraform module
#     sets, instead of being rebuilt from the account ID and region and a hardcoded cluster name. The values
#     are defined once in the root (rules.md B-5).
#   - An ObjectRemoved event deletes the local copy. The original subscribed to removals and then ran
#     "aws s3 cp" for the deleted key, which could only fail.
#   - No running GPU node is not an error. SendCommand rejects an empty instance list, so the original
#     raised on every upload made while the pool was scaled to zero - which is most of the time a model
#     download runs.
import json
import os
import re
from urllib.parse import unquote_plus

import boto3

VALID_MODEL_KEY = re.compile(r'^[a-zA-Z0-9/_.\-]+$')

MODELS_BUCKET = os.environ['MODELS_BUCKET']
NODE_DIR = os.environ['NODE_DIR']
CLUSTER_NAME = os.environ['CLUSTER_NAME']
NODE_POOL_NAME = os.environ['NODE_POOL_NAME']

ec2 = boto3.client('ec2')
ssm = boto3.client('ssm')


def validate_model_key(key):
    # The key ends up in a shell command on every GPU node, so anything outside a plain path is rejected
    # rather than quoted.
    if not key or len(key) > 512 or not VALID_MODEL_KEY.match(key):
        raise ValueError(f"Invalid model key rejected: {key!r}")
    if '..' in key:
        raise ValueError(f"Path traversal rejected: {key!r}")
    return key


def human_size(size):
    for unit, factor in (('GB', 1073741824), ('MB', 1048576), ('KB', 1024)):
        if size > factor:
            return f"{round(size / factor, 2)}{unit}"
    return f"{size}B"


def changed_objects(event):
    changes = []
    for record in event['Records']:
        # S3 event keys are URL-encoded; the object on disk is not.
        key = unquote_plus(record['s3']['object']['key'])
        size = record['s3']['object'].get('size', 0)
        name = record['eventName']
        print(key, human_size(size), name)
        changes.append((key, name.startswith('ObjectRemoved')))
    return changes


def running_gpu_instances():
    paginator = ec2.get_paginator('describe_instances')
    instance_ids = []
    for page in paginator.paginate(Filters=[
        {'Name': 'instance-state-name', 'Values': ['running']},
        {'Name': 'tag:eks:eks-cluster-name', 'Values': [CLUSTER_NAME]},
        {'Name': 'tag:karpenter.sh/nodepool', 'Values': [NODE_POOL_NAME]},
    ]):
        for reservation in page['Reservations']:
            for instance in reservation['Instances']:
                instance_ids.append(instance['InstanceId'])
    return instance_ids


def lambda_handler(event, context):
    changes = changed_objects(event)
    instance_ids = running_gpu_instances()
    if not instance_ids:
        # Nothing to copy onto. A node that boots later copies what it needs from the bucket in its own user
        # data, and anything else ComfyUI asks for is fetched by its auto model downloader.
        print("No running GPU node in pool", NODE_POOL_NAME, "- nothing to sync")
        return {'statusCode': 200, 'body': json.dumps('No GPU nodes running')}

    print("Following instances will be synced:", instance_ids)
    for key, removed in changes:
        try:
            validate_model_key(key)
        except ValueError as e:
            print(f"Skipping invalid model key: {e}")
            continue
        if removed:
            command = f"rm -f {NODE_DIR}/{key}"
        else:
            command = f"aws s3 cp --checksum-mode ENABLED s3://{MODELS_BUCKET}/{key} {NODE_DIR}/{key}"
        response = ssm.send_command(
            InstanceIds=instance_ids,
            DocumentName="AWS-RunShellScript",
            Parameters={'commands': [command]},
        )
        print(response['Command']['Parameters']['commands'], response['Command']['Status'])

    return {'statusCode': 200, 'body': json.dumps('Models synced!')}
