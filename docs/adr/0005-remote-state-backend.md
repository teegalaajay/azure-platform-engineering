# ADR-0005: Remote state backend

- **Status:** Accepted
- **Date:** 2026-09-30
- **Deciders:** platform-team (@teegalaajay)

## Context

Terraform state records every managed object and holds secrets in plaintext (ADR-0002), so it
must live in one access-controlled, recoverable place that every operator and pipeline uses.
Local state cannot be shared, reviewed or recovered. The backend must exist before
`terraform init`, so Terraform cannot create its own backend: it is created by a script.

Azure Storage exposes two planes. The **control plane** (Azure Resource Manager) authorizes
against a role's `actions`; the **data plane** (the blob endpoint) authorizes an Entra token
against `dataActions`, or accepts the account key with no identity check at all. Owner and
Contributor have `dataActions: []`, but they can call `listKeys` and use the key, which
bypasses data-plane RBAC and leaves no caller identity in the logs.

## Options considered

1. **Portal-created account, account-key auth.** Fast; not reproducible; any Contributor can
   read state via the key; access is not attributable.
2. **Terraform-managed backend in a separate bootstrap root.** Declarative, but that root's own
   state is again local, which moves the problem instead of solving it.
3. **Idempotent `az` script, Entra-only auth.** Reproducible and reviewable; converges drift
   on every run; shared key disabled, so every read and write is tied to a named identity.

## Decision

Option 3: `bootstrap/state-backend.sh`, re-runnable, converging (show → update, or create).

- **Names:** resource group `rg-tfstate`, account `stattfstate01`
  (`st<initials>tfstate<nn>`), container `tfstate`, keys `<folder>/<module>.tfstate`.
  The account is **single-purpose**: Terraform state only, no other containers.
- **Region:** `eastus2`, the platform's primary region (three availability zones; paired
  region `centralus`). SKU availability for this subscription was checked before choosing.
- **Redundancy:** `Standard_GZRS`: zone-redundant in `eastus2` plus an asynchronous copy in
  `centralus`, so state survives a zone or region loss. Cost is negligible at kilobyte scale.
- **Recovery from bad writes:** blob versioning, blob soft delete and container soft delete,
  30 days. Redundancy replicates a corrupted write; versioning is what recovers from it.
- **Authentication:** shared key access **disabled**; Entra ID only (`use_azuread_auth = true`
  in every `backend.tf`). Minimum TLS 1.2, HTTPS only, anonymous blob access disabled.
- **Authorization:** `Storage Blob Data Contributor` at **account scope** for the operator
  (granted by the script) and, from Week 3, for each CI identity. Account scope is accepted
  because the account is single-purpose.
- **Tags:** the six mandatory tags, with `environment=shared` (serves dev and prod roots),
  `data_classification=confidential` (state holds secrets) and `managed_by=bootstrap-script`.
- The container is created through ARM (`container-rm`), so it does not depend on a data role.

## Consequences

- Every state read and write is attributable to an Entra identity; no key exists that could
  leak or be shared.
- **Accepted risk:** public network access is enabled because GitHub-hosted runners use
  unpredictable IP addresses. Network restriction is revisited in Week 2 Day 3, and a
  private endpoint in Week 8.
- Every identity that runs Terraform needs the data role explicitly; Owner alone gets HTTP 403
  on the data plane. Role assignments take minutes to propagate to the storage service.
- Versions are kept indefinitely; a lifecycle rule to prune old versions is a follow-up.
- Any future container in this account inherits the account-scope grant, so none is added.
