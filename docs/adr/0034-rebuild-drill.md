# ADR-0034: Rebuild drill: destroy the ephemeral workloads and rebuild them from the pipelines

- **Status:** Accepted
- **Date:** 2026-11-04
- **Deciders:** platform-team (@teegalaajay)
- **Relates to:** ADR-0024 (the self-hosted agent, applied by hand); ADR-0026 to ADR-0028 (the deploy pipeline and its
  gates); ADR-0029 to ADR-0031 (the Ansible stage and the handoff artifact); ADR-0032 (item F3, key file cleanup);
  ADR-0033 (failure report); runbook `rebuild-drill`

## Context

The platform has two kinds of roots. Persistent roots (state backend, hub and spokes, security, cost, identities,
`workloads/storage-demo/prod`) are applied once and kept. Ephemeral roots (`workloads/pipeline-demo/dev`,
`workloads/ansible-target/dev`, `platform/ado-agent`) are built for a purpose and destroyed. Every ephemeral root has
been built from a branch or a pipeline at least once, but never all of them in one sitting from nothing. A claim such
as "the ephemeral layer can be rebuilt from code" is only as good as the last time somebody did it, so this record
fixes what the drill covers, what it leaves out and how it is measured.

## Options considered

1. **Scope:** (a) every root, including the persistent ones; (b) the two ephemeral workload roots and the agent;
   (c) the two ephemeral workload roots only.
2. **How the agent comes back:** (a) by hand from `main` with `terraform apply`; (b) from a pipeline.
3. **What is measured:** (a) wall clock only; (b) the duration of each stage from the run page, with wall clock and
   approval waits kept separate.
4. **Where failure-path tests run:** (a) on `main`; (b) on a throwaway branch that is never merged.

## Decision

1. **Scope (b).** `workloads/pipeline-demo/dev` and `workloads/ansible-target/dev` are destroyed and rebuilt by
   `ado-terraform-deploy` from `main`; `platform/ado-agent` is brought up for the drill and destroyed after.
   `workloads/storage-demo/prod` is excluded: it carries `prevent_destroy` and a `CanNotDelete` lock on purpose and is
   applied by the GitHub apply workflow (`APPLY_ROOTS` in `apply.yml`), not by the Azure DevOps pipeline. Cost of this
   choice: the drill does not show that the persistent roots can be rebuilt, and it does not exercise the GitHub apply
   path.
2. **The agent by hand (a).** The agent hosts the pipelines that would rebuild it, so it cannot be inside that path.
   Cost: one step of the drill is a manual `terraform apply` that no pipeline records, it needs
   `TF_VAR_ado_organization_url` and `TF_VAR_ssh_public_key` set on the workstation, and it depends on the
   registration token in Key Vault, which expires about 2026-11-28.
3. **Measure (b).** Stage durations come from the run page; the run total is wall clock between start and finish; the
   gap between them is approval waiting and queueing. Cost: the numbers are read by hand from a page, not exported.
4. **Failure-path tests on a throwaway branch (b).** The Deploy stage refuses a branch run (ADR-0027, Branch
   control), so a branch can test Build and Plan only. Cost: failure behaviour in `apply` and `configure` stays
   untested until a deploy from `main` is allowed to fail on purpose.

## Observed (2026-11-04)

- Destroyed `pipeline-demo/dev` from the workstation (plan `0 to add, 0 to change, 1 to destroy`); `az group exists`
  `false` and `terraform state list` empty afterwards. `ansible-target/dev` was already at zero.
- Agent applied from `main` (`7 to add`, `7 added`); the pool showed it Online with agent version 5.281.1.
- Run `#20261104.4` (`pipeline-demo/dev`): plan 1 to add, apply `1 added`; Build 13 s, Plan 37 s, Deploy 1 m 07 s;
  total 6 m 10 s. Run `#20261104.5` (`ansible-target/dev`): plan 7 to add, apply `7 added`; Build 14 s, Plan 32 s,
  Deploy 3 m 36 s including `configure`; total 7 m 20 s. Each run waited for an approval.
- Ansible run 1 `ok=6 changed=4`; run 2 `ok=5 changed=0`. A second plan on both roots from the workstation showed
  `No changes`.
- Key file cleanup on a cancelled run (ADR-0032 F3): run `#20261104.2` on a throwaway branch was cancelled during the
  play step; the "Remove the key file and check it is gone" step ran after the cancel and passed; a read-only
  `az vm run-command` on the agent found no key file in `/opt`, `/home`, `/tmp` and `/var/lib`, and no `sleep` or
  `ansible-playbook` process. The first attempt had no usable window (the play took 10 s) and proved nothing.
- Failure report in the `plan` job (ADR-0033): run `#20261104.7` on the throwaway branch with a deliberate `exit 1`
  after the plan line: Plan failed, Deploy was skipped, the run page showed the script error and the
  `FAILED pipeline=... stage=Plan job=Plan ...` line, and one failure email arrived. A "stage approval pending" email
  for run `.5` also arrived.
- Closed: both workload roots and the agent destroyed (`7` and `7`), `az group exists` `false` for both groups,
  throwaway branch deleted, `main` clean and level with `origin/main`.

## Reasoned (not tested)

- Pipeline work was about 6 m 19 s (the sum of the stage durations of the two runs). The rest of each run's total is
  approval waiting and queueing; it was not measured separately. Wall clock for the whole drill was about 1 h 50 min,
  including a pause of about 62 minutes between the agent coming Online and the first run for which no reason was
  recorded.
- A rebuild from nothing is fast because the persistent roots (state, network, vault, identities) already exist; the
  figure says nothing about rebuilding those.

## Unproven

- Cancel before the key file exists, and a hard loss of the agent (VM deleted mid-run).
- The failure report in `apply` and `configure` (both sit behind Branch control).
- A job timeout actually firing, and a retry that succeeds on the Key Vault read.
- A rebuild of `workloads/storage-demo/prod` and of any persistent root.
- Whether the registration token still works after about 2026-11-28.

## Consequences

- The runbook `rebuild-drill` is the procedure. A repeat of the drill should record the same four figures (stage
  durations, run totals, approval waits, wall clock).
- ADR-0032 item F3 is closed for the cancel-during-play case; ADR-0033 loses two of its Unproven items.
- Rotating the registration token becomes a precondition of any drill after 2026-11-28.
