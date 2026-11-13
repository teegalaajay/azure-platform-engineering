# ADR-0043: Hybrid connectivity on paper: ExpressRoute as the primary path, active-active site-to-site VPN as the backup

- **Status:** Accepted as a design. Nothing is built, no resource exists and no price has been read for the gateway or
  the circuit
- **Date:** 2026-11-12
- **Deciders:** platform-team (@teegalaajay)
- **Relates to:** ADR-0007 (network topology and address plan); ADR-0039 (hub firewall); ADR-0042 (private endpoint DNS
  and the resolver inbound endpoint 10.20.4.4)

## Context

The reference platform is a landing zone for a fictional regulated pharmaceutical company. Its on-premises sites need
private IP connectivity to the hub (10.20.0.0/16) and, through the hub peerings, to the spokes. ADR-0042 already assumes
that an on-premises DNS server forwards the public service names to the resolver inbound endpoint 10.20.4.4, so the
link has to carry both application traffic and DNS queries. This ADR chooses the link type. It is design only, in the
same way as the PIM and Conditional Access part of ADR-0041: there is no on-premises site to connect, no provider, and
no gateway in the hub today.

Each claim below is labelled **read** (from the Microsoft pages in "Sources", read on 2026-11-12), **reasoned** (my
inference from them or from the platform's own ADRs) or **not looked up**.

## What the two options are

**Site-to-site VPN.** A virtual network gateway in the hub terminates IPsec/IKE tunnels to a VPN device on-premises. The
tunnel runs over the public internet (read, secondary source). The gateway is a pair of instances: active-standby, or
active-active with two public IPs; zone redundancy needs a gateway SKU with the `AZ` suffix and a Standard SKU public
IP (read). The Microsoft SLA is 99.95% for every gateway SKU except Basic, which is 99.9% and not meant for production
(read). Microsoft's page says the customer is responsible for the reliability of the remote VPN device (read).

**ExpressRoute.** A private circuit through a connectivity provider into a Microsoft peering location. It does not
traverse the public internet and uses BGP (read). Each circuit has two connections to two Microsoft edge routers at one
location; for maximum resiliency Microsoft recommends two circuits in two peering locations (read). Private peering
reaches virtual networks; Microsoft peering reaches public Microsoft endpoints (read). There is an uptime SLA (read;
the figure was not retrieved). Reaching a VNet needs a gateway of the ExpressRoute type in the hub as well (reasoned
from the gateway pages; not re-verified).

## Options considered and decisions

1. **Which link.** (A) Active-active site-to-site VPN only. (B) ExpressRoute only. (C) ExpressRoute as the primary path
   with an active-active site-to-site VPN as the backup. **Decision: (C).** Reasoned (not tested): (a) a regulated
   workload is asked where its data travels, and a private circuit that never crosses the internet is easier to defend
   to an auditor than a VPN over the internet, which needs more evidence (encryption settings, key handling, provider
   path); (b) one link is one failure domain, since a circuit depends on one provider and one pair of Microsoft edge
   routers at one location, while a VPN fails for different reasons (internet path, remote device), so the two together
   rarely fail at once, and (B) alone leaves the platform exposed to a single provider outage; (c) the VPN gateway is a
   small cost next to a circuit, which makes it the sensible insurance (prices not looked up). (A) has no private
   circuit. **Cost of (C), named:** it is the most expensive option and the slowest to start (a provider contract and
   provisioning lead time for the circuit; not looked up), it needs two gateways in the hub, and the team has to run two
   kinds of link and decide which one carries traffic when both are up (item 3).
2. **Gateway subnet.** `GatewaySubnet` is a fixed name and needs its own subnet in the hub. Size it /26 (secondary
   source: this leaves room for an ExpressRoute and a VPN gateway side by side). Like `AzureFirewallSubnet`, it carries
   no NSG (reasoned: Microsoft advises against an NSG on the gateway subnet; not re-verified). No range is chosen here:
   the next free /26 in 10.20.0.0/16 is picked when it is built, after reading ADR-0007's reserved ranges.
3. **Which path wins when both are up.** (reasoned from memory of the routing documentation, not re-read) For the same
   prefix, Azure prefers the ExpressRoute route over the VPN route; for the VPN to be the backup, the on-premises side
   must advertise the same prefixes on both paths. This needs a test before anyone relies on it.
4. **VPN backup shape.** Active-active, zone-redundant SKU (`AZ` suffix), BGP enabled, two Standard public IPs (read for
   the SKU and IP rules). Reasoned: BGP so a failed path withdraws its routes instead of waiting for a probe.
5. **DNS over the link.** The resolver does not care which link carries a query. On-premises DNS servers use a
   conditional forwarder to the inbound endpoint 10.20.4.4 for the public service names (`blob.core.windows.net` and the
   others, never the `privatelink` names; read) and the hub range must be advertised on-premises and routable back. This
   is the same on both paths (reasoned). 168.63.129.16 stays unreachable from on-premises on either (read).
6. **Spokes and the firewall.** The hub peerings need gateway transit on the hub side and "use remote gateways" on the
   spoke side so a spoke can use the hub's gateway (reasoned from how peering works; not re-verified in this session).
   Whether on-premises traffic passes the hub firewall (ADR-0039) is a routing decision for the build day: a route table
   on `GatewaySubnet` sending spoke prefixes to the firewall is the usual way (reasoned). Today the firewall exists only
   while its root is applied.
7. **Second region.** Gateways and the resolver are regional. A `centralus` recovery site needs its own gateway and
   resolver endpoints; two ExpressRoute circuits in two peering locations is how Microsoft describes geographic
   resilience (read). Design only; Day 4 (BCDR) decides what is built.

## Consequences

- No Terraform, pipeline or runbook changes: this ADR creates nothing.
- When it is built: a `GatewaySubnet` in `platform/foundation/hub` through a PR; the two gateways and their public IPs
  in their own root (a persistent or ephemeral choice with the price read first, because gateways bill by the hour while
  they exist); the peering flags in the hub and spoke roots; a new ADR for the routing and firewall decisions in items 3
  and 6.
- The address plan must keep 10.30.0.0/16 (the simulated on-premises range in ADR-0042) free of overlap with the cloud
  ranges, as it does today.
- The simulated forwarder at 10.30.0.53 stays a stand-in: no on-premises site exists to test this design.

## Unproven (nothing was built or tested)

- Every figure for price, lead time and throughput (not looked up); the ExpressRoute SLA percentage.
- Route preference when both paths advertise the same prefix, and failover time.
- Gateway transit and remote-gateway flags on these peerings; behaviour with the hub firewall in the path.
- The `GatewaySubnet` size and range against ADR-0007's reserved ranges.
- That an on-premises conditional forwarder to 10.20.4.4 works over either link (the resolver side was tested from a VM
  in ADR-0042; no on-premises client was used).

## Sources (read 2026-11-12)

- Microsoft Learn: What is Azure ExpressRoute? (`learn.microsoft.com/azure/expressroute/expressroute-introduction`)
- Microsoft Learn: ExpressRoute FAQ; designing for high availability with ExpressRoute
- Microsoft Learn: About zone-redundant virtual network gateways (VPN Gateway)
- Azure SLA for VPN Gateway (the China-cloud copy of the page was the one retrieved; the figures match the global blog
  post that announced the 99.95% gateways)
- Microsoft Learn Architecture Center: Azure DNS Private Resolver; Microsoft Tech Community posts on conditional
  forwarders for private endpoint zones
- A third-party guide (NicheeLab) for the `GatewaySubnet` /26 advice and the active-active SLA table: secondary source,
  marked as such above
