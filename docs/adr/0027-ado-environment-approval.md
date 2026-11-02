# ADR-0027: An approval check on the environment that Deploy targets

- **Status:** Proposed (accepted on merge)
- **Date:** 2026-10-31
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

## Reasoned (not tested)

- The Deploy stage after the permit failed with an empty or missing configuration in the working directory: an
  `init` in a directory with no `.tf` files installs no provider, which fits the lock-file message. The `init` output
  was not captured, so this stays a reasoned explanation.
- A saved plan reused by Retry Stage is the plan that run published; if state changed since then, `apply` should
  refuse it (the refusal is untested, see ADR-0026).

## Consequences

- Every apply from this pipeline now needs a click from the approver, after the plan has been published.
- The approval does not look at the branch. A run started from a feature branch reaches the same approval and, once
  approved, applies that branch's code with the apply identity. This is the exception recorded in ADR-0026 until a
  Branch control check is added to the environment.
- The environment, its check and the permit exist only in Azure DevOps. If the environment is deleted, a manual run
  is refused until it is created again.
- A mistyped environment name in the YAML is refused in a manual run (observed above), not silently created. Whether
  other kinds of run create it automatically was not tested.

## Unproven (to test, not assumed)

- A Branch control check on the environment (restrict to `main`), and what a run from another branch shows.
- What happens at the end of the timeout with no answer (reasoned: the stage fails).
- Whether the approval prompt reaches the approver by email or notification.
- Whether another pipeline naming the same environment would need its own permit.
- Whether a permit survives deleting and recreating the environment.
- Approver groups, and whether a team setup can forbid self-approval (an option on the check, not seen in use).
- The `Apply complete!` line after Retry Stage.
