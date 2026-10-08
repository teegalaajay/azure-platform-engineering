# ADR-0011: Subscription cost budget in Terraform

- **Status:** Accepted
- **Date:** 2026-10-08
- **Deciders:** platform-team (@teegalaajay)
- **Implements:** the cost guardrail promised in ADR-0004 (one subscription, environments separated by resource group)

## Context

All environments share one subscription (`sub-platform-shared-001`, ADR-0004), so a single budget is the only spend control for the whole platform. Until now it existed as a portal hand-fix: a subscription-scope budget whose name field saved as the literal string `undefined`. It was not reviewable, not reproducible, and its name cannot be changed in place. Every other component is Terraform, so a hand-built guardrail is also a rebuild risk.

A budget is a notification, not a brake. Azure evaluates it against cost data that lags real usage, so an alert arrives after the spend, never before it, and nothing is stopped or deleted.

## Options considered

**Where it lives**
1. Inside an existing root (`platform/foundation/hub` or `platform/security`).
2. A root of its own, `platform/cost`.

**Scope**
3. Subscription (`azurerm_consumption_budget_subscription`).
4. Billing account (needs billing roles, not Azure RBAC).
5. One budget per resource group.

**Alert recipients**
6. Email addresses committed in `*.auto.tfvars`.
7. Email addresses supplied at run time through `TF_VAR_budget_contact_emails`, marked `sensitive`.

## Decision

Options 2, 3 and 7.

- **Own root** `platform/cost`, state key `platform/cost.tfstate`. A separate state blob means a separate lease: applying the network or security roots can never lock, change or break the budget, and the reverse. The budget reads nothing from other roots, so there is no reason to couple it. It needs cost-management rights, not network or Key Vault rights; folding it into another root would force that root's identity to carry cost rights too, and would let a cost change ride along in an unrelated PR.
- **One budget** `budget-platform-shared-monthly`: USD 50 per month, starting 2026-10-01 (Azure requires the first day of a month). Notifications at 50, 80 and 100 percent, each on **Actual** and on **Forecasted** spend, operator `GreaterThan`: six alerts, built from the `alert_thresholds` list with a `dynamic` block.
- **Replaces, does not import.** The portal budget `undefined` cannot be renamed, so Terraform created the new budget and the old one was deleted afterwards through the API (2026-10-08). No import.
- **Recipients are an input, never a committed value.** The repository is public and an email address is a personal identifier (same class as the object ID in open item 43). `budget_contact_emails` has no default, is `sensitive`, and comes from `TF_VAR_budget_contact_emails`. `sensitive` matters here for one reason: the PR template requires pasting plan output, and a PR on a public repository is public.
- **No tags.** The resource has no `tags` argument and lives at subscription scope, outside any resource group, so the mandatory-tag rule has nothing to attach to. Ownership is carried by the root itself, the CODEOWNERS entry and this ADR.
- **Billing-account budget `Overall` stays as it is**, created in the portal on 2026-09-29 as an account-wide backstop. It sits outside Terraform on purpose: it needs billing-account roles that the platform identity must not hold. It is a documented, accepted hand-created exception.

## Consequences

- Proven 2026-10-08: `plan` showed `1 to add`; `apply` created it from the branch (Azure accepted `start_date` 2026-10-01); a second `plan` showed `No changes`; reading it back from ARM returned amount 50, grain Monthly, start 2026-10-01 and exactly six alerts (Actual and Forecasted at 50/80/100). After deleting `undefined`, the subscription lists only the new budget.
- Because the email list is `sensitive`, Terraform prints every `notification` block as `(sensitive value)`. The plan therefore cannot show that the thresholds are right. Threshold correctness is verified from ARM (runbook section 3), not from the plan.
- `sensitive` hides the address from the terminal and from pasted plans; it is still stored in plaintext in the state blob. That is acceptable only because state is a private, Entra-only container (ADR-0005).
- Alerts depend on Azure cost data, which lags usage. A budget does not cap spend, delete resources or disable anything. Hard limits would need action groups and automation, not part of this decision.
- `end_date` is not set in code; Azure/the provider computes it. Read it back and decide before it matters.
- Changing the amount, thresholds or recipients is an in-place update. Changing the budget `name` forces replacement.

## Deferred

- Least-privilege role for the identity that applies this root: Cost Management Contributor at subscription scope is the candidate. Unverified; check the role definition and test with a non-Owner identity when per-root identities exist (Week 3).
- Action groups and automated responses, per-environment or tag-based cost views, anomaly alerts (Week 9, with observability and Policy).
- Rolling the budget forward when `end_date` approaches.
