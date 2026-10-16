# Runbook: plan on pull request (`.github/workflows/plan.yml`)

**Purpose:** Operate, change and troubleshoot the CI plan that shows reviewers what a change does to real infrastructure (ADR-0014).
**Owner:** platform-team · **Last validated:** 2026-10-15 (workflow behaviour, in-place comment update, failing-root and missing-permission paths; fork pull requests not yet tested end to end) · **Persistent:** yes (a workflow plus eight repository secrets; it only reads Azure and creates no resources)

## 1. Layout

| Piece | Where | What it does |
|---|---|---|
| Workflow | `.github/workflows/plan.yml` | Runs on `pull_request` for changes under `modules/`, `platform/`, `workloads/` and the workflow itself |
| `discover` job | same file | Finds every directory with a `backend.tf`; fails if fewer than 8 (`MIN_DIRS`) |
| `plan` jobs | same file | One matrix leg per root; signs in as the plan identity (ADR-0013) through Terraform's own OIDC support; runs `plan -lock=false -detailed-exitcode` |
| `comment` job | same file | Builds one comment from all legs, refuses to post if a GUID-shaped string is present, then creates or updates the comment marked `<!-- plan-comment -->` |
| Repository secrets | `bootstrap/github-repo-settings.sh` | Eight secrets: the tenant, subscription and two client IDs, plus the operator's IP range, budget emails, object ID and SSH public key |

Exit codes: 0 is "no changes", 2 is "changes" (both green), 1 is an error (red).

## 2. Converge the repository secrets (from `main` only)

The secrets are copies of values in the operator's shell, so they drift silently. Export all four `TF_VAR_*` inputs first; the script refuses to run without them.

```bash
export TF_VAR_operator_ip_cidr=...
export TF_VAR_budget_contact_emails='["..."]'
export TF_VAR_operator_object_id=...
export TF_VAR_ssh_public_key=...
bash bootstrap/github-repo-settings.sh
```

Expected: eight `set` lines and no `removed` line. A `removed` line means a secret exists that the script does not declare, and it was deleted.

## 3. Verify

Open a pull request that touches a watched path, then check:

```bash
gh pr checks <PR>
gh api repos/{owner}/{repo}/issues/<PR>/comments \
  --jq '[.[] | select(.user.login == "github-actions[bot]")] | length'
gh api repos/{owner}/{repo}/issues/<PR>/comments \
  --jq '.[] | .body | test("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")'
```

Expected: all checks green, exactly one comment, and `false` from the last command. After a second push, the comment ID stays the same and `updated_at` moves forward.

## 4. Change

- Adding or removing a root on purpose: change `MIN_DIRS` in the `discover` job in the same pull request.
- Adding a plan input: add the guard and `set_secret` line to the bootstrap script and the variable to the plan step's `env`, then converge the secrets (section 2).
- Never switch the trigger to `pull_request_target` (ADR-0014).
- The apply workflow must not copy `cancel-in-progress: true` from here.

## 5. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Every leg fails at `terraform init` with `Please run 'az login'` | The plan job has no `id-token: write`, so there is no OIDC token and Terraform falls back to the Azure CLI | Restore `id-token: write` on the plan job. Do not add an `az login` step |
| A row reads `NO RESULT (leg failed before the plan)` | The leg failed before it wrote its output, usually at `init` or sign-in | Open that leg's log and read the failing step |
| A row reads `ERROR`, exit code 1 | The root could not be planned | Read the error in that root's details block in the comment |
| `discover` fails with fewer than 8 roots | A `backend.tf` was renamed, moved or removed | Restore it, or lower `MIN_DIRS` if the root was removed on purpose |
| The CI plan shows changes to an input that the local plan does not | A repository secret has drifted from the operator's value | Section 2, then rerun the plan |
| The `comment` job fails before posting | A GUID-shaped string survived masking | Do not bypass the gate. Find the source in the plan output; if a comment was already posted, delete it |
| A pull request from a fork shows red checks | Forks get no secrets and no OIDC token, so the plan fails closed | Expected. Not yet exercised end to end |

## 6. Teardown

Remove `.github/workflows/plan.yml` in a pull request. Remove the matching `set_secret` lines from the bootstrap script in the same pull request; running the script from `main` then deletes the secrets. Nothing is stored in state and no Azure resource exists. The plan identity itself belongs to ADR-0013.
