# Runbook: platform Key Vault (`platform/security`)

**Purpose:** Deploy, verify and troubleshoot the shared platform Key Vault (ADR-0010).
**Owner:** platform-team · **Last validated:** 2026-10-08 · **Persistent:** yes (purge protection, 90-day name reservation)

Placeholders: `<TENANT_ID>`, `<YOUR_IP>`, `<OBJECT_ID>`. Real values are never committed to this public repository.

## 1. Layout

| Root | State key | Resources |
|---|---|---|
| `platform/security` | `platform/security.tfstate` | `rg-security-shared`, `kv-plat-shared-at01` (`prevent_destroy`), lock `lock-cannotdelete-kv-plat-shared-at01` (`CanNotDelete`, `prevent_destroy`), role assignment operator → Key Vault Secrets Officer (vault scope) |

Depends on `platform/foundation/hub` (reads `mgmt_subnet_id` from its state): apply the hub first.
Network ACL: default Deny, bypass None, allowed = hub `snet-mgmt` + operator IP.

## 2. Deploy or converge (from `main` only)

Prerequisites: `az login --tenant <TENANT_ID>`; `ARM_SUBSCRIPTION_ID`, `TF_VAR_operator_ip_cidr` (`<YOUR_IP>/32`) and `TF_VAR_operator_object_id` exported (workstation-setup runbook). One Terraform session per state key at a time.

```bash
cd platform/security
terraform init
terraform plan -out=tfplan           # review: expected addresses only, never a vault replacement
terraform apply tfplan && rm tfplan  # saved plans contain variable values: never keep or commit them
terraform plan                       # expect: No changes
```

A plan that shows `azurerm_key_vault.this` as `forces replacement` must not be applied: the old name stays reserved for 90 days and cannot be purged.

When your ISP changes your IP: update `TF_VAR_operator_ip_cidr`, open a new shell, plan/apply this root (expect `~ update in-place` on `network_acls` only). Until then, `plan` fails at refresh once the root holds a secret (see §4).

## 3. Verify

Control plane (works from any IP):

```bash
az keyvault show --name kv-plat-shared-at01 --query "{rbac:properties.enableRbacAuthorization, purgeProtection:properties.enablePurgeProtection, retentionDays:properties.softDeleteRetentionInDays, defaultAction:properties.networkAcls.defaultAction, bypass:properties.networkAcls.bypass, ipRuleCount:length(properties.networkAcls.ipRules), vnetRuleCount:length(properties.networkAcls.virtualNetworkRules)}"
```

Expected: `true / true / 90 / Deny / None / 1 / 1`.

Role assignments at vault scope (add `--include-inherited` for an access review: subscription Owner is otherwise hidden):

```bash
az role assignment list --scope $(az keyvault show --name kv-plat-shared-at01 --query id -o tsv) --query "[].{role:roleDefinitionName, principal:principalName}" -o table
```

Data plane (from the operator IP or `snet-mgmt`):

```bash
az keyvault secret list --vault-name kv-plat-shared-at01
```

## 4. Troubleshooting

| Symptom | Gate | Cause | Fix |
|---|---|---|---|
| 403 `ForbiddenByFirewall`, "Client address is not authorized" | network | source IP not in `ipRules` and not from `snet-mgmt` | update `TF_VAR_operator_ip_cidr` and apply this root (ARM call, works from any IP) |
| 403 `ForbiddenByRbac`, "Caller is not authorized to perform action" | identity | no role with the needed data action (e.g. keys with Secrets Officer) | grant the right role through code; never a portal hand-fix |
| `ForbiddenByRbac` right after a new role assignment | identity | assignment not yet propagated to the data plane | wait a few minutes and re-apply |
| `VaultAlreadyExists` / name conflict on create | — | name held by a soft-deleted vault | provider `recover_soft_deleted_key_vaults = true` recovers it; check `az keyvault list-deleted` |

## 5. Secrets in Terraform

Use `value_wo` fed by an `ephemeral = true` variable; never `value` (stores plaintext in state). To push a new value, change the input **and** bump `value_wo_version`. Terraform cannot detect a value changed by hand (refresh reads metadata only).

## 6. Deletion

Not routine, and blocked twice: `prevent_destroy` makes any destroying plan fail, and the `CanNotDelete` lock makes ARM refuse the delete. Removing them is a reviewed PR (drop `prevent_destroy`, apply to remove the lock) before any destroy. Once unblocked, `terraform destroy` soft-deletes the vault and secrets (provider purge flags are `false`); purge protection blocks any purge for 90 days, so the name cannot be reused in that window. Recover with `az keyvault recover --name kv-plat-shared-at01`.
