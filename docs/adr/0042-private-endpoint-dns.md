# ADR-0042: Private endpoint DNS: one copy of each privatelink zone in `platform/dns`, linked to the hub and both spokes

- **Status:** Accepted. Amended 2026-11-12 (session 2): resolver root, forwarding ruleset, end-to-end lookup test, delegation drift
- **Date:** 2026-11-12
- **Deciders:** platform-team (@teegalaajay)
- **Relates to:** ADR-0007 (network topology and address plan); ADR-0036 (registry, public endpoint until Week 10);
  ADR-0040 (Allowed locations policy at `mg-platform`); ADR-0039 (standalone `AzureFirewallSubnet`)

## Context

A private endpoint gives a PaaS account a private IP in a subnet, but clients still ask for the public name. With a
private endpoint in place the public name becomes a CNAME into a `privatelink` name, and only a private DNS zone linked
to the asking VNet can answer that name with the private IP. Without the zone, the lookup returns the public addresses
and the traffic goes the public way. This ADR records where the zones live, who is linked, what a missing record does,
and where the DNS Private Resolver subnets sit. Session 2 added the resolver (ephemeral root `platform/dns-resolver`) and
tested the whole chain with a throwaway private endpoint.

## Options considered and decisions

1. **Where the zones live.** (1) In the hub network root; (2) in their own persistent root `platform/dns`; (3) one set per
   spoke. **Decision: (2)**, chosen by Ajay (no reason was given). Why not (3) (reasoned): two zones with the same name
   answer only for the records registered in each, so some VNets would resolve a private endpoint and others would not.
   Why (2) over (1) (reasoned): the zones have their own lifecycle and should survive a rebuild of a network root. Cost:
   a root, a state key, and entries in three CI lists and floors.
2. **Which zones.** `privatelink.blob.core.windows.net`, `privatelink.vaultcore.azure.net` and `privatelink.azurecr.io`,
   as a map in `dns.auto.tfvars`. One zone per service domain name, because the CNAME target decides which zone must
   answer. A new service or storage sub-resource (file, queue, dfs) is one added line. Cost: an unused zone costs a
   little; a missing one is found only when a private endpoint's lookup returns a public address.
3. **Which VNets are linked.** Hub, dev spoke and prod spoke (nine links). `registration_enabled = false`: auto-registration
   is for VM names and is not used with `privatelink` zones. Cost: a new VNet resolves nothing private until a link is added.
4. **Resolution policy on the links: `NxDomainRedirect`.** **Decision:** Ajay's, with his reason: enterprises must still
   reach vendor-owned accounts (software, installers) that have no private endpoint in our zones. Without it, a name
   that exists in a linked zone but has no record returns NXDOMAIN (reasoned from the documented default). Cost: when a
   record is missing or wrong, the lookup silently falls back to the public address. Until Week 10 turns public access
   off on our own accounts, a client in `snet-app` (service endpoint) would still succeed over the public endpoint, so
   a DNS fault is hidden instead of failing loudly.
5. **Resolver subnets.** `snet-dns-in` (10.20.4.0/28) and `snet-dns-out` (10.20.4.16/28) in the hub, delegated to
   `Microsoft.Network/dnsResolvers`, one endpoint per subnet. They are standalone `azurerm_subnet` resources, like
   `AzureFirewallSubnet` (ADR-0039), because `modules/network` has no delegation option and attaches an NSG to every
   subnet. Ajay chose to create them in this PR. Cost: no NSG on them. Microsoft documents /28 as the minimum and as
   enough for current endpoint limits (read), and Azure accepted both endpoints in them (observed, session 2). Whether
   an NSG can be attached was not settled from a Microsoft source and was not tested.
6. **Simulated on-premises range.** 10.30.0.0/16, with the fake on-prem DNS at 10.30.0.53 (chosen by Ajay, no reason
   given). Cost: the range must not be reused. Taken ranges: 10.10/16, 10.11/16, 10.20/16, 10.0.0.0/16 (AKS service),
   10.244.0.0/16 (AKS pods), 172.17.0.0/16 (Docker bridge).
7. **Applied by CI.** `platform/dns` is in `APPLY_ROOTS` after the foundation roots (chosen by Ajay, no reason given). The
   root creates no role assignments, so the ADR-0013 condition does not apply (reasoned). Cost: the first CI apply of
   this root is untested, and a bad merge changes name resolution for three VNets, with the `production` approval as the
   only gate.
8. **Disaster recovery (design only).** The resolver is regional: a resolver can reference only a VNet in its own
   region, and its ruleset is created in the same region. A second region needs its own VNet, two subnets, resolver,
   endpoints and ruleset. The zones are global and are linked to the new VNets, and an on-premises forwarder can list
   both inbound endpoint addresses. Nothing is built. Cost of the future DR region: a second resolver bill (per
   endpoint and per ruleset).

9. **Where the resolver lives (session 2).** (A) A new ephemeral root `platform/dns-resolver`, in `SKIP_ROOTS`, applied
   and destroyed by hand; (B) inside `platform/dns`. **Decision: (A)**, Ajay, with his reason: the resolver is temporary
   and expensive and separate roots keep the two lifecycles apart. Why not (B) (reasoned): `platform/dns` is in
   `APPLY_ROOTS`, so CI would recreate a resource of about USD 360 per month on every apply. Cost (not named by Ajay): one
   more root, floors `plan.yml` 19 and `validate.yml` 24, and a rebuild each time the resolver is needed.
10. **Price, read before the apply (session 2).** Retail Prices API, Consumption rows: inbound endpoint 180.0, outbound
    endpoint 180.0, forwarding ruleset 2.5. The unit field reads only `1`; the DNS pricing page bills these per month,
    prorated to hours, so about USD 0.50 per hour for the root (reasoned). Go decided by Ajay.
    Not compared with Cost Management.
11. **Static inbound IP 10.20.4.4.** An on-premises conditional forwarder holds a literal address, so the IP must survive a
    destroy and rebuild of the ephemeral root; Dynamic could change it (reasoned). The first four addresses of a subnet
    are reserved, so .4 is the first usable one. Cost: hardcoded in the root.
12. **Forwarder zone name for on-premises.** Forward the public name (`blob.core.windows.net`) to the inbound endpoint,
    not the `privatelink` name (read: Microsoft's DNS Private Resolver architecture guidance). The inbound endpoint then
    follows the public CNAME into the zone linked to the hub (reasoned). Not tested against a real on-premises server.
13. **Fake on-premises rule.** Domain `onprem.internal.` (the `.internal` top-level domain is reserved for private use)
    forwarded to 10.30.0.53, where nothing listens. The ruleset is linked to the hub and the dev spoke, not prod.
14. **Test private endpoint in `snet-data`, not `snet-pe` (session 2 only).** ADR-0007 reserves dev `snet-pe`
    (10.10.4.0/24), which does not exist yet. Ajay chose to use `snet-data` for the throwaway endpoint (no reason or cost
    given). Name resolution does not depend on the subnet of the endpoint's NIC (reasoned). `snet-pe` is built in Week 10.
15. **Delegation drift after a resolver destroy.** Destroying the endpoints removes the delegation from `snet-dns-in` and
    `snet-dns-out` (observed below), and the hub root then plans `2 to change`. Options: (A) a runbook step: apply
    `platform/foundation/hub` after every resolver destroy; (B) `ignore_changes` on the delegation in the hub; (C) move both
    subnets into the resolver root. **Decision: (A)**: one owner per object
    and Terraform keeps enforcing the delegation. Why not (B): it hides the drift and stops enforcement, and a resolver
    build on an undelegated subnet was not tested. Why not (C): an ephemeral root would own subnets in the hub VNet,
    against the single-owner rule of ADR-0007. Cost: a manual step that can be forgotten; until it is done every PR plan
    comment shows the hub with changes, and the next CI apply of the hub corrects it.

## Observed (2026-11-12)

- The public name `stattfstate01.blob.core.windows.net` resolved with no `privatelink` hop (CNAME to a public name, then
  public addresses): there is no private endpoint on it.
- The dev VNet has no custom DNS servers (`dnsServers` empty): it uses the Azure-provided resolver.
- The hub apply created the two subnets (`2 to add`), Azure accepted the delegation and the /28 prefixes, and the next
  plan was `No changes`.
- `platform/dns`: the plan was `13 to add` (resource group, three zones, nine links); the apply completed under the Deny
  assignment at `mg-platform` and the next plan was `No changes`.
- The installed provider's schema for the link resource contains `resolution_policy`.
- Read back from Azure with the CLI: the three blob links are `NxDomainRedirect`, registration `False`, state
  `Completed`; the `acr` and `vault` zones each have three links (their policy value was not read individually).

## Observed (2026-11-12, session 2)

- `platform/dns-resolver`: plan `8 to add` (resource group, resolver, inbound and outbound endpoints, ruleset, rule, two
  ruleset links); apply `8 added`, exit 0; second plan `No changes`. The Deny assignment at `mg-platform` did not block
  any of them. Build and destroy times were not recorded.
- A throwaway storage account (shared key disabled, as the `platform-baseline` initiative requires) with a blob private
  endpoint in dev `snet-data` and a zone group pointing at this root's blob zone: Azure wrote the A record
  `stw9d2pednsat01` -> `10.10.2.4`, TTL 10, into `privatelink.blob.core.windows.net`. No Terraform code declares the record.
- From a dev VM without a public IP, through `az vm run-command`: `dig` is installed on the Ubuntu 24.04 image;
  systemd-resolved forwards to 168.63.129.16. The default path and a query sent to the inbound endpoint `10.20.4.4`
  returned the same chain: public CNAME (TTL 60) into `stw9d2pednsat01.privatelink.blob.core.windows.net`, then `A
  10.10.2.4` (TTL 10).
- From the workstation (no Azure zone in its view): the same first CNAME, then a CNAME to Microsoft's public storage host
  and a public IP.
- From the dev VM: `host.onprem.internal` got no answer within 3 s ("no servers could be reached"); `host.notonprem.internal`
  got `NXDOMAIN`. A name under the rule is handled differently from a name outside it.
- Destroying the private endpoint removed the A record from the zone. After 15 s the public chain no longer contained
  the `privatelink` hop (both paths went straight to the public storage host), so the zone was not consulted.
- After the resolver destroy, the hub plan was `2 to change`: the delegation block was missing on both resolver subnets.
  The activity log shows the caller `Azure DNS Managed Resolver` (Microsoft service principal) deleting the service
  association link and then updating each subnet. `terraform apply` in the hub restored both (`2 changed`); the next plan
  was `No changes`. `platform/dns` and `platform/foundation/dev` were `No changes` after the session.

## Read, not tested

- The Allowed locations rule does not deny `global` resources, so the zones and links are not blocked (read from the
  policy rule; the apply is consistent with it).
- `NxDomainRedirect` applies only to links of `privatelink` zones and to A, AAAA and CNAME queries (Microsoft's resource
  reference).
- A VM asks the Azure host at 168.63.129.16, which is not reachable from on-premises or over a VPN; that is why a
  resolver inbound endpoint is needed for on-premises clients.

## Unproven

- The `NxDomainRedirect` fallback itself: after the endpoint was deleted the public chain dropped the `privatelink` hop,
  so the zone was never asked. A test needs an endpoint that exists without its record (for example no zone group).
- A real on-premises conditional forwarder; the forwarded packet to 10.30.0.53 (the timeout is consistent with it, no
  capture was taken); the final status Azure returns for an unanswered forward.
- That the `dev` ruleset link is what made the difference (indirect: dev has the ruleset in its view only through the
  link; the link was not removed to compare).
- Whether a resolver build on an undelegated subnet fails or the service adds the delegation.
- An NSG on the resolver subnets; a ruleset linked to a VNet in another region; the first CI apply of `platform/dns`.
- Cost of the session against Cost Management.

## Consequences

- Every private endpoint in a later root must register in these zones through a zone group that references the IDs from
  `platform/dns` outputs; a zone group in another resource group would create a second copy.
- Adding a VNet means adding it to `linked_vnets` in `dns.auto.tfvars`; adding a service means adding one zone line.
- The hub root gained two outputs (`dns_inbound_subnet_id`, `dns_outbound_subnet_id`) and was applied by hand from the
  branch before the merge (additive, same exception as PR #59).
- After every destroy of `platform/dns-resolver`, apply `platform/foundation/hub` (runbook `platform-dns`), or the hub
  shows drift until the next apply.
- An on-premises site forwards the public service names (`blob.core.windows.net` and the others) to `10.20.4.4`.
- Owed: `snet-pe` and the real private endpoints (Week 10); a test of the `NxDomainRedirect` fallback;
  `NxDomainRedirect` revisited when public access is disabled (Week 10); hybrid connectivity on paper (ADR-0043); a DR
  region design when Day 4 (BCDR) is built.
