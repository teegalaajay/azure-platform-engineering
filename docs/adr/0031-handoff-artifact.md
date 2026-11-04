# ADR-0031: Hand the Terraform output to Ansible through a pipeline artifact

- **Status:** Accepted
- **Date:** 2026-11-03
- **Deciders:** platform-team (@teegalaajay)
- **Relates to:** ADR-0030 (the one-run provision and configure pipeline; this ADR replaces its option 2a);
  ADR-0026 (project retention, manual runs only); ADR-0027 (Branch control: Deploy runs only from `main`);
  ADR-0028 (the macro rules); ADR-0029 (the shared Ansible steps); runbook `ado-terraform-deploy`

## Context

ADR-0030 passes the target address and user from the `apply` job to the `configure` job as two job output
variables. A job output is a short string stored in the run's record and addressed by job name, then step name. The
first proof runs on 2026-11-03 failed twice around it: a silent end of the publishing step and a wrong addressing
form. A pipeline artifact is a named file or folder uploaded from the agent to storage kept for the run; the
pipeline already uses one for the saved plan (`tfplan`). The question for Week 7 Day 1 was what an artifact adds
to a handoff that already works inside one run.

## Options considered

1. **What the file holds:** (a) a small JSON file with the four fields the consumer or a reader needs
   (`target_host`, `target_user`, `root`, `commit`); (b) the whole `terraform output -json`; (c) no file.
2. **Relation to the job output:** (a) the artifact replaces it; (b) both exist.
3. **How the consumer parses the file:** (a) `python3`; (b) `jq`; (c) `grep` and `sed`.
4. **Where in the `configure` job it is read:** (a) before the shared Ansible template, which starts with
   `checkout: self`; (b) after it.

## Decision

Option (a) in 1, 2, 3 and 4.

1. **A four-field JSON file.** The step after `apply` reads `target_host` and `target_user`, checks the address
   against `10.10.1.x` and the user against a plain-name pattern, and writes
   `{"target_host":...,"target_user":...,"root":...,"commit":...}` with `printf`; `publish` uploads the folder as
   the artifact `handoff`. *Cost:* the field names are a contract between producer and consumer. The JSON is built
   by hand, which is safe only because every value is validated first (the root comes from the allowlisted
   parameter, the commit is a hex SHA); a field that ever takes free text would break it. Option (b) was rejected:
   `terraform output -json` prints sensitive outputs in clear text, so a later sensitive output would become a
   downloadable file readable by anyone who can read the run.
2. **The artifact replaces the job output.** The `targetOutputs` step, its `isOutput` lines and the
   `dependencies.apply.outputs[...]` addressing are removed. *Cost:* the job-output path no longer exists as a
   fallback. Option (b) was rejected because two sources for one value can drift and it removes none of the
   addressing that failed twice. The optional `step_name` parameter of `templates/terraform-azure-step.yml` is now
   unused by this pipeline and stays, because its empty default is what Build and Plan rely on.
3. **`python3` parses the file.** The agent runs `python3 -m venv` for Ansible, so `python3` is on its path
   (reasoned from those runs). *Cost:* `configure` now depends on a system `python3` and on the artifact name
   `handoff` matching in two places. `jq` was not checked for.
4. **The read happens before the shared template.** The `configure` job downloads `handoff`, reads the two values,
   sets two ordinary job variables with `task.setvariable` (no `isOutput`) and only then runs
   `templates/ansible-site-steps.yml`, whose first step is `checkout: self` with `clean: true`. What that checkout
   does to `$(Pipeline.Workspace)` was not tested; reading first removes the question. *Cost:* the read step sits
   in the pipeline file and not in the shared template.

What the artifact adds, stated plainly: nothing for a handoff inside one run. It adds a record that outlives the
agent's disk (kept by the project retention policy of ADR-0026), a file a person can download from the run summary,
and the possibility that a second pipeline consumes it. The third is **not built or tested** here.

## Observed (2026-11-03)

- **Run `#20261103.6`** (branch `feat/w7-artifact-handoff`, root `workloads/ansible-target/dev`, Deploy unticked): Build
  (fmt, init without a backend, validate) 25 s and Plan 55 s green; the plan ended
  `Plan: 7 to add, 0 to change, 0 to destroy.`; the Deploy stage listed two jobs, `Apply the reviewed plan…` and
  `Configure the target with Ansible…`, both not started. So the YAML compiled and the `${{ if }}` produced the
  `configure` job. The new steps themselves did not run: Deploy runs only from `main` (ADR-0027).
- **pre-commit** on `pipelines/ado-terraform-deploy.yml`: `yamllint` passed; the Terraform and Ansible hooks had
  no files to check.
- **Proof run from `main`:** run `#20261103.7` (number read from its run page on 2026-11-04; reasoned to be the
  proof run because it follows branch run `.6` the same day and contains the handoff steps; its branch field was not
  looked at). Build 11 s, Plan 28 s, the `apply` job 1 m 25 s and the `configure` job 1 m 20 s, all steps green,
  including `Write the handoff file`, `Publish the handoff artifact`, `Download the handoff artifact` and `Read the
  target address from the handoff file`. Recorded on 2026-11-03 from the same session: the JSON printed the root
  `workloads/ansible-target/dev` and a commit starting `437d11b3a65`; Ansible run 1 `ok=6 changed=4`, run 2 `ok=5
  changed=0` against `10.10.1.11`; the run page listed the artifacts `handoff` and `tfplan`. The log text of the
  download and read steps was not seen.

## Reasoned (not tested)

- A Retry Stage on Deploy publishes the artifact name `handoff` a second time and may fail on the duplicate name.
- The artifact is readable by anyone who can read the run, so it must never hold a secret.
- A second pipeline can download the artifact of the last run of this one (`resources.pipelines`; read in the
  documentation, not run here).

## Unproven

Everything under Reasoned; `python3` on the agent path (indicated by the green read step, log not seen); the effect of the template's `clean: true` checkout on the
downloaded folder; the failure message when the artifact is missing.
