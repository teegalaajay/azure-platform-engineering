variable "name" {
  description = "VM name, e.g. vm-demo-dev. Also the NIC name suffix (nic-<name>)."
  type        = string

  validation {
    condition     = can(regex("^vm-[a-z0-9-]{1,60}$", var.name))
    error_message = "name must start with vm- and use lowercase letters, digits and hyphens (max 63 chars)."
  }
}

variable "resource_group_name" {
  description = "Existing resource group for the VM and NIC. The caller owns the RG."
  type        = string
}

variable "location" {
  description = "Azure region, e.g. eastus2"
  type        = string
}

variable "subnet_id" {
  description = "Subnet the NIC attaches to, passed by ID (never by name lookup)."
  type        = string

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.subnet_id))
    error_message = "subnet_id must be a full Azure subnet resource ID."
  }
}

variable "size" {
  description = "VM size. No default: availability is per subscription and region (az vm list-skus)."
  type        = string
}

variable "zone" {
  description = "Availability zone (1, 2 or 3). No default: SKU restrictions are per zone."
  type        = string

  validation {
    condition     = contains(["1", "2", "3"], var.zone)
    error_message = "zone must be 1, 2 or 3."
  }
}

variable "admin_username" {
  description = "Local admin user. Password authentication is disabled; SSH key only."
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key" {
  description = "SSH public key TEXT (not a file path). Public, not a secret. Never file(\"~/.ssh/...\")."
  type        = string

  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa) AAAA", var.ssh_public_key))
    error_message = "ssh_public_key must be public key text starting with ssh-ed25519 or ssh-rsa."
  }
}

variable "tags" {
  description = "Tags applied to the VM and NIC"
  type        = map(string)

  validation {
    condition = alltrue([
      for k in ["owner", "environment", "cost_center", "data_classification", "managed_by", "repo"] :
      try(trimspace(var.tags[k]) != "", false)
    ])
    error_message = "tags must include non-empty values for owner, environment, cost_center, data_classification, managed_by and repo."
  }
}

variable "private_ip_address" {
  description = "Static private IPv4 in the subnet (not .0-.3, which Azure reserves). null = Dynamic. Servers registered in DNS should set it."
  type        = string
  default     = null

  validation {
    condition     = var.private_ip_address == null || can(cidrnetmask("${var.private_ip_address}/32"))
    error_message = "private_ip_address must be null or a valid IPv4 address."
  }
}
