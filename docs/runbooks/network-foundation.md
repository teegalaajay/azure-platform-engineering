# Runbook: Network Foundation (hub and spokes)

**Purpose:** Deploy, verify and change the persistent network layer (ADR-0007).
**Owner:** platform-team · **Last validated:** 2026-10-04 · **Persistent:** yes, never torn down casually

Placeholders: `<SUBSCRIPTION_ID>`. Real values are never committed to this public repository.

## 1. Layout

| Root | State key | Contents |
|---|---|---|
| `platform/foundation/hub` | `platform/foundation/hub.tfstate` | `rg-network-shared`, `vnet-hub-shared` (`10.20.0.0/16`), `snet-mgmt` + NSG |
| `platform/foundation/dev` | `platform/foundation/dev.tfstate` | `vnet-spoke-dev` (`10.10.0.0/16`), subnets, NSGs, dev<->hub peering |
| `platform/foundation/prod` | `platform/foundation/prod.tfstate` | `vnet-spoke-prod` (`10.11.0.0/16`), subnets, NSGs, prod<->hub peering |

Apply order: **hub, then dev, then prod.** Spoke roots look the hub VNet up during plan.

## 2. Deploy or converge (from `main` only)

Prerequisites: `az login --tenant <TENANT_ID>`, `ARM_SUBSCRIPTION_ID` exported (workstation-setup
runbook). Spoke roots also need `TF_VAR_operator_ip_cidr` (your public IP as `/32`), set once with
a guarded append to `~/.bashrc`. When your ISP changes your IP, edit that line by hand, then plan
and apply both spoke roots (expect `~ update in-place` on `nsg-app-spoke-*` only) and both
`workloads/storage-demo` roots (storage firewall, see the storage-demo runbook).

```bash
git switch main && git pull
cd platform/foundation/hub
terraform init
terraform plan        # review: only the expected addresses, no destroy
terraform apply
terraform plan        # expect: No changes
```

## 3. Verify

```bash
az network vnet show -g rg-network-shared -n vnet-hub-shared --query "addressSpace.addressPrefixes" -o tsv
# expect: 10.20.0.0/16
az network vnet subnet show -g rg-network-shared --vnet-name vnet-hub-shared -n snet-mgmt \
  --query "[addressPrefix, networkSecurityGroup.id]" -o tsv
# expect: 10.20.3.0/26 and the ID of nsg-mgmt-hub-shared
az network nsg rule list -g rg-network-shared --nsg-name nsg-mgmt-hub-shared -o table
# expect: one custom rule, deny-vnet-inbound, priority 4000
```

Spoke verification (repeat with `prod`):

```bash
az network vnet peering list -g rg-network-dev --vnet-name vnet-spoke-dev --query "[].{name:name, state:peeringState}" -o table
az network vnet peering list -g rg-network-shared --vnet-name vnet-hub-shared --query "[].{name:name, state:peeringState}" -o table
# expect: every peering Connected (Initiated = only one side exists)
az network nsg rule list -g rg-network-dev --nsg-name nsg-app-spoke-dev -o table
# shows the operator IP: run locally, never paste into a PR or issue
```

## 4. Change rules

- Add or change rules only in the root's `subnets` input (`inbound_rules`), priority 100-3999.
  Rules change in place (`~ update`); the plan must not show a replaced NSG or subnet.
- **Never rename an NSG, a subnet key or a subnet** in an existing root. Renames force replacement;
  an NSG replacement leaves the subnet unfiltered between removing the old association and
  creating the new one, and an in-use subnet cannot be deleted.
- Never add standalone `azurerm_network_security_rule` resources for these NSGs.

## 5. Failure modes

| Symptom | Cause | Action |
|---|---|---|
| `NetcfgSubnetRangeOutsideVnet` at apply | subnet prefix outside the VNet address space | fix the prefix; plan cannot catch this |
| `InUseSubnetCannotBeDeleted` | a plan replaces a subnet that has NICs | stop; find the forcing attribute; never force it through |
| `already exists - to be managed via Terraform this resource needs to be imported` | resource exists in Azure but not in this state | `import` block, then plan; never delete the existing resource |
| Spoke plan: hub VNet `not found` | hub not applied yet, or wrong name | apply the hub from `main` first |
| Peering state `Initiated` | only one side exists | apply the spoke root again; both peerings live in it |
| Plan shows `security_rule = (sensitive value)` | NSG contains an operator rule (set redaction) | review rules in the code diff; verify after apply with `az network nsg rule list` |
| `No value for required variable operator_ip_cidr` | `TF_VAR_operator_ip_cidr` not set in this shell | `source ~/.bashrc`; never put the IP in a tfvars file |
