# 119 Kiro

This Terraform root creates or reuses an IAM Identity Center instance, creates a user, issues a one-time password, and creates a monthly billed Kiro subscription by default.

## Architecture

- `modules/network`: one public NAT subnet and one private bootstrap subnet in a single AZ. The NAT gateway preserves the account's VPC Block Public Access `block-ingress` policy while allowing SSM, package, and AWS API egress. It incurs hourly and data-processing charges, so destroy the demo when it is no longer needed.
- `modules/identity_center_instance`: reuses an instance discovered in the selected region, or creates one through AWS Cloud Control when discovery is empty. A pre-existing instance stays external; only an instance created by this root is destroyed with it.
- `modules/identity_center_user`: owns the IAM Identity Center user.
- `modules/kiro_bootstrap_ec2`: owns the outbound-only security group, IAM role, SecureString/ownership/status parameters, custom SSM Command document, minimal EC2 user data, direct SigV4 profile/subscription operations, bootstrap operation Association/waiter, optional cleanup Association/waiter, and instance running/stopped transitions.

The active `init.yaml` is the historical behavior reference. Unsafe implementation details are intentionally not reproduced: public unauthenticated code-server, unused SSH key, credential/OTP logging, plaintext Parameter Store values, Lambda custom-resource round trips, mutation-status-only success, and immediate EC2 termination.

## Prerequisites

1. Terraform 1.11 or newer is required for write-only resource arguments.
2. With `aws_region = null`, both AWS providers use the environment chain. Keep `AWS_DEFAULT_REGION` stable for the lifetime of this state; this deployed state is in `ap-northeast-2`, so set `aws_region = "ap-northeast-2"` (or the matching environment value) before planning. A missing Identity Center instance is created in that selected region, while a changed environment region proposes a different regional deployment.
3. Automatic Identity Center creation is supported only for a standalone account that is neither an AWS Organizations management account nor member account.
4. Load all temporary credentials from the repository root:

   ```bash
   . .aws/credentials.sh
   export MSYS2_ENV_CONV_EXCL='AWS_ACCESS_KEY_ID;AWS_SECRET_ACCESS_KEY;AWS_SESSION_TOKEN'
   aws sts get-caller-identity
   ```

5. Set `expected_account_id` for an additional blocking wrong-account guard.

## Cross-region subscription path and billing

A normal apply must keep cleanup disabled:

```hcl
subscription_cleanup_generation = null
```

Profile and per-user subscription creation are enabled and acknowledged by default because they are the purpose of this root:

```hcl
create_kiro_subscription              = true
acknowledge_monthly_kiro_subscription = true
kiro_region                           = "us-east-1"
```

`aws_region` remains the infrastructure and IAM Identity Center home region (`ap-northeast-2` for the current state), and it also controls the workforce-subscription endpoint and SigV4 signing scope. `kiro_region` is independently validated as `us-east-1` or `eu-central-1`; it controls the Kiro profile and assignment endpoint/signing region and is sent as the subscription list filter. The bootstrap does not perform another regional Identity Center discovery:

- Profile list/create/delete calls use `codewhisperer.<kiro_region>.amazonaws.com`, sign for `kiro_region`, and bind the profile to the actual Terraform-provided Identity Center instance ARN with `ssoRegion = aws_region`.
- Subscription listing calls `service.user-subscriptions.<aws_region>.amazonaws.com`, signs for `aws_region`, sends the actual instance ARN, and sets `subscriptionRegion = kiro_region`. The response normalizes requested `Q_DEVELOPER_STANDALONE_*` plans to `KIRO_ENTERPRISE_*`; observers map those names before requiring the exact user and plan.
- Assignment create/delete calls use the Kiro-region CodeWhisperer endpoint, sign for `kiro_region`, and use the exact Terraform user ID and requested plan.

Every observer parses the JSON response and distinguishes present, absent, and query failure. Mutation HTTP status alone is never treated as success; bootstrap and cleanup re-observe the exact profile identity or exact non-cancelled user/plan after each mutation attempt.

The selected plan is billed monthly. Setting `create_kiro_subscription = false` prevents a new assignment but does not cancel an assignment that already exists. To create only the user and OTP without starting subscription billing, set both subscription booleans to `false` before the first apply. To stop charges for an owned assignment, complete the cleanup workflow below before destroy.

To reproduce the template's instance-wide MFA disable, record the current mode first, then explicitly set:

```hcl
disable_mfa                           = true
acknowledge_instance_wide_mfa_disable = true
```

The original `AdministratorAccess` remains because password issuance and optional MFA changes call undocumented console endpoints. `AmazonSSMManagedInstanceCore` is also attached explicitly because SSM is now the bootstrap execution transport. The instance has no inbound rules or interactive service and is stopped after normal bootstrap verification.

## Apply and Kiro login

```bash
cd 119_kiro
# Remove stale environment overrides that can silently defeat the root defaults.
unset TF_VAR_create_kiro_subscription TF_VAR_acknowledge_monthly_kiro_subscription
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan
terraform apply
```

The direct API, OTP, status, and ownership logic is serialized into a custom SSM Command document instead of EC2 user data. This moves the heavy script out of EC2's 16,384-byte raw user-data limit and keeps it inside the 65,536-byte SSM document limit, which is enforced by a lifecycle precondition. EC2 user data is now only a small launcher that enables `amazon-ssm-agent` and logs the Command document content SHA256. The same SHA256 is embedded in user data, so changing document content changes `user_data`; with `user_data_replace_on_change = true`, Terraform replaces the bootstrap instance rather than silently applying changed one-shot logic to the old instance.

The existing `bootstrap_complete` Association invokes the custom document and its latest version. The document records `running:<instance-id>` before package installation, retries status writes while the instance profile settles, bounds `dnf` to 300 seconds, and records `success:<instance-id>` after the password and optional subscription are observed. `bootstrap_completion_wait` remains the actual completion barrier: it independently reads the issued password, promotes status to `verified:<instance-id>`, and blocks EC2 stop and the plaintext password read until verification succeeds. Files under `/run/terraform` are same-boot diagnostics only; durable completion and ownership live in SSM Parameter Store.

If an apply stops in `bootstrap_completion_wait`, inspect the Association operation rather than EC2 console output. Read the Association ID from the shown resource, then follow the execution to its Run Command invocation:

```bash
terraform state show 'module.kiro_bootstrap.aws_ssm_association.bootstrap_complete'
REGION='<aws-region>'
ASSOCIATION_ID='<association-id>'
aws ssm describe-association-executions \
  --region "$REGION" --association-id "$ASSOCIATION_ID"
EXECUTION_ID='<latest-execution-id>'
aws ssm describe-association-execution-targets \
  --region "$REGION" --association-id "$ASSOCIATION_ID" --execution-id "$EXECUTION_ID"
COMMAND_ID='<OutputSource.OutputSourceId from the target result>'
INSTANCE_ID='<target EC2 instance ID>'
aws ssm get-command-invocation \
  --region "$REGION" --command-id "$COMMAND_ID" --instance-id "$INSTANCE_ID"
```

After fixing a transient runner credential problem, refresh the temporary credentials and rerun apply. A failed waiter is tainted and recreated automatically:

```bash
. ../.aws/credentials.sh
export MSYS2_ENV_CONV_EXCL='AWS_ACCESS_KEY_ID;AWS_SECRET_ACCESS_KEY;AWS_SESSION_TOKEN'
terraform apply
```

AWS CLI errors from the runner are not suppressed; an expired session fails immediately with its original `ExpiredToken` message instead of waiting for the full bootstrap timeout.

The root exposes one CloudFormation-compatible login handoff:

```bash
terraform output -json kiro_login_data
```

It contains only `start_url`, `username`, `one_time_password`, `email`, and `subscription_region`, where `subscription_region` is the IAM Identity Center region (`aws_region`) in which the instance was created. The output deliberately uses `nonsensitive()`, so `terraform apply`, `terraform output`, CI logs, and captured terminal output can display the OTP in plaintext. The OTP is also stored unencrypted inside Terraform state data. Protect terminal/CI logs, the state backend, and backups; restrict readers and change the OTP at first login.

## Terraform-managed subscription cleanup

Cleanup is an explicit two-phase Terraform workflow because an SSM Association executes during create/update apply, not during Association deletion. There is no imperative SSM CLI cleanup path.

### Normal phase

Keep `subscription_cleanup_generation = null`. No cleanup Association exists, and `stop_after_bootstrap = true` leaves the instance stopped after successful bootstrap.

### Teardown phase

Before changing the user, password parameter path, Kiro region, or subscription plan—and before every destroy—set a new plan-known generation:

```hcl
subscription_cleanup_generation = "cleanup-20261014-1"
```

Then run:

```bash
terraform plan
terraform apply
```

The expected plan starts the same EC2 instance, creates or updates `subscription_cleanup`, and replaces a request carrier/waiter for the new generation:

1. `subscription_cleanup_request` generates a unique request ID, even if a previous generation label is reused later.
2. `subscription_cleanup` runs ownership-aware direct API cleanup and writes `running`, `success`, or `failed` with that exact request ID to a Terraform-owned SSM status parameter.
3. `subscription_cleanup_wait` polls the status parameter from the Terraform runner. This is the apply-time barrier because the AWS provider can return from an Association update before its target command completes.

Cleanup does not depend on `/run` surviving an EC2 restart. It preserves pre-existing objects, removes only the exact user/plan and exact Identity Center profile represented by `creating|created` ownership, and retains the owned profile while any active non-cancelled Q subscription remains. The cleanup generation is not included in the bootstrap document content or the minimal user-data SHA256, so later teardown generations must not replace EC2 or issue another OTP.

A successful teardown-generation apply means the Terraform waiter observed `success:<request-id>`, not merely that AWS accepted an Association update. Confirm the apply completed without errors, restore the recorded MFA mode if it was changed, then run `terraform destroy`. Do not destroy the Terraform-managed user before cleanup; assignment deletion requires its user ID.

## Validation

```bash
terraform fmt -check -recursive
terraform init -backend=false -lockfile=readonly -input=false
terraform validate -json
```

Render the default `create_kiro_subscription = true` variant when changing the scripts. The UTF-8 encoded minimal user data must remain at or below 16,384 bytes, the serialized custom document must remain at or below 65,536 bytes, and both the rendered bootstrap and cleanup scripts must pass `bash -n`.

The active configuration should contain the custom bootstrap Command document and only Terraform-managed SSM Associations, not an imperative cleanup command. A credentialed normal plan should show no cleanup Association/request/waiter resources. A teardown-generation plan should show the instance state changing to `running` plus cleanup Association/request/waiter creation or replacement, with no `aws_instance.bootstrap` replacement.
