variable "ssh_allowed_cidr" {
  description = "Public IPv4 address allowed to connect over SSH, in x.x.x.x/32 form"
  type        = string

  validation {
    condition     = can(cidrnetmask(var.ssh_allowed_cidr)) && endswith(var.ssh_allowed_cidr, "/32")
    error_message = "ssh_allowed_cidr must be a single IPv4 address in x.x.x.x/32 form."
  }
}

variable "ssh_public_key_path" {
  description = "Path to the public SSH key uploaded to the server"
  type        = string
}

variable "location" {
  description = "Hetzner location"
  type        = string
  default     = "fsn1"
}

variable "server_type" {
  description = "Server type (cax21 = ARM, 4 vCPU, 8 GB RAM)"
  type        = string
  default     = "cax21"
}

variable "server_name" {
  description = "Server name in Hetzner"
  type        = string
  default     = "socialagent-lab"
}

variable "image" {
  description = "Server operating system image"
  type        = string
  default     = "ubuntu-24.04"
}
