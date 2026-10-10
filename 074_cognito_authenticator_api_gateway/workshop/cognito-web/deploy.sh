#!/bin/bash
# Builds the workshop web app and deploys it to the Lambda function Terraform created for it - what
# "sam build" and "sam deploy" did when the web app was a SAM stack. Run it after changing anything under
# web-app/ or web-ui-js/:
#
#   bash ~/workshop/cognito-web/deploy.sh
#
# The package goes to S3 and the function is pointed at it. Terraform reads that object's checksum, so its
# next plan agrees with what this deployed instead of putting the previous package back.
set -euo pipefail
cd "$(dirname "$0")"
# Written by Terraform's build step: the user pool's IDs, and where the package and the function are.
source ../ws-env.sh

(cd web-app && npm install --omit=dev --no-audit --no-fund)
# web-ui-js/package.json pins the two AWS SDK packages to 3.787.0, the release the workshop was written
# against, where it had ^3.787.0. Later @aws-sdk/credential-providers releases (3.1147.0 when this was
# checked) replaced the package's browser entry point with a per-file map, and esbuild - 0.25 and 0.28 alike -
# then bundles the Node entry and fails on node:child_process. Re-run the bundle before raising either pin.
(cd web-ui-js && npm install --no-audit --no-fund)

# The front end, once there is one. web-ui-js/cognito-sdk.js is a workshop exercise that can start out empty,
# and until it has content there is nothing to bundle.
if grep -q '[^[:space:]]' web-ui-js/cognito-sdk.js; then
  # Only the WS_ variables are substituted, so nothing else in the environment ends up in the bundle.
  envsubst "$(printf '${%s} ' $(env | grep '^WS_' | cut -d= -f1))" < web-ui-js/cognito-env-tmpl.js > web-ui-js/cognito-env.js
  esbuild web-ui-js/cognito-sdk.js --bundle --minify --sourcemap --define:global=window \
    --target=chrome90,firefox90,safari15 > web-app/public/cognito-sdk.js
fi

# The Lambda Web Adapter starts run.sh, so it has to be executable inside the zip. S3, which the workshop tree
# came through, keeps no file modes.
chmod +x web-app/run.sh
build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT
(cd web-app && zip -qr "$build_dir/web-app.zip" .)

# put-object rather than s3 cp: a single PUT, so the SHA-256 S3 stores is of the whole object - the same value
# Lambda reports as CodeSha256, which is what Terraform compares. s3 cp switches to a multipart upload above
# 8 MB and stores a checksum of the parts instead.
checksum=$(aws s3api put-object --region "$WS_REGION" \
  --bucket "$WS_WEBAPP_PACKAGE_BUCKET" --key "$WS_WEBAPP_PACKAGE_KEY" \
  --body "$build_dir/web-app.zip" --checksum-algorithm SHA256 \
  --query ChecksumSHA256 --output text)
echo "uploaded s3://$WS_WEBAPP_PACKAGE_BUCKET/$WS_WEBAPP_PACKAGE_KEY (sha256 $checksum)"

# On the first run the function does not exist yet: Terraform creates it from this package once the build
# step has finished.
if aws lambda get-function --region "$WS_REGION" --function-name "$WS_WEBAPP_FUNCTION_NAME" > /dev/null 2>&1; then
  aws lambda update-function-code --region "$WS_REGION" --function-name "$WS_WEBAPP_FUNCTION_NAME" \
    --s3-bucket "$WS_WEBAPP_PACKAGE_BUCKET" --s3-key "$WS_WEBAPP_PACKAGE_KEY" > /dev/null
  aws lambda wait function-updated --region "$WS_REGION" --function-name "$WS_WEBAPP_FUNCTION_NAME"
  echo "deployed to $WS_WEBAPP_FUNCTION_NAME: $WS_WEBAPP_URL"
fi
