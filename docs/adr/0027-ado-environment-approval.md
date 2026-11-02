# ADR-0027: An approval check on the environment that Deploy targets

- **Status:** Proposed (accepted on merge)
- **Date:** 2026-10-31
- **Amended:** 2026-11-02 (Branch control check added to the environment)
- **Deciders:** platform-team (@teegalaajay)
- **Relates to:** ADR-0026 (the Deploy stage); ADR-0022 (service connections and permits); runbook `ado-terraform-deploy`

## Context

ADR-0026 left the Deploy stage guarded by two things only: the `deploy` run parameter, which whoever starts the run
can tick, and the one-time permit that lets the pipeline use `sc-azure-apply-shared`. Neither asks a named person to
approve a particular run. Anyone who can queue the pipeline can apply to Azure with the apply identity.

## Options considered

1. **An Approvals check on an Azure DevOps environment.** The Deploy job becomes a `deployment:` job that names the
   environment; Azure DevOps evaluates the environment's checks before it assigns an agent.
2. **A manual validation step inside the YAML** (an agentless job that waits for a click). The gate lives in the
   pipeline file, so whoever edits the file can remove it in the same change.
3. **Leave the parameter and the permit as the only controls.**

## Decision

Option 1.

- The Deploy job is `deployment: apply` with `environment: pipeline-demo-dev` and `strategy: runOnce`. *Cost:* the
  job type has its own nesting, and it does not check out the repository unless the steps say so (observed below), so
  the steps keep an explicit `checkout: self` with `persistCredentials: false`.
- The environment is created by hand in the portal before the first run, with Resource set to None, and carries one
  Approvals check ("All approvers must approve"), one approver, an instruction text, timeout 1 day. *Cost:* a
  portal-built object outside Terraform (the RC4 exception already recorded for the other Azure DevOps objects); a
  run nobody answers fails after a day and has to be started again.
- The single approver is the owner, and the owner may approve a run they started. *Cost:* no separation of duties.
  Accepted for a one-person reference platform; a team would name a different approver or a group.
- "Grant access to all pipelines" is left off for the environment, so each pipeline needs its own permit.
- A Branch control check on the same environment, added 2026-11-02: allowed branches `refs/heads/main`, "Verify
  branch protection" off, timeout 1 day (the form's default). Checks run in order: Branch control (1), then All
  approvers must approve (2). *Cost:* a deploy can only start from `main`, so a change has to be merged before it is
  deployed and a pull request's own branch can no longer apply. The check is portal-built, like the environment.
  "Verify branch protection" was left off because its behaviour with a GitHub repository was not tested.

## Observed (2026-10-31)

- With `environment: pipeline-demo-dev` in the YAML and no such environment, the Run pipeline dialog refused the run
  before any stage started: "Job apply: Environment pipeline-demo-dev could not be found. The environment does not
  exist or has not been authorized for use." The Environments list was empty. No automatic creation was seen.
- After creating the environment (Resource None, no checks) the dialog accepted the run. With `deploy` unticked,
  Deploy showed "Skipped due to conditions" and no permit was asked for.
- With `deploy` ticked, Deploy paused: "This pipeline needs permission to access a resource before this run can
  continue to Deploy". View listed one item, Environment `pipeline-demo-dev`, "Permission needed", button Permit.
- After the permit, the Deploy job's steps were Initialize job, Download the plan file, Install pinned Terraform,
  Assert the Terraform version, terraform init and apply, Finalize Job: no Checkout step. The last step failed with
  `Inconsistent dependency lock file` and `azurerm: required by this configuration but no version is selected`.
- With `checkout: self` added as the first deploy step, Checkout and Post-job: Checkout appeared and the apply ended
  with `Apply complete! Resources: 0 added, 0 changed, 0 destroyed.`
- With the Approvals check added (one check, timeout 1d, one approver), the next run stopped at Deploy with "1
  approval needs your review before this run can continue to Deploy". The panel showed the approval on the
  environment, "Waiting for approval", the instruction text, a countdown ("Timeout in 23h"), and Reject and Approve
  buttons that worked for the person who had started the run. The apply job was greyed out with no steps.
- Reject, with a comment: Deploy showed a red X and "1 checks failed", the run's overall result was failed, the
  apply job never started, and a Retry Stage button appeared. Skipped looked different: a neutral symbol and the
  text "Skipped due to conditions".
- Retry Stage on the rejected Deploy requested a new approval; after approving it the stage was green. The `Apply
  complete!` line of that retry was not captured.

## Observed (2026-11-02)

- Run `#20261102.2`, started from a branch `test/branch-control` (same commit as `main`) with `deploy` ticked: Build
  and Plan were green; Deploy showed a red X and "1/2 checks failed", the apply job was greyed out with no steps,
  and a Retry Stage button appeared. The checks panel listed Branch control "Failed" and Approval "Canceled". No
  approval prompt was shown. The stage was already failed when it was opened, so the 1-day timeout was not waited out.
- Run `#20261102.3`, started from `main` with `deploy` ticked: the checks panel listed only the Approval, "Waiting
  for approval", "Timeout in 23h" (Branch control was not shown). After Approve the apply ended with `Apply
  complete! Resources: 0 added, 0 changed, 0 destroyed.`
- The environment's check list showed the execution order: 1 Branch control, 2 All approvers must approve.


## Reasoned (not tested)

- The Deploy stage after the permit failed with an empty or missing configuration in the working directory: an
  `init` in a directory with no `.tf` files installs no provider, which fits the lock-file message. The `init` output
  was not captured, so this stays a reasoned explanation.
- A saved plan reused by Retry Stage is the plan that run published; if state changed since then, `apply` should
  refuse it (the refusal is untested, see ADR-0026).

## Consequences

- Every apply from this pipeline now needs a click from the approver, after the plan has been published.
- A run from any branch other than `main` is refused at Deploy by the Branch control check (observed 2026-11-02):
  the Approval is cancelled and no prompt is shown. This closes the deploy-from-branch exception recorded in
  ADR-0026. Build and Plan still run from any branch, with the plan identity.
- The environment, its check and the permit exist only in Azure DevOps. If the environment is deleted, a manual run
  is refused until it is created again.
- A mistyped environment name in the YAML is refused in a manual run (observed above), not silently created. Whether
  other kinds of run create it automatically was not tested.

## Unproven (to test, not assumed)

- What happens at the end of the timeout with no answer (reasoned: the stage fails).
- Whether the approval prompt reaches the approver by email or notification.
- Whether another pipeline naming the same environment would need its own permit.
- Whether a permit survives deleting and recreating the environment.
- Approver groups, and whether a team setup can forbid self-approval (an option on the check, not seen in use).
- The `Apply complete!` line after Retry Stage.
- What "Verify branch protection" does with a GitHub-hosted repository (left off).
- Whether a run from a tag or a pull request ref is refused by the check; only a branch run was tried.
