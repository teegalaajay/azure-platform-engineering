variable "location" {
  description = "Azure region for the cluster resource groups and the cluster"
  type        = string
}

variable "environment" {
  description = "Environment name; used in resource names and tags"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "data_classification" {
  description = "Data classification tag (engineering_standards section 8)"
  type        = string

  validation {
    condition     = contains(["internal", "confidential", "gxp-regulated"], var.data_classification)
    error_message = "data_classification must be internal, confidential or gxp-regulated."
  }
}

variable "network_resource_group_name" {
  description = "Resource group of the spoke VNet (platform/foundation/<environment>); read, never managed here"
  type        = string
}

variable "vnet_name" {
  description = "Spoke VNet that holds snet-aks-nodes; read, never managed here"
  type        = string
}

variable "pod_cidr" {
  description = "AKS overlay pod range. Must equal aks_pod_cidr in platform/foundation/<environment>, which opens the NSG for it."
  type        = string

  validation {
    condition     = can(cidrhost(var.pod_cidr, 0))
    error_message = "pod_cidr must be a valid CIDR."
  }
}

variable "registry_name" {
  description = "Container registry the kubelet identity may pull from (platform/registry, ADR-0036); read, never managed here"
  type        = string
}

variable "registry_resource_group_name" {
  description = "Resource group of the container registry"
  type        = string
}

variable "system_vm_size" {
  description = "VM size of the tainted system pool (two nodes)"
  type        = string
}

variable "user_vm_size" {
  description = "VM size of the user pool (one node)"
  type        = string
}

variable "grant_acr_pull" {
  description = "Assign AcrPull on the registry to the kubelet identity. False only to observe the refusal before the role exists."
  type        = bool
}
