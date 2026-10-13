# ADR-0012: Validate workflow for every Terraform directory

- **Status:** Accepted
- **Date:** 2026-10-13
- **Deciders:** platform-team (@teegalaajay)
- **Implements:** the "required CI checks" compensating control named in ADR-0003

## Context

Until now, formatting and validity were enforced only by local pre-commit hooks. A hook can be skipped (`git commit --no-verify`, used on purpose while testing this change), so it cannot be the control that protects `main`. The repository has 11 Terraform directories (3 modules, 8 roots), each with a `versions.tf`, and every root points at the remote state backend.

The check that protects `main` has to run on a clean runner, without an Azure identity and without access to the state account. It therefore runs `init -backend=false`, so a green result means "the code is well-formed", never "the code matches what is deployed". That second claim belongs to the plan-on-PR workflow (roadmap Week 3 Day 5).

## Options considered

**Where the list of directories comes from**
1. A static list written in the workflow.
2. Discovery: a first job finds every directory that contains `versions.tf` and feeds it to the matrix.

**How `main` requires the result**
3. Require each matrix check by name.
4. One aggregator job (`validate-gate`) that is the only required check.

**Pinning third-party actions**
5. A major tag (`@v4`).
6. A full commit SHA, with the tag in a comment.

**Terraform version in CI**
7. The newest 1.x on each run.
8. The exact version validated locally.

**Linter configuration**
9. `-d relaxed` written separately in the hook and in CI.
10. One repository `.yamllint` read by both.

**Matrix failure behaviour**
11. `fail-fast: true` (the default).
12. `fail-fast: false`.

## Decision

Options 2, 4, 6, 8, 10 and 12.

- **Triggers:** `pull_request` and `push` to `main`. There is no `paths:` filter. A required check from a workflow that did not run leaves the pull request waiting for a status that never arrives. This is documented GitHub behaviour and was **not reproduced** here.
- **Token:** `permissions: contents: read` and `persist-credentials: false` on every checkout. The repository default is already `read` (checked 2026-10-13: `default_workflow_permissions` read, `can_approve_pull_request_reviews` false), so the block pins the value against a later settings change and states the intent in review.
- **Discovery (option 2):** every directory containing `versions.tf` outside `.terraform/`, emitted as JSON through `$GITHUB_OUTPUT` and read with `fromJSON`. A floor (`MIN_DIRS`, currently 11) fails the discovery job when fewer directories are found.
- **Matrix job:** one job per directory, named `validate (<dir>)`. Steps in order: `terraform fmt -check`, `init -backend=false -input=false`, `validate`, tflint plugin install, `tflint`.
- **Gate (option 4):** `validate-gate` runs with `if: always()` and fails unless both `discover` and `validate` finished as `success`. Branch protection requires the context `validate-gate`, pinned to the GitHub Actions app (integration ID 15368, read from the API), with the strict "branch must be up to date" policy. The rule lives in `bootstrap/github-repo-settings.sh` and is applied from `main`.
- **Pins (options 6 and 8):** Terraform 1.16.4, tflint v0.64.0, tflint azurerm ruleset 0.32.0 (`.tflint.hcl`), provider `hashicorp/azurerm` 4.81.0 (committed lock files). `hashicorp/setup-terraform` v4.0.1 and `terraform-linters/setup-tflint` v6.3.2 are pinned by commit SHA; both declare `node24`. First-party `actions/checkout` stays on its major tag (`v7`). This matches the existing convention in `.pre-commit-config.yaml`, where hooks are frozen to SHAs.
- **`fail-fast: false` (option 12):** a validation run should report every broken directory in one pass.
- **Lint config (option 10):** a repository `.yamllint` (`extends: relaxed`, line length 120). The pre-commit hook no longer passes `-d relaxed`, because `-d` makes yamllint ignore any config file.

## Consequences

Proven 2026-10-13, on this repository:

- First run: green, 13 jobs (`discover`, 11 `validate (...)`, `validate-gate`), 36 seconds.
- Planted formatting error in `modules/network`: `terraform fmt` failed with exit code 3; later steps in that job were skipped; 2 red checks (`validate (modules/network)` and the gate). The roots that call the module stayed green, because `fmt -check` is not recursive.
- Planted undeclared variable in `modules/network`: `fmt` passed, `terraform validate` failed in 4 jobs (the module and the three foundation roots that call it); 5 red checks. `validate` evaluates the modules a root calls.
- Empty discovery with the floor off: `discover` succeeded with 0 directories, `validate` **failed** (not skipped) and produced no per-directory checks, and the gate went red (`discover=success validate=failure`). This corrected a wrong expectation that an empty matrix would be skipped and the pull request would stay green.
- Empty discovery with the floor on: `discover` failed with `expected at least 11 Terraform directories, found 0`, `validate` was skipped, the gate went red (`discover=failure validate=skipped`).
- The tree was restored and the final run was green on the same 13 checks.

Reasoned, not reproduced:

- The real purpose of the floor is **partial** discovery. If a pattern error drops some directories, the matrix is smaller but non-empty and every cell is green, so unvalidated roots would go unnoticed.

Costs accepted:

- The directory list is not visible in the workflow diff; adding a root requires no edit, but the floor must be raised in the same pull request.
- The floor is a number maintained by hand.
- A failing step hides later steps in the same job (a formatting failure hides a validate error until the formatting is fixed).
- A pull request that falls behind `main` must be updated before it can merge (strict policy).
- SHA pins are harder to read and are updated only by a deliberate pull request.
- CI validates with Terraform 1.16.4 only, while each root allows `>= 1.9.0, < 2.0.0`; other versions in that range are not tested.
- The tflint plugin download worked with `GITHUB_TOKEN` set; it was not tested without it.
- The required-check rule is not live until `bootstrap/github-repo-settings.sh` is run from `main`.

A green check does **not** prove: that the configuration matches deployed infrastructure, that Azure would accept the values (`validate` makes no API calls), or that `main` stays green after another pull request merges first.

Fork pull requests run with a read-only token and no secrets, and outside contributors need approval (ADR-0003). This workflow needs no secrets.

## Deferred

- Plan on pull request with OIDC login (Week 3 Day 5); the self-hosted runner (Week 3 Day 6).
- Policy scanning (checkov or tfsec) in the same gate (engineering standards, Week 3).
- Automated updates for the SHA pins.
- Reproducing partial discovery and the path-filter behaviour.
- Testing the tflint plugin download without the token.
