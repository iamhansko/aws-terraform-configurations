terraform {
  required_providers {
    kubectl = { source = "alekc/kubectl" }
  }
}
# No http provider here any more. The bundle is fetched by the root and passed in, because a depends_on
# on this module's block would defer a data source declared here until apply - and the documents have to
# be known at plan time to key the for_each by them (rules.md B-8/D-6). main.tf has the long version.
