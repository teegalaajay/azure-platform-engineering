# ADR-0004: Subscription and environment layout

- **Status:** Accepted
- **Date:** 2026-09-29
- **Deciders:** platform-team (@teegalaajay)

## Context

The platform has at least two environments (dev and prod). In Azure the subscription is the
hard boundary for billing, Azure Policy assignment, RBAC inheritance and service quotas; a
resource group is a softer boundary inside a subscription. Enterprise landing zones normally
give each environment its own subscription under a management group hierarchy. This reference
platform runs on a single, personally funded subscription, and cost and administrative scope
must stay small.

## Options considered

1. **One subscription per environment** under a management group. Strongest isolation;
   the enterprise default. Needs several subscriptions and management group administration.
2. **One subscription, environments separated by resource group.** Cheapest and simplest;
   isolation has to be built with resource-group-scoped RBAC and policy.

## Decision

Option 2, with the design kept ready for option 1.

- One subscription, named `sub-platform-shared-001`. The name says "shared" because it holds
  both dev and prod resource groups; an environment in the name would mislabel it.
- Environments are separated by resource group, named `rg-<purpose>-<env>`
  (for example `rg-platform-dev`, `rg-platform-prod`), and every resource carries the
  mandatory `environment` tag.
- The subscription is always referenced by **ID**, never by display name (names are mutable
  labels). The ID is not committed: it is supplied at runtime through `ARM_SUBSCRIPTION_ID`
  locally and in CI.
- Region, default VM size and image are recorded in `engineering_standards.md` §5 after
  checking SKU availability for this subscription.
- A subscription budget with alerts at 50/80/100% exists before any resource is deployed.

## Consequences

- A mistake with a subscription-scoped identity can reach both environments. Mitigation: CI
  and automation identities receive roles at resource-group scope wherever possible, and the
  apply identity is reachable only through a protected environment (ADR-0002, ADR-0003).
- One budget covers all environments, so cost cannot be attributed by subscription; the
  `environment` and `cost_center` tags provide the split.
- **Migration path to option 1:** root modules take the environment as input and never
  hard-code the subscription, so moving prod to its own subscription is a change of
  `ARM_SUBSCRIPTION_ID` and state backend configuration, not a rewrite.
