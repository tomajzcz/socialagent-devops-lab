variable "ssh_allowed_cidr" {
  description = "Veřejná IPv4 adresa, ze které je povolené SSH, ve tvaru x.x.x.x/32"
  type        = string

  validation {
    condition     = can(cidrnetmask(var.ssh_allowed_cidr)) && endswith(var.ssh_allowed_cidr, "/32")
    error_message = "ssh_allowed_cidr musí být jedna IPv4 adresa ve tvaru x.x.x.x/32."
  }
}

variable "ssh_public_key_path" {
  description = "Cesta k veřejnému SSH klíči, který se nahraje na server"
  type        = string
}

variable "location" {
  description = "Lokalita Hetzneru"
  type        = string
  default     = "fsn1"
}

variable "server_type" {
  description = "Typ serveru (cax21 = ARM, 4 vCPU, 8 GB RAM)"
  type        = string
  default     = "cax21"
}

variable "server_name" {
  description = "Jméno serveru v Hetzneru"
  type        = string
  default     = "socialagent-lab"
}

variable "image" {
  description = "Operační systém serveru"
  type        = string
  default     = "ubuntu-24.04"
}
