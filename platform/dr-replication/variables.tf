variable "location" {
  description = "Target region of the replicated VM and its resource group."
  type        = string
}

variable "environment" {
  description = "Environment tag of the replicated workload."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "data_classification" {
  description = "Data classification tag of the replicated workload."
  type        = string

  validation {
    condition     = contains(["internal", "confidential", "gxp-regulated"], var.data_classification)
    error_message = "data_classification must be internal, confidential or gxp-regulated."
  }
}

variable "source_vm_name" {
  description = "Name of the VM to replicate."
  type        = string
}

variable "source_vm_resource_group_name" {
  description = "Resource group of the VM to replicate."
  type        = string
}

variable "target_resource_group_name" {
  description = "Resource group in the target region that receives the failed-over VM and its disks."
  type        = string
}

variable "target_zone" {
  description = "Availability zone of the VM after failover."
  type        = string

  validation {
    condition     = contains(["1", "2", "3"], var.target_zone)
    error_message = "target_zone must be 1, 2 or 3."
  }
}

variable "target_subnet_name" {
  description = "Subnet of the target network that the failed-over NIC joins."
  type        = string
}

variable "test_subnet_name" {
  description = "Subnet of the isolated test network that a test failover NIC joins."
  type        = string
}
