#!/usr/bin/env bash
# Converge the Azure DevOps identity for Azure (ADR-0022), phase 1: app, service principal, Reader role. No credential yet.
# Requires: az logged in to the target tenant; ARM_SUBSCRIPTION_ID exported (docs/runbooks/workstation-setup.md).
# Usage: bootstrap/ado-oidc.sh
set -euo pipefail                       # -e stop on a failed command; -u unset variable = error; pipefail = a failure in a pipe fails the pipe

ADO_PLAN_APP="app-ado-plan-shared"      # one identity per pipeline system and purpose (ADR-0022); never reuse the GitHub apps

echo "== guard: CLI subscription =="
: "${ARM_SUBSCRIPTION_ID:?ARM_SUBSCRIPTION_ID is not set}"   # abort with a message if unset or empty
current=$(az account show --query id -o tsv)                 # the subscription the CLI points at right now
if [ "$current" != "$ARM_SUBSCRIPTION_ID" ]; then
  echo "az CLI is on $current, not ARM_SUBSCRIPTION_ID. Run: az account set -s \"\$ARM_SUBSCRIPTION_ID\"" >&2
  exit 1                                                     # stop before anything is created
fi
echo "ok"

ensure_app() {                          # $1 = display name; prints the application (client) ID on stdout
  local name="$1" ids n
  ids=$(az ad app list --filter "displayName eq '$name'" --query "[].appId" -o tsv)   # client IDs of every app with this exact name
  n=$(printf '%s' "$ids" | grep -c . || true)                                         # count lines; grep exits 1 on zero matches
  if [ "$n" = "0" ]; then
    echo "creating app registration $name" >&2              # progress goes to stderr so stdout carries only the ID
    ids=$(az ad app create --display-name "$name" --sign-in-audience AzureADMyOrg --query appId -o tsv)   # single-tenant app
  elif [ "$n" = "1" ]; then
    echo "exists: $name" >&2
    az ad app update --id "$ids" --sign-in-audience AzureADMyOrg   # converge the one setting we own
  else
    echo "ERROR: $n app registrations are named $name. Resolve by hand." >&2
    exit 1                                                  # never guess which one is ours
  fi
  printf '%s\n' "$ids"                                      # hand the client ID back to the caller
}

ensure_sp() {                           # $1 = client ID; prints the service principal's object ID
  local sp
  sp=$(az ad sp show --id "$1" --query id -o tsv 2>/dev/null || true)   # empty if the app has no service principal yet
  if [ -z "$sp" ]; then
    echo "creating service principal for $1" >&2
    sp=$(az ad sp create --id "$1" --query id -o tsv)       # the service principal is what receives role assignments
  fi
  printf '%s\n' "$sp"
}

ensure_role() {                         # $1 = service principal object ID, $2 = role name, $3 = scope
  local n
  n=$(az role assignment list --assignee "$1" --all --query "[?roleDefinitionName=='$2' && scope=='$3'] | length(@)" -o tsv)   # 0 or 1
  if [ "$n" = "0" ]; then
    az role assignment create --assignee-object-id "$1" --assignee-principal-type ServicePrincipal \
      --role "$2" --scope "$3" --output none               # object ID plus type avoids a Graph lookup race right after creation
    echo "granted $2 at $3"
  else
    echo "unchanged $2 at $3"
  fi
}

echo "== app registration, service principal, role =="
ado_id=$(ensure_app "$ADO_PLAN_APP")   # an assignment from $(...) stops the script under set -e if the function exits non-zero
ado_sp=$(ensure_sp "$ado_id")
ensure_role "$ado_sp" "Reader" "/subscriptions/${ARM_SUBSCRIPTION_ID}"   # today's only job is to prove auth and read; writes come later, with a reason

# ---- federated credential: the only thing that lets the ADO service connection become this identity (ADR-0022) ----
# Issuer and subject come from the draft service connection in the ADO portal. They are trust parameters, not secrets,
# but they identify our tenant and organization, so they are read from the environment and never stored in the repo.
ADO_AUDIENCE="api://AzureADTokenExchange"   # the audience Entra expects on a federated token for Azure
ADO_CRED="ado-sc-azure-plan-shared"         # credential name inside the app; unique per app and immutable

ensure_fic() {                          # $1 = client ID, $2 = credential name, $3 = subject, $4 = issuer
  local app="$1" name="$2" subject="$3" issuer="$4" body actual want
  body=$(jq -n --arg n "$name" --arg s "$subject" --arg i "$issuer" --arg a "$ADO_AUDIENCE" \
    '{name: $n, issuer: $i, subject: $s, audiences: [$a]}')   # the desired credential as JSON
  want="$subject|$issuer|$ADO_AUDIENCE"                        # one comparable string for subject + issuer + audience
  actual=$(az ad app federated-credential list --id "$app" -o json \
    | jq -r --arg n "$name" '.[] | select(.name == $n) | [.subject, .issuer, .audiences[0]] | join("|")')   # same string from Entra; empty if missing
  if [ -z "$actual" ]; then
    az ad app federated-credential create --id "$app" --parameters "$body" --output none
    echo "created credential $name"
  elif [ "$actual" != "$want" ]; then
    az ad app federated-credential update --id "$app" --federated-credential-id "$name" \
      --parameters "$(jq 'del(.name)' <<<"$body")" --output none   # name is immutable, so it is left out of the update
    echo "updated credential $name"
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

echo "== federated credential =="
if [ -n "${ADO_FIC_ISSUER:-}${ADO_FIC_SUBJECT:-}" ]; then      # at least one of the two is set
  : "${ADO_FIC_ISSUER:?ADO_FIC_ISSUER is not set}"             # then both are required, together
  : "${ADO_FIC_SUBJECT:?ADO_FIC_SUBJECT is not set}"
  ensure_fic "$ado_id" "$ADO_CRED" "$ADO_FIC_SUBJECT" "$ADO_FIC_ISSUER"
  prune_fic  "$ado_id" "$ADO_CRED"                             # exactly one credential may exist on this identity
else
  echo "skipped: ADO_FIC_ISSUER and ADO_FIC_SUBJECT are not set"
fi

echo "== evidence =="
az ad app list --filter "startswith(displayName,'app-ado')" --query "[].[displayName, appId]" -o tsv            # expect exactly one row
az role assignment list --assignee "$ado_sp" --all --query "[].[roleDefinitionName, scope]" -o tsv            # expect exactly Reader at the subscription
echo "federated credentials: $(az ad app federated-credential list --id "$ado_id" --query 'length(@)' -o tsv)"   # expect 0 until B4 gives us issuer and subject
echo "secrets or certificates: $(az ad app credential list --id "$ado_id" --query 'length(@)' -o tsv)"           # expect 0, always
