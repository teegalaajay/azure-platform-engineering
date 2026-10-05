resource "azurerm_network_interface" "this" {
  name                = "nic-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = var.private_ip_address == null ? "Dynamic" : "Static" # private IP only: no public_ip_address_id (ADR-0007)
    private_ip_address            = var.private_ip_address
  }
}

resource "azurerm_linux_virtual_machine" "this" {
  name                  = var.name
  resource_group_name   = var.resource_group_name
  location              = var.location
  size                  = var.size
  zone                  = var.zone
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.this.id] # reference = implicit dependency: NIC first
  tags                  = var.tags

  disable_password_authentication = true # SSH key only

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  # Trusted launch baseline (Gen2 image)
  secure_boot_enabled = true
  vtpm_enabled        = true

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  boot_diagnostics {} # Azure-managed storage: serial log and screenshot without a storage account
}
