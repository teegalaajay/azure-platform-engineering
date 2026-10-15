# Runbook: GitHub OIDC identities, RBAC and the production environment

**Purpose:** Operate, change and troubleshoot the two Azure identities GitHub Actions uses, and the GitHub settings that gate them (ADR-0013).
**Owner:** platform-team · **Last validated:** 2026-10-15 (plan identity token exchange, read, write denial, state-lease denial and the environment refusal on PR #16; the apply identity is validated after the first merge) · **Persistent:** yes (two app registrations, two federated credentials, role assignments, one GitHub environment, four repository secrets; no billable resources)

## 1. Layout

| Piece | Where | What it does |
|---|---|---|
| Plan identity | app registration and service principal `app-gh-plan-shared` | used by pull request jobs. Reader (subscription) and Storage Blob Data Reader (`tfstate` container) |
| Apply identity | `app-gh-apply-shared` | used only by jobs in the `production` environment. Contributor, Storage Blob Data Contributor (`tfstate` container), a conditional Role Based Access Control Administrator (Key Vault Secrets Officer only), and the custom role `Platform Lock Writer` |
| Federated credentials | `github-pr-plan`, `github-env-production-apply` | match issuer, audience `api://AzureADTokenExchange` and the ID-based subject `repo:<owner>@<ownerId>/<repo>@<repoId>:pull_request` or `...:environment:production` |
| Identity script | `bootstrap/github-oidc.sh` | creates or converges the identities, credentials and role assignments; removes anything undeclared |
| GitHub settings script | `bootstrap/github-repo-settings.sh` | converges the `production` environment (reviewer, `main`-only branch policy) and the four repository secrets `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_CLIENT_ID_PLAN`, `AZURE_CLIENT_ID_APPLY` |
| Smoke test | `.github/workflows/oidc-smoke.yml` | exchanges a token as the plan identity, reads, and proves a write and a state lease are denied |

The owner and repository IDs are pinned in `bootstrap/github-oidc.sh` and compared with `gh api` before anything changes. If the repository is deleted and re-created, the script stops; it does not adopt the new repository.

## 2. Apply or converge (from `main` only)

Prerequisites: `az` logged in with rights to create app registrations and assign roles at subscription scope; `gh` authenticated as a repository admin; `jq`; `ARM_SUBSCRIPTION_ID` set. Run the identity script first, because the settings script reads the client IDs from the app registrations. Both scripts are safe to repeat.

```bash
cd ~/azure-platform-engineering
git switch main && git pull --ff-only
export ARM_SUBSCRIPTION_ID=<subscription id>
bootstrap/github-oidc.sh
bootstrap/github-repo-settings.sh
```

Do not edit these objects in the portal. A portal change is drift: the next run removes undeclared role assignments, credentials and secrets. Drift is repaired by the next run, not prevented; see section 6.

## 3. Verify

Federated credentials and role assignments, read back from Azure:

```bash
for app in app-gh-plan-shared app-gh-apply-shared; do
  id=$(az ad app list --display-name "$app" --query "[0].appId" -o tsv)
  echo "== $app"; az ad app federated-credential list --id "$id" --query "[].{name:name, subject:subject}" -o table
  az role assignment list --assignee "$(az ad sp show --id "$id" --query id -o tsv)" --all --query "[].{role:roleDefinitionName, scope:scope}" -o table
done
```

Expected: one credential per identity, with the ID-based subject; plan has two role assignments, apply has four.

The environment and secrets:

```bash
gh api repos/teegalaajay/azure-platform-engineering/environments/production --jq '{branch_policy: .deployment_branch_policy, reviewers: [.protection_rules[].type]}'
gh api repos/teegalaajay/azure-platform-engineering/environments/production/deployment-branch-policies --jq '.branch_policies[].name'
gh secret list --repo teegalaajay/azure-platform-engineering
```

Expected: `custom_branch_policies` true; `reviewers` lists `required_reviewers` and `branch_policy` (the branch policy itself appears as a protection rule); exactly `main` in the branch policies; four secrets and no variables.

End-to-end proof (plan identity): change `.github/workflows/oidc-smoke.yml` in a pull request. Expected log: the claims with the ID-based `sub`; the subscription name in the read; `AuthorizationFailed` for the write; `<Code>AuthorizationPermissionMismatch</Code>` for the state lease; and `***` wherever an ID would appear.

## 4. Change

| Change | How | Notes |
|---|---|---|
| Add a role for an identity | add an `ensure_role` call in `bootstrap/github-oidc.sh`, PR with an ADR update | anything not declared is removed on the next run |
| Allow the apply identity to assign another role | extend the condition (add its GUID) and update ADR-0013 | the condition limits the role, not the principal or scope; every addition widens the residual risk recorded in the ADR |
| Rename a federated credential or change its subject | edit the constants, run the script | the script compares `subject|issuer|audience`, updates in place, and fails if two credentials share a name |
| Rotate nothing | there is no secret to rotate on the identities | the script removes any client secret or certificate it finds |
| Move the repository or change its owner | re-derive the two IDs with `gh api repos/<owner>/<repo> --jq '"\(.owner.id) \(.id)"'`, update the constants, PR | until updated, the guard stops the script |
| Add a second environment | extend `bootstrap/github-repo-settings.sh` and add a credential | a new subject needs a new credential and its own role review |

## 5. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Job refused in seconds: `Branch "refs/pull/N/merge" is not allowed to deploy to production` | observed. A pull request job declared `environment: production`; the branch policy allows only `main` | expected behaviour for pull requests; apply runs only after merge |
| `AuthorizationFailed` on a write from the plan identity | observed. The plan identity is read-only | expected; plan does not write |
| `terraform plan` fails at `Acquiring state lock` with the plan identity | observed at the storage layer: lease acquire returns `AuthorizationPermissionMismatch`. The lock is a blob lease, a write | run plan with `-lock=false`; do not grant Data Contributor to the plan identity |
| `az storage` prints only "You do not have the required permissions" | observed. The CLI replaces the service error; the real code is in the response body | rerun with `--debug` and read `<Code>` |
| Login fails with `AADSTS70021: No matching federated identity record` | expected behaviour, **not reproduced**: the token's `iss`, `aud` or `sub` differs from the credential | print the decoded claims (as the smoke workflow does) and compare `sub` with the credential |
| Script stops with `GitHub IDs for ... are ..., expected ...` | the repository was re-created or transferred | confirm it is intended, then update the pinned IDs |
| `az role assignment show` is not recognised | observed. The command does not exist | use `az role assignment list --query "[?id=='...']"` |
| `az role assignment list --role <name> --all` crashes | observed | list all and filter with `--query` |
| Gitleaks blocks a commit on a variable named `...SECRETS...` | observed false positive on the `generic-api-key` rule | rename the variable; `git add` the fix before committing, because the hook scans the index |
| `terraform destroy` fails on a locked resource | expected behaviour, **not reproduced**: the apply identity cannot delete locks | remove the lock as a human, then destroy; this is a recorded cost in ADR-0013 |
| Fork pull request has no token or secrets | expected behaviour, **not reproduced** (tested in Week 3 Day 5) | none; this is the intended outcome |

## 6. Drift and detection

The scripts repair drift on their next run; they do not detect it. Between runs, an extra role assignment, credential or secret stays in place. The detection controls are outside the scripts and are not yet in place (listed as deferred in ADR-0013): Entra audit-log alerts on changes to these two app registrations and their role assignments, and restricted ownership of the app registrations.

## 7. Teardown

Removing the apply identity or its credential stops all deployments from CI; removing the plan identity stops plan on pull requests. Do it only with a replacement ready. Order: disable the workflows that use them, then delete the role assignments, credentials and app registrations (`az ad app delete`), then the environment and secrets. Management locks are not removed by this; they belong to the resources they protect.
