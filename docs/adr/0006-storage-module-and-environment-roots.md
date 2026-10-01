# ADR-0006: Storage module and per-environment root modules

- **Status:** Accepted
- **Date:** 2026-10-01
- **Deciders:** platform-team (@teegalaajay)

## Context

Workloads need storage accounts that meet one security baseline (Entra-only data access,
TLS 1.2, HTTPS only, no anonymous access, recoverable blobs) in every environment. Writing
that baseline into each root module invites drift: one root forgets a setting, and every call
site has to be reviewed for security. Environments also differ in what they must survive:
dev data is disposable and rebuilt from code; prod data is GxP-regulated, must survive a
datacenter loss and must not be deletable by accident.

## Options considered

**Where the baseline lives**
1. **Every setting a module variable.** Flexible; the module stops being a control, because any
   caller can turn shared key or public access back on in one line.
2. **Baseline hardcoded in the module; only placement and resilience are inputs.** Reviewed
   once, inherited by every caller; weakening it needs a PR against `modules/storage`.

**How environments are laid out**
3. **One root calling the module for dev and prod.** One state blob holds both environments:
   one lock, one blast radius, and any identity that can apply dev can apply prod.
4. **One root per environment** (`workloads/storage-demo/{dev,prod}`), each with its own key.

**How prod data is protected from deletion**
5. **`prevent_destroy` inside the module.** `lifecycle` takes literals only, so it would apply
   to every caller, including ephemeral dev roots, and it only stops Terraform.
6. **ARM `CanNotDelete` lock in the prod root, with `prevent_destroy` on the lock.**

## Decision

Options 2, 4 and 6.

- **`modules/storage`** hardcodes: `Standard` tier, `StorageV2`, shared key disabled,
  TLS 1.2, HTTPS only, nested items never public, blob versioning, blob and container soft
  delete (30 days). Inputs: `name` (validated against Azure's 3-24 lowercase alphanumeric
  rule), `resource_group_name`, `location`, `replication_type` (validated allow-list
  LRS/ZRS/GRS/GZRS, **no default**, so every caller decides redundancy explicitly) and `tags`
  (validated to contain the six mandatory tags). Outputs: `id`, `name`,
  `primary_blob_endpoint`; keys and connection strings are never output, because shared key is
  disabled and outputs are stored in plaintext in the caller's state.
- **Redundancy by environment.** Dev: `LRS` (three copies in one datacenter; data is rebuilt
  from code, RPO/RTO not applicable). Prod: `GRS` (LRS in `eastus2` plus asynchronous
  replication to `centralus`). The secondary is not readable and becomes the primary only after
  a failover, so the recovery point is the last geo-sync (typically minutes, not guaranteed by an
  SLA) and the recovery time is the failover duration.
- **Deletion protection for prod, two layers.** `azurerm_management_lock` `CanNotDelete` on the
  account stops deletion from every tool and identity, including deletion of the resource group
  that contains it. `prevent_destroy = true` on the lock makes Terraform reject any plan that
  would destroy or replace the lock, and therefore the account it depends on. Removing either
  layer requires a reviewed PR.
- The tflint rule `azurerm_resources_missing_prevent_destroy` is suppressed in the module with
  the reason recorded inline; protection is applied per environment instead.
- Child modules declare `required_version` and `required_providers`, never a provider or
  backend block. Lock files in child modules are git-ignored; only the root's lock file counts.

## Consequences

- Every storage account built through the module meets the baseline; Azure Policy (Week 9)
  enforces it for anything built outside the module.
- Dev and prod have separate state blobs, locks and blast radius. Both blobs share the
  `tfstate` container, so an identity with a container-scope data role can still read both;
  per-environment containers or ABAC conditions are decided with the CI identities in Week 3.
- **Prod is not available during a zone outage** under GRS until a geo-failover is performed.
  `GZRS` keeps the primary available through a zone loss and is the stronger choice for
  regulated production data in a zonal region. **Tested 2026-10-01:** azurerm plans
  GRS -> GZRS as `forces replacement` (a new, empty account), and `prevent_destroy` on the lock
  rejected that plan. The change is therefore made as a follow-up: an in-place Azure redundancy
  conversion of the same account (data kept), then `replication_type = "GZRS"` in code so the
  next plan shows no changes; its own PR and runbook. Never by replacing the account.
- **Accepted risk:** public network access stays enabled (as in ADR-0005); network rules or
  private endpoints follow in Week 2 Day 3 and Week 8.
- Tearing down the prod demo root is deliberately a two-step change: a PR removing
  `prevent_destroy`, then `terraform destroy` (which deletes the lock before the account).
- Root modules repeat the tag map until locals and `merge()` are introduced (Week 1 Day 5).
- `modules/storage` is now called from two roots, so it is tagged `modules/storage/v1.0.0`
  after merge (engineering_standards.md section 11).
