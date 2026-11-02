# ADR-0028: One setup template for the checkout and the pinned Terraform install

- **Status:** Proposed (accepted on merge)
- **Date:** 2026-11-02
- **Deciders:** platform-team (@teegalaajay)
- **Relates to:** ADR-0026 (the deploy pipeline and its templates); ADR-0027 (the deployment job); ADR-0025 (version
  checks); runbook `ado-terraform-deploy`

## Context

Each of the three jobs in `pipelines/ado-terraform-deploy.yml` (validate, plan, apply) began with the same lines:
`checkout: self` with `persistCredentials: false`, then a call to `terraform-install.yml` with the same version and
hash. A change made in one copy could be missed in another. The checkout in the deployment job is the one that Week 6
Day 2 showed is not implicit (ADR-0027).

## Options considered

1. **One steps template, `terraform-setup.yml`,** holding the checkout and the install call.
2. **A job template with parameters** (name, service connection, script) for the plan job and the deploy job.
3. **No change.**

## Decision

Option 1.

- New file `pipelines/templates/terraform-setup.yml` with two string parameters, `version` and `sha256`, and no
  defaults. Its steps are `checkout: self` with `persistCredentials: false`, then a call to `terraform-install.yml`
  by a path relative to the template's own folder. *Cost:* the checkout is no longer visible in the pipeline file, so
  the template carries a comment about it; one edit changes all three jobs.
- The Terraform version and its hash stay as variables in `ado-terraform-deploy.yml`, passed in as
  `$(terraformVersion)` and `$(terraformSha256)`. The version check (ADR-0025) is unchanged and still has one place
  per pipeline to look at. *Cost:* the values pass through two template layers before they are used.
- In the deploy job the setup now comes first and the artifact download after it (before: checkout, download,
  install). *Cost:* none expected, because neither step reads what the other produces (reasoned).
- Option 2 was not chosen. The plan job and the deploy job differ (a normal job against a `deployment:` job with an
  environment and a download step), so the template would need conditions and be harder to read than the lines it
  replaces (reasoned).

## Observed (2026-11-02)

- Run `#20261102.4` from the feature branch, `deploy` unticked: Build and Plan were green. The Plan job's steps were
  Checkout, Install pinned Terraform, Assert the Terraform version, terraform init and plan, Publish the plan file,
  Post-job: Checkout, and the plan ended `No changes`. The nested template path resolved.
- A throwaway experiment (a branch, deleted, never merged) added a step with three `echo` lines. Output:
  `compile time: deploy is False`, `runtime macro: version is 1.16.4`, then
  `line 3: doesNotExist: command not found` and `unknown macro: []`. So `${{ }}` was replaced before the run (with the
  text `False`), `$()` of a defined variable was replaced just before the step ran, and `$()` of an undefined name was
  left as written and run by bash as a command substitution.

## Reasoned (not tested)

- The stage condition `eq('${{ parameters.deploy }}', 'true')` matches although the rendered text is `False` or
  `True`, because `eq` compares strings without regard to case. Observed alongside: with `deploy` ticked the Deploy
  stage ran (run `#20261102.3`).

## Consequences

- An edit to `terraform-setup.yml` changes the plan job and the apply job together. The Day 2 failure (a deployment
  job with no Checkout step) would return if the template were removed from the deploy job.
- A pull request that changes a file under `pipelines/templates/` starts `ado-terraform-validate` (its path filters,
  read from the file), although that pipeline does not use the setup template.

## Unproven (to test, not assumed)

- The deploy job with the setup template: a `checkout:` inside a template within a `deployment:` job. It can only be
  run from `main` after the merge, because of the Branch control check (ADR-0027).
