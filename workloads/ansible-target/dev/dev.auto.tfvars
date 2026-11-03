environment         = "dev"
location            = "eastus2"
data_classification = "internal" # dev holds no regulated data
vm_size             = "Standard_D2als_v6"
vm_zone             = "2" # zones 1 and 3 are restricted for this subscription (2026-10-05)
private_ip_address  = "10.10.1.11"

# Public half of the pipeline key (ADR-0029); the private half is in Key Vault.
ansible_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGsCahovzu/3ABbQ9qejeKWj5Exy5Ufa40OocmnLKFUl ansible-pipeline"
