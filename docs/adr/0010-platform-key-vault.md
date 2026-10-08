# ADR-0010: Platform Key Vault (authorization, network access, protection)

- **Status:** Accepted
- **Date:** 2026-10-08
- **Deciders:** platform-team (@teegalaajay)
- **Implements:** ADR-0002 Tier 2 (Key Vault, RBAC, soft delete + purge protection, IP + `snet-mgmt` ACL)

## Context

The platform needs one shared place for platform-level secrets (seeded by the operator, later read by the self-hosted runner in `snet-mgmt`). Key Vault has two planes: ARM (`management.azure.com`) manages the vault resource and never returns secret values; the data plane (`https://<name>.vault.azure.net`) serves secrets. A data-plane request passes two independent gates, in order:

1. **Network gate.** Source IP against `ipRules`, or source subnet (via the `Microsoft.KeyVault` service endpoint) against `virtualNetworkRules`. No match and default action Deny: HTTP 403, inner code `ForbiddenByFirewall`. Identity is not evaluated.
2. **Identity gate.** Entra token from the vault's tenant, then RBAC `dataActions`. Missing data action: HTTP 403, inner code `ForbiddenByRbac`.

Unlike `azurerm_storage_account` (control plane only, ADR-0009), `azurerm_key_vault_secret` reads the data plane on every refresh. Any root holding a secret therefore needs a data role **and** an allowed network path for `plan` to work at all.

## Options considered

**Authorization model**
1. Access policies. Stored on the vault resource; editing them is an ARM write (`Microsoft.KeyVault/vaults/write`), which Contributor holds, so Contributor can grant itself secret access. Whole-vault granularity, 1024-entry limit, outside PIM and access reviews.
2. Azure RBAC. Granting data access needs `Microsoft.Authorization/roleAssignments/write`, which Contributor excludes (`notActions`). Scopes down to a single secret. Governed by PIM, access reviews and Azure Policy like every other assignment.

**Bypass**
3. `AzureServices`: trusted Microsoft services skip the network gate (they still need RBAC).
4. `None`.

**Module**
5. `modules/key-vault` now.
6. Resources inline in the root until a second vault exists.

## Decision

Options 2, 4 and 6, in a persistent root `platform/security` (state key `platform/security.tfstate`, resource group `rg-security-shared`).

- **Vault `kv-plat-shared-at01`**, SKU `standard` (secrets only; no HSM-backed keys needed).
- **Hardcoded, never variables** (a variable can be overridden with one `-var`, open item 26): `rbac_authorization_enabled = true`, `purge_protection_enabled = true` (irreversible), `soft_delete_retention_days = 90`, `enabled_for_deployment/disk_encryption/template_deployment = false`, `network_acls.default_action = "Deny"`, `bypass = "None"`.
- **Allowed paths:** hub `snet-mgmt` (read from `platform/foundation/hub.tfstate`) and the operator IP (`TF_VAR_operator_ip_cidr`, `/32` stripped). Every allowed path has a named consumer. Spoke subnets are excluded: no spoke workload needs a platform secret, and a vault reachable from dev and prod would couple the environments ADR-0007 separates. Workload secrets go in one vault per application per environment, in the workload's own root.
- **`bypass = "None"`:** no trusted Azure service needs this vault. Revisit (ADR amendment) when one does: VM disk encryption, App Service Key Vault references, ARM template deployment.
- **Access:** operator gets `Key Vault Secrets Officer` at vault scope. The principal is an input (`TF_VAR_operator_object_id`), never `data.azurerm_client_config.current.object_id`: that value is whoever runs Terraform, so the first pipeline run would force-replace the assignment onto the pipeline identity. Workload identities get `Key Vault Secrets User` from their own roots.
- **Provider behaviour:** `purge_soft_delete_on_destroy = false`, `purge_soft_deleted_secrets_on_destroy = false` (destroy never purges), `recover_soft_deleted_key_vaults = true`, `recover_soft_deleted_secrets = true`. These are client-side; purge protection is the Azure-side control and holds even if the flags change.
- **Secrets in Terraform use write-only arguments:** `value_wo` fed by an `ephemeral = true` variable, with `value_wo_version` as the change trigger. Plain `value` is not used (it stores the plaintext in state; `sensitive` only hides CLI output).
- **Three deletion controls, each covering a different failure:** `lifecycle { prevent_destroy = true }` on the vault (Terraform refuses any plan that destroys or replaces it), a `CanNotDelete` management lock on the vault (ARM refuses deletes from any client, including Owner, until the lock is removed), itself under `prevent_destroy`, and purge protection (anything deleted stays recoverable for 90 days). None of them stops an in-place change such as opening the ACL; that is caught by code review and the hardcoded baseline. Flagged by tflint `azurerm_resources_missing_prevent_destroy` on the first commit attempt.
- **No module** until a second vault appears; then extract `modules/key-vault` with this baseline.

## Consequences

- Proven 2026-10-07/08 on `kv-plat-shared-at01`:
  - Read back from ARM: RBAC true, purge protection true, retention 90, Deny, bypass None, 1 IP rule, 1 VNet rule. `plan` from `main` state: `No changes`.
  - Operator, allowed IP: `az keyvault secret list` = `[]` (network passed, Secrets Officer effective).
  - Same identity and IP, `az keyvault key list`: 403 `ForbiddenByRbac` (Secrets Officer has no `keys/read` data action).
  - Same identity and action, from Azure Cloud Shell: 403 `ForbiddenByFirewall`, message "Client address is not authorized and caller was ignored because bypass is set to None". The service states identity was not evaluated: network gate first.
- Proven in the sandbox (`azure-iac-sandbox/w2d4-write-only`, Terraform 1.16.4, azurerm 4.81.0): plan shows `value_wo = (write-only attribute)`; the plaintext marker occurs 0 times in state (plain `value` stored as `""`); Key Vault returns the plaintext to an authorized caller; changing only the input gives `No changes`; bumping `value_wo_version` gives `~ update in-place` and a new secret version.
- Write-only means Terraform cannot detect a hand-changed value (refresh only sees metadata; a new version updates the computed `version` silently). Value correctness and rotation are owned outside Terraform (Key Vault version history, diagnostic logs in Week 9, rotation process).
- A new role assignment can take minutes to reach the data plane; `depends_on` orders calls but does not wait. On `ForbiddenByRbac` right after a new assignment: wait and re-apply (did not occur on 2026-10-07/08; not proof it cannot).
- The vault name is reserved for 90 days after deletion and cannot be purged; teardown-and-rebuild under the same name is impossible in that window.
- Inherited Owner at subscription scope does not appear in `az role assignment list --scope <vault>` without `--include-inherited`; access reviews must include it. Owner can still grant itself any data role (`roleAssignments/write`).
- `terraform plan` on this root needs an allowed network path once it holds a secret: GitHub-hosted runners (no fixed IP) cannot plan it; the self-hosted runner in `snet-mgmt` can (Week 3).
- Deferred: diagnostic settings to Log Analytics (Week 9), private endpoint and `public_network_access_enabled = false` (Week 8), secret rotation, test whether Contributor can switch the permission model back to access policies (expected to require `roleAssignments/write`; unverified).
