output "web_server" {
  value       = "http://${module.application_load_balancer.dns_name}"
  description = "Load Test - Auto Scaling"
}

output "key_pair_value" {
  value       = "https://${data.aws_region.current.region}.console.aws.amazon.com/systems-manager/parameters/%252Fec2%252Fkeypair%252F${module.key_pair.key_pair_id}"
  description = "KeyPair Value"
}
