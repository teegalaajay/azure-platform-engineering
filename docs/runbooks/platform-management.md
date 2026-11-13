# Runbook: platform management (workspace, diagnostic settings by policy, cap alert)

- **Purpose:** central Log Analytics workspace for platform logs; Key Vault diagnostic settings enforced by policy; one alert when the daily cap is reached.
- **Owner:** platform-team
- **Last validated:** 2026-11-13 (applied by hand from the branch; first CI apply not yet run)
- **Persistent:** yes (workspace has `prevent_destroy` and a `CanNotDelete` lock)
- **Decisions:** ADR-0044 (workspace, policy, alert), ADR-0040 (governance root), ADR-0010 (vault)

## Layout

| Item | Root | Name |
|---|---|---|
| Resource group, workspace, lock | `platform/management` | `rg-management-shared`, `log-plat-shared-at01` |
| Action group, cap alert | `platform/management` | `ag-platform-shared`, `alert-law-daily-cap-reached` |
| DINE assignment and two role assignments | `platform/governance` | `diag-keyvault-to-law` |

The governance root reads the workspace ID from the `platform/management` state, so apply management first.

## Before you start

1. `az login` as the operator; `ARM_SUBSCRIPTION_ID` set; default subscription equals it.
2. `TF_VAR_alert_contact_emails` set (JSON list; in `~/.bashrc` it copies `TF_VAR_budget_contact_emails`). Never commit it.
3. In CI the same variable comes from the repository secret `BUDGET_CONTACT_EMAILS` (`plan.yml`, `apply.yml`).

## Apply

1. `cd platform/management`, `terraform init`, `terraform plan -out=/tmp/mgmt.tfplan`, read it, `terraform apply /tmp/mgmt.tfplan`, then a second plan: expect `No changes`.
2. `cd platform/governance`, same sequence. Governance is hand-applied (listed in `SKIP_ROOTS`).

## Remediate an existing vault (one-off, CLI)

A policy with `deployIfNotExists` only acts on new or updated resources. A vault that already exists needs a remediation task:

`az policy remediation create --name <name> --policy-assignment <assignment id> --resource-discovery-mode ExistingNonCompliant`

Check with `az policy remediation show`: expect `Succeeded` and 1 of 1 deployments. Observed 2026-11-13: it passed the `Deny` assignment of ADR-0040.

## Test with a throwaway vault

1. Create a resource group and a vault (omit `--enable-purge-protection`: an explicit `false` is refused by Azure).
2. Read `az monitor diagnostic-settings list` on the vault every minute or so. Observed: empty at about 1 minute, the setting present at about 7 minutes.
3. Delete the group, then purge the vault (`az keyvault purge`) to release the name. Verify the group is gone and the soft-deleted list is empty.

## Symptoms

| Symptom | Cause | Status |
|---|---|---|
| Governance plan fails reading remote state | management root not applied | reasoned |
| Management plan fails on `alert_contact_emails` | variable not set (CI: secret not passed) | reasoned |
| `for_each` refused on the recipients | list is sensitive; the code iterates indexes | observed |
| `BadRequest` creating a vault with purge protection `false` | Azure refuses the explicit value | observed |
| New vault has no setting yet | policy deploys after creation, about 1 to 7 minutes | observed |
| Existing vault has no setting | no remediation task run | observed |
| Compliance list is empty | not explained; a scan did not change it | observed |
| Key Vault rows are in `AzureDiagnostics` | the built-in policy does not set the destination type | observed |
| No collection after the daily cap | cap reached until the reset; the alert reports it | read |

## Unproven

First CI apply; the alert firing and the email arriving; the lock blocking a delete; price figures against Cost Management. See ADR-0044.
