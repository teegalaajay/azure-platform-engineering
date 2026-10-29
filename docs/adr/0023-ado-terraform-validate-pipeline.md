# ADR-0023: Azure DevOps Terraform validate pipeline (pinned image, verified download, validate-level scope)

- **Status:** Accepted (2026-10-29)
- **Date:** 2026-10-29
- **Deciders:** platform-team (@teegalaajay)
- **Relates to:** ADR-0012 (validate workflow); ADR-0022 (Azure DevOps identity); runbook `ado-terraform-validate`

## Context

The platform needs a first Azure DevOps pipeline for Terraform, built from a blank file, that later weeks reuse
(self-hosted agent, templates, multi-stage). GitHub already runs the same static checks as the required gate
`validate-gate` (ADR-0012). Three risks drove the design: the hosted image changes under an unchanged YAML file
(the tool drift of v1), the Terraform binary must be the one we reviewed, and a pipeline that holds no
credential should not be given one.

Observed 2026-10-28 and 2026-10-29 (portal and run logs):

1. The Day 3 run used the label `ubuntu-latest`. It resolved to image `ubuntu-24.04`, version `20261025.353.1`;
   the same log reported the current version as `20261026.354.1`. The run warned that the label moves to
   Ubuntu 26 from 2026-10-19; on 2026-10-28 it had not moved for that run. The cause is unknown.
2. On `ubuntu-24.04` the agent runs as user `vsts` on `x86_64` and has no `terraform` on `PATH` (diagnostic
   step, run `#20261029.1`). The image version of that run was not recorded.
3. HashiCorp's `SHA256SUMS` for 1.16.4 is signed by subkey `374E C75B 4859 1360 4A83 1CC7 C820 C6D5 CD27 AB87`
   of the primary key `C874 011F 0AB4 0511 0D02 1055 3436 5D94 72D7 468F`, the fingerprint HashiCorp
   publishes; `gpg --verify` against the key file from hashicorp.com reported a good signature. This is
   not the apt repository key (`D55C 0D1A ...`) that the runner cloud-init pins; the two keys differ.
4. Run `#20261029.1` (feature branch, manual) was green in 1 min 1 s; the checksum line read
   `terraform_1.16.4_linux_amd64.zip: OK`; 13 directories were validated with no provider cache.
5. Run `#20261029.2` (one character of the hash changed) was red after 3 s: `FAILED`, `1 computed checksum
   did NOT match`, exit 1; the assert and validation steps were skipped; the post-job step still ran.
6. Run `#20261029.3` (one misformatted file in `platform/cost`, committed with `--no-verify`) was red; all 13
   directories were visited, the summary read `failed: platform/cost`; in the failing directory `init` and
   `validate` did not run, because the checks are chained with `&&`.
7. The pull request validation settings showed the trigger controlled by the YAML, "Build pull requests from
   forks of this repository" unchecked and greyed out, and "Add a PR comment about pipeline run status" on.
8. The new pipeline wizard opened the OAuth consent screen even though the GitHub connection from Day 3
   existed; installing the Azure Pipelines GitHub App again for the one repository avoided it.
9. Pull request 30 started run `#20261029.4` by itself ("PR automated", 1 min 1 s, green, on commit `71c8c0c`,
   not the pushed head `ffbea5d`). GitHub lists it as a check named `ado-terraform-validate`; the check link
   shows the organization name and the project ID on the public pull request page.
10. After the merge, run `#20261029.6` started by itself ("Individual CI" for `main` @ `e34c850`, 1 min 14 s,
    green). The pipeline's default branch field read `refs/heads/main`.
11. Pull request 31 changed only files under `docs/`, outside the path filter. No run appeared after
    `#20261029.6`, and GitHub listed the check `ado-terraform-validate` as skipped (no elapsed time).

## Options considered

Image: (a) `ubuntu-latest`; (b) a pinned Microsoft-hosted image; (c) a self-hosted pool (Week 5 Day 5).

Terraform source: (a) whatever the image carries (observation 2: nothing); (b) a pinned zip downloaded and
checked against a pinned SHA-256; (c) the HashiCorp apt repository, as the runner does.

Install location: (a) a system path; (b) `$(Agent.TempDirectory)`.

Scope: (a) fmt, init without backend, validate, tflint; (b) the same plus plan through `sc-azure-plan-shared`;
(c) fmt, init without backend, validate only.

Status: (a) required check on `main`; (b) informational.

Structure: (a) one job per directory (needs a runtime matrix); (b) one job with a loop that collects failures.

## Decision

- Pinned image `ubuntu-24.04` (b). A bump is a reviewed change. It still receives weekly image updates, so the
  pin fixes the operating system release, not the preinstalled tools.
- Terraform from a pinned zip (b), version and SHA-256 written once in the YAML, installed into
  `$(Agent.TempDirectory)/terraform` (no root, no collision with the image, same behaviour on the Day 5 agent).
  The step compares the hash before it unpacks and a following step asserts the version string.
- The expected hash is taken from the signed `SHA256SUMS` by a person at each bump (runbook procedure); the
  pipeline compares hashes only. Checking the signature inside the pipeline was not chosen: it would need the
  key and its fingerprint pinned in the YAML for no gain over a reviewed hash.
- Scope (c): no Azure identity, no service connection. `app-ado-plan-shared` has Reader only and cannot read
  state (a data-plane operation), so a plan stage would need a new role and its own decision. `tflint` is
  deferred: it needs a second pinned install and a plugin download from GitHub that has not been tested
  from shared agents.
- Informational (b). The required gate stays `validate-gate` on GitHub; a second required check would make
  merges depend on an organization with one free hosted job and 1,800 minutes a month.
- One job and a loop (b) over every directory that holds a `versions.tf`, a floor of 13, failures collected
  and the job failed at the end. Scripts contain no `$(name)` macros; values arrive through `env:`.
- `trigger` on `main` and `pr` to `main`, with the same path filter: `modules/**`, `platform/**`,
  `workloads/**`, `.tflint.hcl`, `pipelines/ado-terraform-validate.yml`, `pipelines/templates/**`.
- One pipeline definition: `ado-terraform-validate` for `pipelines/ado-terraform-validate.yml`.

## Consequences

- The Terraform version is named in five places (this file, `validate.yml`, `plan.yml`, the version check in
  `apply.yml`, the runner cloud-init); the roots allow `>= 1.9.0, < 2.0.0`, so a mismatch is silent. The rule
  is one pull request per bump, which relies on memory. An automated comparison is owed.
- A bump needs a human signature check and a new hash; the image pin eventually fails when Microsoft retires
  it, loudly, which is intended.
- Two systems run the same checks (duplicated minutes and a second set of path lists that must stay in sync).
- A formatting error hides a validation error in the same directory until it is fixed (observation 6).
- `validate.yml` on GitHub still uses `ubuntu-latest`; its mapping is separate and was not examined. Owed.
- The local hook can be bypassed (`--no-verify`, observation 6); this pipeline and the GitHub gate are the
  second line.
- The wizard reopens the OAuth screen for each new pipeline (observation 8); the runbook row that says
  OAuth means no connection exists is wrong and is corrected.
- The check link on a public pull request exposes the organization name and the project ID of a private
  project (identifiers, not credentials); logs and screenshots still need redaction (ADR-0022).
- GitHub treats a skipped check as passing, so a required `ado-terraform-validate` check would be satisfied
  by pull requests the filter excludes (reasoned, not tested).

## Unproven (to test, not assumed)

A fork pull request being skipped (the setting is off; no second GitHub account); whether the path filter on a
pull request looks at the whole pull request or the last push; the content of the PR status comment; the
image version of the green run; the failure path of the version assert step; the behaviour of `$(...)` text
inside a script (avoided, not tested); `tflint` on a hosted agent; when the pipeline's default branch became
`main` (it read `refs/heads/main` after the merge); an event with a path that does not exist yet
(`pipelines/templates/**` exists in the filter only).
