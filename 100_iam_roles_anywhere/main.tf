data "aws_region" "current" {}
# The AMI id for the export instance, from the public parameter AWS maintains per release.
#
# insecure_value rather than value: the provider marks a parameter's value sensitive whatever its
# type, and a sensitive value cannot be used as an instance's ami without nonsensitive(). A public
# AMI id is not a secret, and insecure_value is the provider's own accessor for that case.
#
# In the root rather than in the module, so the module takes an ami- id and does not have to know
# where it came from (rules.md B-6) - and so the read is not inside a module carrying depends_on,
# which would defer it to apply (rules.md D-6).
data "aws_ssm_parameter" "amazon_linux2023_ami_id" {
  name = var.amazon_linux2023_ami_parameter_name
}
# The terminator Lambda's deployment package.
#
# This one is in the root because it has to be, for two independent reasons. archive_file resolves
# source_file against path.module, and the Python lives at the root of the project - a copy of this
# data source inside modules/instance_terminator_lambda would look for
# modules/instance_terminator_lambda/lambda_src and fail with "no file or directory". And a module
# that carries depends_on has every data source inside it deferred to apply, which would make
# output_base64sha256 unknown at plan and the function's source_code_hash a "known after apply"
# that explains nothing (rules.md D-6).
#
# The zip is written into build/ as a side effect of reading this, which is why that directory
# exists in the repository and why nothing should be edited in it.
data "archive_file" "instance_terminator" {
  type        = "zip"
  source_file = "${path.module}/${var.lambda_source_relative_path}"
  output_path = "${path.module}/${var.lambda_build_relative_path}"
}
module "network" {
  source = "./modules/network"

  vpc_cidr_block          = var.vpc_cidr_block
  vpc_name                = var.vpc_name
  internet_gateway_name   = var.internet_gateway_name
  public_subnet_name      = var.public_subnet_name
  public_route_table_name = var.public_route_table_name
}
module "artifact_bucket" {
  source = "./modules/artifact_bucket"

  bucket_prefix = var.artifact_bucket_prefix
  force_destroy = var.artifact_bucket_force_destroy

  # Uses nothing from network, and does not need a VPC to create a bucket. It waits anyway: the
  # rule is that a root with a network module has no module starting before that module finishes,
  # and an exception here would leave the next reader deciding per module whether the omission was
  # reasoned or forgotten (rules.md D-3).
  depends_on = [module.network]
}
module "private_certificate_authority" {
  source = "./modules/private_certificate_authority"

  key_storage_security_standard   = var.ca_key_storage_security_standard
  key_algorithm                   = var.ca_key_algorithm
  signing_algorithm               = var.ca_signing_algorithm
  subject_organization            = var.ca_subject_organization
  subject_organizational_unit     = var.ca_subject_organizational_unit
  subject_country                 = var.ca_subject_country
  certificate_validity_value      = var.ca_certificate_validity_years
  permanent_deletion_time_in_days = var.ca_permanent_deletion_time_in_days

  # Nothing in a certificate authority touches the VPC. Same reasoning as the bucket above
  # (rules.md D-3).
  depends_on = [module.network]
}
module "client_certificate" {
  source = "./modules/client_certificate"

  certificate_authority_arn = module.private_certificate_authority.certificate_authority_arn
  domain_name               = var.certificate_domain_name
  key_algorithm             = var.certificate_key_algorithm

  # Two preconditions, and the value reference above expresses neither of them.
  #
  # The CA has to be ACTIVE. A newly created certificate authority is PENDING_CERTIFICATE and can
  # sign nothing, and certificate_authority_arn orders this only against the resource that
  # produced the ARN - the empty CA - not against the certificate import that activates it.
  #
  # ACM has to have been granted IssueCertificate on that CA. ACM, not the operator, makes the
  # call, and the grant is a separate resource in the same module. Without it the request fails
  # with a ValidationException about ACM not being authorized, which reads like a problem with this
  # resource.
  #
  # Pointing at the whole module covers both, which is what a module-level depends_on is for
  # (rules.md D-2). It also reaches network through that module, which is what D-3 asks for.
  depends_on = [module.private_certificate_authority]
}
module "roles_anywhere_profile" {
  source = "./modules/roles_anywhere_profile"

  certificate_authority_arn = module.private_certificate_authority.certificate_authority_arn
  trust_anchor_name         = var.trust_anchor_name
  profile_name              = var.profile_name
  session_duration_seconds  = var.session_duration_seconds
  role_policy_arns          = var.vended_role_policy_arns

  # Creating a trust anchor makes IAM Roles Anywhere read the CA's certificate, and a CA Terraform
  # has just created is PENDING_CERTIFICATE and has none. The read fails, reported as
  #
  #   ValidationException: Error creating TrustAnchor. Given AWS PCA did not allow get request.
  #
  # which reads like a permissions problem and is not one - the same CreateTrustAnchor call against
  # the same CA succeeds first time once it is ACTIVE. As above, the ARN reference orders this
  # against the empty CA rather than against its activation, so the ordering has to be stated
  # (rules.md D-2).
  depends_on = [module.private_certificate_authority]
}
module "certificate_export_ec2" {
  source = "./modules/certificate_export_ec2"

  vpc_id    = module.network.vpc_id
  subnet_id = module.network.public_subnet_id
  ami_id    = data.aws_ssm_parameter.amazon_linux2023_ami_id.insecure_value

  certificate_arn      = module.client_certificate.certificate_arn
  artifact_bucket_name = module.artifact_bucket.bucket_name
  artifact_bucket_arn  = module.artifact_bucket.bucket_arn

  instance_type              = var.bastion_instance_type
  instance_name              = var.bastion_instance_name
  security_group_name        = var.bastion_security_group_name
  security_group_description = var.bastion_security_group_description
  iam_policy_arns            = var.bastion_iam_policy_arns
  install_development_tools  = var.bastion_install_development_tools
  passphrase                 = var.passphrase

  # vpc_id and subnet_id order this after the VPC and that one subnet, and after nothing else in
  # the network module - the route to the internet gateway is exactly what that misses. cloud-init
  # starts calling ACM within seconds of the launch, and with no route out those calls hang until
  # they time out, so nothing is uploaded and the apply fails minutes later at the terminator's
  # wait below with nothing pointing at the network (rules.md D-3).
  #
  # The other two are real preconditions rather than tidiness: the bootstrap exports
  # certificate_arn and uploads into artifact_bucket_name, and both of those are also named in the
  # inline IAM policy the module writes (rules.md D-2).
  depends_on = [module.network, module.artifact_bucket, module.client_certificate]
}
# Waits until the export is in S3, then terminates the export instance - both inside one
# synchronous Lambda invocation, so the apply is held open for the whole bootstrap.
#
# This is the half of the CloudFormation CreationPolicy the conversion dropped. depends_on against
# the instance is satisfied the moment EC2 reports it running, which on this AMI is minutes before
# cloud-init finishes, so something has to stand between the launch and the terminate call.
#
# That used to be an aws_ssm_association with wait_for_success_timeout_seconds, polling a marker
# file and running head-object on the four keys. It did not hold, and the apply still ended green
# with an empty bucket. From CloudTrail and the association's own history, 2026-10-08 (KST):
#
#   20:38:10  RunInstances                 export instance launched
#   20:38:22  CreateAssociation            the provider starts polling DescribeAssociation
#   20:38:28  last DescribeAssociation     overview status read Success - the waiter returns
#   20:38:33  association command sent     5 seconds AFTER the "Success" the waiter accepted
#   20:38:44  Lambda invoked
#   20:38:49  TerminateInstances           39 seconds after launch, long before the bootstrap ends
#
#   20:43:05  RunInstances                 next apply: the terminated instance is recreated
#   20:43:17  UpdateAssociation            new target; the provider does not wait on update at all
#   20:43:17  Lambda invoked, terminate    12 seconds after launch
#
# Both executions ended Failed/Undeliverable, and neither failure reached Terraform. The first is
# the provider issue rules.md D-5 warns about - the overview status reflects the association before
# its first run - and the second is the provider's update path, which never calls the waiter. The
# marker file and until loop were correct; the problem was that nothing ordered after the
# association actually waited for them.
#
# So the wait is now in the function that does the irreversible thing: it lists the bucket until
# every exported key is there with a LastModified newer than the instance's launch, and terminates
# only then. It raises at its timeout instead, leaving the instance running for diagnosis. It
# needs nothing from the instance - no marker file, no SSM agent - so the marker is gone and the
# instance's SSM policy is kept only for opening a session when something fails.
#
# Wired here, because it combines three modules' outputs - the instance to terminate, the bucket
# to watch, and the keys to wait for - and combining modules is the root's job (rules.md C-1).
module "instance_terminator_lambda" {
  source = "./modules/instance_terminator_lambda"

  function_name    = "${var.stack_name}-${var.lambda_function_name_suffix}"
  filename         = data.archive_file.instance_terminator.output_path
  source_code_hash = data.archive_file.instance_terminator.output_base64sha256
  instance_ids     = [module.certificate_export_ec2.instance_id]

  # What the function waits for before it terminates. The key list is the one the bootstrap
  # writes, taken from the module that writes it (rules.md B-5).
  wait_bucket_name = module.artifact_bucket.bucket_name
  wait_bucket_arn  = module.artifact_bucket.bucket_arn
  wait_object_keys = values(module.certificate_export_ec2.exported_object_keys)

  handler = var.lambda_handler
  runtime = var.lambda_runtime
  # The export timeout is the function's timeout rather than a second number that has to agree
  # with it: the invocation is the wait, so the two cannot mean different things (rules.md B-1).
  timeout_seconds = var.bastion_export_timeout_seconds
  policy_actions  = var.lambda_policy_actions
  iam_policy_arns = var.lambda_iam_policy_arns

  # instance_ids already orders this after the instance. The module edge is kept for the rest of
  # the export module - the instance's role and policies - and it is how this module reaches
  # network, which is what D-3 asks for. The bucket arrives through the values above.
  depends_on = [module.certificate_export_ec2]
}
# The credential test scripts handed out as outputs, lifted from the _monolithic template with
# their resource references rewritten to module outputs. They live in the root because they
# combine three modules - the trust anchor, profile and role from one, the bucket from another,
# and the exported filenames from the module that writes them - and combining modules is the
# root's job (rules.md C-1).
#
# They are also the only honest answer to "does this work". Terraform can report that a trust
# anchor and a profile exist; whether a certificate can actually be exchanged for credentials
# depends on the CA being ACTIVE, the certificate chaining to it, the trust policy's ArnEquals
# condition, the profile and the role's session limit all agreeing - and the only way to know is
# to present the certificate and see.
locals {
  # The credential helper download table, from
  # https://docs.aws.amazon.com/rolesanywhere/latest/userguide/credential-helper.html
  #
  # Version and checksum stay together in each entry on purpose. Release paths are immutable, so a
  # pinned URL always returns the same bytes; splitting the version into its own value would let a
  # bump leave five checksums behind, and the scripts would then fail on a mismatch that looks like
  # a corrupted download rather than a stale table.
  #
  # Two of these paths moved since the template was written: Windows went Server2019 -> Server2022
  # and macOS x86-64 went Ventura -> Sonoma.
  signing_helper_binaries = {
    linux_x86_64 = {
      label  = "Linux x86-64"
      url    = "https://rolesanywhere.amazonaws.com/releases/1.8.5/X86_64/Linux/Amzn2023/aws_signing_helper"
      sha256 = "beec9ed1c492d93db809890f16713e3556353294b823c2184ad4e891f1b2b54d"
    }
    linux_aarch64 = {
      label  = "Linux Aarch64"
      url    = "https://rolesanywhere.amazonaws.com/releases/1.8.5/Aarch64/Linux/Amzn2023/aws_signing_helper"
      sha256 = "3d131aa888cd56da446f9c6bb460b1f0569f6c7edc74eae6193a2fe3928883ba"
    }
    macos_x86_64 = {
      label  = "macOS x86-64"
      url    = "https://rolesanywhere.amazonaws.com/releases/1.8.5/X86_64/MacOS/Sonoma/aws_signing_helper"
      sha256 = "aab355e1e7468056be88a56bbfb030ea33ff32bef2ce20f5dd6a0b1cae5aae5a"
    }
    macos_aarch64 = {
      label  = "macOS Aarch64"
      url    = "https://rolesanywhere.amazonaws.com/releases/1.8.5/Aarch64/MacOS/Sonoma/aws_signing_helper"
      sha256 = "ac4b656cd83ffde5a6e9e8f2317ffb90e036c9bb704cc80faa6aee414b55915a"
    }
  }
  windows_signing_helper = {
    label  = "Windows x86-64"
    url    = "https://rolesanywhere.amazonaws.com/releases/1.8.5/X86_64/Windows/Server2022/aws_signing_helper.exe"
    sha256 = "fc4c3e65864c1829fcd87ae3718387db03b8ea48b8819f5a6031482ba5d243cd"
  }
  # One script body for all four POSIX targets, because only the helper download differs. The
  # outputs this replaces held four near-copies that had already drifted: the two macOS ones told
  # the reader to fetch the helper with wget, which macOS does not ship (rules.md B-5).
  #
  # Both scripts start by downloading the certificate and key with aws s3 cp, using whatever AWS
  # credentials the shell already has, and clear those credentials before anything is tested. The
  # two identities are kept apart on purpose: reading the bucket is the operator's access, and every
  # check the scripts make is about the session the certificate alone produces. The object keys
  # come from the module that uploads them, so the download and the upload cannot disagree
  # (rules.md B-5).
  posix_credential_test = {
    for key, binary in local.signing_helper_binaries : key => <<-EOT
    #!/usr/bin/env bash
    # IAM Roles Anywhere credential test - ${binary.label}
    #
    # Save as credential_test.sh in an empty directory on the machine standing in for the
    # on-premises server, and run it there:
    #
    #   bash credential_test.sh
    #
    # Two identities appear in this script, one after the other, and keeping them apart is the point.
    #
    #   Step 1 downloads the certificate and its private key from S3 with the AWS credentials this
    #   shell already has - environment variables, a profile, SSO, whatever
    #   `aws sts get-caller-identity` answers with right now. Those are the operator's, and they are
    #   used for the two aws s3 cp calls and nothing else.
    #
    #   Step 5 clears them. From then on the X.509 certificate issued by the private CA is the only
    #   thing that authenticates, and every check below is about that second identity.
    #
    # A machine with no AWS credentials of its own can still run this: copy the two files into this
    # directory first (the certificate_download_url and decrypted_key_download_url outputs), and the
    # failed download falls back to them.
    set -euo pipefail

    TRUST_ANCHOR_ARN='${module.roles_anywhere_profile.trust_anchor_arn}'
    PROFILE_ARN='${module.roles_anywhere_profile.profile_arn}'
    ROLE_ARN='${module.roles_anywhere_profile.role_arn}'
    ROLE_NAME='${module.roles_anywhere_profile.role_name}'
    BUCKET='${module.artifact_bucket.bucket_name}'
    REGION='${data.aws_region.current.region}'
    CERT_OBJECT='${module.certificate_export_ec2.exported_object_keys.certificate}'
    KEY_OBJECT='${module.certificate_export_ec2.exported_object_keys.decrypted_key}'
    HELPER_URL='${binary.url}'
    HELPER_SHA256='${binary.sha256}'

    WORKDIR=$(pwd)
    CERT=$WORKDIR/$CERT_OBJECT
    KEY=$WORKDIR/$KEY_OBJECT
    # Filename carries the pinned version, so this never collides with an aws_signing_helper that
    # happens to be sitting in the working directory already. The version is cut out of the URL
    # rather than written again, so the name and the thing downloaded cannot disagree.
    HELPER=$WORKDIR/aws_signing_helper-${split("/", binary.url)[4]}

    # --- 1. certificate material, downloaded with this shell's own AWS credentials ------------
    # --region because the bucket's region is known here and the shell's default may be another.
    echo "== download from s3://$BUCKET =="
    if aws s3 cp "s3://$BUCKET/$CERT_OBJECT" "$CERT" --region "$REGION" --only-show-errors \
      && aws s3 cp "s3://$BUCKET/$KEY_OBJECT" "$KEY" --region "$REGION" --only-show-errors; then
      echo "  downloaded $CERT_OBJECT and $KEY_OBJECT"
    elif [ -s "$CERT" ] && [ -s "$KEY" ]; then
      # Files copied here by hand. A pair left over from another deployment is caught by step 3
      # (key and certificate do not match) or step 6 (unexpected identity), so this is safe.
      echo "  download failed - using the $CERT_OBJECT and $KEY_OBJECT already in $WORKDIR" >&2
    else
      echo "could not download from s3://$BUCKET, and the files are not in $WORKDIR either." >&2
      echo "  Run this where 'aws sts get-caller-identity' works, or copy both files here first." >&2
      echo "  To see what the bucket holds: aws s3 ls s3://$BUCKET --region $REGION" >&2
      exit 1
    fi
    # Unencrypted, and together with the certificate it is this role's credential.
    chmod 600 "$KEY"

    # --- 2. credential helper ------------------------------------------------------------------
    # Pinned version and verified checksum, because this downloads a binary and then executes it.
    #
    # The checksum decides whether to download, not whether the file is there. Those are different
    # questions, and treating presence as proof is how an earlier version of this script failed:
    # the project directory ships a helper of its own, an existence check accepted it, and the run
    # died on a hash that was simply an older release. A file that does not match the pinned hash
    # is replaced; only a fresh download that still mismatches is worth stopping for.
    helper_sha256() {
      [ -f "$HELPER" ] || { echo ""; return; }
      if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$HELPER" | cut -d' ' -f1
      else
        shasum -a 256 "$HELPER" | cut -d' ' -f1   # macOS ships shasum, not sha256sum
      fi
    }
    if [ "$(helper_sha256)" != "$HELPER_SHA256" ]; then
      curl -fsSL -o "$HELPER" "$HELPER_URL"
      chmod +x "$HELPER"
      SUM=$(helper_sha256)
      if [ "$SUM" != "$HELPER_SHA256" ]; then
        echo "checksum mismatch on a freshly downloaded helper - not running it" >&2
        echo "  from     $HELPER_URL" >&2
        echo "  got      $SUM" >&2
        echo "  expected $HELPER_SHA256" >&2
        exit 1
      fi
    fi

    # --- 3. does the key belong to the certificate? --------------------------------------------
    # The commonest setup mistake, and CreateSession does not say so when it is wrong.
    if command -v openssl >/dev/null 2>&1; then
      [ "$(openssl x509 -in "$CERT" -noout -modulus | openssl md5)" \
        = "$(openssl rsa -in "$KEY" -noout -modulus | openssl md5)" ] \
        || { echo "certificate and private key are not a pair" >&2; exit 1; }
      openssl x509 -in "$CERT" -noout -subject -issuer -dates
    fi

    # --- 4. exchange the certificate for a session ---------------------------------------------
    echo
    echo "== CreateSession =="
    # Piped through grep so the secret fields never reach the terminal or a shell history file.
    "$HELPER" credential-process \
      --trust-anchor-arn "$TRUST_ANCHOR_ARN" \
      --profile-arn "$PROFILE_ARN" \
      --role-arn "$ROLE_ARN" \
      --certificate "$CERT" \
      --private-key "$KEY" \
      | grep -o '"Expiration":"[^"]*"'

    # --- 5. hand the helper to the AWS CLI -----------------------------------------------------
    # credential_process rather than three exported keys: the CLI and the SDKs re-invoke the helper
    # when a session expires, and nothing has to parse JSON. Written to a throwaway config file so
    # the test never touches ~/.aws/config.
    #
    # The helper asks for 3600 seconds unless told otherwise. This deployment allows up to
    # ${var.session_duration_seconds}, so append
    #   --session-duration ${var.session_duration_seconds}
    # to the line below to use the full window.
    export AWS_CONFIG_FILE=$WORKDIR/iamra.config
    printf '%s\n' \
      '[profile iamra]' \
      "region = $REGION" \
      "credential_process = \"$HELPER\" credential-process --trust-anchor-arn $TRUST_ANCHOR_ARN --profile-arn $PROFILE_ARN --role-arn $ROLE_ARN --certificate \"$CERT\" --private-key \"$KEY\"" \
      > "$AWS_CONFIG_FILE"
    export AWS_PROFILE=iamra

    # This is where the operator's credentials from step 1 stop being used. Credentials already in
    # the environment outrank a profile's credential_process, so anything left over here would
    # quietly test the wrong identity and still look like a pass. A profile or SSO session from
    # step 1 is already out of the picture: AWS_CONFIG_FILE above points somewhere else.
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

    # --- 6. who did the certificate make us? ---------------------------------------------------
    echo
    echo "== identity =="
    aws sts get-caller-identity --output json
    case "$(aws sts get-caller-identity --query Arn --output text)" in
      *":assumed-role/$ROLE_NAME/"*) echo "OK: this is the IAM Roles Anywhere role" ;;
      *) echo "FAIL: unexpected identity" >&2; exit 1 ;;
    esac
    # The role session name is the certificate serial number, so the session is traceable back to
    # one issued certificate. Cross-check it against:
    #   openssl x509 -in certificate.pem -noout -serial
    #   aws rolesanywhere list-subjects      (needs separate, AWS-side credentials)

    # --- 7. is the session held to what the role grants? ---------------------------------------
    echo
    echo "== AmazonS3ReadOnlyAccess allows =="
    aws s3api list-objects-v2 --bucket "$BUCKET" --query 'Contents[].Key' --output text

    echo "== and denies =="
    if aws s3api put-object --bucket "$BUCKET" --key probe.txt --body "$CERT" >/dev/null 2>&1; then
      echo "FAIL: s3:PutObject succeeded - this role is broader than intended" >&2; exit 1
    fi
    echo "  s3:PutObject           denied, as expected"
    if aws ec2 describe-instances --max-items 1 >/dev/null 2>&1; then
      echo "FAIL: ec2:DescribeInstances succeeded - this role is broader than intended" >&2; exit 1
    fi
    echo "  ec2:DescribeInstances  denied, as expected"

    # --- 8. the same credentials as environment variables --------------------------------------
    # For tools that read the environment instead of a profile. AWS CLI v2.9+ renders them without
    # jq, which the previous version of this script needed and macOS does not ship. eval keeps the
    # secrets off the terminal.
    eval "$(aws configure export-credentials --format env)"
    echo
    echo "AWS_ACCESS_KEY_ID=$(printf %.5s "$AWS_ACCESS_KEY_ID")...  expires $AWS_CREDENTIAL_EXPIRATION"
    echo
    echo "PASS: the certificate alone produced a working, correctly scoped AWS session."
    echo "Delete $KEY when you are done - with the certificate next to it, it is this role's credential."
    EOT
  }
  windows_credential_test = <<-EOT
  # IAM Roles Anywhere credential test - ${local.windows_signing_helper.label} (PowerShell 5.1+)
  #
  # Save as credential_test.ps1 in an empty directory on the machine standing in for the
  # on-premises server, and run it there:
  #
  #   powershell -ExecutionPolicy Bypass -File .\credential_test.ps1
  #
  # Two identities appear in this script, one after the other, and keeping them apart is the point.
  #
  #   Step 1 downloads the certificate and its private key from S3 with the AWS credentials this
  #   shell already has - environment variables, a profile, SSO, whatever
  #   `aws sts get-caller-identity` answers with right now. Those are the operator's, and they are
  #   used for the two aws s3 cp calls and nothing else.
  #
  #   Step 4 clears them. From then on the X.509 certificate issued by the private CA is the only
  #   thing that authenticates, and every check below is about that second identity.
  #
  # A machine with no AWS credentials of its own can still run this: copy the two files into this
  # directory first (the certificate_download_url and decrypted_key_download_url outputs), and the
  # failed download falls back to them.
  $ErrorActionPreference = 'Stop'
  # Invoke-WebRequest renders a progress bar by repainting the console on every chunk. Downloading
  # an 11 MB binary that way emits several hundred thousand characters, which buries everything
  # this script prints afterwards when the output is piped or captured.
  $ProgressPreference = 'SilentlyContinue'

  $TrustAnchorArn = '${module.roles_anywhere_profile.trust_anchor_arn}'
  $ProfileArn     = '${module.roles_anywhere_profile.profile_arn}'
  $RoleArn        = '${module.roles_anywhere_profile.role_arn}'
  $RoleName       = '${module.roles_anywhere_profile.role_name}'
  $Bucket         = '${module.artifact_bucket.bucket_name}'
  $Region         = '${data.aws_region.current.region}'
  $CertObject     = '${module.certificate_export_ec2.exported_object_keys.certificate}'
  $KeyObject      = '${module.certificate_export_ec2.exported_object_keys.decrypted_key}'
  $HelperUrl      = '${local.windows_signing_helper.url}'
  $HelperSha256   = '${local.windows_signing_helper.sha256}'

  $WorkDir = (Get-Location).Path
  $Cert    = Join-Path $WorkDir $CertObject
  $Key     = Join-Path $WorkDir $KeyObject
  # Filename carries the pinned version, so this never collides with an aws_signing_helper.exe that
  # happens to be sitting in the working directory already - the project directory ships one. The
  # version is cut out of the URL rather than written again, so the name and the thing downloaded
  # cannot disagree.
  $Helper  = Join-Path $WorkDir 'aws_signing_helper-${split("/", local.windows_signing_helper.url)[4]}.exe'

  # --- 1. certificate material, downloaded with this shell's own AWS credentials --------------
  # --region because the bucket's region is known here and the shell's default may be another.
  #
  # 'Continue' inside the function only, so a failing copy reports through $LASTEXITCODE and its
  # message is passed through. Under the script-wide 'Stop', the 2>&1 would turn the CLI's stderr
  # into a terminating NativeCommandError before the exit code could be read - step 5 has the
  # full account of that trap.
  function Copy-FromBucket([string]$ObjectKey, [string]$Path) {
    $ErrorActionPreference = 'Continue'
    $out = & aws s3 cp "s3://$Bucket/$ObjectKey" $Path --region $Region --only-show-errors 2>&1
    if ($LASTEXITCODE -ne 0) {
      Write-Host ('  ' + $ObjectKey + ': ' + ($out -join ' '))
      return $false
    }
    return $true
  }
  Write-Host "== download from s3://$Bucket =="
  if ((Copy-FromBucket $CertObject $Cert) -and (Copy-FromBucket $KeyObject $Key)) {
    Write-Host "  downloaded $CertObject and $KeyObject"
  } elseif ((Test-Path $Cert) -and (Test-Path $Key)) {
    # Files copied here by hand. A pair left over from another deployment fails CreateSession in
    # step 3 or the identity check in step 5, so this is safe.
    Write-Warning "download failed - using the $CertObject and $KeyObject already in $WorkDir"
  } else {
    throw ("could not download from s3://$Bucket, and the files are not in $WorkDir either. " +
           "Run this where 'aws sts get-caller-identity' works, or copy both files here first. " +
           "To see what the bucket holds: aws s3 ls s3://$Bucket --region $Region")
  }

  # --- 2. credential helper --------------------------------------------------------------------
  # Pinned version and verified checksum, because this downloads a binary and then executes it.
  #
  # The checksum decides whether to download, not whether the file is there. Those are different
  # questions, and treating presence as proof is how an earlier version of this script failed: the
  # project directory ships a helper of its own, Test-Path accepted it, and the run died on a hash
  # that was simply an older release. A file that does not match the pinned hash is replaced; only
  # a fresh download that still mismatches is worth stopping for.
  $sum = if (Test-Path $Helper) { (Get-FileHash -Algorithm SHA256 -Path $Helper).Hash.ToLower() } else { '' }
  if ($sum -ne $HelperSha256) {
    Invoke-WebRequest -Uri $HelperUrl -OutFile $Helper
    $sum = (Get-FileHash -Algorithm SHA256 -Path $Helper).Hash.ToLower()
    if ($sum -ne $HelperSha256) {
      throw ('checksum mismatch on a freshly downloaded helper - not running it' +
             [Environment]::NewLine + '  from     ' + $HelperUrl +
             [Environment]::NewLine + '  got      ' + $sum +
             [Environment]::NewLine + '  expected ' + $HelperSha256)
    }
  }

  # --- 3. exchange the certificate for a session -----------------------------------------------
  # PowerShell parses JSON natively, so nothing here needs jq.
  Write-Host ''
  Write-Host '== CreateSession =='
  $session = & $Helper credential-process `
    --trust-anchor-arn $TrustAnchorArn `
    --profile-arn $ProfileArn `
    --role-arn $RoleArn `
    --certificate $Cert `
    --private-key $Key | ConvertFrom-Json
  Write-Host ("  access key id : " + $session.AccessKeyId.Substring(0, 5) + "...")
  Write-Host ("  expires       : " + $session.Expiration)

  # --- 4. hand the helper to the AWS CLI -------------------------------------------------------
  # credential_process rather than three exported keys: the CLI and the SDKs re-invoke the helper
  # when a session expires. Written to a throwaway config file so the test never touches the
  # user's own config.
  #
  # The helper asks for 3600 seconds unless told otherwise. This deployment allows up to
  # ${var.session_duration_seconds}, so append
  #   --session-duration ${var.session_duration_seconds}
  # to $cp below to use the full window.
  $Cfg = Join-Path $WorkDir 'iamra.config'
  $cp = '"' + $Helper + '" credential-process' +
        ' --trust-anchor-arn ' + $TrustAnchorArn +
        ' --profile-arn ' + $ProfileArn +
        ' --role-arn ' + $RoleArn +
        ' --certificate "' + $Cert + '"' +
        ' --private-key "' + $Key + '"'
  # UTF-8 with no BOM, written through .NET because Set-Content in PowerShell 5.1 cannot produce
  # it: -Encoding utf8 prepends a BOM that stops the CLI from reading the profile, and
  # -Encoding ascii replaces every non-ASCII character with "?". The second one matters here
  # because these are paths - a home directory outside US-ASCII turns into C:\Users\???\... and
  # every CLI call then fails with "[WinError 2] file not found".
  $lines = [string[]]@('[profile iamra]', "region = $Region", "credential_process = $cp")
  [System.IO.File]::WriteAllLines($Cfg, $lines, (New-Object System.Text.UTF8Encoding $false))
  $env:AWS_CONFIG_FILE = $Cfg
  $env:AWS_PROFILE     = 'iamra'

  # This is where the operator's credentials from step 1 stop being used. Credentials already in
  # the environment outrank a profile's credential_process, so anything left over here would
  # quietly test the wrong identity and still look like a pass. A profile or SSO session from step 1
  # is already out of the picture: AWS_CONFIG_FILE above points somewhere else.
  Remove-Item Env:AWS_ACCESS_KEY_ID, Env:AWS_SECRET_ACCESS_KEY, Env:AWS_SESSION_TOKEN -ErrorAction SilentlyContinue

  # --- 5. who did the certificate make us? -----------------------------------------------------
  # From here on every AWS CLI call captures its own output and tests $LASTEXITCODE, and the
  # preference drops to 'Continue' for the rest of the script. Both halves of that are necessary:
  #
  #   - Under 'Stop', the 2>&1 on a failing CLI call turns the CLI's stderr into a terminating
  #     error before the exit-code check can run. The script still stops, but the diagnostic is
  #     PowerShell's NativeCommandError and the actual AWS message is lost. Two of these calls are
  #     also meant to fail, so 'Stop' would abort on the expected outcome.
  #   - Under 'Continue' nothing announces a failure by itself, so a missing check means a silent
  #     pass. An earlier version of this script printed "OK" for an identity it had never
  #     retrieved, having compared against an unset variable. A check that can pass without its
  #     evidence is worse than no check, so each one below is explicit and throw stays terminating
  #     regardless of the preference.
  $ErrorActionPreference = 'Continue'
  Write-Host ''
  Write-Host '== identity =='
  $identityJson = & aws sts get-caller-identity --output json 2>&1
  if ($LASTEXITCODE -ne 0) { throw ('sts get-caller-identity failed: ' + ($identityJson -join ' ')) }
  Write-Host ($identityJson -join [Environment]::NewLine)
  $arn = ($identityJson | ConvertFrom-Json).Arn
  if ($arn -notlike "*:assumed-role/$RoleName/*") { throw "unexpected identity: $arn" }
  Write-Host 'OK: this is the IAM Roles Anywhere role'
  # The role session name is the certificate serial number, so the session is traceable back to one
  # issued certificate. Cross-check with: openssl x509 -in certificate.pem -noout -serial

  # --- 6. is the session held to what the role grants? -----------------------------------------
  Write-Host ''
  Write-Host '== AmazonS3ReadOnlyAccess allows =='
  $keys = & aws s3api list-objects-v2 --bucket $Bucket --query 'Contents[].Key' --output text 2>&1
  if ($LASTEXITCODE -ne 0) { throw ('s3:ListBucket should be allowed but failed: ' + ($keys -join ' ')) }
  Write-Host ('  ' + ($keys -join ' '))

  # Here a non-zero exit is the expected result, so these two tests are inverted.
  Write-Host '== and denies =='
  $null = & aws s3api put-object --bucket $Bucket --key probe.txt --body $Cert 2>&1
  $putExit = $LASTEXITCODE
  $null = & aws ec2 describe-instances --max-items 1 2>&1
  $ec2Exit = $LASTEXITCODE
  if ($putExit -eq 0) { throw 's3:PutObject succeeded - this role is broader than intended' }
  Write-Host '  s3:PutObject           denied, as expected'
  if ($ec2Exit -eq 0) { throw 'ec2:DescribeInstances succeeded - this role is broader than intended' }
  Write-Host '  ec2:DescribeInstances  denied, as expected'

  # --- 7. the same credentials as environment variables ----------------------------------------
  # For tools that read the environment instead of a profile.
  $credsJson = & aws configure export-credentials --format process 2>&1
  if ($LASTEXITCODE -ne 0) { throw ('export-credentials failed: ' + ($credsJson -join ' ')) }
  $creds = $credsJson | ConvertFrom-Json
  # Guarded because 'Continue' is in force: without this, an unparseable response would leave
  # $creds null, the Substring below would log a non-terminating error, and the script would still
  # reach its PASS line.
  if (-not $creds.AccessKeyId) { throw ('export-credentials returned no credentials: ' + ($credsJson -join ' ')) }
  $env:AWS_ACCESS_KEY_ID     = $creds.AccessKeyId
  $env:AWS_SECRET_ACCESS_KEY = $creds.SecretAccessKey
  $env:AWS_SESSION_TOKEN     = $creds.SessionToken
  Write-Host ''
  Write-Host ('AWS_ACCESS_KEY_ID=' + $creds.AccessKeyId.Substring(0, 5) + '...  expires ' + $creds.Expiration)
  Write-Host ''
  Write-Host 'PASS: the certificate alone produced a working, correctly scoped AWS session.'
  Write-Host "Delete $Key when you are done - with the certificate next to it, it is this role's credential."
  EOT
}
