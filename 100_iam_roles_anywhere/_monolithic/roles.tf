# Generated from 100_iam_roles_anywhere/roles.yaml by tools/cfn2tf.
# CloudFormation stack -> Terraform root module.
terraform {
  required_version = ">= 1.9"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
  }
}
provider "aws" {
  region = var.aws_region
}
variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. Defaults to the provider chain (AWS_REGION)."
}
variable "stack_name" {
  type        = string
  default     = "roles"
  description = "Stands in for AWS::StackName."
}
data "aws_region" "current" {}
# --- Parameters ---
variable "passphrase" {
  type    = string
  default = "rolePassword1234!"
}
variable "amazon_linux2023_ami_id" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "(SSM parameter path; resolved by the aws_ssm_parameter data source)"
}
data "aws_ssm_parameter" "amazon_linux2023_ami_id" {
  name = var.amazon_linux2023_ami_id
}
# Added by hand rather than by the conversion. These configure the wait that CloudFormation did with
# a CreationPolicy (rules.md B-3).
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the bastion where the bootstrap drops its completion marker. The association that gates the termination waits on that file rather than trusting depends_on or wait_for_success_timeout_seconds (rules.md D-5)"

  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with a slash."
  }
}
variable "bastion_export_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the apply waits for the certificate export to finish and appear in S3. It covers the whole bootstrap, because the association's first statement blocks until the marker file appears - the CreationPolicy this replaces allowed 10 minutes for the same work"

  validation {
    condition     = var.bastion_export_timeout_seconds >= 300 && var.bastion_export_timeout_seconds <= 3600
    error_message = "bastion_export_timeout_seconds must be between 300 and 3600."
  }
}
# One variable for two resources, because a session is only as long as the shorter of them allows:
# IAM Roles Anywhere issues min(profile durationSeconds, role MaxSessionDuration). The template this
# was converted from set 43200 on the profile and left the role at the IAM default of 3600, so the
# profile's 12 hours were unreachable - asking for them returns
#
#   AccessDeniedException: Unable to assume role for arn:aws:iam::...:role/...
#   The requested DurationSeconds exceeds the MaxSessionDuration set for this role.
#
# Nothing reports that until a client actually asks for the longer session, since both values are
# individually valid. Deriving both from here keeps them from drifting apart again (rules.md B-5).
variable "session_duration_seconds" {
  type        = number
  default     = 43200
  description = "Maximum length of the sessions IAM Roles Anywhere hands out. Applied to both the profile's duration_seconds and the role's max_session_duration, because the effective limit is the smaller of the two. The credential helper still requests 3600 unless told otherwise with --session-duration"

  validation {
    # 900 is the IAM floor for MaxSessionDuration, 43200 the ceiling for both it and the profile.
    condition     = var.session_duration_seconds >= 900 && var.session_duration_seconds <= 43200
    error_message = "session_duration_seconds must be between 900 and 43200, the range IAM accepts for a role's MaxSessionDuration."
  }
}
# --- Resources split out of composite CloudFormation resources ---
resource "aws_iam_role_policy_attachment" "s3_read_only_role" {
  role       = aws_iam_role.s3_read_only_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}
resource "aws_iam_role_policy_attachment" "bastion_ec2_iam_role" {
  role       = aws_iam_role.bastion_ec2_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
data "archive_file" "custom_resource_lambda_function" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/custom_resource_lambda_function/index.py"
  output_path = "${path.module}/build/custom_resource_lambda_function.zip"
}
resource "aws_iam_role_policy" "custom_resource_lambda_iam_role" {
  name = "CustomLambdaPolicy"
  role = aws_iam_role.custom_resource_lambda_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ec2:*"]
      Resource = "*"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "custom_resource_lambda_iam_role" {
  role       = aws_iam_role.custom_resource_lambda_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
# --- Resources ---
resource "aws_acmpca_certificate_authority" "private_ca" {
  key_storage_security_standard = "FIPS_140_2_LEVEL_3_OR_HIGHER"
  type                          = "ROOT"
  usage_mode                    = "GENERAL_PURPOSE"
  certificate_authority_configuration {
    key_algorithm     = "RSA_2048"
    signing_algorithm = "SHA256WITHRSA"
    subject {
      organization        = "Peccy Inc"
      organizational_unit = "Red Team"
      country             = "KR"
    }
  }
}
resource "aws_acmpca_certificate_authority_certificate" "private_ca_activation" {
  certificate               = aws_acmpca_certificate.private_ca_certificate.certificate
  certificate_authority_arn = aws_acmpca_certificate_authority.private_ca.arn
  # AWS::ACMPCA::CertificateAuthorityActivation carried Status: ACTIVE, and there is no attribute
  # here to carry it to, because importing the certificate is itself what moves the CA out of
  # PENDING_CERTIFICATE. Whether it then lands on ACTIVE or DISABLED follows the enabled argument of
  # aws_acmpca_certificate_authority, which defaults to true. Nothing is missing - the TODO the
  # conversion left here is answered.
}
resource "aws_acmpca_certificate" "private_ca_certificate" {
  certificate_authority_arn   = aws_acmpca_certificate_authority.private_ca.arn
  certificate_signing_request = aws_acmpca_certificate_authority.private_ca.certificate_signing_request
  signing_algorithm           = "SHA256WITHRSA"
  template_arn                = "arn:aws:acm-pca:::template/RootCACertificate/V1"
  validity {
    type  = "YEARS"
    value = 10
  }
}
resource "aws_acmpca_permission" "private_ca_permission" {
  actions                   = ["IssueCertificate", "GetCertificate", "ListPermissions"]
  certificate_authority_arn = aws_acmpca_certificate_authority.private_ca.arn
  principal                 = "acm.amazonaws.com"
}
resource "aws_acm_certificate" "acm_certificate" {
  certificate_authority_arn = aws_acmpca_certificate_authority.private_ca.arn
  domain_name               = "rolesanywhere.com"
  key_algorithm             = "RSA_2048"
  depends_on                = [aws_acmpca_certificate_authority_certificate.private_ca_activation, aws_acmpca_permission.private_ca_permission]
}
resource "aws_rolesanywhere_trust_anchor" "iam_ra_trust_anchor" {
  enabled = true
  name    = "iam-ra-ta"
  source {
    source_data {
      acm_pca_arn = aws_acmpca_certificate_authority.private_ca.arn
    }
    source_type = "AWS_ACM_PCA"
  }

  # Creating a trust anchor makes IAM Roles Anywhere read the CA's certificate. A certificate
  # authority Terraform has just created is PENDING_CERTIFICATE and has none, and the read fails -
  # reported, unhelpfully, as
  #
  #   ValidationException: Error creating TrustAnchor. Given AWS PCA did not allow get request.
  #
  # which reads like a permissions problem and is not one. The same CreateTrustAnchor call against
  # the same CA succeeds on the first attempt once it is ACTIVE.
  #
  # The acm_pca_arn reference above is not enough to order this: a value reference only orders
  # against the resource that produced the value, which here is the empty CA, not the certificate
  # import that activates it. So the two were free to run in parallel, and did (rules.md D-1).
  depends_on = [aws_acmpca_certificate_authority_certificate.private_ca_activation]
}
resource "aws_rolesanywhere_profile" "iam_ra_profile" {
  enabled          = true
  name             = "iam-ra-profile"
  duration_seconds = var.session_duration_seconds
  role_arns        = [aws_iam_role.s3_read_only_role.arn]
}
resource "aws_iam_role" "s3_read_only_role" {
  # Hand edit, not conversion output. The template left this at the IAM default of 3600 while giving
  # the profile 43200; see the comment on var.session_duration_seconds for why that combination
  # cannot produce a 12 hour session.
  max_session_duration = var.session_duration_seconds
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["rolesanywhere.amazonaws.com"]
      }
      Action = ["sts:AssumeRole", "sts:TagSession", "sts:SetSourceIdentity"]
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = [aws_rolesanywhere_trust_anchor.iam_ra_trust_anchor.arn]
        }
      }
    }]
  })
}
resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "vpc"
  }
}
resource "aws_internet_gateway" "internet_gateway" {
  tags = {
    Name = "igw"
  }
}
resource "aws_internet_gateway_attachment" "vpc_internet_gateway_attachment" {
  internet_gateway_id = aws_internet_gateway.internet_gateway.id
  vpc_id              = aws_vpc.vpc.id
}
resource "aws_route_table" "public_subnet_route_table" {
  tags = {
    Name = "public-rt"
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route" "public_subnet_route" {
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
  route_table_id         = aws_route_table.public_subnet_route_table.id
}
resource "aws_subnet" "public_subnet" {
  availability_zone       = "${data.aws_region.current.region}a"
  cidr_block              = "10.0.0.0/24"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet"
  }
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route_table_association" "public_subnet_route_table_association" {
  route_table_id = aws_route_table.public_subnet_route_table.id
  subnet_id      = aws_subnet.public_subnet.id
}
# CreationPolicy: CloudFormation CreationPolicy (cfn-signal) has no Terraform equivalent; the wait is not reproduced.
# # {
# #   "ResourceSignal": {
# #     "Count": "1",
# #     "Timeout": "PT10M"
# #   }
# # }
resource "aws_instance" "bastion_ec2" {
  ami           = data.aws_ssm_parameter.amazon_linux2023_ami_id.insecure_value
  instance_type = "t3.medium"
  tags = {
    Name = "bastion-ec2"
  }
  iam_instance_profile        = aws_iam_instance_profile.bastion_ec2_instance_profile.name
  user_data                   = <<EOT
#!/bin/bash
dnf update -yq
dnf groupinstall -yq "Development Tools"

aws acm export-certificate \
--certificate-arn "${aws_acm_certificate.acm_certificate.arn}" \
--passphrase $(echo -n "${var.passphrase}" | base64) > /home/ec2-user/export.json
cat /home/ec2-user/export.json | jq -r '"\(.Certificate)"' > /home/ec2-user/certificate.pem
cat /home/ec2-user/export.json | jq -r '"\(.CertificateChain)"' > /home/ec2-user/certificate_chain.pem
cat /home/ec2-user/export.json | jq -r '"\(.PrivateKey)"' > /home/ec2-user/private_key.pem
openssl rsa -in /home/ec2-user/private_key.pem -out /home/ec2-user/decrypted_key.pem -passin pass:${var.passphrase}

aws s3api put-object --bucket ${aws_s3_bucket.s3_bucket.id} --key certificate.pem --body /home/ec2-user/certificate.pem
aws s3api put-object --bucket ${aws_s3_bucket.s3_bucket.id} --key certificate_chain.pem --body /home/ec2-user/certificate_chain.pem
aws s3api put-object --bucket ${aws_s3_bucket.s3_bucket.id} --key private_key.pem --body /home/ec2-user/private_key.pem
aws s3api put-object --bucket ${aws_s3_bucket.s3_bucket.id} --key decrypted_key.pem --body /home/ec2-user/decrypted_key.pem

# cfn-signal answered a CreationPolicy that no longer exists. The binary is on this AMI, so the call
# ran and failed - "ValidationError: Stack with id ${var.stack_name} does not exist or has been
# deleted" - which left this script on a non-zero exit and cloud-init reporting status: error for a
# bootstrap that had in fact done all of its work.
#
# The marker file replaces it, and is deliberately the last thing the script does. The association
# below waits for this file, and the Lambda that terminates this instance waits for the association,
# so touching it any earlier would hand the certificate export a deadline it cannot meet
# (rules.md B-4/D-5).
mkdir -p ${var.marker_file_path}
touch ${var.marker_file_path}/userdata
EOT
  subnet_id                   = aws_subnet.public_subnet.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_vpc.vpc.default_security_group_id]
  # user_data changes stop and start an instance by default, and cloud-init does not re-run its
  # script on a restart - the edited bootstrap would never execute. Replacement is what runs it.
  user_data_replace_on_change = true

  # iam_instance_profile orders this after the profile, not after the policy attached to the role in
  # it. Everything the bootstrap does needs that policy: exporting the certificate, writing to S3,
  # and registering with SSM for the association below (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.bastion_ec2_iam_role]
}
resource "aws_iam_role" "bastion_ec2_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["ec2.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
resource "aws_iam_instance_profile" "bastion_ec2_instance_profile" {
  # name_prefix, not name. Instance profile names are account-wide, and this literal was shared with
  # 031_ecs_alb_integration, 035_codepipeline_ecs_bluegreen and 096_s3_static_website - the second of them
  # applied into an account fails on EntityAlreadyExists. The role above has no explicit name, so only this
  # one needed it (rules.md G-3).
  name_prefix = "Ec2AdminProfile-"
  # Hand edit, not conversion output. CloudFormation's AWS::IAM::InstanceProfile takes a Roles list, so the
  # conversion wrote jsonencode([...]) - but this attribute is a single role name, a profile holds at most one
  # role, and a JSON array string is not a role name. validate and plan pass; the apply fails in IAM
  # (rules.md A-3).
  role = aws_iam_role.bastion_ec2_iam_role.name
}
# Holds the apply open until the bastion has finished exporting the certificate.
#
# This is the half of the CreationPolicy that the conversion dropped, and without it fixing the
# Lambda would have replaced a loud failure with a silent one. depends_on = [aws_instance.bastion_ec2]
# is satisfied the moment EC2 reports the instance running, which on this AMI is about 90 seconds
# before cloud-init finishes - so the terminate call landed in the middle of the export and the four
# objects the whole project hands out were never written. Nothing would have reported an error
# (rules.md D-5).
resource "aws_ssm_association" "bastion_export" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.bastion_export_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [aws_instance.bastion_ec2.id]
  }
  parameters = {
    commands = <<-EOT
      set -e
      until [ -f ${var.marker_file_path}/userdata ]; do sleep 10; done
      # Checked here, while the instance that can still produce them exists. After the termination
      # below there is nothing left to retry with, and a missing object would otherwise surface as
      # an empty S3 console page at the end of a successful apply.
      for key in certificate.pem certificate_chain.pem private_key.pem decrypted_key.pem; do
        aws s3api head-object --bucket ${aws_s3_bucket.s3_bucket.id} --key "$key" >/dev/null
      done
      touch ${var.marker_file_path}/bastion_export
      EOT
  }
}
# Terminates the bastion, so the demo does not leave an instance holding AdministratorAccess.
#
# The instance id travels in the input rather than in the function's source, where the template put
# it with Fn::Sub - see the comment at the top of lambda_src/.../index.py.
#
# Worth knowing about the next apply: the instance this created is gone, so Terraform plans to
# recreate it, and recreating it changes the input here, which re-invokes this and terminates the new
# one. That loop is the design working, not drift.
resource "aws_lambda_invocation" "terminate_bastion_ec2" {
  function_name = aws_lambda_function.custom_resource_lambda_function.arn
  input = jsonencode({
    instance_ids = [aws_instance.bastion_ec2.id]
  })

  # The association, not the instance: the export has to be finished and verified before the
  # instance that did it is destroyed. The inline policy carries ec2:*, and an invocation that
  # races it fails with UnauthorizedOperation (rules.md D-1).
  depends_on = [
    aws_ssm_association.bastion_export,
    aws_iam_role_policy.custom_resource_lambda_iam_role,
  ]
}
resource "aws_lambda_function" "custom_resource_lambda_function" {
  handler          = "index.lambda_handler"
  role             = aws_iam_role.custom_resource_lambda_iam_role.arn
  runtime          = "python3.13"
  timeout          = 60
  filename         = data.archive_file.custom_resource_lambda_function.output_path
  source_code_hash = data.archive_file.custom_resource_lambda_function.output_base64sha256
  # CloudFormation generated this name automatically; Terraform requires it, so it is derived from the stack name.
  function_name = "${var.stack_name}-custom-resource-lambda-function"
}
resource "aws_iam_role" "custom_resource_lambda_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
# force_destroy because the bootstrap writes four objects into this bucket and Terraform did not
# create them, so destroy fails with BucketNotEmpty. Deleting them along with the bucket is the point
# rather than a cost: one of them is the unencrypted private key.
resource "aws_s3_bucket" "s3_bucket" {
  force_destroy = true
}
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
  # One script body for all four POSIX targets, because only the download differs. The outputs this
  # replaces held four near-copies that had already drifted: the two macOS ones told the reader to
  # fetch the helper with wget, which macOS does not ship (rules.md B-5).
  posix_credential_test = {
    for key, binary in local.signing_helper_binaries : key => <<-EOT
    #!/usr/bin/env bash
    # IAM Roles Anywhere credential test - ${binary.label}
    #
    # Run this on the machine standing in for the on-premises server. It needs no AWS credentials of
    # its own, which is the whole point: the X.509 certificate issued by the private CA is what
    # authenticates, and the only AWS-shaped thing here is the CLI that consumes the result.
    set -euo pipefail

    TRUST_ANCHOR_ARN='${aws_rolesanywhere_trust_anchor.iam_ra_trust_anchor.arn}'
    PROFILE_ARN='${aws_rolesanywhere_profile.iam_ra_profile.arn}'
    ROLE_ARN='${aws_iam_role.s3_read_only_role.arn}'
    ROLE_NAME='${aws_iam_role.s3_read_only_role.name}'
    BUCKET='${aws_s3_bucket.s3_bucket.id}'
    REGION='${data.aws_region.current.region}'
    HELPER_URL='${binary.url}'
    HELPER_SHA256='${binary.sha256}'

    WORKDIR=$(pwd)
    CERT=$WORKDIR/certificate.pem
    KEY=$WORKDIR/decrypted_key.pem
    # Filename carries the pinned version, so this never collides with an aws_signing_helper that
    # happens to be sitting in the working directory already. The version is cut out of the URL
    # rather than written again, so the name and the thing downloaded cannot disagree.
    HELPER=$WORKDIR/aws_signing_helper-${split("/", binary.url)[4]}

    # --- 1. certificate material ---------------------------------------------------------------
    # Download certificate.pem and decrypted_key.pem into this directory first, from the
    # certificate_download_url and decrypted_key_download_url outputs. This script deliberately
    # does not fetch them: reading that bucket needs the very credentials the certificate replaces.
    for f in "$CERT" "$KEY"; do
      [ -s "$f" ] || { echo "missing $f - download it from the console link in terraform output" >&2; exit 1; }
    done

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

    # Credentials already in the environment outrank a profile's credential_process, so anything
    # left over here would quietly test the wrong identity and still look like a pass.
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
    EOT
  }
  windows_credential_test = <<-EOT
  # IAM Roles Anywhere credential test - ${local.windows_signing_helper.label} (PowerShell 5.1+)
  #
  # Run this on the machine standing in for the on-premises server. It needs no AWS credentials of
  # its own, which is the whole point: the X.509 certificate issued by the private CA is what
  # authenticates, and the only AWS-shaped thing here is the CLI that consumes the result.
  $ErrorActionPreference = 'Stop'
  # Invoke-WebRequest renders a progress bar by repainting the console on every chunk. Downloading
  # an 11 MB binary that way emits several hundred thousand characters, which buries everything
  # this script prints afterwards when the output is piped or captured.
  $ProgressPreference = 'SilentlyContinue'

  $TrustAnchorArn = '${aws_rolesanywhere_trust_anchor.iam_ra_trust_anchor.arn}'
  $ProfileArn     = '${aws_rolesanywhere_profile.iam_ra_profile.arn}'
  $RoleArn        = '${aws_iam_role.s3_read_only_role.arn}'
  $RoleName       = '${aws_iam_role.s3_read_only_role.name}'
  $Bucket         = '${aws_s3_bucket.s3_bucket.id}'
  $Region         = '${data.aws_region.current.region}'
  $HelperUrl      = '${local.windows_signing_helper.url}'
  $HelperSha256   = '${local.windows_signing_helper.sha256}'

  $WorkDir = (Get-Location).Path
  $Cert    = Join-Path $WorkDir 'certificate.pem'
  $Key     = Join-Path $WorkDir 'decrypted_key.pem'
  # Filename carries the pinned version, so this never collides with an aws_signing_helper.exe that
  # happens to be sitting in the working directory already - the project directory ships one. The
  # version is cut out of the URL rather than written again, so the name and the thing downloaded
  # cannot disagree.
  $Helper  = Join-Path $WorkDir 'aws_signing_helper-${split("/", local.windows_signing_helper.url)[4]}.exe'

  # --- 1. certificate material -----------------------------------------------------------------
  # Download certificate.pem and decrypted_key.pem into this directory first, from the
  # certificate_download_url and decrypted_key_download_url outputs. This script deliberately does
  # not fetch them: reading that bucket needs the very credentials the certificate replaces.
  foreach ($f in @($Cert, $Key)) {
    if (-not (Test-Path $f)) { throw "missing $f - download it from the console link in terraform output" }
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

  # Credentials already in the environment outrank a profile's credential_process, so anything left
  # over here would quietly test the wrong identity and still look like a pass.
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
  EOT
}
# --- Outputs ---
# No local.outputs map here, and no SSM association mirroring these into a README: this root has no
# vscode_ec2 instance to render them onto. Its only instance was the bastion, which exists to export
# the certificate and is terminated before the apply finishes, so plain outputs with their value
# expressions written inline are the right shape (rules.md H-2).
#
# The scripts below are built from locals rather than written out five times, which is what keeps
# the POSIX variants identical apart from their download URL.
# CloudFormation output: CertificatePemFileDownload
output "certificate_download_url" {
  # https:// included. The converted output omitted the scheme, so the value could not be opened as
  # a link and had to be edited by hand first.
  value       = "https://${data.aws_region.current.region}.console.aws.amazon.com/s3/object/${aws_s3_bucket.s3_bucket.id}?region=${data.aws_region.current.region}&prefix=certificate.pem"
  description = "Console link to download certificate.pem, the end-entity certificate the private CA issued. Put it next to the test script before running it"
}
# CloudFormation output: DecryptedPriateKeyPemFileDownload
output "decrypted_key_download_url" {
  value       = "https://${data.aws_region.current.region}.console.aws.amazon.com/s3/object/${aws_s3_bucket.s3_bucket.id}?region=${data.aws_region.current.region}&prefix=decrypted_key.pem"
  description = "Console link to download decrypted_key.pem, the unencrypted private key for that certificate. Anyone holding both files can obtain this role's credentials, so treat this bucket as a secret store until the stack is destroyed"
}
output "credential_test_linux_x86_64" {
  value       = local.posix_credential_test["linux_x86_64"]
  description = "Full IAM Roles Anywhere credential test for Linux x86-64: verifies the key matches the certificate, exchanges it for a session, confirms the resulting identity is the profile's role, and checks the session is denied everything outside AmazonS3ReadOnlyAccess"
}
output "credential_test_linux_aarch64" {
  value       = local.posix_credential_test["linux_aarch64"]
  description = "Full IAM Roles Anywhere credential test for Linux Aarch64: verifies the key matches the certificate, exchanges it for a session, confirms the resulting identity is the profile's role, and checks the session is denied everything outside AmazonS3ReadOnlyAccess"
}
output "credential_test_macos_x86_64" {
  value       = local.posix_credential_test["macos_x86_64"]
  description = "Full IAM Roles Anywhere credential test for macOS x86-64: verifies the key matches the certificate, exchanges it for a session, confirms the resulting identity is the profile's role, and checks the session is denied everything outside AmazonS3ReadOnlyAccess"
}
output "credential_test_macos_aarch64" {
  value       = local.posix_credential_test["macos_aarch64"]
  description = "Full IAM Roles Anywhere credential test for macOS Aarch64: verifies the key matches the certificate, exchanges it for a session, confirms the resulting identity is the profile's role, and checks the session is denied everything outside AmazonS3ReadOnlyAccess"
}
output "credential_test_windows_x86_64" {
  value       = local.windows_credential_test
  description = "Full IAM Roles Anywhere credential test for Windows x86-64 as a PowerShell script: verifies the certificate exchange, confirms the resulting identity is the profile's role, and checks the session is denied everything outside AmazonS3ReadOnlyAccess"
}
output "trust_anchor_arn" {
  value       = aws_rolesanywhere_trust_anchor.iam_ra_trust_anchor.arn
  description = "Trust anchor the certificate is presented to. The role's trust policy names this ARN in an ArnEquals condition, so a certificate from any other anchor cannot assume the role"
}
output "profile_arn" {
  value       = aws_rolesanywhere_profile.iam_ra_profile.arn
  description = "IAM Roles Anywhere profile that lists the assumable role and caps the session length"
}
output "role_arn" {
  value       = aws_iam_role.s3_read_only_role.arn
  description = "Role the session assumes. Its permissions are exactly AmazonS3ReadOnlyAccess, which is what the test script's allow and deny checks assert"
}
output "session_duration_seconds" {
  value       = var.session_duration_seconds
  description = "Longest session this deployment can issue, applied to both the profile and the role's MaxSessionDuration. The credential helper still requests 3600 unless given --session-duration"
}
