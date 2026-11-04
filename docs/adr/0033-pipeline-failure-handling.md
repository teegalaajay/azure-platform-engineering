# ADR-0033: Failure report, retries, timeouts and a failure email for the Azure DevOps pipelines

- **Status:** Accepted
- **Date:** 2026-11-04
- **Deciders:** platform-team (@teegalaajay)
- **Relates to:** ADR-0026 (the deploy pipeline, project retention); ADR-0027 (Branch control and the approval on
  `pipeline-demo-dev`); ADR-0028 (the shared setup template); ADR-0029 to ADR-0031 (the Ansible stage and the
  handoff); ADR-0032 (masking matches exact values only; item F3, cleanup on cancel); runbook `ado-terraform-deploy`

## Context

A failed run has to be noticed, explained and, where the cause is transient, survived. Before this change the five
pipelines had two conditions between them (the Deploy stage's `deploy` parameter check and `always()` on the SSH key
cleanup), no retry, no failure report and no job timeout set (observed: a search of `pipelines/` on 2026-11-04).

Read from Microsoft's documentation, not observed here: a step, job or stage runs only when its `condition` is true;
the default is `succeeded()`, `failed()` is true when something before it failed, and `always()` is true whatever
happened. `retryCountOnTaskFailure` reruns a failed step up to 10 times, waits 1 second before the first retry and 4
before the second, and does not make the step idempotent. A job without `timeoutInMinutes` is stopped after 60
minutes; `0` means no limit on a self-hosted agent.

Observed in the organization on 2026-11-04: three default subscriptions in the Build and Pipelines categories, all
on: "Build completes" (any outcome), "Run stage waiting for approval" and "Manual validation pending". No
subscription for failures alone existed.

## Options considered

1. **The failure email:** (a) keep "Build completes" only; (b) add a "Build fails" subscription and keep "Build
   completes"; (c) turn "Build completes" off and add a "Build fails" subscription for the project.
2. **What gets a retry:** (a) the Terraform download and the Key Vault read; (b) those plus the Ansible run;
   (c) nothing.
3. **A failure report:** (a) none, read the log; (b) one shared template step with `condition: failed()`.
4. **Job timeouts:** (a) rely on the 60-minute default; (b) set a value per job.

## Decision

Option (c) in 1, (a) in 2, (b) in 3 and (b) in 4.

1. **A personal "Build fails" subscription** named "platform pipelines: build fails" (category Build, the team
   project `azure-platform-engineering`, filter `Status = Failed`), and the default "Build completes" turned off.
   *Cost:* it is a personal portal setting, not code (an exception to RC4, recorded in the runbook), so it notifies
   only the account that made it; a team needs a project subscription made by a project administrator. The success
   email is gone (the run page still shows success). It cannot report a run that never reaches Failed: an offline
   agent leaves a job waiting (reasoned). `Status = Failed` presumably does not match a run that ends "partially
   succeeded" (reasoned).
2. **`retryCountOnTaskFailure: 2` on three steps:** "Install pinned Terraform" in `templates/terraform-install.yml`
   and its inline twin in `ado-terraform-validate.yml`, and the `AzureKeyVault@2` read in
   `templates/ansible-site-steps.yml`. These steps are safe to run twice and fail mostly for transient reasons.
   `plan`, `apply` and the Ansible run get no retry: a failed apply may already have written state, so a second
   attempt would meet "Saved plan is stale" (observed on Week 6 Day 3) and bury the first error; a failed plan or
   Ansible run is usually a real fault. *Cost:* the step is one unit, so a wrong SHA-256 is retried too (observed
   below); a retry that succeeds leaves only warnings on the run page and nobody is told; three attempts add about
   five seconds of waiting (observed 1000 ms and 4000 ms).
3. **A failure report:** `pipelines/templates/failure-report.yml`, the last step of the four jobs in
   `ado-terraform-deploy` (`validate`, `plan`, `apply`, `configure`), with `condition: failed()`. It writes one
   `##vso[task.logissue type=error]` line built from a fixed list of non-secret predefined variables (pipeline, run
   number, stage, job, ref, short commit and the Terraform root) and never prints the environment (ADR-0032: masking
   matches exact values only). *Cost:* one more step per job. It does not run when the job never starts (observed: a
   rejected gate), when the agent dies, or in the pipelines that do not call it (`ado-ansible-run`,
   `ado-agent-check`, `ado-terraform-validate`, `ado-auth-check`).
4. **`timeoutInMinutes`:** `validate` 10, `plan` 10, `apply` 30, `configure` 15, set from observed durations (11 s,
   28 s, 1 m 25 s and 1 m 20 s in run `#20261103.7`; the largest values seen for the first two were 25 s and 55 s).
   The 60-minute default already bounded a hung job (read); the values shorten detection and put the decision in
   code. *Cost:* a limit that is too tight kills a valid job; a kill in the middle of `terraform apply` can leave a
   partly applied change and a stuck state lock, which is why `apply` has the widest margin (about 20 times the
   observed time).

## Observed (2026-11-04)

- **Run `#20261104.1`**, throwaway branch `test/w7d3-bad-hash` (the last two digits of the pipeline's SHA-256
  changed; never merged, deleted afterwards), root `workloads/pipeline-demo/dev`, Deploy unticked, 17 s. Build failed
  after 14 s; Plan and Deploy "Skipped due to conditions". The Errors tab held four entries: three
  `Bash exited with code '1'` from "Install pinned Terraform" and one from the step "Failure report":
  `FAILED pipeline=ado-terraform-deploy run=20261104.1 stage=Build job=fmt, init without a backend, validate
  ref=refs/heads/test/w7d3-bad-hash commit=ddbdc6f root=workloads/pipeline-demo/dev`. Every variable had resolved.
  The Warnings tab held two: `RetryHelper encountered task failure, will retry (attempt #: 1 out of 2) after
  1000 ms` and the same with `2 out of 2` and `4000 ms`. So: three attempts, and a wrong hash is retried like any
  failure.
- **Email, both subscriptions on:** one email for that run, subject starting `[Build failed]` followed by the
  pipeline, repository and branch, the project and the short commit, at 9:58 AM. The second email I expected did not
  arrive; the cause is unknown. The subject carries no run number.
- **Email, "Build completes" off:** a second failing run from the same branch produced one `[Build failed]` email
  at 10:15 AM (its run number was not recorded). An email of 2026-11-03, `[Build succeeded]` for `ado-auth-check`,
  shows that the default subscription also mails successes.
- **Run `#20261104.3`**, branch `feat/pipeline-failure-handling`, Deploy ticked, root `workloads/pipeline-demo/dev`:
  Build (14 s) and Plan (31 s, one artifact) passed; Deploy failed with "1/2 checks failed" (Branch control
  Failed, Approval Canceled); the `apply` job started no step, no approval was asked for, and the run page showed
  no Errors panel, so no failure report was written. A `[Build failed]` email arrived at 10:28 AM.
- **The subscription form** for the "A build fails" template offers a project filter (one project listed) and a
  default clause `Status = Failed`. The field names behind "Add new clause" were not looked at.

- Amended 2026-11-04 (ADR-0034): a run whose `plan` job failed on a throwaway branch (run `#20261104.7`) showed the
  failure report line and sent one failure email; a cancel during the Ansible play (run `#20261104.2`) still ran the
  key cleanup step, which passed.

## Reasoned (not tested)

- A retry that succeeds ends with the two warnings and a green step; whether the run counts as "partially
  succeeded", and whether `Status = Failed` would then match, was not observed.
- An offline self-hosted agent leaves a job waiting and sends no email.
- `always()` also runs the key cleanup on a cancelled run (read: it is true whatever happened).

## Unproven

- Cleanup of the key file after a hard loss of the agent, and a cancel before the key file exists (the cancel during
  the play step was observed in the rebuild drill, ADR-0034).
- The failure report in `apply` and `configure` (observed in `validate` and, in the rebuild drill, in `plan`; the
  other two sit behind Branch control).
- The retry on the Key Vault read and on the inline copy in `ado-terraform-validate` (the second is first compiled
  by this pull request's own run of that pipeline).
- A timeout actually firing, and what it does to a running apply.
- Why one email arrived where two subscriptions matched.
