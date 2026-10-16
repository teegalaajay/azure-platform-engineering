variable "environment" {
  description = "Environment tag value and name suffix; the runner serves the whole platform"
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

variable "repo_url" {
  description = "Repository the runner registers to"
  type        = string
}

variable "registration_token" {
  description = "One-hour runner registration token. Supplied inline as TF_VAR_registration_token for a single command; never committed, never in .bashrc."
  type        = string
  sensitive   = true
}

variable "runner_version" {
  description = "Pinned actions/runner version without the leading v"
  type        = string
}

variable "runner_sha256" {
  description = "SHA-256 of the pinned linux-x64 runner tarball (no sha256: prefix)"
  type        = string
}

variable "terraform_version" {
  description = "Terraform version installed on the runner (held); matches engineering_standards §4"
  type        = string
}
