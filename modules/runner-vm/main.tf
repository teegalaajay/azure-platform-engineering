module "vm" {
  source = "../linux-vm"

  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.subnet_id
  size                = var.size
  zone                = var.zone
  ssh_public_key      = var.ssh_public_key
  private_ip_address  = var.private_ip_address
  tags                = var.tags

  # Rendered at plan time; the result is sensitive because registration_token is.
  custom_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    registration_token = var.registration_token
    runner_version     = var.runner_version
    runner_sha256      = var.runner_sha256
    terraform_version  = var.terraform_version
    repo_url           = var.repo_url
    runner_name        = var.name
    labels             = join(",", var.labels)
  })
}
