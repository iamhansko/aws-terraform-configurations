terraform {
  required_providers {
    # aws only: a certificate, its validation records and the wait. Nothing here touches the
    # cluster.
    aws = { source = "hashicorp/aws" }
  }
}
