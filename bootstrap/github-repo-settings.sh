#!/usr/bin/env bash
# Converge GitHub repository settings to ADR-0003. Idempotent: every run leaves the same state.
# Requires: gh authenticated as a repository admin, jq.
# Usage: bootstrap/github-repo-settings.sh [owner/repo]
set -euo pipefail

REPO="${1:-teegalaajay/azure-platform-engineering}"
RULESET_NAME="protect-main"

echo "== repository settings =="
gh api -X PATCH "repos/$REPO" --silent \
  -F has_wiki=false \
  -F allow_squash_merge=true -F allow_merge_commit=false -F allow_rebase_merge=false \
  -F delete_branch_on_merge=true \
  -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY

echo "== ruleset: $RULESET_NAME =="
ruleset_json=$(cat <<'JSON'
{
  "name": "protect-main",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "required_linear_history" },
    { "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "required_reviewers": [],
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": true,
        "require_extra_approval_for_unattributed_changes": true,
        "allowed_merge_methods": ["squash"]
      }
    },
    { "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": true,
        "do_not_enforce_on_create": false,
        "required_status_checks": [
          { "context": "validate-gate", "integration_id": 15368 }
        ]
      }
    }
  ]
}
JSON
)
id=$(gh api "repos/$REPO/rulesets" --jq ".[] | select(.name == \"$RULESET_NAME\") | .id")
if [ -z "$id" ]; then
  gh api -X POST "repos/$REPO/rulesets" --input - --silent <<<"$ruleset_json"
  echo "created"
else
  gh api -X PUT "repos/$REPO/rulesets/$id" --input - --silent <<<"$ruleset_json"
  echo "updated id $id to the declared definition"
fi

echo "== private vulnerability reporting =="
gh api -X PUT "repos/$REPO/private-vulnerability-reporting" --silent
echo "enabled"

echo "== fork PR workflow approval =="
gh api -X PUT "repos/$REPO/actions/permissions/fork-pr-contributor-approval" --silent \
  -f approval_policy=all_external_contributors
echo "all_external_contributors"

ENV_NAME="production"

echo "== environment: $ENV_NAME =="
reviewer_id=$(gh api user --jq .id)
env_json=$(jq -n --argjson reviewer "$reviewer_id" '{
  wait_timer: 0,
  prevent_self_review: false,
  reviewers: [{type: "User", id: $reviewer}],
  deployment_branch_policy: {protected_branches: false, custom_branch_policies: true}
}')
gh api -X PUT "repos/$REPO/environments/$ENV_NAME" --input - --silent <<<"$env_json"
echo "declared"

echo "== environment deployment branches: $ENV_NAME =="
policies=$(gh api "repos/$REPO/environments/$ENV_NAME/deployment-branch-policies" \
  --jq '.branch_policies[] | "\(.id)\t\(.name)\t\(.type)"')
has_main=0
while IFS=$'\t' read -r pid pname ptype; do
  [ -z "$pid" ] && continue
  if [ "$pname" = "main" ] && [ "$ptype" = "branch" ]; then
    has_main=1
  else
    gh api -X DELETE "repos/$REPO/environments/$ENV_NAME/deployment-branch-policies/$pid" --silent
    echo "removed deployment branch policy $ptype:$pname"
  fi
done <<<"$policies"
if [ "$has_main" = 0 ]; then
  gh api -X POST "repos/$REPO/environments/$ENV_NAME/deployment-branch-policies" --silent -f name=main -f type=branch
  echo "added main"
else
  echo "unchanged main"
fi

echo "== repository secrets (identifiers stored as secrets so GitHub masks them in public logs) =="
az_app_id() {                           # $1 = display name; fails unless exactly one app registration matches
  local ids n
  ids=$(az ad app list --display-name "$1" --query "[].appId" -o tsv)
  n=$(printf '%s\n' "$ids" | grep -c . || true)
  [ "$n" = "1" ] || { echo "ERROR: $n app registrations named $1" >&2; return 1; }
  printf '%s' "$ids"
}
tenant_id=$(az account show --query tenantId -o tsv)
subscription_id=$(az account show --query id -o tsv)
plan_client_id=$(az_app_id app-gh-plan-shared)
apply_client_id=$(az_app_id app-gh-apply-shared)
: "${TF_VAR_operator_ip_cidr:?export TF_VAR_operator_ip_cidr first}"   # stop with a clear message instead of storing an empty secret
: "${TF_VAR_budget_contact_emails:?export TF_VAR_budget_contact_emails first}"   # the JSON list for platform/cost
: "${TF_VAR_operator_object_id:?export TF_VAR_operator_object_id first}"   # your Entra object ID for platform/security
: "${TF_VAR_ssh_public_key:?export TF_VAR_ssh_public_key first}"   # the key text for workloads/vm-demo/dev
DECLARED_SECRETS=""
set_secret() { gh secret set "$1" --repo "$REPO" --body "$2"; DECLARED_SECRETS+=" $1"; echo "set $1"; }
set_secret AZURE_TENANT_ID "$tenant_id"
set_secret AZURE_SUBSCRIPTION_ID "$subscription_id"
set_secret AZURE_CLIENT_ID_PLAN "$plan_client_id"
set_secret AZURE_CLIENT_ID_APPLY "$apply_client_id"
set_secret OPERATOR_IP_CIDR "$TF_VAR_operator_ip_cidr"   # declared, so the prune loop below keeps it
set_secret BUDGET_CONTACT_EMAILS "$TF_VAR_budget_contact_emails"   # same bytes Terraform reads on your laptop, so CI and laptop agree
set_secret OPERATOR_OBJECT_ID "$TF_VAR_operator_object_id"   # declared, so the prune loop keeps it
set_secret SSH_PUBLIC_KEY "$TF_VAR_ssh_public_key"   # declared, so the prune loop keeps it
for name in $(gh secret list --repo "$REPO" --json name --jq '.[].name'); do
  case "$DECLARED_SECRETS " in
    *" $name "*) ;;
    *) gh secret delete "$name" --repo "$REPO"; echo "removed undeclared secret $name" ;;
  esac
done
for name in $(gh variable list --repo "$REPO" --json name --jq '.[].name'); do
  gh variable delete "$name" --repo "$REPO"
  echo "removed variable $name (this repo declares none)"
done
# Requires: gh authenticated as a repository admin, az logged in to the target subscription, jq

echo "== verify =="
gh api "repos/$REPO" --jq '{has_wiki, allow_squash_merge, allow_merge_commit, allow_rebase_merge, delete_branch_on_merge, squash_merge_commit_title, squash_merge_commit_message}'
gh api "repos/$REPO/rulesets/$(gh api "repos/$REPO/rulesets" --jq ".[] | select(.name == \"$RULESET_NAME\") | .id")" \
  --jq '{enforcement, bypass_actors, rules: [.rules[].type]}'
gh api "repos/$REPO/private-vulnerability-reporting"
gh api "repos/$REPO/actions/permissions/fork-pr-contributor-approval"
gh api "repos/$REPO/environments/$ENV_NAME" --jq '{name, deployment_branch_policy, protection_rules}'
gh api "repos/$REPO/environments/$ENV_NAME/deployment-branch-policies" --jq '[.branch_policies[] | {name, type}]'
gh secret list --repo "$REPO"
