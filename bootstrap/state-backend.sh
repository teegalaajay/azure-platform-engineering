#!/usr/bin/env bash
# Converge the Terraform remote-state backend (ADR-0005). Idempotent: every run leaves the same state.
# Requires: az logged in to the target tenant; ARM_SUBSCRIPTION_ID exported (docs/runbooks/workstation-setup.md).
# Usage: bootstrap/state-backend.sh [storage-account-name]
set -euo pipefail                       # -e stop on any failed command; -u unset variable = error; pipefail = a failure anywhere in a pipe fails the pipe

# ---- settings ----
SA_NAME="${1:-stattfstate01}"
RG_NAME="rg-tfstate"
LOCATION="eastus2"
SKU="Standard_GZRS"
TAGS=(
  owner=platform-team
  environment=shared
  cost_center=cc-platform-001
  data_classification=confidential
  managed_by=bootstrap-script
  repo=azure-platform-engineering
)

# ---- guard: never touch the wrong subscription ----
echo "== guard: CLI subscription =="    # progress marker so the output shows which stage ran
: "${ARM_SUBSCRIPTION_ID:?ARM_SUBSCRIPTION_ID is not set}"   # ':' does nothing; the ${VAR:?msg} expansion aborts the script with msg if VAR is unset or empty
current=$(az account show --query id -o tsv)                 # control-plane read: the subscription the az CLI is pointed at right now
if [ "$current" != "$ARM_SUBSCRIPTION_ID" ]; then            # CLI context must equal the subscription Terraform will use
  echo "az CLI is on $current, not ARM_SUBSCRIPTION_ID. Run: az account set -s \"\$ARM_SUBSCRIPTION_ID\"" >&2   # >&2 sends the message to stderr
  exit 1                                                     # non-zero exit stops here, before anything is created
fi
echo "ok"                               # reached only when both checks passed

# ---- resource group ----
echo "== resource group: $RG_NAME =="    # progress marker
az group create \
  --name "$RG_NAME" \
  --location "$LOCATION" \
  --tags "${TAGS[@]}" \
  --output none                          # ARM PUT: creates if missing, else converges tags to exactly these; errors if the RG exists in another region
echo "converged"


# ---- storage account ----
echo "== storage account: $SA_NAME =="   # progress marker
hardening=(                               # settings that CAN change after creation; applied on create AND re-applied on every run
  --min-tls-version TLS1_2                # refuse TLS 1.0/1.1 clients
  --https-only true                       # refuse plain HTTP
  --allow-blob-public-access false        # no anonymous reads, ever
  --allow-shared-key-access false         # disable account keys: only Entra tokens + a data role can reach blobs (Part A)
  --public-network-access Enabled         # accepted risk until Week 2 Day 3: GitHub-hosted runners have unpredictable IPs
)
if az storage account show --name "$SA_NAME" --resource-group "$RG_NAME" --output none 2>/dev/null; then   # exit 0 = exists; non-zero = missing
  az storage account update \
    --name "$SA_NAME" --resource-group "$RG_NAME" \
    "${hardening[@]}" --tags "${TAGS[@]}" \
    --output none                         # exists: re-apply hardening + tags, which undoes any portal drift
  echo "exists: converged settings and tags"
else
  az storage account create \
    --name "$SA_NAME" --resource-group "$RG_NAME" \
    --location "$LOCATION" --sku "$SKU" --kind StorageV2 \
    "${hardening[@]}" --tags "${TAGS[@]}" \
    --output none                         # missing: create with the create-only properties (kind, sku) plus hardening
  echo "created"
fi

# ---- evidence: what Azure actually holds ----
az storage account show --name "$SA_NAME" --resource-group "$RG_NAME" \
  --query "[name, sku.name, allowSharedKeyAccess, minimumTlsVersion, allowBlobPublicAccess, enableHttpsTrafficOnly]" -o tsv



# ---- blob protection: recover from bad writes and deletes (GZRS only covers infrastructure loss) ----
RETENTION_DAYS=30                          # how long deleted blobs/containers stay recoverable; ADR-0005 decision
echo "== blob protection: versioning + soft delete ($RETENTION_DAYS days) =="   # progress marker
az storage account blob-service-properties update \
  --account-name "$SA_NAME" --resource-group "$RG_NAME" \
  --enable-versioning true \
  --enable-delete-retention true --delete-retention-days "$RETENTION_DAYS" \
  --enable-container-delete-retention true --container-delete-retention-days "$RETENTION_DAYS" \
  --output none                            # ARM PUT on blobServices/default: control plane, idempotent, no show/create branch needed
az storage account blob-service-properties show \
  --account-name "$SA_NAME" --resource-group "$RG_NAME" \
  --query "[isVersioningEnabled, deleteRetentionPolicy.enabled, deleteRetentionPolicy.days, containerDeleteRetentionPolicy.enabled, containerDeleteRetentionPolicy.days]" \
  -o tsv                                   # evidence from Azure: expect true, true, 30, true, 30



# ---- container: created through ARM (control plane) so it works before any data-role grant ----
CONTAINER_NAME="tfstate"                   # fixed by engineering_standards.md §3; every backend.tf points here
echo "== container: $CONTAINER_NAME =="    # progress marker
exists=$(az storage container-rm exists \
  --storage-account "$SA_NAME" --resource-group "$RG_NAME" --name "$CONTAINER_NAME" \
  --query exists -o tsv)                   # ARM read: prints true or false
if [ "$exists" = "true" ]; then            # string compare; anything but "true" (incl. an empty result) falls to create
  echo "exists"
else
  az storage container-rm create \
    --storage-account "$SA_NAME" --resource-group "$RG_NAME" --name "$CONTAINER_NAME" \
    --public-access off \
    --output none                          # ARM PUT on blobServices/default/containers/tfstate: checked against actions (Owner has *)
  echo "created"
fi
az storage container-rm show \
  --storage-account "$SA_NAME" --resource-group "$RG_NAME" --name "$CONTAINER_NAME" \
  --query "[name, publicAccess]" -o tsv    # evidence: the container name, and public access None




# ---- data-plane access for the operator running this script (CI identities are granted in Week 3) ----
ROLE="Storage Blob Data Contributor"       # exact role name: the data role with blob read/write/delete dataActions
echo "== data role: $ROLE for the signed-in user =="   # progress marker
sa_id=$(az storage account show --name "$SA_NAME" --resource-group "$RG_NAME" --query id -o tsv)   # full ARM resource ID of the account = the scope
me=$(az ad signed-in-user show --query id -o tsv)   # Entra object ID of the human running bootstrap
count=$(az role assignment list --assignee "$me" --role "$ROLE" --scope "$sa_id" --query "length(@)" -o tsv)   # 0 = not yet granted at this exact scope
if [ "$count" = "0" ]; then
  az role assignment create \
    --assignee-object-id "$me" --assignee-principal-type User \
    --role "$ROLE" --scope "$sa_id" \
    --output none                          # control-plane write: needs Microsoft.Authorization/roleAssignments/write, which Owner has
  echo "granted (RBAC can take a few minutes to reach the storage service)"
else
  echo "already granted"
fi
az role assignment list --assignee "$me" --scope "$sa_id" --query "[].roleDefinitionName" -o tsv   # evidence: roles held at exactly this scope
