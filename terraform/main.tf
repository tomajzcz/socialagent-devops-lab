resource "hcloud_ssh_key" "admin" {
  name       = "${var.server_name}-admin"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

resource "hcloud_firewall" "lab" {
  name = "${var.server_name}-fw"

  rule {
    description = "SSH from admin IP only"
    direction   = "in"
    protocol    = "tcp"
    port        = "22"
    source_ips  = [var.ssh_allowed_cidr]
  }

  rule {
    description = "ICMP (ping) from admin IP only"
    direction   = "in"
    protocol    = "icmp"
    source_ips  = [var.ssh_allowed_cidr]
  }
}

resource "hcloud_server" "lab" {
  name         = var.server_name
  server_type  = var.server_type
  location     = var.location
  image        = var.image
  ssh_keys     = [hcloud_ssh_key.admin.id]
  firewall_ids = [hcloud_firewall.lab.id]

  public_net {
    ipv4_enabled = true # primary IPv4 is billed separately
    ipv6_enabled = true
  }

  labels = {
    project = "socialagent-devops-lab"
    managed = "terraform"
  }
}
