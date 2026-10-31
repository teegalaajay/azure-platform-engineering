#!/usr/bin/env bash
# Converge the Azure DevOps identities for Azure (ADR-0022, ADR-0026): a plan and an apply app registration,
# their service principals, roles and federated credentials.
# Requires: az logged in to the target tenant; ARM_SUBSCRIPTION_ID exported (docs/runbooks/workstation-setup.md); jq.
# Usage: bootstrap/ado-oidc.sh
# A credential is converged only when both variables of its pair are set, copied from the service connection in the ADO portal:
#   ADO_PLAN_FIC_ISSUER and ADO_PLAN_FIC_SUBJECT      for sc-azure-plan-shared
#   ADO_APPLY_FIC_ISSUER and ADO_APPLY_FIC_SUBJECT    for sc-azure-apply-shared
# One pair per connection, so a value left in the shell for one connection can never be read for another.
set -euo pipefail                       # -e stop on a failed command; -u unset variable = error; pipefail = a failure in a pipe fails the pipe

ADO_PLAN_APP="app-ado-plan-shared"      # one identity per pipeline system and purpose (ADR-0022); never reuse the GitHub apps
ADO_APPLY_APP="app-ado-apply-shared"    # the identity that may write (ADR-0026)
ADO_PLAN_CRED="ado-sc-azure-plan-shared"     # credential name inside the plan app; unique per app and immutable
ADO_APPLY_CRED="ado-sc-azure-apply-shared"   # credential name inside the apply app
ADO_AUDIENCE="api://AzureADTokenExchange"    # the audience Entra expects on a federated token for Azure

echo "== guard: CLI subscription =="
: "${ARM_SUBSCRIPTION_ID:?ARM_SUBSCRIPTION_ID is not set}"   # abort with a message if unset or empty
current=$(az account show --query id -o tsv)                 # the subscription the CLI points at right now
if [ "$current" != "$ARM_SUBSCRIPTION_ID" ]; then
  echo "az CLI is on $current, not ARM_SUBSCRIPTION_ID. Run: az account set -s \"\$ARM_SUBSCRIPTION_ID\"" >&2
  exit 1                                                     # stop before anything is created
fi
for retired in ADO_FIC_ISSUER ADO_FIC_SUBJECT; do            # the old shared names: a value left in the shell once overwrote the wrong credential
  if [ -n "${!retired:-}" ]; then
    echo "ERROR: $retired is a retired name and is still set in this shell. Run: unset ADO_FIC_ISSUER ADO_FIC_SUBJECT" >&2
    exit 1
  fi
done
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

SUB_SCOPE="/subscriptions/${ARM_SUBSCRIPTION_ID}"
STATE_RG="rg-tfstate"                   # names fixed by ADR-0005 / bootstrap/state-backend.sh
STATE_SA="stattfstate01"
STATE_CONTAINER="tfstate"
container_scope=$(az storage container-rm show --storage-account "$STATE_SA" --resource-group "$STATE_RG" \
  --name "$STATE_CONTAINER" --query id -o tsv)   # ARM's own spelling of the container ID, so scope comparisons match exactly

echo "== plan identity: app registration, service principal, roles =="
plan_id=$(ensure_app "$ADO_PLAN_APP")  # an assignment from $(...) stops the script under set -e if the function exits non-zero
plan_sp=$(ensure_sp "$plan_id")
ensure_role "$plan_sp" "Reader" "$SUB_SCOPE"                                  # control plane: read every resource for refresh
ensure_role "$plan_sp" "Storage Blob Data Reader" "$container_scope"          # data plane: read state blobs; no write, so no lease (ADR-0013)

echo "== apply identity: app registration, service principal, roles =="
apply_id=$(ensure_app "$ADO_APPLY_APP")
apply_sp=$(ensure_sp "$apply_id")
ensure_role "$apply_sp" "Contributor" "$SUB_SCOPE"                            # control plane: may create the demo resource group (ADR-0026, B6)
ensure_role "$apply_sp" "Storage Blob Data Contributor" "$container_scope"    # data plane: write state and take the lease

# ---- federated credentials: the only thing that lets an ADO service connection become one of these identities ----
# Issuer and subject come from the service connection in the ADO portal. They are trust parameters, not secrets,
# but they identify our tenant and organization, so they are read from the environment and never stored in the repo.
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

converge_fic() {                        # $1 = client ID, $2 = credential name, $3 = variable prefix (ADO_PLAN or ADO_APPLY)
  local app="$1" cred="$2" prefix="$3" iss_var sub_var
  iss_var="${prefix}_FIC_ISSUER"        # the names of this connection's two variables, built from the prefix
  sub_var="${prefix}_FIC_SUBJECT"
  if [ -n "${!iss_var:-}${!sub_var:-}" ]; then      # ${!name} reads the variable whose name is in $name; at least one of the two is set
    : "${!iss_var:?$iss_var is not set}"            # then both are required, together
    : "${!sub_var:?$sub_var is not set}"
    ensure_fic "$app" "$cred" "${!sub_var}" "${!iss_var}"
    prune_fic  "$app" "$cred"                       # exactly one credential may exist on this identity
  else
    echo "skipped: $iss_var and $sub_var are not set"
  fi
}

echo "== federated credentials =="
converge_fic "$plan_id"  "$ADO_PLAN_CRED"  ADO_PLAN
converge_fic "$apply_id" "$ADO_APPLY_CRED" ADO_APPLY

echo "== evidence =="
az ad app list --filter "startswith(displayName,'app-ado')" --query "[].[displayName, appId]" -o tsv        # expect exactly two rows
echo "-- plan roles: Reader at the subscription and Storage Blob Data Reader on the tfstate container"
az role assignment list --assignee "$plan_sp" --all --query "[].[roleDefinitionName, scope]" -o tsv
echo "-- apply roles: Contributor at the subscription and Storage Blob Data Contributor on the tfstate container"
az role assignment list --assignee "$apply_sp" --all --query "[].[roleDefinitionName, scope]" -o tsv
echo "plan federated credentials: $(az ad app federated-credential list --id "$plan_id" --query 'length(@)' -o tsv)"     # expect 1
echo "apply federated credentials: $(az ad app federated-credential list --id "$apply_id" --query 'length(@)' -o tsv)"   # expect 0 until the apply connection exists
echo "secrets or certificates: plan $(az ad app credential list --id "$plan_id" --query 'length(@)' -o tsv), apply $(az ad app credential list --id "$apply_id" --query 'length(@)' -o tsv)"   # expect 0 and 0, always
