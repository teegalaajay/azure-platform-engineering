# Runbook: platform-dns (private DNS zones and the ephemeral DNS Private Resolver)

- **Purpose:** Keep the three `privatelink` zones and their VNet links correct, add a zone or a VNet, check a link
  against Azure, and build, test and destroy the DNS Private Resolver (`platform/dns-resolver`). See ADR-0042.
- **Owner:** platform-team
- **Last validated:** 2026-11-12 (session 2: resolver built and destroyed, a throwaway private endpoint registered in the
  blob zone, lookups from a dev VM and through the inbound endpoint returned the private IP)
- **Persistent:** `platform/dns` yes (zones and links, small items, cost not looked up). `platform/dns-resolver` no: about
  USD 0.50 per hour (two endpoints at 180 per month each, one ruleset at 2.5 per month, read from the Retail Prices API);
  build, test and destroy in the same session.

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
| Resolver root | `platform/dns-resolver`, state key `platform/dns-resolver.tfstate`, in `SKIP_ROOTS`, applied by hand |
| Resolver objects | `rg-dns-resolver-shared`: `dnspr-hub-shared` (hub VNet), inbound `in-dnspr-hub-shared` at static `10.20.4.4` in `snet-dns-in`, outbound `out-dnspr-hub-shared` in `snet-dns-out`, ruleset `dnsfrs-hub-shared` with rule `onprem.internal.` -> `10.30.0.53:53`, ruleset links `vnetlink-hub` and `vnetlink-dev` |

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

## Build the resolver (ephemeral)

1. Read the price first (Retail Prices API, `serviceName eq 'Azure DNS'`, Consumption rows for the resolver meters).
2. `terraform plan` in `platform/foundation/hub` is `No changes`: both resolver subnets must carry their delegation before
   the build (see Destroy, step 3).
3. In `platform/dns-resolver`: `terraform plan -out=tfplan`, expect `8 to add`; `terraform apply tfplan`; the second plan
   is `No changes`. The output `inbound_endpoint_ip` is `10.20.4.4`.

## Test from a VM (no public IP, through run-command)

- `az vm run-command invoke -g <rg> -n <vm> --command-id RunShellScript --scripts "dig +noall +answer <account>.blob.core.windows.net; dig +noall +answer @10.20.4.4 <account>.blob.core.windows.net" --query "value[0].message" -o tsv`
- Expect the public CNAME into `<account>.privatelink.blob.core.windows.net`, then the endpoint's private IP, on both
  paths (observed 2026-11-12). The record in the zone: `az network private-dns record-set a list -g rg-dns-shared -z privatelink.blob.core.windows.net -o table`.
- Forwarding: `dig +time=3 +tries=1 host.onprem.internal` times out (forwarded to 10.30.0.53, where nothing listens);
  `host.notonprem.internal` returns `NXDOMAIN` (observed 2026-11-12).

## Destroy the resolver

1. In `platform/dns-resolver`: `terraform destroy`, expect `8 to destroy`.
2. `az group exists -n rg-dns-resolver-shared` prints `false`.
3. **Then apply the hub (ADR-0042, decision 15).** Azure DNS Managed Resolver removes the delegation from `snet-dns-in`
   and `snet-dns-out` when the endpoints are deleted. In `platform/foundation/hub`: `terraform plan -out=tfplan`, expect
   `0 to add, 2 to change, 0 to destroy` (the two `delegation` blocks); `terraform apply tfplan`; the next plan is
   `No changes` (observed 2026-11-12).
4. `terraform plan` in `platform/dns` is `No changes`: records written by zone groups are not part of this root.

## What a client sees

| Situation | Answer |
|---|---|
| Private endpoint exists and its zone group wrote the A record in the matching zone | the private IP (observed 2026-11-12) |
| Same, asked through the inbound endpoint `10.20.4.4` | the same private IP (observed 2026-11-12) |
| Client outside every link (the workstation) | CNAME to Microsoft's public storage host, public IP (observed 2026-11-12) |
| Private endpoint deleted | no `privatelink` hop any more, public address (observed 2026-11-12); the zone is not asked |
| Private endpoint exists, no A record in the zone | with `NxDomainRedirect`, the public address; with the default policy, NXDOMAIN (read, not tested) |
| VNet not linked to the zone | the public address, with no sign of a problem (read) |
| Account without a private endpoint (a vendor's account) | the public address (read) |

Under `NxDomainRedirect` a missing record is not an error to the client. Check the zone, not the client, when a name
resolves to a public address that should be private.

## Symptoms

| Symptom | Likely cause and check |
|---|---|
| Plan fails reading a VNet in `data.azurerm_virtual_network.this` | wrong name or resource group in `linked_vnets` (reasoned from the data source) |
| Apply refused with `RequestDisallowedByPolicy` | a policy at `mg-platform` objects; read the error, it names the assignment. Zones and links applied without this on 2026-11-12 |
| A name resolves to a public address from a linked VNet | no private endpoint, no A record in the zone, or the VNet's resolver is not Azure-provided (custom DNS servers must forward to 168.63.129.16) |
| The hub plan wants to add `delegation` to `snet-dns-in` and `snet-dns-out` | the resolver was destroyed: Azure DNS Managed Resolver removes the delegation (activity log: `Delete Service Association Link`, then `Create or Update Virtual Network Subnet`). Apply the hub (Destroy, step 3) |
| Apply refused for the storage account with `RequestDisallowedByPolicy` | the `platform-baseline` initiative requires `shared_access_key_enabled = false` on every storage account |
| A name under `onprem.internal` returns `NXDOMAIN` from a dev VM | the ruleset is not linked to that VNet, or the resolver is not built |

## Not tested

- The `NxDomainRedirect` fallback (the zone was never asked after the endpoint was deleted); a real on-premises
  forwarder; a resolver build on an undelegated subnet; an NSG on the resolver subnets; deleting a link or a zone that
  holds records; the first apply of `platform/dns` from CI; build and destroy times.
