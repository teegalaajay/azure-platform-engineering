# ADR-0013: GitHub Actions identities for Azure (OIDC, plan and apply)

- **Status:** Accepted (2026-10-15; `bootstrap/github-oidc.sh` applied and read back twice, token exchange and denials proven on PR #16)
- **Date:** 2026-10-15
- **Deciders:** platform-team (@teegalaajay)
- **Implements:** Tier 1 of ADR-0002 ("a plan-only identity for pull requests and a separate apply identity reachable only through a protected environment")
- **Supersedes:** the state-access rule (section 3) and the apply-identity line (CI section) of `engineering_standards.md`, which are superseded by this ADR

## Context

The validate workflow (ADR-0012) needs no Azure identity. The next two workflows do: plan on pull request (Week 3 Day 5) reads Azure resources and the state blob, and apply on merge (Week 3 Day 6) changes Azure and writes state.

A workflow run on a pull request executes the workflow file from the pull request's merge ref, so the author of a pull request controls the code that holds the token. Anything a pull request job can authenticate as, a pull request author can use. The identity a pull request can reach therefore has to be unable to change Azure or state.

Authentication must follow ADR-0002: no stored secret. GitHub issues each job a signed OIDC token whose `sub` claim describes how the job was triggered. Microsoft Entra ID exchanges it for an Azure access token only if issuer, audience and subject match a federated credential exactly. The credential decides who can become the identity. RBAC decides what the identity can do. They are separate controls.

## Options considered

**Identity model**
1. One identity for plan and apply.
2. Two identities, one per purpose.

**Credential type**
3. Client secret stored in GitHub.
4. OIDC federated credential, no stored secret.

**Subject format**
5. Name-based: `repo:<owner>/<repo>:<context>`.
6. ID-based: `repo:<owner>@<ownerId>/<repo>@<repoId>:<context>`.

**State access for the plan identity**
7. Storage Blob Data Reader, and plan runs with `-lock=false`.
8. Storage Blob Data Contributor, so plan can take the state lock.

**Apply identity, control plane**
9. Contributor only.
10. Owner.
11. Contributor plus Role Based Access Control Administrator limited by an ABAC condition to the one role this repository assigns, plus a small custom role for management locks.

**What gates the apply credential**
12. Branch subject (`ref:refs/heads/main`).
13. Environment subject (`environment:production`) on a protected GitHub environment.

**How the identifiers reach workflows**
14. Repository variables.
15. Repository secrets.

**Where it is configured**
16. Portal and `gh` by hand.
17. An idempotent script in `bootstrap/`.

## Decision

Options 2, 4, 6, 7, 11, 13, 15 and 17.

- **Names:** `app-gh-plan-shared` and `app-gh-apply-shared` (`<type-prefix>-<purpose>-<env>`, `shared` as in ADR-0005). Credentials: `github-pr-plan` and `github-env-production-apply`.
- **Federated credentials**, issuer `https://token.actions.githubusercontent.com`, audience `api://AzureADTokenExchange`:
  - plan: `repo:<owner>@<ownerId>/<repo>@<repoId>:pull_request`
  - apply: `repo:<owner>@<ownerId>/<repo>@<repoId>:environment:production`
  - No wildcard and no credential for any other subject.
- **ID-based subjects (option 6).** The token GitHub issues for this repository carries the owner and repository IDs in `sub`; the name-only form does not match it. Besides matching, the ID form means a repository deleted and re-created under the same name cannot obtain a token for these credentials. The two IDs are pinned as constants in `bootstrap/github-oidc.sh`, and the script compares them with `gh api` before touching Entra and stops on a mismatch. They are not derived at run time: deriving them would silently adopt a re-created repository, which is exactly what the pin is meant to prevent.
- **Plan identity roles:** Reader at subscription scope; Storage Blob Data Reader on the `tfstate` container. Plan runs with `-lock=false`. The state lock is a lease on the blob, and taking a lease is a write that Data Reader does not grant. Proven: with the plan identity, reading the state blob succeeds and `az storage blob lease acquire` returns `AuthorizationPermissionMismatch`. Option 8 would give every pull request job write access to state.
- **Apply identity roles:**
  - Storage Blob Data Contributor on the `tfstate` container only.
  - Contributor at subscription scope. Contributor excludes `Microsoft.Authorization/*/Write` and `*/Delete`, so it cannot create role assignments or locks. Role permissions are the union of all assignments; a role's `NotActions` do not subtract from another role.
  - Role Based Access Control Administrator at subscription scope, with an ABAC condition (condition version 2.0) on the assignment. The condition is: for role-assignment write (checked against the request) and delete (checked against the existing assignment), the role definition must be Key Vault Secrets Officer (`b86a8fe4-44ce-4948-aee5-eccb2c155cd7`), the one role `platform/security` assigns. Any other role is refused.
  - Custom role `Platform Lock Writer`: `Microsoft.Authorization/locks/read` and `locks/write`, **no delete**.
- **Protected environment `production`:** deployment branches restricted to `main` through an explicit branch policy; one required reviewer; "prevent self-review" off (a sole maintainer could never approve otherwise). GitHub evaluates these before the job starts, so a refused or waiting job holds no token. Proven: a pull request job declaring `environment: production` failed in 3 seconds with `Branch "refs/pull/16/merge" is not allowed to deploy to production`, with no steps run and no reviewer prompt.
- **Identifiers as repository secrets (option 15).** Tenant ID, subscription ID and the two client IDs are not credentials, but this repository is public and step logs are public. Measured in a throwaway repository: variables print in plain text in the `env:` header and in any echo; secrets print as `***`. They are stored as secrets so they are masked. Secrets are also withheld from workflows triggered from forks. Proven on PR #16: all four print as `***`. The `sub` claim still shows owner and repository IDs, which are public values.
- **Configured by** `bootstrap/github-oidc.sh` (identities, credentials, role assignments) and `bootstrap/github-repo-settings.sh` (the environment, its branch policy and the secrets). Both are idempotent.
- **Convergence.** Each script finds an object by name, creates it if absent, updates it if one exists, and fails if two exist. Federated credentials are compared by `subject|issuer|audience`; role assignments by `principal|role|scope` plus the stored condition string. Anything undeclared is removed: credentials, client secrets, role assignments, repository secrets and variables.

## Consequences

Proven in this repository (PR #16 and the bootstrap runs):

- The plan identity can read the subscription and the state blob, and is refused a subscription write (`AuthorizationFailed`) and the state lease.
- The token exchange succeeds with the ID-based subject.
- A pull request job cannot enter `production`.
- Role grants converge. A manually added role assignment (Owner) on either identity is removed on the next run; a changed condition is repaired.

Reasoned, not yet reproduced:

- A pull request from a fork gets no `id-token` permission and no secrets (Week 3 Day 5).
- Contributor alone fails `AuthorizationFailed` on role-assignment and lock resources (apply identity, tested after merge).

Costs accepted:

- **Lock cost.** `terraform destroy` on a locked resource fails until a human removes the lock, because the apply identity cannot delete locks. A lock guards against accidents, not against an identity that may delete locks.
- **Residual privilege.** The condition limits the role that can be assigned, not the principal or the scope. The apply identity can assign Key Vault Secrets Officer to any principal in the subscription. Narrowing the assignment scope is a later fix.
- **The script is a repair, not a guard.** Drift persists until the next run. Detection belongs outside the script: Entra audit-log alerts on changes to these app registrations and role assignments, and restricted ownership of the app registrations.
- A pull request plan can read state that an apply changes a moment later. Apply plans again, so only review accuracy is affected.
- With one maintainer the required reviewer is the same person who merged. The approval is a deliberate pause, not an independent control. The compensating controls are the branch policy, the ruleset and required checks.
- The identities, credentials and role assignments are not Terraform-managed (bootstrap script, as with the state backend).

## Deferred

- Azure DevOps workload identity federation (Weeks 6 to 7).
- ~~A managed identity for the self-hosted runner.~~ Superseded by ADR-0015: the runner has no managed identity.
- Firewalling the state account (open item 42). Hosted runners have no fixed IP. ADR-0015 puts only apply on the runner and keeps plan on hosted runners, so this still waits for a private path for plan.
- A least-privilege role for the cost root (open item 50).
- Entra audit-log alerting for these objects.
- Testing `joinViaServiceEndpoint/action` and Contributor switching a vault back to access policies (open items 35 and 44).
