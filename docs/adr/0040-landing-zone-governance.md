# ADR-0040: Landing zone and governance as code: one management group, a custom policy, a two-member baseline initiative, Deny

- **Status:** Accepted
- **Date:** 2026-11-11
- **Deciders:** platform-team (@teegalaajay)
- **Relates to:** ADR-0004 (one subscription, environments by resource group; this ADR is the first step of its migration
  path); ADR-0013 (apply identity); ADR-0035 and ADR-0009 (the storage baseline this policy restates); ADR-0041 (identity)

## Context

ADR-0004 put everything in one subscription and named a migration path to a subscription per environment under a
management group. Week 9 starts that path with governance: a place above the subscription where rules are assigned once
and reach everything below. The choices below were made before the root was written; each states what it costs.

## Options considered and decisions

1. **Where to assign.** (a) On the Tenant Root Group; (b) create a management group, assign there, and move the
   subscription in; (c) assign on the subscription. **Decision: (b)**, chosen by the mentor (no reason was given). (c)
   enforces the same rules today; (b) is chosen because the hierarchy is the migration path in ADR-0004 and an
   assignment on a group reaches every subscription later placed under it. Cost: the root is applied by hand, a group
   and a placement exist that a single subscription does not need, and the diagram looks bigger than the estate.
2. **Group ID.** `mg-platform`, display name "Platform", directly under the Tenant Root Group. The ID is permanent; the
   display name is not. Chosen by the mentor. Cost: a second group later needs a qualifier in its own name.
3. **Azure Verified Modules.** (a) Keep `modules/network` and `modules/storage`, evaluate AVM on paper, hand-write the
   governance root; (b) build the governance root from the ALZ pattern module `avm-ptn-alz`; (c) replace the modules.
   **Decision: (a)**, chosen by the mentor (no reason was given). Read, from search results only (the registry pages
   could not be fetched): AVM resource modules default to Well-Architected settings that a caller can change, they ship
   telemetry on by default, new Terraform AVM modules use AzAPI, and the releases seen were all 0.x with breaking
   changes between minor versions. Our storage module fixes its baseline (shared key off, TLS 1.2, Deny firewall,
   versioning) so the caller cannot change it, and validates six mandatory tags and at least one allowed network path;
   those are our rules, not generic ones, so a wrapper would have to carry them. Cost: the repo shows no AVM in use and
   the hand-written policy set is far smaller than the ALZ library. Option (b) remains the migration path.
4. **What the baseline holds.** One custom definition, `storage-shared-key-disabled` (restates `shared_access_key_enabled
   = false` from the storage module), and the built-in "Allowed locations" with `eastus2` and `centralus` (our region
   and its BCDR pair, ADR-0005). They are bundled in the initiative `platform-baseline` so there is one assignment and
   one compliance view. Cost: a built-in is maintained by Microsoft and can change under us (version 1.1.0 seen).
5. **Effect as a parameter.** The definition and the initiative take `effect` (`Audit`, `Deny`, `Disabled`); the
   assignment sets it. The assignment was applied as `Audit`, the violation was audited, and the same code was then
   changed to `Deny`. Cost: `Deny` rejects any request that breaks a rule, including requests from our own pipelines.
6. **No identity on the assignment.** `Audit` and `Deny` read the request and need no identity, so the assignment has
   none and no `location`. The system-assigned or user-assigned choice moves to Week 9 Day 3, with the first
   `deployIfNotExists` policy.
7. **Hand-applied.** `platform/governance` is in `SKIP_ROOTS` of `apply.yml`. Reasoned from ADR-0013, not tested: the
   apply identity holds Contributor at the subscription and cannot write at management-group scope. The plan floor is 17
   and the validate floor 22.
8. **Subscription vending.** Concept only. The alias API creates a subscription and can place it in a group; a vended
   subscription would need a baseline (budget, tags, role assignments, a pipeline identity, spoke peering). Whether a
   pay-as-you-go account can use it was not checked. Nothing is built.
9. **Probe resources.** The proofs used a resource group and two storage accounts made by hand with the Azure CLI and
   deleted the same day. They are the only hand-made resources of this change.

## Observed (2026-11-11)

- Before any elevation, `az account management-group list` as Owner of the subscription failed with
  `AuthorizationFailed` on `Microsoft.Management/managementGroups/read`. After `elevateAccess` (Global Administrator,
  User Access Administrator at `/`) it listed one group, the Tenant Root Group, and the subscription was its only child.
- Group: plan `1 to add`, apply `1 added`; read-back showed `mg-platform`, "Platform", parent Tenant Root Group.
- The alias `Microsoft.Storage/storageAccounts/allowSharedKeyAccess` exists in Azure (listed from the provider, with the
  per-service aliases next to it).
- Definition: `1 added`; read-back `Custom`, `Indexed`, default `Audit`, effect stored as the text
  `[parameters('effect')]`.
- The built-in "Allowed locations" takes the parameters `listOfAllowedLocations` and `effect`.
- Initiative: the first plan warned that `management_group_id` on `azurerm_policy_set_definition` is deprecated and
  removed in provider v5.0; the code uses `azurerm_management_group_policy_set_definition`. The provider lists no
  management-group variant for plain definitions. Read-back: two members (`storage-shared-key-disabled`,
  `allowed-locations`), two parameters (`effect`, `allowedLocations`).
- Assignment: read-back `Default` enforcement, `identity` null, effect `Audit`, both regions.
- Placement: `1 added`; the group's children listed the subscription. `platform/cost` planned `No changes` afterwards,
  so the move did not change resource IDs.
- `az policy assignment list --scope <subscription>`, with and without `--disable-scope-strict-match`, listed only
  `SecurityCenterBuiltIn` and not `platform-baseline`. A first `az policy state list` for the assignment was empty; a
  later one returned 17 records, all `Compliant`: 15 for `allowed-locations` and 2 for `storage-shared-key-disabled`.
- Audit: a storage account in `westus2` with shared key access on was created under `Audit` without error. After a scan
  and a wait it appeared as `NonCompliant` for both members.
- Deny: `Audit` to `Deny` was an in-place change (`0 to add, 1 to change`). The same request was then refused with
  `RequestDisallowedByPolicy`, naming both definitions, the initiative and the assignment at `mg-platform`; the
  evaluation showed `allowSharedKeyAccess` `true` against `NotEquals False` and the location `westus2` `NotIn` the list.
  The time between the apply and the first refusal was not measured.
- Move out: removing the association (`1 to destroy`) left the group with no children, and the same request that had
  been refused succeeded. Applying the association again restored the placement; the plan was `No changes`.
- Elevation removed with `az role assignment delete`; afterwards `az account management-group list` showed only
  `mg-platform`, and `terraform plan` in `platform/governance` was `No changes` without the elevation.
- The probe resource group was deleted; `az group exists` printed `false`.

## Plan identity at the group

- Observed (PR 61): the first plan leg for this root failed after 26 seconds with two `AuthorizationFailed` (403) reads
  at `mg-platform`: `policyAssignments/read` and `managementGroups/read`. The plan identity's Reader is at the
  subscription, below the group; role assignments inherit downward only, so nothing reached the group.
- Decision 10: grant the plan identity Reader at `mg-platform`, declared in `bootstrap/github-oidc.sh` (`GROUP_SCOPE`).
  Chosen from three options (grant, leave the leg red, exclude the root from the plan matrix) on the mentor's
  recommendation; Ajay gave no reason (Gate 2 list).
- Observed after the grant: the first script run printed `granted Reader` at the group and `unchanged` for every other
  role; a second run printed `unchanged` for it and no `removed`, so the prune keeps it. The re-run of the failed leg gave
  46 of 46 checks green.
- Cost: the plan identity runs code from any same-repository branch (ADR-0014), and it now also reads the structure and
  policy above the subscription (read only, no write). Rejected: a permanently red leg teaches reviewers to ignore red;
  excluding the root leaves reviewers without a diff for the highest-risk root. The script was run from the branch, not
  from `main`.

## Reasoned, not tested

- Creating `mg-platform` made the creator its Owner (documented default); only reads and a plan were tried without the
  elevation.
- The `exists = false` branch of the rule is there for an account with no stored value; the refusal matched the
  `NotEquals` branch, so the other branch was never exercised.
- A hierarchy change takes time to reach the policy service; the observation (empty, then 17 records) fits but does not
  measure it.
- "Allowed locations" lets `global` resources through (the evaluation showed the `NotEquals global` test).

## Unproven

- Why the subscription-scope assignment list hid an assignment that the policy state showed as applying.
- Propagation times for placement, assignment and effect change.
- The apply identity being refused at management-group scope: it holds no role there and was not tested. The plan identity needed Reader at the group (see Plan identity at the group).
- Whether existing roots still apply under `Deny` from CI (not run); resources Azure creates itself in other regions
  (for example Defender or Network Watcher) being refused.
- Remediation and exemptions; any `deployIfNotExists` behaviour (Week 9 Day 3).
- Which two storage accounts were the two `Compliant` records; the AVM module inputs and defaults from the primary
  source; subscription vending; whether `azurerm_policy_definition` carries the same deprecation as the set definition
  (the `validate` output was reported without its warning text).

## Consequences

- Every new subscription under `mg-platform` inherits the baseline; a child scope cannot turn it off, only an
  exemption can.
- The elevation window: to read or change the tenant root a Global Administrator runs `elevateAccess` and removes the
  assignment afterwards. Nothing in the code needs it after the group exists (reasoned for writes).
- Owed: the diagnostic-settings policy and its identity (Day 3), an exemption example, and tagging policy with the `NetworkWatcherRG` exception. The CI plan leg is closed (see Plan identity at the group).
