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
