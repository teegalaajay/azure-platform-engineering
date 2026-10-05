variable "environment" {
  description = "Environment name; selects the foundation state and drives names and the environment tag"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "location" {
  description = "Azure region for the workload resource group and VM"
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
  description = "VM size; availability is per subscription and region (az vm list-skus)"
  type        = string
}

variable "vm_zone" {
  description = "Availability zone for the VM; SKU restrictions are per zone"
  type        = string
}

variable "private_ip_address" {
  description = "Static private IP in snet-app (not .0-.3, reserved by Azure)"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key text. Supplied as TF_VAR_ssh_public_key; never committed."
  type        = string
}
