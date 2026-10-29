# Runbook: Azure DevOps Terraform validate pipeline

**Purpose:** Create, verify, bump and troubleshoot the `ado-terraform-validate` pipeline (ADR-0023): fmt, init without a backend and validate on every Terraform directory, from a pinned image and a verified Terraform download.
**Owner:** platform-team · **Last validated:** 2026-10-29 (green run, checksum failure and formatting failure, runs `#20261029.1` to `#20261029.3`; run `#20261029.4` started by pull request 30; run `#20261029.6` started by the merge to `main`) · **Persistent:** yes (the pipeline definition stays; it runs on matching changes and on demand and holds no credential)

## 1. Layout

| Piece | Where | What it does |
|---|---|---|
| Pipeline definition | Azure DevOps project `azure-platform-engineering`, name `ado-terraform-validate` | one definition for `pipelines/ado-terraform-validate.yml`; the YAML stays in GitHub |
| Image | `vmImage: ubuntu-24.04` in the YAML | Microsoft-hosted agent; the pin fixes the OS release, not the preinstalled tools |
| Terraform | variables `terraformVersion` and `terraformSha256` in the YAML | the only place this pipeline names a version; downloaded into `$(Agent.TempDirectory)/terraform` and compared with the hash |
| Scope | the last step of the YAML | `fmt -check`, `init -backend=false`, `validate` in every directory that holds a `versions.tf`, floor 13 |
| Triggers | `trigger` on `main`, `pr` to `main`, same path filter | `modules/**`, `platform/**`, `workloads/**`, `.tflint.hcl`, the pipeline file, `pipelines/templates/**` |
| Identity | none | no service connection and no Azure sign-in; the GitHub App reads the YAML and the repository |
| Status | informational | the required gate stays `validate-gate` on GitHub |

## 2. Create or rebuild the pipeline

1. Do not accept the OAuth consent screen (admin on webhooks, all repositories). Install the Azure Pipelines GitHub App for the one repository, finish ADO's setup page and approve GitHub's "by Microsoft" authorization. The wizard then reaches the repository step without OAuth (observed, also after the connection from ADR-0022 existed).
2. Pipelines, New pipeline, GitHub (YAML), the repository, Existing Azure Pipelines YAML file, the branch and `/pipelines/ado-terraform-validate.yml`. Choose Save, not Run.
3. Rename it to exactly `ado-terraform-validate` (Rename/move). Two definitions for one file break the one-definition rule.
4. Check the pipeline's default branch (Edit, the `...` menu, Triggers, YAML tab, Get sources, "Default branch for manual and scheduled builds"). It read `refs/heads/main` after the merge (observed 2026-10-29); whether it was `main` from creation or changed by itself was not observed.
5. Check Pipelines, Edit, Triggers: pull request validation enabled, "Override the YAML pull request trigger from here" off, "Build pull requests from forks" off (observed 2026-10-29).

## 3. Bump Terraform (one pull request)

Do all of this on your workstation, then change every file that names the version in the same pull request: this pipeline, `.github/workflows/validate.yml`, `.github/workflows/plan.yml`, the version check in `.github/workflows/apply.yml` and the runner module's `terraform_version`.

```bash
cd "$(mktemp -d)"
V=1.17.0
curl -fsSLO "https://releases.hashicorp.com/terraform/${V}/terraform_${V}_SHA256SUMS"
curl -fsSLO "https://releases.hashicorp.com/terraform/${V}/terraform_${V}_SHA256SUMS.sig"
curl -fsSLO https://www.hashicorp.com/.well-known/pgp-key.txt
gpg --show-keys --fingerprint pgp-key.txt
mkdir -m 700 gnupg-tmp
gpg --homedir gnupg-tmp --import pgp-key.txt
gpg --homedir gnupg-tmp --verify "terraform_${V}_SHA256SUMS.sig" "terraform_${V}_SHA256SUMS"
grep linux_amd64 "terraform_${V}_SHA256SUMS"
```

Required results: the primary key fingerprint printed by `--show-keys` and by `--verify` is `C874 011F 0AB4 0511 0D02 1055 3436 5D94 72D7 468F`, the one HashiCorp publishes (check it on their security page, not only here); `--verify` says Good signature; the `grep` prints one line. Copy the 64-character hash into `terraformSha256`. The `[unknown]` trust label and its warning are expected, because the comparison of fingerprints is the trust step. If a release is signed by a key that is not a subkey of that primary key, stop.

Then run the pipeline from the branch: the install step must print `terraform_<version>_linux_amd64.zip: OK`.

## 4. Bump the image

Trigger: a retirement notice, or a run failing because the image cannot be found. Change `vmImage`, run from the branch, read the Initialize job lines (image name and version) and the diagnostic step, then record the change in a new ADR or an amendment to ADR-0023.

## 5. Verify a healthy run

On the Pull request or from the branch: the diagnostic step prints `x86_64` and whether the image carries Terraform (it did not on 2026-10-29); the install step prints `...linux_amd64.zip: OK`; the assert step prints `Terraform v<version>`; the last step prints `found 13 Terraform directories` and ends `validated 13 directories`. The first green run took 1 minute 1 second.

## 6. Symptoms

| Symptom | Cause | Action |
|---|---|---|
| Install step: `FAILED`, `1 computed checksum did NOT match`, exit 1; assert and validation steps skipped (observed) | the downloaded zip differs from `terraformSha256` (the test changed one character of the hash) | do not continue. Re-check the hash against the signed `SHA256SUMS` (section 3); a real mismatch for an unchanged version is a security event |
| A directory's group shows only a formatting diff and `checks failed in <dir>`, the summary ends `failed: <dir>` (observed) | `terraform fmt -check` failed; `init` and `validate` do not run in that directory because the checks are chained with `&&` | run `terraform fmt` in that directory, commit, rerun; a validation error in the same directory shows only after that |
| The loop visits all 13 directories even after one fails (observed) | failures are collected and the job fails at the end | read the `failed:` line and the red error lines in the run summary |
| Diagnostic prints `no terraform on PATH before our install` (observed, informational) | the image carries no Terraform | none; the pipeline installs its own |
| `expected at least 13 Terraform directories` (expected, not yet observed) | discovery found fewer than the floor: a directory was removed or `find` broke | check `find . -name versions.tf`; change the floor in the same pull request that adds or removes a root |
| Wizard opens "Authorize Azure Pipelines (OAuth)" although a GitHub connection exists (observed) | the wizard started from the portal asks for OAuth for each new pipeline | cancel; use the app route in section 2 |
| A pull request starts no run (expected, not yet observed) | no changed file matches the path filter | compare the changed files with the filter; docs, `ansible/`, `bootstrap/` and `.github/` are outside it on purpose |
| Run fails because the image cannot be found (expected, not yet observed) | Microsoft retired the pinned image | section 4 |
| A fork pull request starts a run (expected not to; not tested) | the fork option is off in the portal | check Triggers; the run would hold no secret and no connection |

## 7. Teardown

Delete the definition in the portal (Pipelines, the `...` menu, Delete). Nothing else was created: no connection, no identity, no Azure resource. Run history is lost; the YAML stays in the repository.
