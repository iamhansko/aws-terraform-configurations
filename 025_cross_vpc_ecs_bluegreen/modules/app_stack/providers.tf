terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
    # Zips the seed artefact the pipeline's creation-triggered execution reads. See
    # data.archive_file.seed_artifact.
    archive = { source = "hashicorp/archive" }
  }
}
