module "vm" {
  source = "../linux-vm"

  name                       = var.name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  subnet_id                  = var.subnet_id
  size                       = var.size
  zone                       = var.zone
  ssh_public_key             = var.ssh_public_key
  private_ip_address         = var.private_ip_address
  tags                       = var.tags
  user_assigned_identity_ids = [var.user_assigned_identity_id]

  # Rendered at plan time. No secret goes in: the agent token is read from Key Vault at first boot.
  custom_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    identity_client_id      = var.identity_client_id
    key_vault_name          = var.key_vault_name
    agent_token_secret_name = var.agent_token_secret_name
    ado_organization_url    = var.ado_organization_url
    agent_pool              = var.agent_pool
    agent_version           = var.agent_version
    agent_sha256            = var.agent_sha256
    terraform_version       = var.terraform_version
    agent_name              = var.name
  })
}
