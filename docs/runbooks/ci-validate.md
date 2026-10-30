# Runbook: validate workflow and the required check (`.github/workflows/validate.yml`)

**Purpose:** Operate, change and troubleshoot the CI check that protects `main` (ADR-0012).
**Owner:** platform-team · **Last validated:** 2026-10-13 (workflow behaviour); the ruleset read-back in section 3 is validated when the rule is applied · **Persistent:** yes (a required check on `main`; no Azure resources, no cost)

## 1. Layout

| Piece | Where | What it does |
|---|---|---|
| Workflow | `.github/workflows/validate.yml` | `discover` finds every directory containing `versions.tf`; `validate` runs `fmt -check`, `init -backend=false`, `validate` and `tflint` in each; `validate-gate` requires both to be `success` |
| Required check | `bootstrap/github-repo-settings.sh` (ruleset `protect-main`) | requires the context `validate-gate` from the GitHub Actions app, with the "branch up to date" policy |
| Lint config | `.yamllint`, `.tflint.hcl` | one config each, read by the pre-commit hooks and by CI |
| Pins | `validate.yml`, `.terraform.lock.hcl`, `.tflint.hcl` | Terraform 1.16.4, tflint v0.64.0, azurerm ruleset 0.32.0, provider 4.81.0, two third-party actions pinned by SHA |

No Azure identity is involved. The workflow holds `contents: read` and nothing else. It never runs `plan`, so a green check means the code is well-formed, not that it matches what is deployed.

## 2. Apply or converge the required check (from `main` only)

Prerequisites: `gh` authenticated as a repository admin, `jq` installed. The script replaces the whole ruleset with the declared definition, so running it twice gives the same result.

```bash
cd ~/azure-platform-engineering
git switch main && git pull --ff-only
bootstrap/github-repo-settings.sh
```

Do not edit the ruleset in the portal. A portal change is a hand-fix: the next script run overwrites it.

## 3. Verify

Read the rule back from GitHub (the script's own verify section prints only the rule types):

```bash
gh api repos/teegalaajay/azure-platform-engineering/rulesets/$(gh api repos/teegalaajay/azure-platform-engineering/rulesets --jq '.[] | select(.name == "protect-main") | .id') --jq '.rules[] | select(.type == "required_status_checks") | .parameters'
```

Expected: strict policy `true` and one required check with context `validate-gate` and integration ID 15368.

Reproduce the workflow's checks on a clean clone, without Azure access:

```bash
git clone https://github.com/teegalaajay/azure-platform-engineering.git ~/hermetic-check
cd ~/hermetic-check
for d in $(find . -name versions.tf -not -path '*/.terraform/*' -printf '%h\n' | sort); do echo "== $d"; (cd "$d" && terraform init -backend=false -input=false -no-color > /dev/null && terraform validate -no-color && tflint --config="$HOME/hermetic-check/.tflint.hcl") || echo "FAILED: $d"; done
```

Expected: no `FAILED:` line. (Run `terraform fmt -check -recursive` separately; it needs no `init`.)

## 4. Change

| Change | How | Notes |
|---|---|---|
| Add a Terraform root or module | add the directory with a `versions.tf` | no workflow edit needed; **raise `MIN_DIRS` in the same PR**, or a later accidental drop goes unnoticed |
| Remove a root or module | remove the directory | lower `MIN_DIRS` in the same PR |
| Bump Terraform or tflint | change `terraform_version` or `tflint_version`, run the loop above with that version, PR | CI validates one version only; the roots allow `>= 1.9.0, < 2.0.0` |
| Bump a pinned action | find the new tag, resolve it to a commit, replace the SHA and the tag comment | see below |
| Change the required check name | change the job `name:` and the ruleset in the same PR, then re-run the script | a mismatch leaves the pull request waiting for a status that never arrives |
| Line-length limit | `.yamllint` | the hook and CI read the same file |

Resolving a tag to a commit SHA (`<OWNER/REPO>` and `<TAG>` are placeholders):

```bash
gh api repos/<OWNER/REPO>/commits/<TAG> --jq .sha
gh api repos/<OWNER/REPO>/contents/action.yml --jq .content | base64 -d | grep -A2 '^runs:'
```

The second command confirms the action's runtime (`node24` at the time of ADR-0012).

## 5. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `validate (<dir>)` red at the `terraform fmt` step | formatting differs; later steps in that job are skipped | `terraform fmt -diff` in that directory, commit the result |
| `validate (<dir>)` red at the `terraform validate` step | a real configuration error; a module error appears in the module **and** in every root that calls it | fix the module first; the roots clear together |
| `validate-gate` red, `discover` red, message `expected at least N Terraform directories, found M` | the floor tripped: the pattern broke or directories were removed | fix the pattern, or lower `MIN_DIRS` if directories were removed on purpose |
| `validate-gate` red, `discover` green, no `validate (...)` checks at all | the list was empty (observed 2026-10-13 with the floor off): `validate` fails at start-up | check the `discover` log line `found N Terraform directories` |
| Gate log shows `discover=failure validate=skipped` | `validate` needs `discover`, so it is skipped when discovery fails | fix `discover` first |
| Pull request says it is out of date with `main` | the strict policy | update the branch from `main` and let the checks run again |
| tflint plugin step fails with an HTTP 403 or rate-limit message | anonymous GitHub download limits (expected behaviour, **not reproduced**) | the step already sets `GITHUB_TOKEN`; confirm it is still present |
| Pull request waits on a required status that never appears | the required context no longer matches a job name (expected behaviour, **not reproduced**) | align the job name and the ruleset |

## 6. Teardown

Do not remove the required check without replacing it: without it, `main` is protected only by the local hooks, which can be skipped. To disable the workflow temporarily, remove the rule in `bootstrap/github-repo-settings.sh`, run the script, and say why in the pull request.

## 7. Repository consistency checks (ADR-0025)

Two scripts in `scripts/` guard values that are written in more than one place. Both run as pre-commit hooks (only when a file they read changes) and as the first step of the `discover` job in `validate.yml`, so a mismatch turns the required check `validate-gate` red.

- `scripts/check-terraform-version.sh` compares `.terraform-version` with the six places that name the version: `apply.yml` (assertion), `plan.yml`, `validate.yml`, `pipelines/ado-terraform-validate.yml` (variable and the hash comment), `platform/runner/runner.auto.tfvars` and `platform/ado-agent/ado-agent.auto.tfvars`. It fails on a different value and on a place it cannot find (a changed line format reads as `found 0`, not as a pass). It does not verify the SHA-256 beside the ADO pipeline's version.
- `scripts/check-cloud-init-drift.sh` compares the block from `ARCH=$(dpkg ...)` to `apt-mark hold terraform` in `modules/runner-vm/cloud-init.yaml.tftpl` and `modules/ado-agent-vm/cloud-init.yaml.tftpl`. It fails when the two differ or a marker is missing.

To change the Terraform version: edit `.terraform-version`, change the six places, replace the SHA-256 on `pipelines/ado-terraform-validate.yml` with the hash of the new zip from the `SHA256SUMS` file HashiCorp signs, run `bash scripts/check-terraform-version.sh`, and plan every root. A changed `terraform_version` in the two `*.auto.tfvars` changes the rendered boot script, which forces a VM replacement (observed for the agent on 2026-10-29), so a version bump is a rebuild of any live runner or agent.
