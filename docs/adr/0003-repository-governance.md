# ADR-0003: Repository visibility and change control on `main`

- **Status:** Accepted
- **Date:** 2026-09-29
- **Deciders:** platform-team (@teegalaajay)

## Context

The platform is maintained by one engineer on a personal GitHub account. It must still
demonstrate the change control a regulated platform team runs: no unreviewed change
reaches `main`, history cannot be rewritten, and every change leaves a record.
GitHub plan limits at the time of writing (2026-09): on a personal Free account, rulesets
are not enforced on private repositories; environment required reviewers are not available
on private repositories on Free or Pro; secret scanning push protection is free only on
public repositories. Teams (and therefore team-based CODEOWNERS) exist only in organisations.

## Options considered

1. **Private repository until the project is finished.** Hides unfinished work, but loses
   rulesets, environment approvals and secret scanning — the controls this repository
   exists to demonstrate.
2. **Public repository with one required approval.** GitHub never counts an author's own
   approval, so with one maintainer no PR could merge without a bypass, which defeats the rule.
3. **Public repository, PR required, zero approvals, compensating controls.**

## Decision

Option 3.

- **Visibility:** public from the first commit.
- **Ruleset `protect-main`** on the default branch: changes only through a pull request
  (0 required approvals), squash merge only, linear history, no force-push, no deletion.
  **Bypass list is empty** — nobody, including the repository owner, can skip the rules.
  Verified: a direct push by the owner was rejected with `GH013`.
- **Compensating controls for zero approvals:** the pull request template (what / why / plan /
  risk / rollback), pre-commit hooks, required CI status checks (from Week 3), and a protected
  `production` environment with required reviewers before any apply.
- **Bootstrap exception:** the root commit `522e64a` (`.gitignore` only) was pushed directly,
  because a pull request needs an existing base branch. It is the only direct commit; the
  ruleset was created immediately after it.
- **CODEOWNERS** names individual users (a personal account has no teams); the intended team
  per path is documented as comments. Code-owner review is not required.
- Squash commits use the **PR title** as subject and the **PR description** as body, so the change record (what / why / plan / risk / rollback) is kept in `git log` on `main`.
- Private vulnerability reporting is enabled (see `SECURITY.md`).
- These settings are codified in `bootstrap/github-repo-settings.sh` so they can be rebuilt.

## Consequences

- Every change to `main` has a reviewable pull request, and the ruleset is enforced by GitHub
  on the server; nothing on the client (`--no-verify`, local config) can skip it.
- **Not provided: segregation of duties.** For a team the configuration would be at least one
  required approval, required code-owner review, dismissal of stale approvals on new pushes,
  approval of the most recent push, and required status checks, with the bypass list empty or
  limited to an audited break-glass group.
- Public visibility means anyone can read the code and open pull requests from forks. Workflows
  therefore never use `pull_request_target` with a checkout of PR code, outside contributors'
  workflow runs need approval, and Azure federated credentials are scoped by subject.
- No subscription IDs, tenant IDs, personal IPs or secrets are ever committed; `gitleaks`
  enforces this at commit time.
