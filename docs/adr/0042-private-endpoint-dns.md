# ADR-0042: Private endpoint DNS: one copy of each privatelink zone in `platform/dns`, linked to the hub and both spokes

- **Status:** Accepted (the resolver, the forwarding ruleset and the end-to-end lookup are built in session 2 and added here)
- **Date:** 2026-11-12
- **Deciders:** platform-team (@teegalaajay)
- **Relates to:** ADR-0007 (network topology and address plan); ADR-0036 (registry, public endpoint until Week 10);
  ADR-0040 (Allowed locations policy at `mg-platform`); ADR-0039 (standalone `AzureFirewallSubnet`)

## Context

A private endpoint gives a PaaS account a private IP in a subnet, but clients still ask for the public name. With a
private endpoint in place the public name becomes a CNAME into a `privatelink` name, and only a private DNS zone linked
to the asking VNet can answer that name with the private IP. Without the zone, the lookup returns the public addresses
and the traffic goes the public way. This ADR records where the zones live, who is linked, what a missing record does,
and where the DNS Private Resolver subnets sit. The resolver itself is built in session 2.

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
   subnet. Ajay chose to create them in this PR. Cost: no NSG on them. Whether these subnets accept an NSG, and whether
   /28 is enough for the endpoints, were not read or tested.
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

## Read, not tested

- The Allowed locations rule does not deny `global` resources, so the zones and links are not blocked (read from the
  policy rule; the apply is consistent with it).
- `NxDomainRedirect` applies only to links of `privatelink` zones and to A, AAAA and CNAME queries (Microsoft's resource
  reference).
- A VM asks the Azure host at 168.63.129.16, which is not reachable from on-premises or over a VPN; that is why a
  resolver inbound endpoint is needed for on-premises clients.

## Unproven

- That a private endpoint's zone group writes the A record into these zones, and that a VM in the dev spoke then resolves
  the private IP (session 2).
- Which zone name an on-premises conditional forwarder should use: the public name (`blob.core.windows.net`) or the
  `privatelink` name. Search results lean to the public name with `privatelink` excluded; to be settled from the
  documentation and a test in session 2.
- That `/28` is enough for a resolver endpoint, and whether an NSG can be attached to these subnets.
- Whether a ruleset can be linked to a VNet in a different region than the resolver.
- The first CI apply of this root, and what a missing record does to a client with `NxDomainRedirect` (to be observed by
  deleting a record in session 2).

## Consequences

- Every private endpoint in a later root must register in these zones through a zone group that references the IDs from
  `platform/dns` outputs; a zone group in another resource group would create a second copy.
- Adding a VNet means adding it to `linked_vnets` in `dns.auto.tfvars`; adding a service means adding one zone line.
- The hub root gained two outputs (`dns_inbound_subnet_id`, `dns_outbound_subnet_id`) and was applied by hand from the
  branch before the merge (additive, same exception as PR #59).
- Owed: the resolver root and forwarding ruleset (session 2); `NxDomainRedirect` revisited when public access is disabled
  (Week 10); a DR region design when Day 4 (BCDR) is built.
