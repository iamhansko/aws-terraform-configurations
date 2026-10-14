locals {
  marker_file_path                      = "/run/terraform"
  password_placeholder                  = "pending-bootstrap"
  bootstrap_status_parameter_name       = "${var.password_parameter_name}-bootstrap-status"
  cleanup_status_parameter_name         = "${var.password_parameter_name}-cleanup-status"
  profile_ownership_parameter_name      = "${var.password_parameter_name}-profile-ownership"
  subscription_ownership_parameter_name = "${var.password_parameter_name}-subscription-ownership"

  # The original template explicitly attached these broad policies. AdministratorAccess remains necessary
  # until the two undocumented console endpoints can be mapped to verified IAM actions (rules.md A-5).
  # AmazonSSMManagedInstanceCore is explicit because the bootstrap now runs through an SSM Command document.
  # Stopping the instance does not remove this role; it remains until terraform destroy. Amazon Q access and
  # the component policy are present only when the caller explicitly requests the billed subscription.
  required_iam_policy_arns = concat(
    [
      "arn:aws:iam::aws:policy/AdministratorAccess",
      "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    ],
    var.create_kiro_subscription ? ["arn:aws:iam::aws:policy/AmazonQDeveloperAccess"] : [],
  )
  iam_policy_arns = toset(concat(local.required_iam_policy_arns, var.additional_iam_policy_arns))
}

# This is an outbound-only, one-shot host rather than the unauthenticated public code-server created by the
# _monolithic conversion. New security groups use standalone rules (rules.md F-2).
resource "aws_security_group" "bootstrap" {
  name        = var.security_group_name
  description = "Kiro bootstrap instance - outbound only"
  vpc_id      = var.vpc_id

  tags = {
    Name = var.security_group_name
  }
}

resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.bootstrap.id
  description       = "AWS APIs and package installation"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_iam_role" "bootstrap" {
  name_prefix = "${var.name}-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "bootstrap" {
  for_each = local.iam_policy_arns

  role       = aws_iam_role.bootstrap.name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "kiro" {
  count = var.create_kiro_subscription ? 1 : 0

  name = "KiroIamPolicy"
  role = aws_iam_role.bootstrap.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["q:*", "codewhisperer:*", "user-subscriptions:*"]
      Resource = "*"
    }]
  })
}

# An instance profile accepts one role name, not a JSON-encoded CloudFormation Roles list (rules.md A-3).
resource "aws_iam_instance_profile" "bootstrap" {
  name_prefix = "${var.name}-"
  role        = aws_iam_role.bootstrap.name
}

# Terraform owns these parameters while the SSM Command bootstrap and cleanup operations own their values.
# Write-only arguments keep the password and out-of-band ownership transitions out of state. A stable version
# means later plans do not overwrite values written by the bootstrap or cleanup scripts.
resource "aws_ssm_parameter" "password" {
  name             = var.password_parameter_name
  description      = "One-time password for the IAM Identity Center user"
  type             = "SecureString"
  value_wo         = local.password_placeholder
  value_wo_version = 1
}

resource "aws_ssm_parameter" "profile_ownership" {
  name             = local.profile_ownership_parameter_name
  description      = "Whether this Terraform root created the state-external Kiro profile"
  type             = "String"
  value_wo         = "unobserved"
  value_wo_version = 1
}

resource "aws_ssm_parameter" "subscription_ownership" {
  name             = local.subscription_ownership_parameter_name
  description      = "Whether this Terraform root created the state-external Kiro subscription"
  type             = "String"
  value_wo         = "unobserved"
  value_wo_version = 1
}

resource "aws_ssm_parameter" "bootstrap_status" {
  name             = local.bootstrap_status_parameter_name
  description      = "Bootstrap result keyed by EC2 instance ID for Terraform completion polling"
  type             = "String"
  value_wo         = "pending"
  value_wo_version = 1
}

resource "aws_ssm_parameter" "cleanup_status" {
  name             = local.cleanup_status_parameter_name
  description      = "Subscription cleanup result keyed by Terraform cleanup request ID"
  type             = "String"
  value_wo         = "idle"
  value_wo_version = 1
}

# These shell libraries are rendered once and embedded unchanged in the bootstrap Command document and the
# cleanup operation. Kiro requests need a signing region independent from the infrastructure and Identity
# Center region.
locals {
  sigv4_post_shell = <<-EOT
    load_instance_credentials() {
      local imds_token role_name credentials
      imds_token=$(curl -sf --connect-timeout 2 --max-time 5 -X PUT http://169.254.169.254/latest/api/token \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 21600") || return 1
      role_name=$(curl -sf --connect-timeout 2 --max-time 5 \
        -H "X-aws-ec2-metadata-token: $imds_token" \
        http://169.254.169.254/latest/meta-data/iam/security-credentials/) || return 1
      credentials=$(curl -sf --connect-timeout 2 --max-time 5 \
        -H "X-aws-ec2-metadata-token: $imds_token" \
        "http://169.254.169.254/latest/meta-data/iam/security-credentials/$role_name") || return 1
      AWS_ACCESS_KEY_ID=$(printf '%s' "$credentials" | jq -er '.AccessKeyId | select(type == "string" and length > 0)') || return 1
      AWS_SECRET_ACCESS_KEY=$(printf '%s' "$credentials" | jq -er '.SecretAccessKey | select(type == "string" and length > 0)') || return 1
      AWS_SESSION_TOKEN=$(printf '%s' "$credentials" | jq -er '.Token | select(type == "string" and length > 0)') || return 1
      export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
    }

    hex_sha256() { printf '%s' "$1" | openssl dgst -sha256 -hex | sed 's/^.* //'; }
    hex_hmac() { printf '%s' "$2" | openssl dgst -sha256 -mac HMAC -macopt "$1" -hex | sed 's/^.* //'; }
    signed_post() {
      [ "$#" -eq 8 ] || { echo "signed_post requires service, signing_region, host, path, target, content_type, user_agent, and body" >&2; return 64; }
      local service=$1 signing_region=$2 host=$3 path=$4 target=$5 content_type=$6 user_agent=$7 body=$8
      local signed_headers="host;x-amz-content-sha256;x-amz-date;x-amz-security-token;x-amz-target;x-amz-user-agent"
      local timestamp datestamp payload_hash canonical_request scope string_to_sign k_date k_region k_service k_signing signature
      timestamp=$(date -u +%Y%m%dT%H%M%SZ)
      datestamp=$(printf '%s' "$timestamp" | cut -c1-8)
      payload_hash=$(hex_sha256 "$body")
      canonical_request=$(printf 'POST\n%s\n\nhost:%s\nx-amz-content-sha256:%s\nx-amz-date:%s\nx-amz-security-token:%s\nx-amz-target:%s\nx-amz-user-agent:%s\n\n%s\n%s' \
        "$path" "$host" "$payload_hash" "$timestamp" "$AWS_SESSION_TOKEN" "$target" "$user_agent" "$signed_headers" "$payload_hash")
      scope="$datestamp/$signing_region/$service/aws4_request"
      string_to_sign=$(printf 'AWS4-HMAC-SHA256\n%s\n%s\n%s' "$timestamp" "$scope" "$(hex_sha256 "$canonical_request")")
      k_date=$(hex_hmac "key:AWS4$AWS_SECRET_ACCESS_KEY" "$datestamp")
      k_region=$(hex_hmac "hexkey:$k_date" "$signing_region")
      k_service=$(hex_hmac "hexkey:$k_region" "$service")
      k_signing=$(hex_hmac "hexkey:$k_service" "aws4_request")
      signature=$(hex_hmac "hexkey:$k_signing" "$string_to_sign")
      curl -sS --fail-with-body --connect-timeout 10 --max-time 60 -X POST "https://$host$path" \
        -H "Host: $host" \
        -H "Content-Type: $content_type" \
        -H "X-Amz-User-Agent: $user_agent" \
        -H "X-Amz-Target: $target" \
        -H "X-Amz-Content-Sha256: $payload_hash" \
        -H "X-Amz-Date: $timestamp" \
        -H "X-Amz-Security-Token: $AWS_SESSION_TOKEN" \
        -H "Authorization: AWS4-HMAC-SHA256 Credential=$AWS_ACCESS_KEY_ID/$scope, SignedHeaders=$signed_headers, Signature=$signature" \
        --data-raw "$body"
    }
  EOT

  kiro_api_shell = <<-EOT
    KIRO_REGION='${var.kiro_region}'
    IDENTITY_CENTER_REGION='${var.aws_region}'
    IDENTITY_CENTER_INSTANCE_ARN='${var.identity_center_instance_arn}'
    KIRO_USER_ID='${var.user_id}'
    KIRO_SUBSCRIPTION_PLAN='${var.kiro_subscription_plan}'
    KIRO_PROFILE_NAME='KiroProfile-${var.kiro_region}'
    KIRO_PROFILE_HOST='codewhisperer.${var.kiro_region}.amazonaws.com'
    KIRO_SUBSCRIPTION_HOST='service.user-subscriptions.${var.aws_region}.amazonaws.com'
    KIRO_USER_AGENT='aws-sdk-js/2.1692.0 promise'
    KIRO_SUBSCRIPTION_USER_AGENT='aws-sdk-js/1.0.0 ua/2.0'

    kiro_list_profiles() {
      signed_post codewhisperer "$KIRO_REGION" "$KIRO_PROFILE_HOST" / \
        AWSCodeWhispererService.ListProfiles application/x-amz-json-1.0 "$KIRO_USER_AGENT" '{}'
    }

    kiro_create_profile() {
      local client_token body
      client_token=$(date -u +%s%N)
      body=$(jq -nc \
        --arg profileName "$KIRO_PROFILE_NAME" \
        --arg instanceArn "$IDENTITY_CENTER_INSTANCE_ARN" \
        --arg ssoRegion "$IDENTITY_CENTER_REGION" \
        --arg clientToken "$client_token" \
        '{
          profileName: $profileName,
          referenceTrackerConfiguration: {recommendationsWithReferences: "ALLOW"},
          activeFunctionalities: ["ANALYSIS", "CONVERSATIONS", "TASK_ASSIST", "TRANSFORMATIONS", "COMPLETIONS"],
          optInFeatures: {dashboardAnalytics: {toggle: "ON"}},
          identitySource: {ssoIdentitySource: {instanceArn: $instanceArn, ssoRegion: $ssoRegion}},
          clientToken: $clientToken
        }') || return 1
      signed_post codewhisperer "$KIRO_REGION" "$KIRO_PROFILE_HOST" / \
        AWSCodeWhispererService.CreateProfile application/x-amz-json-1.0 "$KIRO_USER_AGENT" "$body"
    }

    kiro_delete_profile() {
      local profile_arn=$1 body
      [ -n "$profile_arn" ] || return 1
      body=$(jq -nc --arg profileArn "$profile_arn" '{profileArn: $profileArn}') || return 1
      signed_post codewhisperer "$KIRO_REGION" "$KIRO_PROFILE_HOST" / \
        AWSCodeWhispererService.DeleteProfile application/x-amz-json-1.0 "$KIRO_USER_AGENT" "$body"
    }

    kiro_list_user_subscriptions() {
      local body
      # The workforce-subscription endpoint and signing scope belong to the Identity Center region, while
      # subscriptionRegion selects the Kiro profile/assignment region whose records should be returned.
      body=$(jq -nc \
        --arg instanceArn "$IDENTITY_CENTER_INSTANCE_ARN" \
        --arg subscriptionRegion "$KIRO_REGION" \
        '{instanceArn: $instanceArn, maxResults: 1000, subscriptionRegion: $subscriptionRegion}') || return 1
      signed_post user-subscriptions "$IDENTITY_CENTER_REGION" "$KIRO_SUBSCRIPTION_HOST" / \
        AWSZornControlPlaneService.ListUserSubscriptions application/x-amz-json-1.0 \
        "$KIRO_SUBSCRIPTION_USER_AGENT" "$body"
    }

    kiro_create_assignment() {
      local body
      body=$(jq -nc \
        --arg principalId "$KIRO_USER_ID" \
        --arg subscriptionType "$KIRO_SUBSCRIPTION_PLAN" \
        '{principalId: $principalId, principalType: "USER", subscriptionType: $subscriptionType}') || return 1
      signed_post q "$KIRO_REGION" "$KIRO_PROFILE_HOST" / \
        AmazonQDeveloperService.CreateAssignment application/x-amz-json-1.0 "$KIRO_USER_AGENT" "$body"
    }

    kiro_delete_assignment() {
      local body
      # DeleteAssignment identifies the assignment by principal; subscription_state proves the exact plan first.
      body=$(jq -nc --arg principalId "$KIRO_USER_ID" \
        '{principalId: $principalId, principalType: "USER"}') || return 1
      signed_post q "$KIRO_REGION" "$KIRO_PROFILE_HOST" / \
        AmazonQDeveloperService.DeleteAssignment application/x-amz-json-1.0 "$KIRO_USER_AGENT" "$body"
    }

    list_profiles_json() {
      local response
      if response=$(kiro_list_profiles 2>&1); then
        :
      else
        printf '%s\n' "$response" >&2
        return 2
      fi
      if ! printf '%s' "$response" | jq -e 'type == "object" and ((.profiles | type) == "array")' > /dev/null; then
        printf 'ListProfiles returned an invalid response: %s\n' "$response" >&2
        return 2
      fi
      printf '%s\n' "$response"
    }

    profile_state() {
      local profiles matches match_count profile_arn query_status
      if profiles=$(list_profiles_json); then
        :
      else
        query_status=$?
        return "$query_status"
      fi
      if matches=$(printf '%s' "$profiles" | jq -c \
        --arg instanceArn "$IDENTITY_CENTER_INSTANCE_ARN" \
        --arg ssoRegion "$IDENTITY_CENTER_REGION" \
        '[.profiles[] | select(
          .identityDetails.ssoIdentityDetails.instanceArn == $instanceArn and
          .identityDetails.ssoIdentityDetails.ssoRegion == $ssoRegion
        )]'); then
        :
      else
        printf 'could not query the exact Kiro profile\n' >&2
        return 2
      fi
      match_count=$(printf '%s' "$matches" | jq -r 'length') || return 2
      case "$match_count" in
        0) return 1 ;;
        1) ;;
        *) printf 'ListProfiles returned %s profiles for the exact Identity Center source\n' "$match_count" >&2; return 2 ;;
      esac
      profile_arn=$(printf '%s' "$matches" | jq -er '.[0].arn | select(type == "string" and length > 0)') || {
        printf 'the matching Kiro profile has no ARN\n' >&2
        return 2
      }
      printf '%s\n' "$profile_arn"
    }

    list_user_subscriptions_json() {
      local response
      if response=$(kiro_list_user_subscriptions 2>&1); then
        :
      else
        printf '%s\n' "$response" >&2
        return 2
      fi
      if ! printf '%s' "$response" | jq -e 'type == "object" and ((.subscriptions | type) == "array")' > /dev/null; then
        printf 'ListUserSubscriptions returned an invalid response: %s\n' "$response" >&2
        return 2
      fi
      printf '%s\n' "$response"
    }

    subscription_state() {
      local subscriptions query_status
      if subscriptions=$(list_user_subscriptions_json); then
        :
      else
        query_status=$?
        return "$query_status"
      fi
      if printf '%s' "$subscriptions" | jq -e \
        --arg userId "$KIRO_USER_ID" \
        --arg plan "$KIRO_SUBSCRIPTION_PLAN" \
        '($plan | sub("^Q_DEVELOPER_STANDALONE_"; "KIRO_ENTERPRISE_")) as $observedPlan |
        any(.subscriptions[];
          .principal.user == $userId and
          (.type.amazonQ == $plan or .type.amazonQ == $observedPlan) and
          ((.status | type) == "string") and
          .status != "CANCELLED"
        )' > /dev/null; then
        return 0
      else
        query_status=$?
        if [ "$query_status" -eq 1 ]; then return 1; fi
        printf 'could not query the exact Kiro user subscription\n' >&2
        return 2
      fi
    }

    user_active_q_subscription_count() {
      local subscriptions count query_status
      if subscriptions=$(list_user_subscriptions_json); then
        :
      else
        query_status=$?
        return "$query_status"
      fi
      count=$(printf '%s' "$subscriptions" | jq -er \
        --arg userId "$KIRO_USER_ID" \
        '[.subscriptions[] | select(
          .principal.user == $userId and
          ((.status | type) == "string") and
          .status != "CANCELLED" and
          ((.type.amazonQ | type) == "string") and
          ((.type.amazonQ | startswith("Q_")) or (.type.amazonQ | startswith("KIRO_ENTERPRISE_")))
        )] | length') || return 2
      printf '%s\n' "$count"
    }

    active_q_subscription_count() {
      local subscriptions count query_status
      if subscriptions=$(list_user_subscriptions_json); then
        :
      else
        query_status=$?
        return "$query_status"
      fi
      count=$(printf '%s' "$subscriptions" | jq -er \
        '[.subscriptions[] | select(
          ((.status | type) == "string") and
          .status != "CANCELLED" and
          ((.type.amazonQ | type) == "string") and
          ((.type.amazonQ | startswith("Q_")) or (.type.amazonQ | startswith("KIRO_ENTERPRISE_")))
        )] | length') || return 2
      printf '%s\n' "$count"
    }
  EOT
}

# Self-contained cleanup is embedded directly in its SSM Association command. This keeps recovery independent
# of the bootstrap document and of ephemeral files under /run if a later bootstrap update fails.
locals {
  kiro_cleanup_script = <<-EOT
    #!/bin/bash
    set -Eeuo pipefail
    export AWS_DEFAULT_REGION='${var.aws_region}'
    ATTEMPTS=${var.subscribe_attempts}
    PROFILE_OWNERSHIP_PARAMETER='${local.profile_ownership_parameter_name}'
    SUBSCRIPTION_OWNERSHIP_PARAMETER='${local.subscription_ownership_parameter_name}'
    log() { echo "[kiro-cleanup] $1"; }
    read_ownership() { aws ssm get-parameter --region ${var.aws_region} --name "$1" --query Parameter.Value --output text; }
    write_ownership() { aws ssm put-parameter --region ${var.aws_region} --name "$1" --type String --value "$2" --overwrite > /dev/null; }

    ${local.sigv4_post_shell}

    ${local.kiro_api_shell}

    subscription_ownership=$(read_ownership "$SUBSCRIPTION_OWNERSHIP_PARAMETER")
    profile_ownership=$(read_ownership "$PROFILE_OWNERSHIP_PARAMETER")
    if [[ "$subscription_ownership" != "creating" && "$subscription_ownership" != "created" && "$profile_ownership" != "creating" && "$profile_ownership" != "created" ]]; then
      log "no state-external Kiro object is owned by this root"
      exit 0
    fi
    load_instance_credentials || { log "could not load instance role credentials"; exit 1; }

    if [[ "$subscription_ownership" == "creating" || "$subscription_ownership" == "created" ]]; then
      subscription_removed=false
      if subscription_state > /dev/null; then
        for attempt in $(seq 1 "$ATTEMPTS"); do
          log "unsubscribe attempt $attempt of $ATTEMPTS for $KIRO_USER_ID and $KIRO_SUBSCRIPTION_PLAN"
          kiro_delete_assignment || true
          sleep 5
          if subscription_state > /dev/null; then
            log "the exact subscription is still active"
          else
            state_status=$?
            if [ "$state_status" -eq 1 ]; then
              subscription_removed=true
              break
            fi
            log "subscription observation failed"
          fi
        done
      else
        state_status=$?
        if [ "$state_status" -eq 1 ]; then
          subscription_removed=true
        else
          log "could not query the exact subscription before cleanup"
          exit 1
        fi
      fi
      [ "$subscription_removed" = true ] || { log "could not verify exact subscription removal"; exit 1; }
      write_ownership "$SUBSCRIPTION_OWNERSHIP_PARAMETER" removed
    else
      log "subscription predated this root or was already removed; preserving it"
    fi

    if [[ "$profile_ownership" != "creating" && "$profile_ownership" != "created" ]]; then
      log "profile predated this root or was already removed; preserving it"
      exit 0
    fi

    if profile_arn=$(profile_state); then
      :
    else
      state_status=$?
      if [ "$state_status" -eq 1 ]; then
        write_ownership "$PROFILE_OWNERSHIP_PARAMETER" removed
        log "the exact profile is already absent"
        exit 0
      fi
      log "could not query the exact profile before cleanup"
      exit 1
    fi

    if active_count=$(active_q_subscription_count); then
      :
    else
      log "could not count active Q subscriptions"
      exit 1
    fi
    if [ "$active_count" -gt 0 ]; then
      log "preserving the profile because $active_count active Q subscription(s) remain"
      exit 0
    fi

    profile_removed=false
    for attempt in $(seq 1 "$ATTEMPTS"); do
      log "profile delete attempt $attempt of $ATTEMPTS for the exact Identity Center source"
      kiro_delete_profile "$profile_arn" || true
      sleep 5
      if profile_arn=$(profile_state); then
        log "the exact profile is still present"
      else
        state_status=$?
        if [ "$state_status" -eq 1 ]; then
          profile_removed=true
          break
        fi
        log "profile observation failed"
      fi
    done
    [ "$profile_removed" = true ] || { log "could not verify exact profile removal"; exit 1; }
    write_ownership "$PROFILE_OWNERSHIP_PARAMETER" removed
    log "subscription cleanup complete"
  EOT
}

locals {
  # No set -x: credentials and the OTP are not written to SSM command output. The SigV4 helper still passes
  # credentials in transient local process arguments, which is why this host has no inbound path and is
  # stopped immediately after verification. The ERR trap records unexpected failures at their source line.
  bootstrap_script = <<-EOT
    #!/bin/bash
    set -Eeuo pipefail
    export HOME=/root
    # Files under /run are same-boot diagnostics only; SSM Parameter Store carries durable coordination.
    MARKER_DIR=${local.marker_file_path}
    OTP_INPUT="$MARKER_DIR/password-input.json"
    INSTANCE_ID=$(tr -d '[:space:]' < /var/lib/cloud/data/instance-id 2>/dev/null || true)
    mkdir -p "$MARKER_DIR"
    chmod 700 "$MARKER_DIR"
    rm -f "$MARKER_DIR/bootstrap" "$MARKER_DIR/failed" "$MARKER_DIR/subscription" "$OTP_INPUT"
    log() { echo "[kiro-bootstrap] $1"; }
    record_status() {
      value=$1
      for attempt in 1 2 3 4 5 6 7 8 9 10 11 12; do
        if output=$(aws ssm put-parameter --region ${var.aws_region} --name '${local.bootstrap_status_parameter_name}' --type String --value "$value" --overwrite --cli-connect-timeout 5 --cli-read-timeout 10 2>&1); then
          return 0
        fi
        log "status write attempt $attempt failed: $output"
        sleep 5
      done
      return 1
    }
    on_error() {
      status=$?
      line=$1
      trap - ERR
      rm -f "$OTP_INPUT"
      if [ ! -f "$MARKER_DIR/failed" ]; then
        echo "unexpected failure at bootstrap command line $line" > "$MARKER_DIR/failed"
      fi
      if [ -n "$INSTANCE_ID" ]; then
        record_status "failed:$INSTANCE_ID:unexpected bootstrap command failure at line $line" || log "could not record failed status"
      fi
      exit "$status"
    }
    trap 'on_error $LINENO' ERR
    fail() {
      log "FAILED: $1"
      echo "$1" > "$MARKER_DIR/failed"
      rm -f "$OTP_INPUT"
      if [ -n "$INSTANCE_ID" ]; then
        record_status "failed:$INSTANCE_ID:$1" || log "could not record failed status"
      fi
      trap - ERR
      exit 1
    }

    # Establish the instance identity and remote diagnostic channel before any package/network work. AWS CLI
    # uses the IMDS credential provider here and can retry while the instance profile becomes available.
    IMDS_TOKEN=$(curl -sf --connect-timeout 2 --max-time 5 -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 21600") || fail "no IMDSv2 token"
    imds() { curl -sf --connect-timeout 2 --max-time 5 -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" "http://169.254.169.254/latest/meta-data/$1"; }
    case "$INSTANCE_ID" in
      i-*) ;;
      *) INSTANCE_ID=$(imds instance-id) || fail "could not read the EC2 instance ID" ;;
    esac
    record_status "running:$INSTANCE_ID" || fail "could not record bootstrap running status"

    timeout 300 dnf install -yq jq openssl || fail "dnf could not install jq and openssl within 300 seconds"

    # Credentials for hand-signed requests. The reusable signer receives its service and signing region for
    # every call, so Identity Center remains in aws_region while Kiro endpoints use kiro_region.
    AWS_DEFAULT_REGION=$(imds placement/region) || fail "could not read the instance region"
    [ "$AWS_DEFAULT_REGION" = '${var.aws_region}' ] || fail "the instance region does not match aws_region"
    export AWS_DEFAULT_REGION

    ${local.sigv4_post_shell}

    ${local.kiro_api_shell}

    load_instance_credentials || fail "could not load instance role credentials"
    aws sts get-caller-identity --region ${var.aws_region} --query Arn --output text > /dev/null \
      || fail "the instance role credentials do not work"

    read_ownership() {
      aws ssm get-parameter --region ${var.aws_region} --name "$1" --query Parameter.Value --output text
    }
    write_ownership() {
      aws ssm put-parameter --region ${var.aws_region} --name "$1" --type String --value "$2" --overwrite > /dev/null
    }

    %{if var.disable_mfa~}
    log "disabling MFA for the entire IAM Identity Center instance"
    signed_post sso '${var.aws_region}' 'sso.${var.aws_region}.amazonaws.com' /control/ \
      SWBService.UpdateSsoConfiguration application/x-amz-json-1.1 'aws-sdk-js/2.1467.0 promise' \
      '{"instanceArn":"${var.identity_center_instance_arn}","configurationType":"APP_AUTHENTICATION_CONFIGURATION","ssoConfiguration":{"mfaMode":"DISABLED"}}' > /dev/null \
      || fail "UpdateSsoConfiguration was rejected"
    %{else~}
    log "preserving the current IAM Identity Center MFA mode"
    %{endif~}

    log "issuing a one-time password for user ${var.user_id}"
    OTP_RESPONSE=$(signed_post userpool '${var.aws_region}' 'identitystore.${var.aws_region}.amazonaws.com' / \
      SWBUPService.UpdatePassword application/x-amz-json-1.0 'aws-sdk-js/2.1467.0 promise' \
      '{"UserId":"${var.user_id}","PasswordMode":"OTP"}') || fail "UpdatePassword was rejected"
    OTP=$(echo "$OTP_RESPONSE" | jq -er '.Password | select(length > 0)') || fail "UpdatePassword returned no password"
    umask 077
    printf '%s' "$OTP" | jq -Rs --arg name "${var.password_parameter_name}" \
      '{Name:$name,Type:"SecureString",Value:.,Overwrite:true}' > "$OTP_INPUT"
    unset OTP OTP_RESPONSE
    aws ssm put-parameter --cli-input-json "file://$OTP_INPUT" > /dev/null \
      || fail "could not write the password to ${var.password_parameter_name}"
    rm -f "$OTP_INPUT"

    # Keep a local diagnostic copy, but the cleanup Association embeds the same self-contained script and
    # never depends on ephemeral instance files for recovery.
    printf '%s' '${base64gzip(local.kiro_cleanup_script)}' | base64 -d | gzip -d > /usr/local/sbin/kiro-cleanup
    chmod 0755 /usr/local/sbin/kiro-cleanup

    %{if var.create_kiro_subscription~}
    profile_ownership=$(read_ownership '${local.profile_ownership_parameter_name}') || fail "could not read profile ownership"
    profile_ready=false
    if profile_arn=$(profile_state); then
      profile_ready=true
      case "$profile_ownership" in
        creating|created) write_ownership '${local.profile_ownership_parameter_name}' created ;;
        *) write_ownership '${local.profile_ownership_parameter_name}' preexisting ;;
      esac
      log "using the profile with the exact Identity Center instance and region"
    else
      profile_state_status=$?
      [ "$profile_state_status" -eq 1 ] || fail "could not observe the exact Kiro profile"
      write_ownership '${local.profile_ownership_parameter_name}' creating || fail "could not record profile ownership intent"
      for attempt in $(seq 1 ${var.subscribe_attempts}); do
        log "profile create attempt $attempt of ${var.subscribe_attempts}"
        kiro_create_profile || true
        sleep 5
        if profile_arn=$(profile_state); then
          profile_ready=true
          write_ownership '${local.profile_ownership_parameter_name}' created || fail "could not record profile ownership"
          break
        else
          profile_state_status=$?
          if [ "$profile_state_status" -eq 2 ]; then log "profile observation failed after create attempt $attempt"; fi
        fi
      done
    fi
    [ "$profile_ready" = true ] || fail "could not verify exact Kiro profile creation"

    # Profile discovery can precede assignment readiness.
    sleep 20
    subscription_ownership=$(read_ownership '${local.subscription_ownership_parameter_name}') || fail "could not read subscription ownership"
    subscription_ready=false
    if subscription_state; then
      subscription_ready=true
      case "$subscription_ownership" in
        creating|created) write_ownership '${local.subscription_ownership_parameter_name}' created ;;
        *) write_ownership '${local.subscription_ownership_parameter_name}' preexisting ;;
      esac
      log "using the observed exact user and plan subscription"
    else
      subscription_state_status=$?
      [ "$subscription_state_status" -eq 1 ] || fail "could not query the exact Kiro subscription"
      if active_count=$(user_active_q_subscription_count); then
        [ "$active_count" -eq 0 ] || fail "the user already has an active Q subscription with a different plan"
      else
        fail "could not query existing Kiro subscriptions"
      fi
      write_ownership '${local.subscription_ownership_parameter_name}' creating || fail "could not record subscription ownership intent"
      for attempt in $(seq 1 ${var.subscribe_attempts}); do
        log "subscribe attempt $attempt of ${var.subscribe_attempts} for $KIRO_USER_ID and $KIRO_SUBSCRIPTION_PLAN"
        kiro_create_assignment || true
        sleep 5
        if subscription_state; then
          subscription_ready=true
          write_ownership '${local.subscription_ownership_parameter_name}' created || fail "could not record subscription ownership"
          break
        else
          subscription_state_status=$?
          if [ "$subscription_state_status" -eq 2 ]; then log "subscription observation failed after create attempt $attempt"; fi
        fi
      done
    fi
    [ "$subscription_ready" = true ] || fail "could not observe the requested exact Kiro subscription"
    touch "$MARKER_DIR/subscription"
    %{else~}
    log "skipping the billed Kiro profile and subscription"
    %{endif~}

    touch "$MARKER_DIR/bootstrap"
    record_status "success:$INSTANCE_ID" || fail "could not record bootstrap success status"
    trap - ERR
    log "done"
  EOT

  bootstrap_document_content = jsonencode({
    schemaVersion = "2.2"
    description   = "Runs the one-shot Kiro bootstrap and records durable completion status"
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "bootstrap"
      inputs = {
        timeoutSeconds = tostring(var.bootstrap_timeout_seconds)
        runCommand     = [local.bootstrap_script]
      }
    }]
  })
  bootstrap_document_content_base64 = base64encode(local.bootstrap_document_content)
  bootstrap_document_content_size_bytes = (
    floor(length(local.bootstrap_document_content_base64) * 3 / 4) -
    length(regexall("=", local.bootstrap_document_content_base64))
  )
  bootstrap_document_content_sha256 = sha256(local.bootstrap_document_content)

  # The heavy bootstrap stays in the 64 KiB SSM Command document. This small launcher remains far below the
  # 16 KiB EC2 user-data limit; embedding the document digest preserves replacement-on-bootstrap-change.
  minimal_user_data = <<-EOT
    #!/bin/bash
    set -e
    # Kiro bootstrap SSM document content SHA256: ${local.bootstrap_document_content_sha256}
    echo "[kiro-bootstrap-launcher] document content SHA256: ${local.bootstrap_document_content_sha256}"
    systemctl enable --now amazon-ssm-agent
  EOT
}

resource "aws_ssm_document" "bootstrap" {
  name            = "kiro-${replace(replace(var.name, ".", "-"), "_", "-")}-bootstrap"
  document_type   = "Command"
  document_format = "JSON"
  content         = local.bootstrap_document_content

  lifecycle {
    precondition {
      condition     = local.bootstrap_document_content_size_bytes <= 65536
      error_message = "The serialized bootstrap Command document must not exceed 65536 UTF-8 bytes."
    }
  }
}

resource "aws_instance" "bootstrap" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  iam_instance_profile        = aws_iam_instance_profile.bootstrap.name
  subnet_id                   = var.subnet_id
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.bootstrap.id]

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  user_data                   = local.minimal_user_data
  user_data_replace_on_change = true

  tags = {
    Name = var.name
  }

  # The agent can receive the bootstrap operation as soon as the host registers, so its document, policies,
  # parameters, and outbound path must all exist before EC2 starts.
  depends_on = [
    aws_ssm_document.bootstrap,
    aws_iam_role_policy_attachment.bootstrap,
    aws_iam_role_policy.kiro,
    aws_ssm_parameter.password,
    aws_ssm_parameter.profile_ownership,
    aws_ssm_parameter.subscription_ownership,
    aws_ssm_parameter.bootstrap_status,
    aws_ssm_parameter.cleanup_status,
    aws_vpc_security_group_egress_rule.all_outbound,
  ]
}

# This existing Association address now executes the custom bootstrap Command document. The document writes
# instance-specific success or failure status; the Terraform-side waiter below verifies the password and is
# the actual completion barrier before stop and password output.
resource "aws_ssm_association" "bootstrap_complete" {
  name                             = aws_ssm_document.bootstrap.name
  document_version                 = aws_ssm_document.bootstrap.latest_version
  association_name                 = "${var.name}-${aws_instance.bootstrap.id}-complete"
  wait_for_success_timeout_seconds = var.bootstrap_timeout_seconds

  targets {
    key    = "InstanceIds"
    values = [aws_instance.bootstrap.id]
  }
}

# Provider Association waiters can return before target commands complete. This Terraform-side waiter polls
# the instance-specific `success` status written by the custom document, verifies the SecureString password,
# and promotes the status to `verified`; it is the actual barrier before stop and password output.
resource "terraform_data" "bootstrap_completion_wait" {
  input            = aws_instance.bootstrap.id
  triggers_replace = [aws_instance.bootstrap.id]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      export MSYS2_ARG_CONV_EXCL='*'
      export MSYS2_ENV_CONV_EXCL='AWS_ACCESS_KEY_ID;AWS_SECRET_ACCESS_KEY;AWS_SESSION_TOKEN'
      export AWS_PAGER=''
      REGION='${var.aws_region}'
      INSTANCE_ID='${aws_instance.bootstrap.id}'
      ASSOCIATION_ID='${aws_ssm_association.bootstrap_complete.id}'
      STATUS_PARAMETER='${aws_ssm_parameter.bootstrap_status.name}'
      PASSWORD_PARAMETER='${aws_ssm_parameter.password.name}'
      PASSWORD_PLACEHOLDER='${local.password_placeholder}'
      LAST_STATUS=''
      waited=0
      while true; do
        if ! STATUS=$(aws ssm get-parameter --region "$REGION" --name "$STATUS_PARAMETER" --query Parameter.Value --output text --cli-connect-timeout 5 --cli-read-timeout 10 2>&1); then
          echo "could not read bootstrap status $STATUS_PARAMETER: $STATUS" >&2
          exit 1
        fi
        if [ "$STATUS" != "$LAST_STATUS" ]; then
          echo "bootstrap status: $STATUS"
          LAST_STATUS=$STATUS
        fi
        # Recovery path when the document operation completed but the runner has not yet written verified.
        # Custom-document success is terminal; re-check the password from the runner before promoting it.
        if [ "$STATUS" = "success:$INSTANCE_ID" ]; then
          if ! PASSWORD=$(aws ssm get-parameter --region "$REGION" --name "$PASSWORD_PARAMETER" --with-decryption --query Parameter.Value --output text --cli-connect-timeout 5 --cli-read-timeout 10 2>&1); then
            echo "could not verify bootstrap password $PASSWORD_PARAMETER: $PASSWORD" >&2
            exit 1
          fi
          if [ -z "$PASSWORD" ] || [ "$PASSWORD" = "$PASSWORD_PLACEHOLDER" ]; then
            echo "bootstrap reported success but $PASSWORD_PARAMETER has no issued password" >&2
            exit 1
          fi
          unset PASSWORD
          if ! aws ssm put-parameter --region "$REGION" --name "$STATUS_PARAMETER" --type String --value "verified:$INSTANCE_ID" --overwrite > /dev/null; then
            echo "could not promote bootstrap status to verified for $INSTANCE_ID" >&2
            exit 1
          fi
          STATUS="verified:$INSTANCE_ID"
        fi
        if [ "$STATUS" = "verified:$INSTANCE_ID" ]; then exit 0; fi
        case "$STATUS" in
          failed:$INSTANCE_ID:*) echo "$STATUS" >&2; exit 1 ;;
        esac
        waited=$((waited + 10))
        if [ "$waited" -ge ${var.bootstrap_timeout_seconds} ]; then
          echo "bootstrap for $INSTANCE_ID was not verified within ${var.bootstrap_timeout_seconds} seconds; last status: $STATUS" >&2
          echo "inspect: aws ssm describe-association-executions --region $REGION --association-id $ASSOCIATION_ID" >&2
          exit 1
        fi
        sleep 10
      done
    EOT
  }

  depends_on = [aws_ssm_association.bootstrap_complete]
}

# The normal apply ends with a stopped instance. A non-null cleanup generation changes the same state
# resource to running. The generation is not part of the bootstrap document or minimal user-data digest, so
# later teardown generations do not replace the EC2 instance or issue another OTP.
resource "aws_ec2_instance_state" "bootstrap" {
  count = var.stop_after_bootstrap || var.subscription_cleanup_generation != null ? 1 : 0

  instance_id = aws_instance.bootstrap.id
  state       = var.subscription_cleanup_generation != null ? "running" : "stopped"

  depends_on = [terraform_data.bootstrap_completion_wait]
}

# Each changed generation replaces this request carrier and yields a new ID. Association parameters and the
# completion status therefore cannot mistake an old successful generation for the current execution.
resource "terraform_data" "subscription_cleanup_request" {
  count = var.subscription_cleanup_generation != null ? 1 : 0

  input            = var.subscription_cleanup_generation
  triggers_replace = [var.subscription_cleanup_generation]
}

# Terraform-managed replacement for the former imperative cleanup command. State Manager may return from an
# association update early, so this action writes an exact request ID to an SSM status parameter and the
# following terraform_data waiter supplies the apply-time completion barrier.
resource "aws_ssm_association" "subscription_cleanup" {
  count = var.subscription_cleanup_generation != null ? 1 : 0

  name                             = "AWS-RunShellScript"
  association_name                 = "${var.name}-${aws_instance.bootstrap.id}-subscription-cleanup"
  wait_for_success_timeout_seconds = var.subscription_cleanup_timeout_seconds

  targets {
    key    = "InstanceIds"
    values = [aws_instance.bootstrap.id]
  }

  parameters = {
    commands = <<-EOT
      set -uo pipefail
      REQUEST_ID='${terraform_data.subscription_cleanup_request[0].id}'
      STATUS_PARAMETER='${aws_ssm_parameter.cleanup_status.name}'
      aws ssm put-parameter --region ${var.aws_region} --name "$STATUS_PARAMETER" --type String --value "running:$REQUEST_ID" --overwrite > /dev/null
      if (printf '%s' '${base64gzip(local.kiro_cleanup_script)}' | base64 -d | gzip -d > /tmp/kiro-cleanup && chmod 0700 /tmp/kiro-cleanup && /tmp/kiro-cleanup); then
        aws ssm put-parameter --region ${var.aws_region} --name "$STATUS_PARAMETER" --type String --value "success:$REQUEST_ID" --overwrite > /dev/null
      else
        status=$?
        aws ssm put-parameter --region ${var.aws_region} --name "$STATUS_PARAMETER" --type String --value "failed:$REQUEST_ID:$status" --overwrite > /dev/null || true
        exit "$status"
      fi
    EOT
  }

  depends_on = [
    aws_ec2_instance_state.bootstrap,
    terraform_data.subscription_cleanup_request,
  ]
}

resource "terraform_data" "subscription_cleanup_wait" {
  count = var.subscription_cleanup_generation != null ? 1 : 0

  input            = terraform_data.subscription_cleanup_request[0].id
  triggers_replace = [terraform_data.subscription_cleanup_request[0].id]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      export MSYS2_ARG_CONV_EXCL='*'
      export MSYS2_ENV_CONV_EXCL='AWS_ACCESS_KEY_ID;AWS_SECRET_ACCESS_KEY;AWS_SESSION_TOKEN'
      export AWS_PAGER=''
      REGION='${var.aws_region}'
      REQUEST_ID='${terraform_data.subscription_cleanup_request[0].id}'
      STATUS_PARAMETER='${aws_ssm_parameter.cleanup_status.name}'
      LAST_STATUS=''
      waited=0
      while true; do
        if ! STATUS=$(aws ssm get-parameter --region "$REGION" --name "$STATUS_PARAMETER" --query Parameter.Value --output text --cli-connect-timeout 5 --cli-read-timeout 10 2>&1); then
          echo "could not read cleanup status $STATUS_PARAMETER: $STATUS" >&2
          exit 1
        fi
        if [ "$STATUS" != "$LAST_STATUS" ]; then
          echo "cleanup status: $STATUS"
          LAST_STATUS=$STATUS
        fi
        if [ "$STATUS" = "success:$REQUEST_ID" ]; then exit 0; fi
        case "$STATUS" in
          failed:$REQUEST_ID:*) echo "$STATUS" >&2; exit 1 ;;
        esac
        waited=$((waited + 10))
        if [ "$waited" -ge ${var.subscription_cleanup_timeout_seconds} ]; then
          echo "subscription cleanup request $REQUEST_ID did not finish within ${var.subscription_cleanup_timeout_seconds} seconds; last status: $STATUS" >&2
          exit 1
        fi
        sleep 10
      done
    EOT
  }

  depends_on = [aws_ssm_association.subscription_cleanup]
}
