# ADR-0008: Linux VM module and the vm-demo workload root

- **Status:** Accepted
- **Date:** 2026-10-05
- **Deciders:** platform-team (@teegalaajay)

## Context

Workloads need Linux VMs that meet one baseline in every environment: private only, key-based
SSH, trusted launch. VM size and zone availability differ per subscription and region, so a size
chosen from memory can fail at apply. A VM registered in DNS must keep its address across
rebuilds, and ADR-0007 requires explicit egress for subnets that no longer offer implicit
outbound access. The workload also has to find the subnet that the foundation roots own.

## Options considered

**Where the baseline lives**
1. **Every setting a module variable.** Any caller can add a public IP or enable passwords.
2. **Baseline hardcoded in `modules/linux-vm`; placement and identity are inputs.**

**Private IP**
3. **Always dynamic.** Stable while the NIC exists, but a rebuilt or restored VM gets a new NIC and
   an address Azure documents as not deterministic.
4. **Optional static input (`private_ip_address`, default `null` = dynamic).**

**How the workload finds the subnet**
5. **Name lookup inside the module** (data source: subnet, VNet and RG names). Couples the module
   to the foundation's naming, hides the dependency edge and fails at plan if the subnet is absent.
6. **Subnet ID as a module input, fed from the foundation's output via `terraform_remote_state`.**

**Egress for a VM with no public IP**
7. **Public IP on the NIC.** An admin shortcut; not an enterprise pattern.
8. **Standing NAT Gateway in the foundation.** About USD 33/month against a USD 50 budget.
9. **Interim NAT Gateway in the workload root**, replaced by the Week 8 firewall and UDR.

## Decision

Options 2, 4, 6 and 9.

- **`modules/linux-vm`** hardcodes: no public IP, password authentication disabled, trusted launch
  (secure boot and vTPM), Gen2 Ubuntu 24.04 LTS, `StandardSSD_LRS`, managed boot diagnostics.
  Inputs: `name`, `resource_group_name`, `location`, `subnet_id` (validated as a subnet resource
  ID), `size` and `zone` (no defaults: availability is per subscription and zone), `ssh_public_key`
  (key text, validated; never a file path), `admin_username`, optional `private_ip_address` and
  `tags` (six mandatory tags validated, null and blank rejected).
- **`workloads/vm-demo/dev`** owns its resource group, so its lifecycle is separate from the
  foundation's. It reads `subnet_ids["app"]` from `platform/foundation/dev.tfstate`. The key is
  supplied as `TF_VAR_ssh_public_key`, not committed.
- **Size and zone from evidence (2026-10-05):** `Standard_D2as_v6` and `Standard_D2als_v6` are
  restricted (`NotAvailableForSubscription`) in zones 1 and 3 of `eastus2`; zone 2 is usable. The
  demo uses `Standard_D2als_v6` in zone 2. Re-check with `az vm list-skus` before changing either.
- **Static IP:** the demo pins `10.10.1.10` (`.0` to `.3` are reserved by Azure).
- **Egress:** the NAT Gateway, its public IP and the `azurerm_subnet_nat_gateway_association` live
  in the workload root, so the cost stops when the workload is destroyed.

## Consequences

- **Cross-root coupling.** Terraform tracks no dependency between roots. Renaming the foundation
  output key breaks this root at its next `plan` (`Invalid index`), and nothing warns the
  foundation's PR. Foundation outputs are a contract; rename them with the consumers.
- **State read is a data-plane call.** The operator needs Storage Blob Data Reader (Contributor
  here) on the state account; `Reader`, Owner and Contributor roles carry no blob data actions.
  Anyone who can read the foundation state can read all its outputs.
- **NAT association on a foundation-owned subnet.** After the apply, `plan` in
  `platform/foundation/dev` showed `No changes` (2026-10-05). Not tested: whether an in-place
  update of the foundation subnet drops the NAT link.
- **No interactive access yet.** The VM is private with no inbound path; Bastion (Week 8) or the
  runner in `snet-mgmt` (Week 3 Day 6) provide it. Day 2 verification used the control plane
  (`az vm show -d`, read-only `az vm run-command`).
- **Proven egress:** the VM's source address equalled the NAT's public IP.
- Cost while up: the VM and the NAT Gateway bill hourly; the workload is destroyed the same day.
