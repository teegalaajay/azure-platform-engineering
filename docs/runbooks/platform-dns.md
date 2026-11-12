# Runbook: platform-dns (private DNS zones for private endpoints)

- **Purpose:** Keep the three `privatelink` zones and their VNet links correct, add a zone or a VNet, and check a link
  against Azure. See ADR-0042.
- **Owner:** platform-team
- **Last validated:** 2026-11-12 (apply, second plan `No changes`, links read back with the CLI; no private endpoint writes
  into these zones yet, so a name lookup has not been tested)
- **Persistent:** Yes. The root stays applied. The cost was not looked up; zones and links are small items.

## Layout

| Item | Value |
|---|---|
| Root | `platform/dns`, state key `platform/dns.tfstate` in the shared backend |
| Resource group | `rg-dns-shared` (eastus2). The zones and links are global resources |
| Zones | `privatelink.blob.core.windows.net`, `privatelink.vaultcore.azure.net`, `privatelink.azurecr.io` |
| Links | each zone to `vnet-hub-shared`, `vnet-spoke-dev`, `vnet-spoke-prod` (nine); registration off; `NxDomainRedirect` |
| Inputs | `dns.auto.tfvars`: `private_dns_zones` (map) and `linked_vnets` (map of name and resource group) |
| Outputs | `resource_group_name`, `private_dns_zone_ids`, `private_dns_zone_names` (keyed `blob`, `vault`, `acr`) |
| Hub subnets for the resolver | `snet-dns-in` 10.20.4.0/28 and `snet-dns-out` 10.20.4.16/28, created by `platform/foundation/hub`, delegated to `Microsoft.Network/dnsResolvers`, no NSG |
| Applied by | the apply workflow (`APPLY_ROOTS`, after the foundation roots). The first CI apply of this root has not run yet |

## Before you start

1. `[ "$(az account show --query id -o tsv)" = "$ARM_SUBSCRIPTION_ID" ] && echo MATCH || echo MISMATCH` prints `MATCH`.
   The CLI can also hold another account's subscription.
2. `terraform plan` in `platform/dns` is `No changes`.
3. Mask GUIDs before pasting anything: zone and link IDs contain the subscription ID.

## Add a service (a new zone)

1. Add one line to `private_dns_zones` in `dns.auto.tfvars`, for example a storage sub-resource such as `dfs`. Use the
   exact zone name Microsoft documents for that service; Terraform only checks the `privatelink.` prefix.
2. `terraform plan`: expect `4 to add` (the zone and three links), no change to existing resources.
3. Apply, then read the links back (see below).

## Add a VNet

1. Add an entry to `linked_vnets` with the VNet name and its resource group. The data source reads it by name, so a
   wrong name fails at plan time.
2. `terraform plan`: expect one new link per zone (three today).
3. Apply and read the links back.

## Read the links back from Azure

- Per zone: `az network private-dns link vnet list -g rg-dns-shared -z <zone name> --query "[].{name:name, policy:resolutionPolicy, registration:registrationEnabled, state:virtualNetworkLinkState}" -o table`.
- Expect one row per VNet, `NxDomainRedirect`, registration `False`, state `Completed` (observed for the blob zone on
  2026-11-12; the other two zones were counted, three each).
- `terraform plan` showing `No changes` proves Terraform agrees with its own read of Azure; the CLI read proves what Azure
  holds.

## What a client sees (read from the documentation; the lookup test is session 2)

| Situation | Expected answer |
|---|---|
| Private endpoint exists and its zone group wrote the A record in the matching zone | the private IP |
| Private endpoint exists, no A record in the zone | with `NxDomainRedirect`, the public address; with the default policy, NXDOMAIN |
| VNet not linked to the zone | the public address, with no sign of a problem |
| Account without a private endpoint (a vendor's account) | the public address |

Under `NxDomainRedirect` a missing record is not an error to the client. Check the zone, not the client, when a name
resolves to a public address that should be private.

## Symptoms

| Symptom | Likely cause and check |
|---|---|
| Plan fails reading a VNet in `data.azurerm_virtual_network.this` | wrong name or resource group in `linked_vnets` (reasoned from the data source) |
| Apply refused with `RequestDisallowedByPolicy` | a policy at `mg-platform` objects; read the error, it names the assignment. Zones and links applied without this on 2026-11-12 |
| A name resolves to a public address from a linked VNet | no private endpoint, no A record in the zone, or the VNet's resolver is not Azure-provided (custom DNS servers must forward to 168.63.129.16) |
| The hub plan wants to change `snet-dns-in` or `snet-dns-out` | the delegation block was edited or removed; both subnets must stay delegated to `Microsoft.Network/dnsResolvers` |

## Not tested

- A private endpoint registering in these zones; a lookup from a VM; the resolver endpoints; deleting a link or a zone
  that holds records; the first apply of this root from CI.
