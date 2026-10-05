/**
 * Starts a CodeBuild build and returns its id.
 *
 * This exists because Terraform has no resource for "run this build once": a CodeBuild project is
 * infrastructure, a build is not. So the deployment is kicked off through this function, invoked by
 * aws_lambda_invocation at apply time.
 *
 * Rewritten from the version the _monolithic template carried, which could not run. That one did
 * require('cfn-response') - a module CloudFormation makes available only to inline Lambda code, so a zipped
 * function fails while loading it - and read its arguments from event.ResourceProperties, which is the shape
 * CloudFormation sends a custom resource rather than what the Terraform invocation sends. Two independent
 * reasons the same call could never have succeeded.
 */
import { CodeBuildClient, StartBuildCommand } from "@aws-sdk/client-codebuild";

// AWS_REGION is set by the runtime; the SDK reads it on its own, so passing it explicitly only matters if
// the build has to be started in a different region than the function runs in.
const codebuild = new CodeBuildClient({ maxAttempts: 3 });

export const handler = async (event) => {
  console.log("Event:", JSON.stringify(event, null, 2));

  const projectName = event.projectName;
  if (!projectName) {
    // Thrown rather than reported and swallowed. The CloudFormation original sent a FAILED response through
    // cfn-response and returned normally, so a stack could succeed having started nothing; here a failure
    // fails the apply, which is something a caller can act on.
    throw new Error("projectName is required");
  }

  const result = await codebuild.send(new StartBuildCommand({ projectName }));

  return {
    buildId: result.build.id,
    buildArn: result.build.arn,
    buildNumber: result.build.buildNumber,
    startedAt: result.build.startTime,
  };
};
