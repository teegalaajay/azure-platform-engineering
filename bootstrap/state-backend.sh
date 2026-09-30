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
