# Runbook: Rebuild drill (destroy the ephemeral workloads, rebuild from the pipelines)

**Purpose:** Prove that the ephemeral layer comes back from code alone, and time it (ADR-0034). Scope: `workloads/pipeline-demo/dev`, `workloads/ansible-target/dev` and the agent root `platform/ado-agent`. Persistent roots and `workloads/storage-demo/prod` are not touched.
**Owner:** platform-team · **Last validated:** 2026-11-04 (full drill; both workload roots rebuilt by `ado-terraform-deploy` from `main`, second plans `No changes`; the Ansible target and the agent were destroyed afterwards, `pipeline-demo/dev` was kept)

Statements marked *observed* were seen on 2026-11-04; *reasoned* means derived, not tested. This runbook links to the component runbooks for commands; it does not repeat them.

## 1. Pre-flight (each as its own command)

1. `cd ~/azure-platform-engineering && git fetch --prune && git status -sb` shows `## main...origin/main` and nothing else.
2. `az rest --method get --url "https://management.azure.com/subscriptions/$ARM_SUBSCRIPTION_ID?api-version=2022-12-01" --query state` prints `"Enabled"`.
3. `az group exists --name rg-ado-agent-shared` and `az group exists --name rg-ansible-target-dev` both print `false`.
4. The CLI default subscription equals `ARM_SUBSCRIPTION_ID` (compare only the first and last four characters in chat).
5. The registration token has not expired (about 2026-11-28; after that date rotate it first, runbook `ado-agent` section 1).

## 2. Destroy what exists

1. From the workstation, in `workloads/pipeline-demo/dev`: `terraform plan -destroy`, read it (observed: `0 to add, 0 to change, 1 to destroy`), then `terraform destroy`.
2. Check: `az group exists --name rg-pipeline-demo-dev` prints `false` and `terraform state list` prints nothing.
3. `workloads/ansible-target/dev` is destroyed with runbook `ansible-target`, section 6, if it exists.

## 3. Bring up the agent (by hand, ADR-0034 decision 2)

Follow runbook `ado-agent`, sections 2 and 3: apply `platform/ado-agent` from `main` (7 to add, observed), then wait until the pool shows the agent **Online** (observed: Online at 12:40 PM). Start the clock for the pipeline part only after the agent is Online.

## 4. Rebuild from the pipelines

Run `ado-terraform-deploy` from branch `main`, once per root, ticking "Run the Deploy stage" and approving the stop at Deploy:

1. `terraformRoot` = `workloads/pipeline-demo/dev` (observed: plan 1 to add, apply `1 added`).
2. `terraformRoot` = `workloads/ansible-target/dev` (steps in runbook `ado-terraform-deploy` section 5a; observed: plan 7 to add, apply `7 added`, Ansible run 1 `ok=6 changed=4`, run 2 `ok=5 changed=0`).
3. Check from the workstation: `terraform plan` in each root prints `No changes`.

## 5. Record the timing

For each run write down, from the run page: start time, duration of Build, Plan and Deploy, run total, and the time spent waiting for the approval. Sum of the stage durations is the pipeline work; total minus that sum is approval waiting and queueing (reasoned: not separately measured on 2026-11-04). Reference figures from 2026-11-04:

| Run | Root | Build | Plan | Deploy | Total |
|---|---|---|---|---|---|
| `#20261104.4` | `workloads/pipeline-demo/dev` | 13 s | 37 s | 1 m 07 s | 6 m 10 s |
| `#20261104.5` | `workloads/ansible-target/dev` | 14 s | 32 s | 3 m 36 s | 7 m 20 s |

## 6. Optional failure-path tests (throwaway branch, never merged)

Create the branch from `main`, change one thing, run `ado-terraform-deploy` **from that branch** with Deploy unticked (a branch cannot pass Branch control, ADR-0027), then delete the branch on origin and locally.

- **Cancel during the Ansible play (ADR-0032 F3):** needs a play long enough to cancel (observed: the unmodified play took 10 s, no window; a `sleep 120` before the first run gave one). Cancel the run during the play step, then confirm the cleanup step ran and passed, and check the agent read-only with `az vm run-command invoke` that no key file and no `sleep`/`ansible-playbook` process is left.
- **Failure report in `plan` (ADR-0033):** add `exit 1` after the plan line; expect Plan red, Deploy skipped, the `FAILED pipeline=...` line in the run's errors and one failure email.

## 7. Take it down

1. Destroy `workloads/ansible-target/dev` (runbook `ansible-target` section 6) and `workloads/pipeline-demo/dev` if it should not stay (it costs nothing; the drill destroyed it only to prove the rebuild).
2. Destroy `platform/ado-agent` (runbook `ado-agent` section 5).
3. `az group exists` prints `false` for `rg-ado-agent-shared` and `rg-ansible-target-dev`.
4. Definition of done: `git status -sb` clean, and `find . -name "*.tfstate*" -not -path "*/.terraform/*"` prints nothing.

## 8. Symptoms

| Symptom | Cause | Fix |
|---|---|---|
| A test run is green and shows nothing | The run was started from `main`, not the branch (observed: run `#20261104.6`) | Check the branch name in the run header and start the run again from the branch |
| Cancel test passes but proves nothing | The play finished before the cancel (observed: 10 s) | Lengthen the play on the throwaway branch only |
| `configure` waits and never starts | The agent is not Online (runbook `ado-agent` section 3) | Fix the agent first |
| Agent registration fails after 2026-11-28 | The registration token expired (reasoned) | Rotate the token in Key Vault, then apply the agent again |
| A long pause between agent Online and the first run | Not diagnosed on 2026-11-04 (about 62 minutes) | Record the reason next time |
