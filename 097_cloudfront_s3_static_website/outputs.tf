# These outputs carry their value expressions directly rather than projecting a local.outputs map.
#
# That map exists to keep a root's outputs and the README written onto a VS Code instance from drifting
# apart, so it applies only to roots that declare module "vscode_ec2" (rules.md H-2). There is no instance
# in this root - the whole project is a bucket and a distribution - so there is no second copy of these
# values to keep in step.
output "site_url" {
  value       = module.distribution.url
  description = "The site, through CloudFront. A newly created distribution takes several minutes to deploy after apply returns, so a failure here straight away is usually distribution_status_command rather than a broken configuration"
}
output "distribution_id" {
  value       = module.distribution.id
  description = "Distribution id, which an invalidation names"
}
output "distribution_domain_name" {
  value       = module.distribution.domain_name
  description = "The distribution's hostname under cloudfront.net"
}
output "bucket_name" {
  value       = module.website_bucket.bucket_name
  description = "Generated name of the bucket holding the site"
}
output "direct_website_url" {
  value       = module.website_bucket.direct_website_url
  description = "The origin, reachable without CloudFront. With restrict_origin_to_cloudfront on this should return 403 while site_url returns the page - that difference is the point of the setting. With it off, both serve the site, which is what the _monolithic template left open"
}
output "origin_is_restricted" {
  value       = module.website_bucket.requires_referer
  description = "Whether the bucket policy requires the secret header the distribution sends. False means the bucket is readable by anyone who knows the endpoint, which is not visible from the outside"
}
output "bypass_check_command" {
  # %%{ rather than %{ because %{ opens a template directive in HCL, and curl's format string uses the same
  # two characters. Written plainly it fails with "http_code is not a valid template control keyword".
  value       = "echo -n 'through cloudfront: '; curl -s -o /dev/null -w '%%{http_code}\\n' ${module.distribution.url}/; echo -n 'direct to origin:   '; curl -s -o /dev/null -w '%%{http_code}\\n' ${module.website_bucket.direct_website_url}/"
  description = "Both paths in one command. 200 then 403 is the restriction working; 200 then 200 means the origin is serving the world directly, which is what to expect with restrict_origin_to_cloudfront set false"
}
output "object_keys" {
  value       = module.website_bucket.object_keys
  description = "What is actually in the bucket. An empty list explains a distribution that answers 404 to everything, which is what the _monolithic template produced - it created the bucket and uploaded nothing"
}
output "distribution_status_command" {
  value       = module.distribution.status_command
  description = "Whether the distribution has finished deploying. It has to read Deployed before site_url answers"
}
output "invalidate_command" {
  value       = module.distribution.invalidate_command
  description = "Clears the edge caches after changing a page. The managed caching policy keeps a hit for a day, so an updated page still showing the old content is this rather than a failed upload"
}
