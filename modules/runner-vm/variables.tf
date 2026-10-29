variable "name" {
  description = "VM name, e.g. vm-runner-shared. Passed to modules/linux-vm, which validates it."
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
  description = "Subnet the runner attaches to (snet-mgmt), passed by ID."
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
  description = "SSH public key TEXT, required by modules/linux-vm. The runner has no inbound path."
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

variable "repo_url" {
  description = "Repository the runner registers to, e.g. https://github.com/owner/repo"
  type        = string

  validation {
    condition     = can(regex("^https://github\\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.repo_url))
    error_message = "repo_url must look like https://github.com/<owner>/<repo>."
  }
}

variable "registration_token" {
  description = "One-hour runner registration token, minted just before apply. Ends up in state and in the VM's boot data."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.registration_token) > 0
    error_message = "registration_token must not be empty."
  }
}

variable "runner_version" {
  description = "Pinned actions/runner version without the leading v, e.g. 2.338.0"
  type        = string

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.runner_version))
    error_message = "runner_version must look like 2.338.0 (no leading v)."
  }
}

variable "runner_sha256" {
  description = "SHA-256 of the pinned linux-x64 runner tarball (64 hex characters)"
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.runner_sha256))
    error_message = "runner_sha256 must be 64 lowercase hex characters (no sha256: prefix)."
  }
}

variable "terraform_version" {
  description = "Terraform version installed from the HashiCorp apt repo and held, without the -1 suffix"
  type        = string
}

variable "labels" {
  description = "Runner labels; workflows select the runner with these"
  type        = list(string)
  default     = ["platform-apply"]
}

variable "user_assigned_identity_ids" {
  description = "Resource IDs of user-assigned managed identities attached to the VM; passed to linux-vm. Empty = no identity."
  type        = list(string)
  default     = []
}
