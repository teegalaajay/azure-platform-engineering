# Runbook: Network Foundation (hub and spokes)

**Purpose:** Deploy, verify and change the persistent network layer (ADR-0007).
**Owner:** platform-team · **Last validated:** 2026-10-04 (hub only) · **Persistent:** yes, never torn down casually

Placeholders: `<SUBSCRIPTION_ID>`. Real values are never committed to this public repository.

## 1. Layout

| Root | State key | Contents |
|---|---|---|
| `platform/foundation/hub` | `platform/foundation/hub.tfstate` | `rg-network-shared`, `vnet-hub-shared` (`10.20.0.0/16`), `snet-mgmt` + NSG |
| `platform/foundation/dev` (PR B) | `platform/foundation/dev.tfstate` | `vnet-spoke-dev` (`10.10.0.0/16`), subnets, NSGs, dev<->hub peering |
| `platform/foundation/prod` (PR B) | `platform/foundation/prod.tfstate` | `vnet-spoke-prod` (`10.11.0.0/16`), subnets, NSGs, prod<->hub peering |

Apply order: **hub, then dev, then prod.** Spoke roots look the hub VNet up during plan.

## 2. Deploy or converge (from `main` only)

Prerequisites: `az login --tenant <TENANT_ID>`, `ARM_SUBSCRIPTION_ID` exported (workstation-setup
runbook). Spoke roots also need `TF_VAR_operator_ip_cidr` (your public IP as `/32`).

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
