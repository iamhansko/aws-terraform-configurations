terraform {
  required_providers {
    # aws only: a CodeStar connection, a CodeBuild source credential and an S3 bucket. Nothing
    # here touches the cluster.
    aws = { source = "hashicorp/aws" }
  }
}
