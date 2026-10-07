# ADR-0009: Storage network access (firewall and allow-lists)

- **Status:** Accepted
- **Date:** 2026-10-07
- **Deciders:** platform-team (@teegalaajay)
- **Amends:** ADR-0006 (closes its "public network access stays enabled" accepted risk)

## Context

Accounts built by `modules/storage` accept data-plane requests from any network. Shared key is
off, so every request already needs an Entra token and an RBAC data role, but that is one gate.
A regulated workload needs a second, independent gate: a request must also come from an approved
network. The storage firewall (`networkAcls` on the account) provides it. It is configured through
ARM (control plane) and enforced only by the storage front ends (data plane): ARM calls are never
checked against it, so the firewall can always be repaired from anywhere by an identity with
`Microsoft.Storage/storageAccounts/write`.

Request evaluation at the data plane, in order (proven 2026-10-07, see Consequences):
1. **Network gate.** Public source IP matched against `ipRules`; traffic from a subnet with the
   `Microsoft.Storage` service endpoint arrives with a private source IP and a subnet tag and is
   matched against `virtualNetworkRules` only. No match and default action Deny:
   HTTP 403 `AuthorizationFailure`. Identity is not evaluated.
2. **Identity gate.** Entra token, then RBAC data action. Missing data action:
   HTTP 403 `AuthorizationPermissionMismatch`.

## Options considered

**Where the firewall is declared**
1. Inline `network_rules` block in `azurerm_storage_account` (the module).
2. Separate `azurerm_storage_account_network_rules` resource. Only useful when the ACL owner is a
   different root from the account creator.

**Default action**
3. Variable. Any root could open an account with a one-line, in-place `0/1/0` change that neither
   `prevent_destroy` nor `CanNotDelete` stops (the same path as the prod redundancy downgrade).
4. Hardcoded `Deny`.

**Bypass**
5. `None`: nothing skips the network gate.
6. `AzureServices`: Microsoft trusted services skip the network gate only.

## Decision

Options 1, 4 and 6.

- **One owner of the ACL.** `networkAcls` is a single property holding the complete list; whoever
  writes it replaces it. The workload root owns the account and is the only writer, inline in the
  module. Other roots contribute subnet IDs only as outputs and never write the ACL. A separate
  network-rules resource must never be added for these accounts (two writers = permanent diff,
  last writer wins).
- **Hardcoded baseline:** `default_action = "Deny"`, `bypass = ["AzureServices"]`,
  `public_network_access_enabled = true` (the firewall guards the public endpoint; `false` means
  private endpoints only, Week 8).
- **Caller inputs, required, no defaults:** `virtual_network_subnet_ids` (full subnet IDs,
  case-insensitive regex per element) and `ip_rules` (IPv4 address or CIDR format; no RFC 1918
  ranges; no `/31` or `/32`, single hosts as a bare IP). A cross-variable validation rejects two
  empty lists (Terraform >= 1.9), because Deny with no allowed path makes the data plane
  unreachable.
- **Allowed paths for `storage-demo` (dev and prod):** the environment's spoke `snet-app` (read
  from `platform/foundation/<env>.tfstate`), the hub `snet-mgmt` (runner and operations, read from
  `platform/foundation/hub.tfstate`) and the operator IP (`TF_VAR_operator_ip_cidr`, `/32`
  stripped in the root, never committed). `snet-data` has the service endpoint but is excluded:
  every allowed subnet needs a named consumer, and the data tier does not read this account.
- `AzureServices` is accepted because the bypass skips the network gate only: trusted services
  still need an RBAC data role through their managed identity, and shared key is off. It is
  required for Site Recovery cache accounts and diagnostic export (Week 9).
- Breaking change to the module interface and behaviour: tagged `modules/storage/v2.0.0`.

## Consequences

- Proven on dev 2026-10-07:
  - Operator IP allowed, no data role: List Containers succeeds (authorized by the *action*
    `blobServices/containers/read`, which Owner holds); List Blobs returns 403
    `AuthorizationPermissionMismatch`.
  - Operator IP replaced (`-var` with a documentation address), same identity: 403
    `AuthorizationFailure`. The identity problem is not reported, so the network gate is
    evaluated first.
  - `terraform plan` from the blocked IP succeeded (`0/1/0`): refresh, plan and apply of
    `azurerm_storage_account` with these arguments use the control plane only. CI runners without a
    fixed IP can manage the account's configuration but cannot read or write its data.
    Not yet proven for other storage resources (e.g. containers declared by account name).
- Every account needs at least one allowed path; data-plane work from hosted runners is impossible
  by design. Week 3 places a self-hosted runner in `snet-mgmt`.
- No public accounts can be built from this module, and no account without a Microsoft-side path;
  either needs a module change, an ADR and a new major version.
- **Accepted risk until Week 3:** one operator identity holds Owner on the subscription, so the
  single-writer rule is enforced by review only. Week 3 gives each root its own identity scoped to
  its resource group (other roots get `AuthorizationFailed` from ARM) and a CI check rejecting
  `azurerm_storage_account_network_rules`; Week 9 adds an Activity Log alert on account writes by
  other principals and the access review.
- Incompatible with a "public network access disabled" deny policy; superseded by the Week 8
  private-endpoint design (`RequestDisallowedByPolicy` would appear at apply, not plan).
- The operator IP is sensitive, so `ip_rules` renders as `(sensitive value)` in plans. When the ISP
  changes the IP, both storage-demo roots must be planned and applied as well as the spokes.
