#!/usr/bin/env bash
# Converge the GitHub Actions identities for Azure (ADR-0013). Convergent: every run leaves the same state.
# Requires: az logged in to the target tenant; ARM_SUBSCRIPTION_ID exported (docs/runbooks/workstation-setup.md).
# Usage: bootstrap/github-oidc.sh
set -euo pipefail                       # -e stop on any failed command; -u unset variable = error; pipefail = a failure anywhere in a pipe fails the pipe

# ---- settings ----
PLAN_APP="app-gh-plan-shared"           # identity used by pull-request plans (read-only); name per ADR-0013
APPLY_APP="app-gh-apply-shared"         # identity used by apply on merge, reachable only through the protected environment

# ---- guard: never touch the wrong subscription ----
echo "== guard: CLI subscription =="
: "${ARM_SUBSCRIPTION_ID:?ARM_SUBSCRIPTION_ID is not set}"   # abort with a message if unset or empty
current=$(az account show --query id -o tsv)                 # the subscription the az CLI is pointed at right now
if [ "$current" != "$ARM_SUBSCRIPTION_ID" ]; then
  echo "az CLI is on $current, not ARM_SUBSCRIPTION_ID. Run: az account set -s \"\$ARM_SUBSCRIPTION_ID\"" >&2
  exit 1                                                     # stop before anything is created
fi
echo "ok"

# ---- app registration: find by name, create only if missing ----
ensure_app() {                          # $1 = display name; prints the application (client) ID on stdout
  local name="$1" ids n
  ids=$(az ad app list --filter "displayName eq '$name'" --query "[].appId" -o tsv)   # Graph read: client IDs of every app with this exact name
  n=$(printf '%s' "$ids" | grep -c . || true)                                         # count lines; grep exits 1 on zero matches, so || true
  if [ "$n" = "0" ]; then
    echo "creating app registration $name" >&2              # progress goes to stderr so stdout carries only the ID
    ids=$(az ad app create --display-name "$name" --sign-in-audience AzureADMyOrg --query appId -o tsv)   # single-tenant app
  elif [ "$n" = "1" ]; then
    echo "exists: $name" >&2
    az ad app update --id "$ids" --sign-in-audience AzureADMyOrg   # converge the one mutable setting we own, so portal drift is undone
  else
    echo "ERROR: $n app registrations are named $name (Entra does not enforce unique names). Resolve by hand." >&2
    exit 1                                                  # never guess which one is ours
  fi
  printf '%s\n' "$ids"                                      # hand the client ID back to the caller
}

ensure_sp() {                           # $1 = client ID; prints the service principal's object ID
  local sp
  sp=$(az ad sp show --id "$1" --query id -o tsv 2>/dev/null || true)   # empty if the app has no service principal yet
  if [ -z "$sp" ]; then
    echo "creating service principal for $1" >&2
    sp=$(az ad sp create --id "$1" --query id -o tsv)       # the service principal is what receives RBAC role assignments
  fi
  printf '%s\n' "$sp"
}

echo "== app registrations and service principals =="
plan_id=$(ensure_app "$PLAN_APP")       # an assignment from $(...) stops the script under set -e if the function exits non-zero
apply_id=$(ensure_app "$APPLY_APP")
plan_sp=$(ensure_sp "$plan_id")
apply_sp=$(ensure_sp "$apply_id")

# ---- evidence: what Entra actually holds ----
az ad app list --filter "startswith(displayName,'app-gh')" --query "[].[displayName, signInAudience]" -o tsv   # expect exactly two rows

# ---- federated credentials: who may become each identity (ADR-0013) ----
GH_REPO="teegalaajay/azure-platform-engineering"
ISSUER="https://token.actions.githubusercontent.com"   # GitHub's OIDC issuer: Entra fetches signing keys from here
AUDIENCE="api://AzureADTokenExchange"                  # the audience GitHub puts in the token for Azure
PLAN_CRED="github-pr-plan"
APPLY_CRED="github-env-production-apply"

ensure_fic() {                          # $1 = client ID, $2 = credential name, $3 = subject
  local app="$1" name="$2" subject="$3" body actual want
  body=$(jq -n --arg n "$name" --arg s "$subject" --arg i "$ISSUER" --arg a "$AUDIENCE" \
    '{name: $n, issuer: $i, subject: $s, audiences: [$a]}')   # the desired credential as JSON
  want="$subject|$ISSUER|$AUDIENCE"                            # one comparable string for subject + issuer + audience
  actual=$(az ad app federated-credential list --id "$app" -o json \
    | jq -r --arg n "$name" '.[] | select(.name == $n) | [.subject, .issuer, .audiences[0]] | join("|")')   # same string, from Entra; empty if missing
  if [ -z "$actual" ]; then
    az ad app federated-credential create --id "$app" --parameters "$body" --output none
    echo "created credential $name"
  elif [ "$actual" != "$want" ]; then
    az ad app federated-credential update --id "$app" --federated-credential-id "$name" \
      --parameters "$(jq 'del(.name)' <<<"$body")" --output none   # name is immutable, so it is left out of the update
    echo "updated credential $name (was: $actual)"
  else
    echo "unchanged credential $name"
  fi
}

prune_fic() {                           # $1 = client ID, $2 = the one credential name to keep; deletes every other credential
  local app="$1" keep="$2" n
  for n in $(az ad app federated-credential list --id "$app" --query "[].name" -o tsv); do
    if [ "$n" != "$keep" ]; then
      az ad app federated-credential delete --id "$app" --federated-credential-id "$n"
      echo "pruned credential $n"
    fi
  done
}

echo "== federated credentials =="
ensure_fic "$plan_id"  "$PLAN_CRED"  "repo:${GH_REPO}:pull_request"
ensure_fic "$apply_id" "$APPLY_CRED" "repo:${GH_REPO}:environment:production"
prune_fic  "$plan_id"  "$PLAN_CRED"
prune_fic  "$apply_id" "$APPLY_CRED"

az ad app federated-credential list --id "$plan_id"  --query "[].[name, subject]" -o tsv   # evidence: plan app
az ad app federated-credential list --id "$apply_id" --query "[].[name, subject]" -o tsv   # evidence: apply app

# ---- no client secrets or certificates: the only way in is the federated credential (ADR-0013) ----
prune_secrets() {                       # $1 = client ID, $2 = app name (for the message); removes every secret and certificate
  local app="$1" label="$2" k
  for k in $(az ad app credential list --id "$app" --query "[].keyId" -o tsv); do   # key IDs only, never secret values
    az ad app credential delete --id "$app" --key-id "$k"
    echo "removed secret/certificate $k from $label"
  done
}

echo "== secrets and certificates (expect none) =="
prune_secrets "$plan_id"  "$PLAN_APP"
prune_secrets "$apply_id" "$APPLY_APP"
az ad app credential list --id "$plan_id"  --query "length(@)" -o tsv   # evidence: secrets/certs on the plan app
az ad app credential list --id "$apply_id" --query "length(@)" -o tsv   # evidence: secrets/certs on the apply app

# ---- role assignments: what each identity can do (ADR-0013) ----
SUB_SCOPE="/subscriptions/${ARM_SUBSCRIPTION_ID}"
STATE_RG="rg-tfstate"
STATE_SA="stattfstate01"
STATE_CONTAINER="tfstate"               # names fixed by ADR-0005 / bootstrap/state-backend.sh
container_scope=$(az storage container-rm show --storage-account "$STATE_SA" --resource-group "$STATE_RG" \
  --name "$STATE_CONTAINER" --query id -o tsv)   # ARM's own spelling of the container ID, so scope comparisons match exactly

ensure_role() {                         # $1 = SP object ID, $2 = role name, $3 = scope, $4 = optional condition
  local sp="$1" role="$2" scope="$3" cond="${4:-}" id got ok=0
  local extra=()
  [ -n "$cond" ] && extra=(--condition "$cond" --condition-version 2.0)
  for id in $(az role assignment list --assignee "$sp" --all \
      --query "[?roleDefinitionName=='$role' && scope=='$scope'].id" -o tsv); do
    got=""
    [ -n "$cond" ] && [ -n "$cond" ] && got=$(az role assignment list --assignee "$sp" --all --query "[?id=='$id'].condition | [0]" -o tsv)
    if [ -z "$cond" ] || [ "$got" = "$cond" ]; then
      ok=1
    else
      az role assignment delete --ids "$id"
      echo "removed drifted $role at $scope"
    fi
  done
  if [ "$ok" = "0" ]; then
    az role assignment create --assignee-object-id "$sp" --assignee-principal-type ServicePrincipal \
      --role "$role" --scope "$scope" "${extra[@]}" --output none
    echo "granted $role at $scope"
  else
    echo "unchanged $role at $scope"
  fi
}
echo "== role assignments =="
ensure_role "$plan_sp" "Reader" "$SUB_SCOPE"                                  # control plane: read every resource for refresh
ensure_role "$plan_sp" "Storage Blob Data Reader" "$container_scope"          # data plane: read state blobs; no write, so no lease (ADR-0013, option 5)
ensure_role "$apply_sp" "Contributor" "$SUB_SCOPE"
ensure_role "$apply_sp" "Storage Blob Data Contributor" "$container_scope"
# built-in role definition ID; identical in every tenant, public in Microsoft docs
ROLE_ID_KV_OFFICER="b86a8fe4-44ce-4948-aee5-eccb2c155cd7"
RBAC_CONDITION="((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${ROLE_ID_KV_OFFICER}})) AND ((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${ROLE_ID_KV_OFFICER}}))"
ensure_role "$apply_sp" "Role Based Access Control Administrator" "$SUB_SCOPE" "$RBAC_CONDITION"
echo "-- plan identity --"
az role assignment list --assignee "$plan_sp" --all --query "[].[roleDefinitionName, scope]" -o tsv
echo "-- apply identity --"
az role assignment list --assignee "$apply_sp" --all --query "[].[roleDefinitionName, scope]" -o tsv
