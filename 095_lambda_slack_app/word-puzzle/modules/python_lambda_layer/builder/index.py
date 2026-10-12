"""Builds a Python Lambda layer from a list of pip requirements and uploads it to S3.

Invoked once by Terraform (aws_lambda_invocation) with the requirements, the bucket and the key, and again
whenever the requirements change. It runs on the same runtime and architecture as the functions that will
use the layer, so pip picks exactly the wheels those functions can import - the reason it runs here rather
than on the machine running terraform, where an unqualified pip install fetches wheels for that machine's
Python and operating system.

The result is JSON: where the package went, its base64-encoded SHA-256 (what the layer version is published
for), and the distributions it contains.
"""
import base64
import hashlib
import importlib.metadata
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile

import boto3


def _zip_directory(source_root, zip_path):
    """Zip source_root/python into zip_path with the python/ prefix Lambda expects in a layer."""
    with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as archive:
        for directory, subdirectories, files in os.walk(os.path.join(source_root, 'python')):
            # Sorted, so the archive lists its entries in the same order on every build.
            subdirectories.sort()
            for name in sorted(files):
                path = os.path.join(directory, name)
                archive.write(path, os.path.relpath(path, source_root))


def lambda_handler(event, context):
    requirements = event['requirements']
    bucket = event['bucket']
    key = event['key']
    if not requirements:
        raise ValueError('requirements is empty: a layer with nothing in it has nothing to publish.')

    work_dir = tempfile.mkdtemp(dir='/tmp')
    try:
        target = os.path.join(work_dir, 'python')
        # --only-binary, because there is no compiler in the runtime: a package without a wheel for it fails
        # here, by name, instead of halfway through a source build. --target implies --ignore-installed, so the
        # runtime's own boto3 does not satisfy a requirement on it and every dependency lands in the layer.
        command = [
            sys.executable, '-m', 'pip', 'install',
            '--no-cache-dir', '--disable-pip-version-check', '--no-input',
            '--only-binary=:all:',
            '--target', target,
            *requirements,
        ]
        # HOME on /tmp, the only writable place: pip writes its configuration and build state under it.
        process = subprocess.run(
            command, capture_output=True, text=True,
            env={**os.environ, 'HOME': '/tmp', 'PIP_ROOT_USER_ACTION': 'ignore'},
        )
        if process.returncode != 0:
            # The tail of pip's output is the part that says which requirement failed; the invocation's error
            # message is what terraform apply prints.
            raise RuntimeError(f'pip install failed ({process.returncode}):\n{process.stderr[-3000:]}')

        zip_path = os.path.join(work_dir, 'layer.zip')
        _zip_directory(work_dir, zip_path)
        with open(zip_path, 'rb') as package:
            body = package.read()
        sha256 = base64.b64encode(hashlib.sha256(body).digest()).decode('ascii')

        # A whole-object SHA-256 stored with the object, so the value can also be checked from S3.
        boto3.client('s3').put_object(Bucket=bucket, Key=key, Body=body, ChecksumAlgorithm='SHA256')

        packages = sorted(
            f"{distribution.metadata['Name']}=={distribution.version}"
            for distribution in importlib.metadata.distributions(path=[target])
        )
        return {
            'bucket': bucket,
            'key': key,
            'sha256': sha256,
            'size': len(body),
            'runtime': f'python{sys.version_info.major}.{sys.version_info.minor}',
            'packages': packages,
        }
    finally:
        shutil.rmtree(work_dir, ignore_errors=True)
