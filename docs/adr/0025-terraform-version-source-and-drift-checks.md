# ADR-0025: One source for the Terraform version, and checks for text that is written twice

- **Status:** Proposed (accepted on merge)
- **Date:** 2026-10-30
- **Deciders:** platform-team (@teegalaajay)
- **Relates to:** ADR-0012 (validate workflow); ADR-0023 (ADO validate pipeline); ADR-0024 (ADO agent); runbook `ci-validate`

## Context

Two kinds of text in this repository must stay identical and nothing checks them:

1. **The Terraform version.** It is written in six places (observed by search, 2026-10-30): the assertion in
   `apply.yml`, `plan.yml`, `validate.yml`, `pipelines/ado-terraform-validate.yml` (plus a SHA-256 tied to that
   version), `platform/runner/runner.auto.tfvars` and `platform/ado-agent/ado-agent.auto.tfvars`. The roots
   accept `>= 1.9.0, < 2.0.0`, so a mismatch among the six is silent until one runner plans differently from
   another. Earlier notes counted five places; the sixth came with the agent root (PR #32).
2. **A shared cloud-init block.** `modules/ado-agent-vm` and `modules/runner-vm` carry the same nine lines
   (from `ARCH=$(dpkg ...)` to `apt-mark hold terraform`). A comment in the agent template says they must
   stay identical; nothing enforced it.

Saved plan files are a separate gap: `.gitignore` already ignores `*tfplan*`, so the failure on 2026-10-29
(a destroy plan named `tfdestroy`) was a naming problem, not a missing rule.

## Options considered

- **A. A `.terraform-version` file as the single source, with two check scripts** run as pre-commit hooks and
  in the validate workflow.
- **B. Document the places in a runbook only.** Nothing detects drift.
- **C. Generate the workflows and variable files from the source.** Static YAML cannot read a file, so this
  needs a template step and a second moving part; rejected as larger than the problem.

## Decision

Option A.

- `.terraform-version` holds one line, `1.16.4`.
- `scripts/check-terraform-version.sh` compares it with the six places and fails on a different value or on a
  place it cannot find (zero matches is a failure, so a changed line format cannot pass silently).
- `scripts/check-cloud-init-drift.sh` compares the shared block in the two templates and fails on a
  difference or a missing marker. The markers are anchored to the indented command lines because a comment in
  the agent template also contains the text `ARCH=`.
- Both run as local pre-commit hooks (only when a file they read changes) and as the first step of the
  `discover` job in `validate.yml`, which has no path filter, so `validate-gate` carries the result.
- The saved-plan rule goes into the runbook: name saved plans with `tfplan` in the name, outside the repository.

## Observed (2026-10-30)

- Version script, run against copies of the real files: all six agree, exit 0; one place changed to `1.16.5`,
  it names the file and exits 1; a renamed line, it fails with `found 0`.
- Drift script, five runs against copies: real files identical (9 lines), exit 0; an edit to the update line
  inside the block fails and prints the diff; an end marker removed fails; an edit outside the block passes.
- The first version of the drift script started its block at the agent template's comment line and failed on
  unchanged files. Two of my first test edits changed a line outside the block (the template has two
  `apt-get update` lines) and passed, which was the correct result.

## Consequences

- The duplication remains. The checks detect drift; they do not remove it.
- The scripts read text patterns, so a change to a line's format breaks the check (loudly) until the pattern is
  updated.
- The SHA-256 beside the ADO pipeline's version is not verified by the script; changing the version still
  needs the hash replaced by hand from HashiCorp's signed `SHA256SUMS`.
- A version change in the two `*.auto.tfvars` files changes the rendered boot script, which forces a VM
  replacement (observed for the agent on 2026-10-29).
- Every pull request pays a few seconds for the new step in `discover`.

## Unproven (to test, not assumed)

- That the new CI step turns `validate-gate` red on a real mismatch (planned: one deliberate commit on the PR).
- That the pre-commit hooks fire on a real commit that changes one of the watched files.
- That the version check is complete: a seventh place added later would not be known to the script.
- That the scripts work from a working directory other than the repository root (they `cd` to the root).

## Enterprise equivalent

A tool-version manager file (`.terraform-version`, `.tool-versions`) read by CI and developers, with automated
dependency updates (a bot pull request that changes every place together), and base images built from the pinned
version instead of installing at boot.
