#!/usr/bin/env bash
# Converge the federated credential on the agent's managed identity (ADR-0024), so an Azure DevOps service
# connection of type "Managed identity (manual)" can become that identity. Terraform owns the identity and its role.
# Requires: az logged in to the target tenant; ARM_SUBSCRIPTION_ID exported (docs/runbooks/workstation-setup.md);
#           ADO_KV_FIC_ISSUER and ADO_KV_FIC_SUBJECT copied from the draft service connection in the ADO portal.
# Usage: bootstrap/ado-agent-fic.sh
set -euo pipefail                       # -e stop on a failed command; -u unset variable = error; pipefail = a failure in a pipe fails the pipe

IDENTITY="id-ado-agent-shared"          # created by platform/agent-identity; this script never creates it
GROUP="rg-agent-identity-shared"        # the identity's resource group, same root
CRED="ado-sc-azure-keyvault-shared"     # credential name inside the identity; unique per identity and immutable
AUDIENCE="api://AzureADTokenExchange"   # the audience Entra expects on a federated token for Azure

echo "== guard: CLI subscription =="
: "${ARM_SUBSCRIPTION_ID:?ARM_SUBSCRIPTION_ID is not set}"   # abort with a message if unset or empty
current=$(az account show --query id -o tsv)                 # the subscription the CLI points at right now
if [ "$current" != "$ARM_SUBSCRIPTION_ID" ]; then
  echo "az CLI is on $current, not ARM_SUBSCRIPTION_ID. Run: az account set -s \"\$ARM_SUBSCRIPTION_ID\"" >&2
  exit 1                                                     # stop before anything is changed
fi
: "${ADO_KV_FIC_ISSUER:?ADO_KV_FIC_ISSUER is not set}"             # both come from the draft connection and are never stored in the repo
: "${ADO_KV_FIC_SUBJECT:?ADO_KV_FIC_SUBJECT is not set}"
echo "ok"

echo "== the identity exists =="
az identity show --name "$IDENTITY" --resource-group "$GROUP" --query name -o tsv   # fails with a clear error if platform/agent-identity is not applied

echo "== federated credential =="
want="$ADO_KV_FIC_SUBJECT|$ADO_KV_FIC_ISSUER|$AUDIENCE"              # one comparable string for subject + issuer + audience
actual=$(az identity federated-credential list --identity-name "$IDENTITY" --resource-group "$GROUP" -o json \
  | jq -r --arg n "$CRED" '.[] | select(.name == $n) | [.subject, .issuer, .audiences[0]] | join("|")')   # same string from Entra; empty if missing
if [ -z "$actual" ]; then
  az identity federated-credential create --identity-name "$IDENTITY" --resource-group "$GROUP" --name "$CRED" \
    --issuer "$ADO_KV_FIC_ISSUER" --subject "$ADO_KV_FIC_SUBJECT" --audiences "$AUDIENCE" --output none
  echo "created credential $CRED"
elif [ "$actual" != "$want" ]; then
  az identity federated-credential update --identity-name "$IDENTITY" --resource-group "$GROUP" --name "$CRED" \
    --issuer "$ADO_KV_FIC_ISSUER" --subject "$ADO_KV_FIC_SUBJECT" --audiences "$AUDIENCE" --output none
  echo "updated credential $CRED"
else
  echo "unchanged credential $CRED"
fi

for n in $(az identity federated-credential list --identity-name "$IDENTITY" --resource-group "$GROUP" --query "[].name" -o tsv); do
  if [ "$n" != "$CRED" ]; then                                  # exactly one credential may exist on this identity
    az identity federated-credential delete --identity-name "$IDENTITY" --resource-group "$GROUP" --name "$n" --yes
    echo "pruned credential $n"
  fi
done

echo "== evidence =="
echo "federated credentials: $(az identity federated-credential list --identity-name "$IDENTITY" --resource-group "$GROUP" --query 'length(@)' -o tsv)"   # expect 1
