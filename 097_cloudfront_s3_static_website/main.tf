data "aws_region" "current" {}
# The managed cache policy, looked up by name. The alternative is writing the uuid into the configuration,
# which is what the console shows and what most examples copy - and a bare uuid tells a reader nothing.
data "aws_cloudfront_cache_policy" "default" {
  name = var.cache_policy_name
}
# The secret the distribution sends and the bucket policy requires.
#
# Generated rather than configured, so it is never a value someone chose and reused. It lands in state, which
# is unavoidable for a shared secret and is the reason this mitigation is weak - see
# restrict_origin_to_cloudfront for what it does and does not buy.
#
# special = false because the value travels in a Referer header and is compared by S3 as a literal string:
# punctuation would survive but adds nothing and makes the value harder to paste into a curl command when
# testing the restriction by hand.
resource "random_password" "origin_referer" {
  count   = var.restrict_origin_to_cloudfront ? 1 : 0
  length  = 32
  special = false
}
locals {
  origin_referer = var.restrict_origin_to_cloudfront ? random_password.origin_referer[0].result : null
  # The two pages. Inline rather than files on disk, so the project is self-contained and a plan shows what
  # will be served - and so the title can come from a variable (rules.md B-3).
  site_pages = merge(
    {
      (var.index_document) = <<-HTML
        <!DOCTYPE html>
        <html lang="en">
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>${var.site_title}</title>
          </head>
          <body>
            <h1>${var.site_title}</h1>
            <p>Served from an S3 website endpoint through CloudFront.</p>
            <p><a href="/missing-page">Follow this link</a> to see the error document, which the website
            endpoint resolves rather than CloudFront.</p>
          </body>
        </html>
      HTML
    },
    var.error_document == null ? {} : {
      (var.error_document) = <<-HTML
        <!DOCTYPE html>
        <html lang="en">
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>${var.site_title} - not found</title>
          </head>
          <body>
            <h1>Not found</h1>
            <p>This is the bucket's error document. Reaching it means the website endpoint resolved the
            request, not CloudFront - the REST endpoint would have returned its own XML instead.</p>
            <p><a href="/">Back to the start</a></p>
          </body>
        </html>
      HTML
    },
  )
}
module "website_bucket" {
  source = "./modules/static_website_bucket"

  name_prefix    = "${var.project_name}-"
  index_document = var.index_document
  error_document = var.error_document
  objects        = local.site_pages
  # Null when the restriction is off, which is the _monolithic template's behaviour: a bucket policy that
  # allows anyone to read every object.
  required_referer = local.origin_referer
}
module "distribution" {
  source = "./modules/cloudfront_distribution"

  comment = "${var.project_name} - ${var.site_title}"
  # The website endpoint's hostname, taken from the bucket module rather than assembled here: its shape
  # differs between older and newer regions and an assembled one that is wrong is an origin that never
  # resolves (rules.md B-5).
  origin_domain_name = module.website_bucket.website_endpoint
  # The same key the website configuration serves for a directory, so the two cannot disagree.
  default_root_object = module.website_bucket.index_document
  # The secret, as the header S3 will compare. Empty when the restriction is off.
  origin_custom_headers  = local.origin_referer == null ? {} : { Referer = local.origin_referer }
  viewer_protocol_policy = var.viewer_protocol_policy
  cache_policy_id        = data.aws_cloudfront_cache_policy.default.id
  price_class            = var.price_class

  # The bucket policy has to be in place before the distribution starts serving, or the first requests are
  # 403s that then sit in the edge caches. Referencing the website endpoint orders this after the website
  # configuration only, not after the policy (rules.md D-2).
  depends_on = [module.website_bucket]
}
