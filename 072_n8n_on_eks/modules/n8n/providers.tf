terraform {
  required_providers {
    kubectl = { source = "alekc/kubectl" }
    # The Postgres credentials are generated here rather than shipped as literals, so this module
    # owns a random resource as well as manifests.
    random = { source = "hashicorp/random" }
  }
}
