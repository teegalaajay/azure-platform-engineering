# ADR-0007: Network topology: minimal hub and per-environment spokes

- **Status:** Accepted
- **Date:** 2026-10-03
- **Deciders:** platform-team (@teegalaajay)

## Context

Every later component needs a network: workload VMs (Week 2), network-restricted Storage and
Key Vault (Week 2), the CI runner and ADO agent (Weeks 3 and 6), Ansible over SSH (Weeks 4-7),
AKS (Week 8) and private endpoints (Weeks 9-10). Address ranges are the hardest decision to
undo: a subnet's prefix cannot change while any NIC, private endpoint or node uses it, and
peering is refused between overlapping ranges. The workload is GxP-regulated, so production must
be demonstrably isolated from non-production. ADR-0004 fixes one subscription with environments
separated by resource group.

## Options considered

**Topology**
1. **One shared spoke for all environments.** Dev and prod in the same subnets, separated only by
   NSG rules. Least work; isolation depends on rules a single change can break.
2. **One spoke per environment plus a minimal hub now.** Spokes peer only to the hub; peering is
   not transitive, so dev and prod have no route to each other.
3. **Full landing zone now** (subscription per environment, management groups). Production
   pattern; needs provider aliases per subscription and multiplies Week 3 OIDC/RBAC work.

**Service access**
4. **Service endpoints now, private endpoints later.**
5. **Private endpoints now.** Requires private DNS zones (Week 9 design) before anything else.

**NSG wiring**
6. **Inline `subnet` blocks** in the VNet resource. The VNet then owns the full subnet list;
   any standalone subnet (or later addition) is overwritten on apply.
7. **Standalone `azurerm_subnet` + `azurerm_subnet_network_security_group_association`.**
   NSG rules stay inline (`security_rule` blocks, generated with `dynamic`): the rules share the
   NSG's lifecycle, and no standalone `azurerm_network_security_rule` may ever target these NSGs
   (mixing the two styles makes each apply remove the other's rules).

## Decision

Options 2, 4 and 7.

**Address plan (region `eastus2`):**

| Network | Resource group | CIDR | Subnets |
|---|---|---|---|
| `vnet-hub-shared` | `rg-network-shared` | `10.20.0.0/16` | `snet-mgmt` `10.20.3.0/26` (59 usable). Week 8 adds firewall/Bastion subnets here. |
| `vnet-spoke-dev` | `rg-network-dev` | `10.10.0.0/16` | `snet-app` `10.10.1.0/24`, `snet-data` `10.10.2.0/24` (251 usable each) |
| `vnet-spoke-prod` | `rg-network-prod` | `10.11.0.0/16` | `snet-app` `10.11.1.0/24`, `snet-data` `10.11.2.0/24` |

Reserved in every spoke, not created yet: `snet-pe` `.4.0/24` (private endpoints, Weeks 9-10),
`snet-aks-nodes` `.8.0/22` (AKS with Azure CNI Overlay, Week 8; pods use the overlay range).
`.0.0/24` and `.5.0`-`.7.255` stay free for growth. A simulated on-premises range for the Week 9
hybrid design must not overlap `10.10-10.11/16` or `10.20/16`.

**Peering:** hub <-> each spoke, built now (two peering resources per pair). No spoke-to-spoke
peering.

**Root modules and state (one per network):**

| Root | Contains | State key |
|---|---|---|
| `platform/foundation/hub` | `rg-network-shared`, `vnet-hub-shared`, `snet-mgmt` + NSG | `platform/foundation/hub.tfstate` |
| `platform/foundation/dev` | `rg-network-dev`, `vnet-spoke-dev`, subnets, NSGs, both dev<->hub peerings | `platform/foundation/dev.tfstate` |
| `platform/foundation/prod` | same for prod | `platform/foundation/prod.tfstate` |

All three call `modules/network`. Each spoke root reads the hub VNet with a
`data "azurerm_virtual_network"` lookup by name; apply order is hub, then dev, then prod.
Rejected: one root for all three networks. It puts dev and prod in one plan, one lease lock, one
identity scope and one state file, so a dev change or mistake can reach prod networking.

**NSGs:** one per subnet, associated at subnet level only. A `deny-vnet-inbound` rule
(priority 4000, source `VirtualNetwork`) overrides the default `AllowVnetInBound`, because the
`VirtualNetwork` tag includes every peered range. Allow rules sit at 100-3999, `Tcp` only:

- `snet-app`: SSH 22 and HTTP 80 from the operator IP (`/32`), SSH 22 from `snet-mgmt`.
- `snet-data`: SSH 22 from `snet-mgmt` only. App-to-data ports are added by the PR that
  introduces the data store, scoped to one port.
- `snet-mgmt`: no allow rules. The runner/agent only opens outbound HTTPS; stateful return
  traffic needs no rule. Spokes cannot initiate into the subnet that holds deploy identities.

The deny also blocks traffic between VMs in the same subnet (enforcement is per NIC on the host);
this is intended.

**Operator IP:** variable `operator_ip_cidr`, no default, `sensitive = true`, validated as a
`/32`. Supplied as `TF_VAR_operator_ip_cidr` (workstation) or a GitHub Actions secret (CI).
Never committed: the repo is public, and plan output is posted to public PR comments.

**Service endpoints (interim):** `snet-app` and `snet-mgmt`: `Microsoft.Storage`,
`Microsoft.KeyVault`; `snet-data`: `Microsoft.Storage`. Microsoft recommends private endpoints
for private access to PaaS services. Service endpoints are scoped to a service type (any account
of that service), not to one resource, and are not reachable from peered or on-premises
networks; private endpoints fix both but need private DNS. Target: private endpoints in
`snet-pe` in Weeks 9-10, with public network access disabled.

**Change rule:** NSG names never change; rules change in place. Replacing an NSG runs
destroy-then-create by default, leaving the subnet unfiltered between removing the old
association and creating the new one. Whether `create_before_destroy` is safe with the
association resource (whose ID is the subnet ID) is to be tested in the sandbox before it is
relied on.

## Consequences

- Dev and prod are isolated by routing, not only by rules; cross-environment traffic is possible
  only through the hub firewall (Week 8), which will deny it.
- The networks are **persistent** (`platform/`). Workload roots attach to subnets by ID and are
  never allowed to replace a subnet.
- Hub-spoke peering exists from the start, so the Week 8 hub work adds Azure Firewall, UDRs and
  Bastion to an existing hub instead of retrofitting peering.
- Subscription-per-environment remains the production pattern; it is shown in Week 9 as a
  separate build. These networks are not migrated (a cross-subscription move changes resource IDs
  and requires removing peerings).
- `engineering_standards.md` section 6 ("one VNet") is superseded by this ADR.
- **Residual coupling:** the identity applying a spoke root needs write access to peerings on the
  hub VNet. Enterprises often give the hub side to the connectivity team or use Azure Virtual
  Network Manager; revisit with the CI identities in Week 3.
- **Delivery order:** the spoke roots read the hub VNet with a data source during plan, so the
  hub must exist first. PR A delivers `modules/network`, the hub root and this ADR and is applied
  from `main`; PR B adds the dev and prod spoke roots with peering.
- **Explicit egress (decided 2026-10-05).** Every subnet sets
  `default_outbound_access_enabled = false` in `modules/network`: no implicit Azure-owned
  outbound IP, and nothing reaches the internet without an explicit path. Spoke VMs get no public
  IP. Egress is a NAT Gateway created by the workload root that needs it (interim and ephemeral,
  roughly USD 1/day while it exists), to be replaced by the Week 8 firewall with a UDR. The
  `snet-mgmt` runner (Week 3 Day 6) gets its egress path in its own PR. Rejected: a public IP on
  the NIC (an admin shortcut, not an enterprise pattern), a standing NAT Gateway in the
  foundation (about USD 33/month against a USD 50 budget), keeping the default (implicit,
  unauditable, being retired). Consequence: a VM in these subnets has no internet until its root
  adds NAT. The `azurerm_subnet_nat_gateway_association` lives in the workload root beside the NAT
  Gateway (a separate resource, so the foundation plan is unaffected) and is destroyed with it.
- **Operator rules hide every rule in the plan (tested 2026-10-04).** `security_rule` is a set;
  one element carrying the sensitive `operator_ip_cidr` makes Terraform render the whole set as
  `(sensitive value)`. NSGs without operator rules render in full. Accepted: rule content is
  reviewed in the code diff (names, priorities, ports, `var.operator_ip_cidr`), and the applied
  rules are verified with `az network nsg rule list` (output not posted publicly). Exit: replace
  internet-facing operator rules with Azure Bastion in the hub (Week 8) and remove the variable.
- Cost: VNets, subnets, NSGs and peerings have no hourly charge; peering is billed per GB.
