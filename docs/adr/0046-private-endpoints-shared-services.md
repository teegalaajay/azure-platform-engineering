# ADR-0046: Private endpoints for shared platform services: in the hub, with public access left as a recorded exception

- **Status:** Accepted
- **Date:** 2026-11-25
- **Deciders:** platform-team (@teegalaajay)
- **Relates to:** ADR-0007 (hub `snet-pe`); ADR-0010 (platform Key Vault); ADR-0013 (apply identity condition); ADR-0014
  (plan on pull request); ADR-0015 (self-hosted apply runner); ADR-0036 (container registry); ADR-0042 (private DNS zones)

## Context

ADR-0042 put one copy of each `privatelink` zone in `platform/dns` and linked it to the hub and both spokes. No private
endpoint used those zones yet. ADR-0007 reserved `snet-pe` and set the target of private endpoints "with public network
access disabled". Today this ADR builds the first two endpoints, for the platform Key Vault (`kv-plat-shared-at01`) and
the state account (`stattfstate01`), and has to say what the endpoints change and what they do not.

Who reaches the state account matters most, because state reads and writes are data-plane calls to the blob endpoint and
a client without a private path is refused once public network access is off. The workflow and pipeline files show the
clients (read from `runs-on`, `vmImage` and `pool:` on 2026-11-25):

- `apply.yml` runs on the self-hosted runner in the hub `snet-mgmt`: it has a private path.
- `plan.yml` and `oidc-smoke.yml` run on `ubuntu-latest`, and `ado-terraform-deploy.yml` sets a Microsoft-hosted
  `ubuntu-24.04` pool at the top: none has a private path. Only the `configure` job overrides the pool.
- The workstation (WSL) has no route into the hub (reasoned from ADR-0007).

The platform vault already has a firewall: default action Deny, bypass None, allowed hub `snet-mgmt` and the operator IP
(ADR-0010). The state account has none (open item since ADR-0005). The registry is Basic with a public endpoint
(ADR-0036).

## Options considered

- **Where shared endpoints live.** In each consuming spoke, or in the hub.
- **Network policies on the endpoint subnet.** Leave them at the default (`Disabled`), or enable them so the subnet's NSG
  filters endpoint traffic.
- **Which services get an endpoint now.** The vault and the state blob service; the registry only with the Premium SKU,
  which is the SKU that supports private endpoints (read from the Azure documentation).
- **State account access once an endpoint exists.** X: close public network access now and give every client a private
  route. Y: leave public access Enabled as a documented exception. Z: default action Deny with an operator IP
  allowlist.
- **Protection against deletion for the endpoints.** None now; a `CanNotDelete` lock and `prevent_destroy` from the
  start; or none now and both added when public access closes.
- **Which apply list the new root belongs to.** `APPLY_ROOTS` (CI applies it after approval) or `SKIP_ROOTS` (applied by
  hand).

## Decision

1. **A root of its own: `platform/private-endpoints`.** State key `platform/private-endpoints.tfstate`, resource group
   `rg-private-endpoints-shared`, the six mandatory tags with `environment` `shared` and `data_classification` `internal`.
   The root reads the hub subnet, the two zones, the vault and the state account with data sources by name, the pattern
   of `platform/dns-resolver`, and not with remote state. Reason: no reason recorded. Cost: one more root, which means a
   state key, an entry in the CI lists and a floor bump in three workflows.
2. **Endpoints for shared services live in the hub `snet-pe` (`10.20.4.32/27`).** Reason: peering is not transitive, so an
   endpoint placed in dev would not be reachable from prod (reasoned; the dev path is observed below). The block is the
   lowest aligned `/27` left in `10.20.4.0/24` after the two resolver `/28` subnets. Azure reserves five addresses in a
   subnet (read), so the first usable address is `.36`, which matches the observed endpoint addresses. Cost: shared
   services are tied to the hub subnet, and moving an endpoint later means replacing it. Rejected: a `snet-pe` per spoke
   for shared services, which needs one endpoint per consumer environment per service when the zone links already cover
   every VNet.
3. **Private endpoint network policies stay at the default (`Disabled`).** Reason: while they are `Disabled` the subnet's
   NSG does not filter traffic to the endpoints (read), and enabling them adds NSG and route table behaviour to the
   endpoint path that nothing needs yet. Cost: no network-level filtering of endpoint traffic. The `deny-vnet-inbound`
   rule of the subnet's NSG therefore protects nothing, and the endpoints are protected by Entra authentication and RBAC
   on the target resources.
4. **Two endpoints, each registered through a zone group.** The vault (`vault`, zone `privatelink.vaultcore.azure.net`) and
   the state account (`blob`, zone `privatelink.blob.core.windows.net`). Reason: the zone group writes the A record and
   removes it with the endpoint, so no stale record is left to clean up (observed in ADR-0042 with a throwaway endpoint).
   Cost: a zone group per endpoint in the code, and an endpoint without one resolves publicly.
5. **The registry gets no endpoint now.** Private endpoints need the Premium SKU (read). The Retail Prices API on
   2026-11-25 listed Basic at 0.1666 per day and Premium at 1.6666, so Premium costs about USD 1.50 more per day (observed
   price list, not compared with Cost Management). The registry stays Basic and public, authenticated, admin user off,
   anonymous pull off (ADR-0036), and no workload runs from it now. Premium with an endpoint is the plan for the capstone,
   recorded here and not built. Cost: until then the registry is reachable from the internet by authenticated principals.
6. **Public network access stays Enabled on the state account, as a recorded exception.** Reason: closing it now would
   break the plan on pull request, the smoke workflow, the plan and deploy stages of `ado-terraform-deploy`, and the
   workstation, and giving them a private path changes the CI trust model. ADR-0015 keeps pull request code, including
   plan, on hosted runners, so that the machine inside the hub runs only code that has been merged and approved; plan on
   a self-hosted runner would reverse that (reasoned). Cost: the
   account stays reachable from the internet by authenticated principals; its protection is Entra authentication, RBAC,
   shared key disabled and TLS 1.2 (ADR-0005). The state endpoint serves the clients that have a private path (the
   apply runner and the agent) and does not close the public one. Exit: a private path for plan (ephemeral self-hosted
   runners, one job each) and for the workstation (Point-to-Site VPN or Bastion), then close public access in its own
   pull request. Rejected: closing now, which is that rework plus a VPN gateway billed by the hour; and default action
   Deny with an operator IP allowlist, because hosted runners have no fixed address, so plan would still fail. The vault
   keeps its firewall (default Deny, the hub `snet-mgmt` and the operator IP, ADR-0010): the endpoint adds a path that
   the spokes did not have, since service endpoints are not reachable from peered networks (ADR-0007).
7. **No lock and no `prevent_destroy` on the endpoints now; both are added when public access closes.** Reason: deleting
   an endpoint becomes an outage only after public access is off, and the lock's cost is paid only when it buys
   something. Cost: until then a destroy of the root passes without a guard (public access is still on, so clients fall
   back to the public path), and adding the lock later is one more pull request after which any replacement of an
   endpoint starts with removing the lock (reasoned).
8. **The root is in `APPLY_ROOTS`, after `platform/security`, which it reads.** Reason: it is persistent, creates no role
   assignments and needs only what Contributor grants (reasoned), so CI corrects drift like it does for the other
   persistent roots. Cost: the first CI apply is untested; if Contributor falls short it fails on the runner after the
   approval. The floors move with the root: `plan.yml` 24, `validate.yml` 29 and `pipelines/ado-terraform-validate.yml`
   29 (it was 18, below the real count).

## Observed (2026-11-25)

- The hub subnet was applied by hand from its branch (`3 added`, then an output-only apply, then `No changes`). The plan
  comment of the pull request, signed in as the plan identity, showed `platform/foundation/hub` with `no changes`.
- `platform/private-endpoints`: `validate` succeeded, the plan was `3 to add`, the apply `3 added`, the second plan
  `No changes`. The outputs were added afterwards with a plan that changed no resource and an apply of the outputs
  only, and the plan after it was `No changes`.
- Read back from Azure: both endpoints `Approved` and `Succeeded` (`pe-kv-plat-shared-at01`, `pe-stattfstate01-blob`);
  an A record for `kv-plat-shared-at01` in `privatelink.vaultcore.azure.net` and one for `stattfstate01` in
  `privatelink.blob.core.windows.net`, TTL 10, created by the endpoints. The root's outputs list the addresses:
  `10.20.4.36` for the vault and `10.20.4.37` for the state blob service.
- A VM with no public IP in the dev `snet-app` (`workloads/vm-demo/dev`, run through `az vm run-command`) resolved
  `kv-plat-shared-at01.vault.azure.net` to `10.20.4.36` and `stattfstate01.blob.core.windows.net` to `10.20.4.37`, each
  answer naming the `privatelink` canonical name. The workstation resolved the same names to public addresses.
- From that VM, with a 10 second timeout: `https://kv-plat-shared-at01.vault.azure.net/` returned `404` from `10.20.4.36`
  and `https://stattfstate01.blob.core.windows.net/` returned `400` from `10.20.4.37`. The services answered an
  anonymous request, so TCP and TLS reached the hub endpoints over the dev-to-hub peering.
- The test VM root was destroyed (`7 destroyed`), `az group exists rg-vm-demo-dev` returned `false`, and the dev plan
  returned to the standing baseline of `7 to add`.
- The Retail Prices API listed the private endpoint at 0.01 per hour, and Basic and Premium registry at 0.1666 and
  1.6666 per day. The inventory of state clients above comes from `runs-on`, `vmImage` and `pool:` in the repository.

## Reasoned

- The hub placement is justified by non-transitive peering; the prod path to the hub endpoints was not tested.
- The subnet's NSG does not filter traffic to the endpoints while network policies are `Disabled` (read from the Azure
  documentation); the flag was read back as `Disabled` on `snet-mgmt`, and not on `snet-pe`.
- Contributor at the subscription covers creating the endpoints and zone groups, and the root creates no role
  assignment, so the ABAC condition of ADR-0013 does not apply.
- The two endpoints cost about USD 14.60 per month at the list price of 0.01 per hour (2 x 0.01 x 730 hours), plus data
  processing, whose price was not read; this is not compared with Cost Management.
- The zones are linked to the hub as well as to the spokes (ADR-0042), so the self-hosted runner and the agent in the
  hub should now resolve the two names to the endpoint addresses.

## Consequences

- Two endpoints bill by the hour for as long as the root exists, a new persistent cost against the USD 50 monthly budget.
- Clients in the hub, dev and prod VNets resolve both names to private addresses from now on (the dev case is observed;
  the hub and prod cases are reasoned). The workstation and the hosted runners are unaffected and keep using the public
  path.
- The state account and the vault gain a private path that the spokes did not have. Nothing public is closed: the
  state account is reachable from the internet to authenticated principals exactly as before, and that is the exception
  of decision 6.
- The subnet and its NSG are free per hour (reasoned), and the NSG filters nothing on this subnet (decision 3).

## Unproven

- The first CI apply of `platform/private-endpoints`: whether the apply identity can create the endpoints and zone
  groups. The apply run of the merge waits for the `production` approval on a runner that is offline.
- Whether the self-hosted runner and the agent now reach state and the vault through the endpoint, and that the apply
  still works over that path. A lookup and a connection test from a hub VM would settle it.
- An authenticated call to the vault over the endpoint: the `404` shows the service answering, not that a secret read
  succeeds from a spoke. The vault firewall is Deny with bypass None, and the documented behaviour of endpoint
  connections against that firewall was not tested here.
- A prod client reaching the hub endpoints, and the lookup from prod.
- Plan and apply with public network access off on the real state account; session 2 proves the mechanism on a
  throwaway account and not on this one.
- The `NxDomainRedirect` fallback for these zones (still not observed, ADR-0042).
- The network policies value on `snet-pe`, the number of addresses a registry endpoint takes (reasoned as two) and the
  lock's effect on a destroy.
- Cost Management against the list prices, and the data processing charge.
