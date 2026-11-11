# ADR-0039: Azure Firewall in the hub: an ephemeral root, the firewall in the hub's resource group, a route table on one dev subnet

- **Status:** Accepted
- **Date:** 2026-11-11
- **Deciders:** platform-team (@teegalaajay)
- **Relates to:** ADR-0007 (network topology; the hub, the peerings and the explicit-egress decision this replaces);
  ADR-0013 (apply identity); ADR-0038 (the other ephemeral hand-applied root); runbook `platform-firewall`

## Context

ADR-0007 left the hub without a firewall and said cross-environment traffic would be denied there "in Week 8". The
firewall bills by the hour, so it is built, tested and destroyed in one session, like the AKS cluster. The choices
below were made before the root was written; each states what it costs. The price figures are from Microsoft's public
Retail Prices API for `eastus2`, read on 2026-11-11: Standard deployment USD 1.25 per hour and USD 0.016 per GB
processed; Basic USD 0.395 per hour; Premium USD 1.75 per hour. A started hour is billed as a full hour (read, from
Microsoft's pricing page).

## Options considered and decisions

1. **Where the firewall lives.** Azure requires a firewall to be in the same resource group as the VNet whose subnet it
   uses (observed, below). (a) Only the firewall in `rg-network-shared`, through `var.hub_resource_group_name`, with the
   policy, public IP and route table in the root's own `rg-firewall-shared`; (b) every resource of the root in the hub's
   group. **Decision: (a).** (b) would mix an ephemeral root with the persistent hub in one group, so one wrong group
   delete would reach the VNet. Cost: the firewall is not in a group of ours, so `az group exists rg-firewall-shared`
   being `false` does not prove the firewall is gone; the check is a resource list of the hub group (runbook). The
   hub root does not manage the group's contents, so the hub plan is unaffected (observed).
2. **Lifecycle.** A separate ephemeral root, `platform/firewall`, applied by hand from the workstation and listed in
   `SKIP_ROOTS` of `apply.yml`. The reason is cost (USD 1.25 per hour while it exists), not identity: the root has no
   role assignments. Cost: no CI correction of drift here and a manual destroy that must not be forgotten.
3. **SKU.** Standard with a Standard policy. Cost: USD 1.25 per hour against Basic at USD 0.395; Standard was chosen
   for the FQDN application rule and threat intelligence in the policy (whether Basic supports both was not checked).
   Premium (TLS inspection and intrusion detection, from documentation memory, not re-read) is not needed here and
   costs USD 1.75 per hour.
4. **Policy.** One policy, `threat_intelligence_mode = "Deny"`, one rule collection group. DNS proxy is left off:
   private DNS and its resolution path are decided in Week 9, and no rule here uses an FQDN in a network rule. Cost:
   the firewall does not resolve names for the spokes.
5. **Zones.** `["1","2","3"]` on the firewall and its public IP, set once in `local.zones`. Read: no extra charge for
   zones, inter-zone data transfer free since May 2024 (announcement, not re-fetched), 99.99% availability, zones cannot
   be added after creation. Cost: a capacity failure in one zone fails the create; the mitigation is a retry with two
   zones (not needed, not tested).
6. **Rules.** Network collection `deny-dev-to-prod` (priority 100, Deny, the dev address space to the prod address
   space, any protocol and port) and application collection `allow-ipify` (priority 200, Allow, source the dev
   `snet-app` prefix, destination `api.ipify.org` over HTTPS 443). Network rules are evaluated before application
   rules (read). Azure Firewall also denies any flow with no matching allow (read), so the explicit deny and the default
   deny give the same observable result; the deny is there to state the intent and to keep winning if a broader allow
   is added later. Cost: nothing at runtime; it is not proven by a packet (below).
7. **Routing.** A route table `rt-snet-app-dev` in the firewall root, associated with dev `snet-app` by an association
   resource in the same root, so destroying the firewall also removes the route that points at it. Two routes, both
   `VirtualAppliance` to the firewall's private address: `0.0.0.0/0` and the prod range `10.11.0.0/16`.
   `bgp_route_propagation_enabled = false` (reasoned: dev has no gateway today). Cost: while the root exists, every
   workload in dev `snet-app` reaches the internet only through the firewall, and only `api.ipify.org` is allowed.
8. **Hub subnet and peerings** (PR #59, applied before the firewall). `AzureFirewallSubnet` `10.20.0.0/26` in the hub
   (the name is required by Azure), `allow_forwarded_traffic = true` on both dev peerings, the prod peerings unchanged
   (hub to prod stays `False`, observed). Whether the flag is required on each side was not tested.
9. **Test VM.** A throwaway VM with no public IP in dev `snet-app`, built outside this repository and reached with
   `az vm run-command`, so no SSH path and no NSG rule were opened. It was destroyed before the firewall.

## Observed (2026-11-11)

- The first apply failed with `AzureFirewallReferencesSubnetInDifferentResourceGroup` (HTTP 400): the firewall was in
  `rg-firewall-shared` and the subnet in `rg-network-shared`. The plan had passed (`7 to add`): `plan` does not check
  Azure's placement rules. The resource group, policy, rule collection group and public IP had already been created;
  the firewall, route table and association had not. After the change in decision 1 the plan was `3 to add`, and no
  resource that already existed was touched.
- Apply `3 added` in 8 minutes 33 seconds (17:01:18 to 17:09:51). Firewall private address `10.20.0.4`. The second plan
  was `No changes`. `az resource show` reported `Standard`, `Succeeded`, zones `2`, `3`, `1` (all three, in that order)
  and a policy in `rg-firewall-shared`; the policy in a different group from the firewall was accepted.
- The dev root plan was `No changes` with the association present (the association belongs to the firewall root).
- Effective routes on the test VM's NIC (service-endpoint rows removed): `10.10.0.0/16` `VnetLocal`; `10.20.0.0/16`
  `VNetPeering` (no firewall in the path); the default `0.0.0.0/0` `Internet` route `Invalid`; user routes `0.0.0.0/0`
  and `10.11.0.0/16` `VirtualAppliance` at `10.20.0.4`, both `Active`. No `10.0.0.0/8` `None` row was listed.
- Test VM `Standard_D2als_v6`, zone 2, `10.10.1.4`, no public IP. `az vm run-command` returned the hostname with the
  route table in place. A call to `https://api.ipify.org` returned the firewall's public IP with curl exit code 0. A
  call to `https://example.com` returned `http=000` with curl exit code 35 (SSL connect error).
- Destroy: the test VM root `3 destroyed` in 1 minute 11 seconds (17:43:38 to 17:44:49); the firewall root `7 destroyed`
  in 8 minutes 35 seconds (17:49:01 to 17:57:36). `az group exists` was `false` for `rg-firewall-shared` and the test
  group; `rg-network-shared` held only the VNet and the NSG; hub, dev and prod plans were `No changes`.
- The firewall existed for at most 56 minutes (created between 17:01:18 and 17:09:51, deleted between 17:49:01 and
  17:57:36), so 1 or 2 billed hours: USD 1.25 to USD 2.50 for the firewall.
- `az network firewall show` needs the `azure-firewall` CLI extension, which is a preview and was not installed;
  `az resource show --resource-type Microsoft.Network/azureFirewalls` reads the same properties.

## Reasoned, not tested

- Exit code 35 means the TCP connection opened and the TLS handshake failed, which fits a firewall that reads the
  requested name, finds no allow and closes the connection; the codes of a reset and a drop were not compared.
- The explicit deny and the default deny are indistinguishable from a client in dev.
- A subnet attached to `AzureFirewallSubnet` accepts no NSG (read, not tried); the subnet keeps the provider default for
  `default_outbound_access_enabled`.
- `depends_on` from the firewall to the rule collection group is a precaution (rules written before the firewall
  attaches); it was not tested without it.
- The management channel used by `az vm run-command` (a platform address) is not routed through a user route; it worked
  under the route table, which is the observation, the mechanism is read.

## Unproven

- A packet from dev to prod being denied (there is no VM in prod), and a packet from dev to the hub taking the peering
  and skipping the firewall (the effective routes show it; no hub VM exists).
- Whether the `10.11.0.0/16` user route is needed. The `10.0.0.0/8` `None` system route that justified it in the
  design was not in the effective routes, and traffic to prod would also match `0.0.0.0/0`. Removing it and reading the
  table again was not done.
- Which peering side needs `allow_forwarded_traffic`; whether both are needed.
- Firewall logs: no diagnostic settings exist, so denied flows are not visible except through the client's exit code.
- Whether the policy, the public IP or the test VM add a charge worth counting (their rates were not read), and the
  real bill from Cost Management (billing data lags by about a day).
- Capacity failure in a zone, `apply` of this root from CI, and a rebuild from zero.
- Which wins on one subnet, a user route to a firewall or a NAT Gateway association: `workloads/ansible-target/dev`
  associates a NAT Gateway with dev `snet-app`.

## Consequences

- `platform/firewall` is destroyed after each use. Check the hub group's resource list, not only `rg-firewall-shared`.
- Do not apply `workloads/ansible-target/dev` while the firewall root exists (NAT and route precedence unproven).
- The hub now has `AzureFirewallSubnet`; Bastion keeps its own subnet when it is built.
- ADR-0007's "explicit egress" interim (a NAT Gateway per workload root) remains in force until a standing firewall is
  decided; this build proves the path and does not replace it.
- Owed: diagnostic settings and a log destination (Week 9), a decision on a standing firewall against its monthly cost
  (about USD 912 for the deployment fee alone at 730 hours; arithmetic on the observed rate), DNS proxy with private
  DNS, and the Cost Management comparison.
