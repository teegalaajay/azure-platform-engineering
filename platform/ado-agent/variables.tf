variable "environment" {
  description = "Environment tag value and name suffix; the agent serves the whole platform"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "data_classification" {
  description = "Data classification tag (engineering_standards §8)"
  type        = string

  validation {
    condition     = contains(["internal", "confidential", "gxp-regulated"], var.data_classification)
    error_message = "data_classification must be internal, confidential or gxp-regulated."
  }
}

variable "vm_size" {
  description = "VM size; availability is per subscription and zone (az vm list-skus)"
  type        = string
}

variable "vm_zone" {
  description = "Availability zone; SKU restrictions are per zone"
  type        = string
}

variable "private_ip_address" {
  description = "Static private IP in snet-mgmt (not .0-.3, reserved by Azure)"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key text. Supplied as TF_VAR_ssh_public_key; never committed."
  type        = string
}

variable "ado_organization_url" {
  description = "Azure DevOps organization URL. Supplied as TF_VAR_ado_organization_url; never committed."
  type        = string
}

variable "agent_pool" {
  description = "Agent pool the agent registers into; created in Azure DevOps before the apply"
  type        = string
}

variable "agent_token_secret_name" {
  description = "Key Vault secret holding the agent registration PAT"
  type        = string
}

variable "agent_version" {
  description = "Pinned Azure Pipelines agent version"
  type        = string
}

variable "agent_sha256" {
  description = "SHA-256 of the pinned pipelines-agent-linux-x64 tarball"
  type        = string
}

variable "terraform_version" {
  description = "Terraform version installed on the agent (held); matches engineering_standards §4"
  type        = string
}
