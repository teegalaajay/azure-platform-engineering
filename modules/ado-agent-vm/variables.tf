variable "name" {
  description = "VM name, e.g. vm-adoagent-shared. Passed to modules/linux-vm, which validates it."
  type        = string
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
  description = "Subnet the agent attaches to (snet-mgmt), passed by ID. The Key Vault firewall allows this subnet only."
  type        = string
}

variable "size" {
  description = "VM size. No default: availability is per subscription and zone."
  type        = string
}

variable "zone" {
  description = "Availability zone (1, 2 or 3). No default: SKU restrictions are per zone."
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key TEXT, required by modules/linux-vm. The agent has no inbound path."
  type        = string
}

variable "tags" {
  description = "Tags applied to the VM and NIC (six mandatory tags are validated by modules/linux-vm)"
  type        = map(string)
}

variable "private_ip_address" {
  description = "Static private IPv4 in the subnet, or null for Dynamic"
  type        = string
  default     = null
}

variable "user_assigned_identity_id" {
  description = "Resource ID of the user-assigned managed identity attached to the VM (from platform/agent-identity). modules/linux-vm validates its format."
  type        = string
}

variable "identity_client_id" {
  description = "Client ID (GUID) of that identity. cloud-init passes it to az login --identity so the right identity is used."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.identity_client_id))
    error_message = "identity_client_id must be a GUID."
  }
}

variable "key_vault_name" {
  description = "Key Vault that holds the agent token secret"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.key_vault_name))
    error_message = "key_vault_name must be 3-24 characters: letters, digits and hyphens, starting with a letter."
  }
}

variable "agent_token_secret_name" {
  description = "Name of the Key Vault secret holding the Azure DevOps PAT used only to register the agent"
  type        = string

  validation {
    condition     = can(regex("^[0-9a-zA-Z-]{1,127}$", var.agent_token_secret_name))
    error_message = "agent_token_secret_name must be 1-127 characters: letters, digits and hyphens."
  }
}

variable "ado_organization_url" {
  description = "Azure DevOps organization URL, e.g. https://dev.azure.com/myorg"
  type        = string

  validation {
    condition     = can(regex("^https://dev\\.azure\\.com/[A-Za-z0-9][A-Za-z0-9-]*$", var.ado_organization_url))
    error_message = "ado_organization_url must look like https://dev.azure.com/<organization>."
  }
}

variable "agent_pool" {
  description = "Agent pool the agent registers into. The pool must already exist."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]{1,64}$", var.agent_pool))
    error_message = "agent_pool must be 1-64 characters: letters, digits, underscore, dot and hyphen (no spaces)."
  }
}

variable "agent_version" {
  description = "Pinned Azure Pipelines agent version, e.g. 5.281.1"
  type        = string

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.agent_version))
    error_message = "agent_version must look like 5.281.1."
  }
}

variable "agent_sha256" {
  description = "SHA-256 of the pinned pipelines-agent-linux-x64 tarball (64 lowercase hex characters)"
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.agent_sha256))
    error_message = "agent_sha256 must be 64 lowercase hex characters."
  }
}

variable "terraform_version" {
  description = "Terraform version installed from the HashiCorp apt repo and held, without the -1 suffix"
  type        = string

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.terraform_version))
    error_message = "terraform_version must look like 1.16.4."
  }
}
