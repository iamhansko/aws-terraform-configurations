terraform {
  # 1.14, above the repository's 1.9, for one feature: the aws_codebuild_start_build action that builds the
  # ComfyUI image during the apply and holds the ECS task definition until the image exists (main.tf). The
  # write-only certificate key below needs 1.11, which this already covers.
  required_version = ">= 1.14"
  required_providers {
    # ~> 6.47 rather than the repository's ~> 6.0: aws_acm_certificate gained private_key_wo in 6.47, and the
    # aws_codebuild_start_build action arrived in 6.15. An older 6.x fails on either with an error about an
    # unsupported argument or action type rather than about a version. Still major version 6.
    aws = { source = "hashicorp/aws", version = "~> 6.47" }
    # ~> 4.4 for tls_self_signed_cert's private_key_pem_wo, which keeps the load balancer's private key out of
    # state (modules/load_balancer).
    tls = { source = "hashicorp/tls", version = "~> 4.4" }
    # time_sleep, for the one wait in modules/load_balancer: ACM will not import a certificate its own clock
    # says is still in the future, and the certificate's notBefore comes from this machine's clock.
    time = { source = "hashicorp/time", version = "~> 0.14" }
    # One read, and it is what the load balancer's security group admits: the address this machine appears as
    # from outside (data.http.my_ip in main.tf). It makes plan reach something that is not an AWS API, which
    # is a real cost - alb_ingress_cidr_blocks is how a caller avoids it.
    http    = { source = "hashicorp/http", version = "~> 3.4" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
  }
}
provider "aws" {
  region = var.aws_region
}
# What this configuration is, after the change.
#
# It used to manage a CodeBuild project that cloned aws-samples/cost-effective-aws-deployment-of-comfyui at
# build time and ran cdk deploy on it, so the VPC, the load balancer, the Cognito user pool, the GPU Auto
# Scaling group and the ECS service came from a CloudFormation stack this configuration never saw - and that
# terraform destroy left running. Every one of those is a resource here now, and nothing is cloned: the parts
# of the blueprint that are not infrastructure (the Dockerfile and its config file, the admin Lambda code, the
# sign-up domain check) are kept in this directory and shipped from it.
#
# No CDK bootstrap stack either. The blueprint published its container image and its Lambda code through
# CDKToolkit, which the old build created in a region that had none and which outlived everything else; the
# image now goes to an ECR repository of this configuration's own, and the Lambda code is uploaded directly.
