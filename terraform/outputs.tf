output "server_ipv4" {
  description = "Veřejná IPv4 serveru"
  value       = hcloud_server.lab.ipv4_address
}

output "server_ipv6" {
  description = "Veřejná IPv6 serveru"
  value       = hcloud_server.lab.ipv6_address
}

output "ssh_command" {
  description = "Příkaz pro první připojení"
  value       = "ssh root@${hcloud_server.lab.ipv4_address}"
}