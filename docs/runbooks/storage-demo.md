# Runbook: storage-demo accounts (firewall and data access)

**Purpose:** Deploy, verify and troubleshoot the `storage-demo` accounts and their network
firewall (ADR-0006, ADR-0009).
**Owner:** platform-team · **Last validated:** 2026-10-07 · **Persistent:** prod kept (lock +
`prevent_destroy`), dev ephemeral

Placeholders: `<SUBSCRIPTION_ID>`, `<YOUR_IP>`. Real values are never committed to this public repository.

## 1. Layout

| Root | State key | Account | Protection |
|---|---|---|---|
| `workloads/storage-demo/dev` | `workloads/storage-demo/dev.tfstate` | `stdemodevat01` (LRS) | none, ephemeral |
| `workloads/storage-demo/prod` | `workloads/storage-demo/prod.tfstate` | `stdemoprodat01` (GRS) | `CanNotDelete` lock, `prevent_destroy` |

Both roots read the foundation state (spoke `snet-app`, hub `snet-mgmt`), so the foundation roots
must be applied first. Firewall: default Deny, bypass AzureServices, allowed = spoke `snet-app`,
hub `snet-mgmt`, operator IP.

## 2. Deploy or converge (from `main` only)

Prerequisites: `az login --tenant <TENANT_ID>`, `ARM_SUBSCRIPTION_ID` and
`TF_VAR_operator_ip_cidr` (`<YOUR_IP>/32`) exported (workstation-setup runbook).

```bash
cd workloads/storage-demo/dev        # or prod
terraform init
terraform plan -out=tfplan           # review: only expected addresses, no destroy
terraform apply tfplan && rm tfplan  # saved plans contain variable values: never keep or commit them
terraform plan                       # expect: No changes
```

When your ISP changes your IP: update the `TF_VAR_operator_ip_cidr` line in `~/.bashrc`, open a new
shell, then plan and apply both spoke roots and both storage-demo roots (expect `~ update in-place`
on the account's `network_rules` only).

## 3. Verify

Control plane (works from any IP):

```bash
az storage account show -n stdemodevat01 -g rg-storage-demo-dev \
  --query "{publicAccess:publicNetworkAccess, acls:networkRuleSet}" -o json
# expect: publicAccess Enabled, defaultAction Deny, bypass AzureServices,
#         one ipRule (bare IP, no /32), two virtualNetworkRules in state Succeeded
```

Data plane, raw response (shows the real error code; the CLI hides it):

```bash
TOKEN=$(az account get-access-token --resource https://storage.azure.com --query accessToken -o tsv)
curl -s -i -H "Authorization: Bearer $TOKEN" -H "x-ms-version: 2023-11-03" \
  "https://stdemodevat01.blob.core.windows.net/<container>?restype=container&comp=list"
```

## 4. Troubleshoot a 403

| `x-ms-error-code` | Gate | Meaning | Fix |
|---|---|---|---|
| `AuthorizationFailure` | Network | Source IP or subnet not on the allow-list (or the rule is still propagating) | Check your current public IP against `ipRules`; for VNet clients check the subnet is listed and has the `Microsoft.Storage` service endpoint |
| `AuthorizationPermissionMismatch` | Identity | Network passed; the identity lacks the RBAC data action | Assign a Storage Blob Data role at the right scope (via Terraform), wait for propagation |
| `KeyBasedAuthenticationNotPermitted` | Identity | Shared key or SAS used; shared key is disabled | Use Entra auth (`--auth-mode login`) |
| HTTP 401 | Authentication | Token missing, expired or wrong audience | Get a token for `https://storage.azure.com` |

Owner on the subscription grants no data actions. List Containers is authorized by an action and
may succeed without a data role; listing or reading blobs never does.

## 5. Recover from a firewall lock-out

The firewall never applies to ARM. If a bad apply removed your IP, Terraform can still plan and
apply (proven 2026-10-07): fix `TF_VAR_operator_ip_cidr` and apply from `main`. Do not add rules by
hand; if you had to, remove them again by applying from `main` and record it.
