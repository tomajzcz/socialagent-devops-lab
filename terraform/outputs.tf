output "server_ipv4" {
  description = "Server public IPv4"
  value       = hcloud_server.lab.ipv4_address
}

output "server_ipv6" {
  description = "Server public IPv6"
  value       = hcloud_server.lab.ipv6_address
}
