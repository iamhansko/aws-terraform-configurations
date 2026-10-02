terraform {
  required_providers {
    # github only. This module owns the Git repository Argo CD is pointed at and nothing in AWS -
    # the CodeStar connection, the CodeBuild credential and the source bucket stay in
    # modules/github_source, which owns no GitHub object in return.
    github = { source = "integrations/github" }
  }
}
