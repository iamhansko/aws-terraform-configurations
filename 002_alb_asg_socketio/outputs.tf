output "game_access_link" {
  value       = "http://${module.application_load_balancer.dns_name}"
  description = "Multiplayer Game"
}
