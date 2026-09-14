output "game_access_link" {
  value       = "http://${module.network_load_balancer.dns_name}"
  description = "Multiplayer Game"
}
