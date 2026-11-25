# Runbook: platform-private-endpoints (private endpoints for the platform vault and the state account)

Root `platform/private-endpoints` (state key `platform/private-endpoints.tfstate`) puts one private endpoint for the
platform Key Vault and one for the state account blob service into the hub `snet-pe`. It is persistent and in
`APPLY_ROOTS`. The decisions and the evidence are in ADR-0046; DNS is in `platform-dns`.

## Layout

| Item | Where | Notes |
|---|---|---|
| Resource group | `rg-private-endpoints-shared` | holds the endpoints and their network interfaces |
| Vault endpoint | `pe-kv-plat-shared-at01` (sub-resource `vault`) | address `10.20.4.36` (root output, observed) |
| State endpoint | `pe-stattfstate01-blob` (sub-resource `blob`) | address `10.20.4.37` (root output, observed) |
| Subnet | hub `snet-pe` `10.20.4.32/27` | created by `platform/foundation/hub`; the NSG filters nothing here (ADR-0046, decision 3) |
| DNS records | zone groups `pdzg-vault` and `pdzg-blob` | write and remove the A records in the zones of `platform/dns` |
| Inputs read by name | `private-endpoints.auto.tfvars` | subnet, zones, vault, state account; data sources, not remote state |
| Outputs | `resource_group_name`, `private_endpoint_names`, `private_ip_addresses` | no resource IDs on purpose: an ID contains the subscription ID |

## Before you start

1. The subscription is `Enabled` and the CLI default matches `ARM_SUBSCRIPTION_ID`.
2. The hub subnet exists: `az network vnet subnet list -g rg-network-shared --vnet-name vnet-hub-shared -o table` lists
   `snet-pe`.
3. The zones exist: `az network private-dns zone list -g rg-dns-shared -o table` lists the blob, vault and ACR zones.

## Add an endpoint (a new service)

1. The zone for the service exists in `platform/dns` (`platform-dns`, "Add a service").
2. In `main.tf` add the zone to `zone_names`, a data source for the target resource and an entry in the `endpoints`
   map (name, resource ID, sub-resource, zone key).
3. `terraform plan` shows one endpoint to add per entry and nothing else. Apply from the branch by hand, or let the
   apply workflow do it after merge and approval.
4. Resolve the name from a VM in a linked VNet (below) before you call it done.
5. Cost: each endpoint bills about 0.01 per hour at list price (observed price list) plus data processed. A registry
   endpoint needs the Premium SKU (ADR-0046, decision 5).
6. When public access on the target is closed, add `CanNotDelete` and `prevent_destroy` to its endpoint (ADR-0046,
   decision 7).

## Read the endpoints back from Azure

    az network private-endpoint list -g rg-private-endpoints-shared -o table
    az network private-dns record-set a list -g rg-dns-shared -z privatelink.vaultcore.azure.net -o table
    az network private-dns record-set a list -g rg-dns-shared -z privatelink.blob.core.windows.net -o table
    cd platform/private-endpoints && terraform output

Observed 2026-11-25: both endpoints `Approved` and `Succeeded`; an A record `kv-plat-shared-at01` in the vault zone and
`stattfstate01` in the blob zone, TTL 10, created by the endpoints; the outputs list `10.20.4.36` and `10.20.4.37`.

## Test from a VM (no public IP, through run-command)

No VM is kept for this. `workloads/vm-demo/dev` is ephemeral and bills while it exists.

1. Apply it: `cd workloads/vm-demo/dev && terraform apply` (7 resources).
2. Resolve the names from inside the VNet:
   `az vm run-command invoke -g rg-vm-demo-dev -n vm-demo-dev --command-id RunShellScript --scripts "getent hosts kv-plat-shared-at01.vault.azure.net; getent hosts stattfstate01.blob.core.windows.net" --query "value[0].message" -o tsv`
3. Connect, with a timeout so a blocked path shows as `000`:
   `az vm run-command invoke -g rg-vm-demo-dev -n vm-demo-dev --command-id RunShellScript --scripts "curl -sS -o /dev/null --max-time 10 -w 'kv   %{http_code} %{remote_ip}\n' https://kv-plat-shared-at01.vault.azure.net/; curl -sS -o /dev/null --max-time 10 -w 'blob %{http_code} %{remote_ip}\n' https://stattfstate01.blob.core.windows.net/" --query "value[0].message" -o tsv`
4. Destroy it: `terraform destroy` (7), then `az group exists -n rg-vm-demo-dev` is `false` and the dev plan is back to
   `7 to add`.

Observed 2026-11-25: step 2 returned `10.20.4.36` and `10.20.4.37`, each with the `privatelink` name; step 3 returned
`kv   404 10.20.4.36` and `blob 400 10.20.4.37`.

## What a client sees

| Client | Resolves to | Status |
|---|---|---|
| VM in the dev spoke | the endpoint address; connects over the peering | observed 2026-11-25 |
| Workstation | the public address | observed 2026-11-25 |
| Self-hosted runner and agent in the hub | the endpoint address (the zones are linked to the hub) | reasoned, not tested |
| A VM in the prod spoke | the endpoint address | reasoned, not tested |
| GitHub-hosted runners and Microsoft-hosted agents | the public address (no link to the zones) | reasoned |

## Symptoms

| Symptom | Likely cause | Action |
|---|---|---|
| The vault answers `404` or the state account answers `400` on the root path | none: the service answered an anonymous request over the private path (observed) | nothing |
| A VM in a linked VNet resolves a name to a public address (expected, not observed) | no zone group on the endpoint, or the VNet has no link to the zone | check the A record and the link (`platform-dns`) |
| `curl` prints `000` after the timeout (expected, not observed) | no route: peering not `Connected`, or the VM is in a VNet that does not reach the hub | check the peering state, then the source subnet's NSG |
| The first CI apply fails with `AuthorizationFailed` (expected, not observed) | the apply identity lacks a permission this root needs | apply by hand, then move the root to `SKIP_ROOTS` with the reason in ADR-0046 |
| `plan` shows an endpoint replaced | its subnet or target resource ID changed (reasoned) | read the `forces replacement` line before applying |

## Not tested

The first CI apply of this root; the runner or agent reaching state and the vault through the endpoint; an authenticated
secret read over the endpoint; the prod path; plan and apply with public access off; the `NxDomainRedirect` fallback;
the lock's effect on a destroy. See ADR-0046, Unproven.
