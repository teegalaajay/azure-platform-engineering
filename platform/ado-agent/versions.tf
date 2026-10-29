# Copy into every root module (platform/*, workloads/*). Keep versions identical everywhere.
terraform {
  # Guard, not a pin (the exact pin is apt-mark hold + CI). Floor = oldest Terraform with every
  # language feature this code uses: raise it when a newer one is adopted (e.g. write-only args need 1.11).
  required_version = ">= 1.9.0, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}
