# Runbook: platform-firewall (ephemeral Azure Firewall in the hub)

- **Purpose:** Build Azure Firewall Standard in the hub, route dev `snet-app` through it, prove the allowed and the
  blocked path from a throwaway VM, and destroy it in the same session. See ADR-0039.
- **Owner:** platform-team
- **Last validated:** 2026-11-11 (apply, route and egress proof, destroy; not rebuilt from zero since)
- **Persistent:** No. The root is destroyed after each use. The firewall bills USD 1.25 per hour while it exists.

## Layout

| Item | Value |
|---|---|
| Root | `platform/firewall`, state key `platform/firewall.tfstate` in the shared backend |
| Resource groups | `rg-firewall-shared` (policy, public IP, route table) and `rg-network-shared` (the firewall itself, hub group) |
| Firewall | `fw-hub-shared`, `AZFW_VNet` Standard, zones 1, 2, 3, in `AzureFirewallSubnet` `10.20.0.0/26` (hub) |
| Policy | `fwp-hub-shared`, threat intelligence `Deny`, DNS proxy off, group `rcg-hub-shared` |
| Rules | network `deny-dev-to-prod` (100, Deny); application `allow-ipify` (200, Allow, `api.ipify.org` HTTPS from dev `snet-app`) |
| Routing | `rt-snet-app-dev` on dev `snet-app`: `0.0.0.0/0` and `10.11.0.0/16` to the firewall's private address |
| Applied by | hand, as Owner. The root is in `SKIP_ROOTS` of `apply.yml`. The CI plan on a PR shows it as all-to-add |

## Before you start

1. The subscription state is `Enabled` (`az rest` on `subscriptions/$ARM_SUBSCRIPTION_ID`, query `state`).
2. `rg-firewall-shared` prints `false` for `az group exists`, and `az resource list -g rg-network-shared` shows no
   firewall.
3. `platform/foundation/hub` and `platform/foundation/dev` plan `No changes` (the hub has `AzureFirewallSubnet`; both dev
   peerings allow forwarded traffic).
4. Nothing is attached to dev `snet-app`: `az network vnet subnet show` with the query `ipConfigurations` prints
   `null`. The route table changes that subnet's traffic the moment it is associated.
5. `workloads/ansible-target/dev` is not applied (NAT and route precedence is unproven, ADR-0039).
6. Read the price: Microsoft's Retail Prices API, service `Azure Firewall`, region `eastus2`. Set a time limit and a
   cost cap before the apply. On 2026-11-11 the limit was 3 hours and USD 5.

## Deploy

1. `cd platform/firewall`, then `terraform init` and `terraform plan -out=/tmp/firewall.tfplan` (the plan file stays
   outside the repository). Expect `7 to add`. Read it; mask GUIDs (`sed -E` on the GUID shape, with `2>&1` before the
   pipe so errors are masked too) before pasting anything.
2. Note the time, then `terraform apply /tmp/firewall.tfplan`. Use `set -o pipefail` in a subshell when the output is
   piped, or a failed apply does not stop a command chain. Observed: about 8.5 minutes.
3. `terraform plan` again and expect `No changes`, then delete the plan file.
4. Read the firewall back: `az resource show -g rg-network-shared -n fw-hub-shared --resource-type
   Microsoft.Network/azureFirewalls`. Expect `Succeeded`, `Standard`, three zones. (`az network firewall` needs a preview
   CLI extension.)

## Verify

- **Routes:** a VM in dev `snet-app` shows user routes `0.0.0.0/0` and `10.11.0.0/16` to the firewall's private address
  in `az network nic show-effective-route-table`, and the default internet route `Invalid`. The route to the hub is
  the peering, not the firewall.
- **Allowed:** `curl -s https://api.ipify.org` from that VM returns the firewall's public IP.
- **Blocked:** `curl https://example.com` fails (observed: `http=000`, exit code 35).
- **Method:** a VM with no public IP, reached with `az vm run-command invoke`, so no inbound path is opened. A
  positive control (hostname, then the allowed call) comes before every negative result.
- The dev root still plans `No changes` with the association present.

## Destroy

1. Destroy the test VM and its root first.
2. `terraform plan -destroy -out=/tmp/firewall-destroy.tfplan` in `platform/firewall`; expect 7 to destroy and nothing
   from `rg-network-shared` except the firewall itself. Then apply that plan; observed: about 8.5 minutes.
3. Check the hub group, which is where the firewall was: `az resource list -g rg-network-shared` shows the VNet and the
   NSG and nothing of type `azureFirewalls`. Then `az group exists -n rg-firewall-shared` prints `false`.
4. Hub, dev and prod foundation plans are `No changes`; no `*.tfstate*` file in the repository; delete the saved plans.

If the firewall is still listed after the destroy, stop and look at it. It bills until the resource is deleted;
removing it from the VNet does not stop the charge.

## Failure signs

| Sign | Meaning | Action |
|---|---|---|
| `AzureFirewallReferencesSubnetInDifferentResourceGroup` | The firewall is not in the VNet's resource group | Use `var.hub_resource_group_name` for the firewall (ADR-0039). Resources created before the error still exist: list them before retrying |
| Apply stops on a zone or capacity error | A zone has no capacity | Paste the error; the fallback is two zones in `local.zones`, which needs a new plan |
| `az network firewall` prints an extension warning and nothing else | The preview extension is not allowed | Use `az resource show` as above |
| A command chain went on after a failed apply | The pipe hid the exit status | `set -o pipefail` in a subshell |
| Test VM has no outbound at all | The firewall is absent but the route table remains, or the rule is missing | Check the association and the application rule collection |
| Dev root plan shows a change after the firewall root is applied | The route table association is seen by the dev root | Stop and read the plan; it was `No changes` on 2026-11-11 |

## Cost

USD 1.25 per hour for the deployment plus USD 0.016 per GB processed (observed rates, 2026-11-11); a started hour is
a full hour. The public IP, the policy and the test VM were not priced. The run of 2026-11-11 was at most 56 minutes.
Do not leave it up overnight: 24 hours is USD 30.
