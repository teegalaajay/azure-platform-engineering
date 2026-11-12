# ADR-0041: Identity design: two permission layers, the bootstrap scripts stay, PIM and Conditional Access on paper

- **Status:** Accepted
- **Date:** 2026-11-11
- **Deciders:** platform-team (@teegalaajay)
- **Relates to:** ADR-0013 (GitHub identities and the apply identity's limits); ADR-0022 (Azure DevOps identity);
  ADR-0040 (governance, where the elevation was used); ADR-0002 (secrets and identity)

## Context

`roadmap_plan.md` asked, on 2026-10-28, for a decision on a `platform/identity` Terraform root (the `azuread`
provider) that would replace `bootstrap/github-oidc.sh` and `bootstrap/ado-oidc.sh`. Week 9 also covers the identity
controls an enterprise adds around people: Privileged Identity Management and Conditional Access. This ADR records the
design and one decision. Nothing in it changes a resource.

## The two layers

- **Azure RBAC** controls Azure resources at management-group, subscription, resource-group and resource scope.
  Assignments inherit downward only. It holds Reader, Contributor, the data-plane roles, the conditional RBAC
  Administrator and the custom `Platform Lock Writer`.
- **Entra ID roles** control the directory: users, groups, app registrations, Conditional Access. Global Administrator
  is one of them and grants nothing on resources by itself.
- The bridge is `elevateAccess`, which gives a Global Administrator User Access Administrator at `/`.

## Options considered and decisions

1. **`platform/identity` root.** (A) Keep the two scripts and record an exit condition; (B) build the root for the two
   GitHub apps first, import them, retire that script only after a clean plan; (C) replace both scripts at once.
   **Decision: (A)**, chosen by the mentor (no reason was given). The scripts are idempotent, prune what they do not
   declare, and were exercised on real runs (PR #16, PR #28); the apply workflow depends on them. Cost: an identity
   change has no plan view and no state, and the repo has two styles for infrastructure. Why not B or C now (reasoned):
   a mistake that makes Terraform recreate an app gives it a new client ID, and that ID is stored in eight GitHub
   secrets, the Azure DevOps connections and the federated credentials; and Terraform manages only what it declares, so
   it would lose the scripts' removal of undeclared credentials. The portal-built Azure DevOps objects (connections,
   pipelines) could not move in either case (item 119). **Exit condition for (B):** import the GitHub apps and role
   assignments, and require `terraform plan` to show `No changes` before any script is retired.
2. **Standing privilege for people (PIM).** Design only: human administrators hold Entra and Azure roles as eligible and
   activate them for a limited time with a reason and MFA. Service identities (`app-gh-apply-shared`,
   `app-ado-apply-shared`) stay permanently active, because an unattended job cannot activate a role (reasoned; whether
   PIM can make a service principal eligible was not checked). Their risk is limited by narrow roles, the ABAC condition
   on RBAC Administrator, no delete on the lock role and the `production` environment approval (ADR-0013, ADR-0015).
   Cost of leaving it on paper: the tenant has standing Global Administrator for its one human.
3. **Sign-in controls (Conditional Access).** Design only. Security defaults stay on. They are Microsoft's baseline (MFA
   for all users, extra MFA for administrators, legacy protocols blocked) and are mutually exclusive with Conditional
   Access, so building CA means turning them off first. Target state when a licence exists: MFA for everyone,
   phishing-resistant MFA for privileged activation, legacy authentication blocked, two break-glass accounts excluded
   from every policy and alerted on use, and a location rule for workload identities. Cost: no custom policy, and no
   break-glass account exists today (one human, one account), so a mistake in any future policy could lock the
   administrator out.
4. **Role assignment for people.** Direct assignment to the one human today (including the duplicate Owner, open item
   15). Cost: a team needs groups and membership changes instead; that is the rule once there is a second person.

## Observed (2026-11-11)

- Owner on the subscription could not read management groups (`AuthorizationFailed` on
  `Microsoft.Management/managementGroups/read`); the account holds Global Administrator.
- `elevateAccess` returned an empty body and the group list worked afterwards; the assignment was removed with
  `az role assignment delete` and the list then showed only `mg-platform` and not the Tenant Root Group.

## Reasoned, not tested

- PIM needs Entra ID P2 or an Entra ID Governance licence; Conditional Access needs P1 or higher; Conditional Access for
  workload identities needs a separate licence. None of the tenant's licences was looked up.
- Security defaults are the reason device-code login was blocked in Week 1 (recorded in the workstation notes).
- A location rule could name the self-hosted runner's fixed NAT address but not GitHub-hosted runners, which have no
  fixed address (ADR-0014).

## Unproven

- The tenant's licences; PIM for service principals; every Conditional Access behaviour; the `azuread` provider
  resources, an `azurerm_role_assignment` with an ABAC `condition`, and an import of the existing apps.
- Whether an Entra audit-log alert on the two app registrations exists (open item 63).

## Consequences

- The two scripts remain the source of identity changes. A change to them is a normal PR with its ADR amendment.
- The elevation is a manual, temporary act: run `elevateAccess`, do the work, remove the assignment, and confirm with a
  list that the root group is no longer visible. It is recorded here because it has no expiry of its own.
- Owed: licence check, break-glass accounts, PIM and Conditional Access when a licence exists, and the `platform/identity`
  decision again when the exit condition can be met.
