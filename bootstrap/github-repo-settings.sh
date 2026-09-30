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

echo "== verify =="
gh api "repos/$REPO" --jq '{has_wiki, allow_squash_merge, allow_merge_commit, allow_rebase_merge, delete_branch_on_merge, squash_merge_commit_title, squash_merge_commit_message}'
gh api "repos/$REPO/rulesets/$(gh api "repos/$REPO/rulesets" --jq ".[] | select(.name == \"$RULESET_NAME\") | .id")" \
  --jq '{enforcement, bypass_actors, rules: [.rules[].type]}'
gh api "repos/$REPO/private-vulnerability-reporting"
gh api "repos/$REPO/actions/permissions/fork-pr-contributor-approval"
