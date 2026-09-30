# Runbook: Terraform State Backend

**Purpose:** Create, verify and recover the remote state backend (ADR-0005).
**Owner:** platform-team · **Last validated:** 2026-09-30 · **Persistent:** yes, never torn down

Placeholders: `<SUBSCRIPTION_ID>`. Real values are never committed to this public repository.

## 1. Create or converge

Prerequisites: `az login --tenant <TENANT_ID>` done, and `ARM_SUBSCRIPTION_ID` exported
(workstation-setup runbook). The script refuses to run against any other subscription.

```bash
bootstrap/state-backend.sh               # safe to re-run: creates what is missing, resets drifted settings
```

Expected: every section ends in `converged`, `exists` or `already granted` on a second run.

## 2. Verify

```bash
az storage account show -n stattfstate01 -g rg-tfstate \
  --query "[sku.name, allowSharedKeyAccess, minimumTlsVersion, allowBlobPublicAccess]" -o tsv
# expect: Standard_GZRS  false  TLS1_2  false
az storage blob list --account-name stattfstate01 -c tfstate --auth-mode login --query "length(@)" -o tsv
# expect a number; "You do not have the required permissions" = missing data role or not yet propagated
```

## 3. Grant a new identity access to state

The operator running the script is granted automatically. For another identity (e.g. a CI
service principal), grant `Storage Blob Data Contributor` at the account scope with
`--assignee-object-id` and `--assignee-principal-type`, then allow a few minutes to propagate.

## 4. Recover a corrupted or deleted state file

1. Stop all runs against that key (no plan/apply in progress).
2. List versions of the blob:
   `az storage blob list --account-name stattfstate01 -c tfstate --prefix <key> --include v --auth-mode login --query "[].{v:versionId, cur:isCurrentVersion, t:properties.lastModified}" -o table`
3. Download the last known-good version (`--version-id`), inspect it, then upload it as the
   current blob. A deleted blob is restored with `az storage blob undelete` within 30 days.
4. Run `terraform plan` and confirm it shows no unexpected changes before any apply.

## 5. Failure modes

| Symptom | Cause | Action |
|---|---|---|
| `az CLI is on …, not ARM_SUBSCRIPTION_ID` | CLI context on another subscription | `az account set -s "$ARM_SUBSCRIPTION_ID"` |
| `You do not have the required permissions` on blob commands | no data role, or propagation lag | check `az role assignment list --scope <account id>`; wait, don't re-grant |
| `KeyBasedAuthenticationNotPermitted` | a tool fell back to account keys | use `--auth-mode login` / `use_azuread_auth = true` |
