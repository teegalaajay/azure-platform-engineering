# ADR-0030: Provision and configure the Ansible target in one pipeline run

- **Status:** Proposed (accepted on merge)
- **Date:** 2026-11-03
- **Deciders:** platform-team (@teegalaajay)
- **Relates to:** ADR-0029 (the Ansible steps and the target); ADR-0026 (the multi-stage pipeline, manual runs only,
  the public-repository rule); ADR-0027 (the environment, the approval and Branch control); ADR-0028 (the setup
  template and the macro rules); ADR-0024 (the agent and its Key Vault access); ADR-0007 (no path from a hosted image
  to `snet-app`); runbook `ado-terraform-deploy`

## Context

On Day 4 the target was applied by hand and its address was typed into `ado-ansible-run`. Day 5 removes both manual
steps: one run of `ado-terraform-deploy` provisions the target with Terraform, and an Ansible job configures it with
the address that Terraform produced. Three constraints apply. Deploy can only start from `main` (Branch control,
ADR-0027). A Microsoft-hosted image has no route to `snet-app` (ADR-0007), so the Ansible work has to run on the
self-hosted agent in `snet-mgmt` (ADR-0029). The repository is public, so no push or pull request may start a run that
holds a service connection (ADR-0026).

## Options considered

1. **Choosing the root:** (a) a parameter with a `values:` allowlist that feeds the existing `rootDir` variable;
   (b) a free-text parameter; (c) a copy of the pipeline per root.
2. **Passing the address to Ansible:** (a) a job output variable (`isOutput=true`) published by a step after `apply`
   and read by a later job; (b) the Ansible job runs `terraform output` itself against the state; (c) a file in a
   pipeline artifact (Week 7 Day 1).
3. **Where the Ansible work sits:** (a) a second job in the Deploy stage; (b) a separate stage after Deploy; (c) the
   separate manual pipeline from Day 4.
4. **Environment for the new root:** (a) reuse `pipeline-demo-dev`; (b) a second environment.
5. **The Ansible steps:** (a) one shared step template called by both pipelines; (b) a copy in each pipeline.
6. **The `target_user` output:** (a) a literal in the root; (b) a new output on `modules/linux-vm`.

## Decision

Option (a) in every case.

1. **An allowlisted parameter feeds `rootDir`.** `terraformRoot` is a string parameter with a `values:` list
   (`workloads/pipeline-demo/dev`, `workloads/ansible-target/dev`) and the first value as default. `rootDir` stays a
   variable whose value is `${{ parameters.terraformRoot }}`, so the three existing uses of `$(rootDir)` did not change.
   *Cost:* a new root needs a pull request that edits the list. The path of the Ansible root is written in three places
   (the list and two `${{ if }}` conditions); renaming the root removes the output step and the Ansible job from the run
   without any error. The run title does not show which root was chosen.
2. **A job output variable.** The step `targetOutputs`, after `apply`, reads `target_host` and `target_user` with
   `terraform output -raw`, checks the address against `10.10.1.x` and the user against a plain-name pattern, and only
   then prints two `##vso[task.setvariable ...;isOutput=true]` lines. It uses `read -r x < <(...)` and not `$(...)`, so
   the macro scanner (ADR-0028) has nothing to match. The shared step template gained an optional `step_name` parameter:
   an output is addressed by step name, and an empty value leaves out the `name:` key, so Build and Plan are unchanged.
   *Cost:* the address is validated in the producer and again in the consumer, two copies of one rule. Option (b) was
   rejected because the Ansible job would need Terraform, a sign-in and a state read on the agent; option (c) is Week 7
   Day 1.
3. **A second job in the Deploy stage.** `configure` has `dependsOn: apply`, its own `pool: pool-platform-shared`, and
   reads the outputs with `dependencies.apply.outputs['deploy.targetOutputs.targetHost']` (and `targetUser`). The only
   documented form I read for the output of a deployment job (Microsoft Learn, Azure DevOps sprint 164 release notes)
   is for jobs in the same stage; no cross-stage form was read, so a separate stage was not used.
   *Cost:* the Deploy stage holds two kinds of work and one condition (the `deploy` box) covers both. `configure` is a
   plain job: Branch control (ADR-0027) protects the environment, not this job, so a changed YAML on another branch
   could point the job at the agent and the Key Vault connection. The pipeline therefore needs permits on
   `pool-platform-shared` and on `sc-azure-keyvault-shared`, like `ado-ansible-run`. Accepted: runs are manual, one
   person can start them, and the repository takes no run from a pull request. If `configure` fails after `apply`
   succeeded, the target exists unconfigured; a second run is expected to plan no change and run `configure` again,
   which is idempotent (ADR-0029).
4. **The same environment `pipeline-demo-dev`** for both roots. *Cost:* the name is wrong for the Ansible root, the
   deployment history cannot tell the roots apart by environment, and both share one approval policy and one
   instruction text (written on Day 2 and not re-read today). A second environment is one more portal-built object with
   its own two checks and a permit; deferred to the Week 9 identity-layer revisit.
5. **One shared step template, `ansible-site-steps.yml`,** called by `ado-ansible-run.yml` (`targetHost` from the typed
   parameter) and by `configure` (`$(targetHost)`, a runtime macro, because the value exists only after `apply`).
   *Cost:* a change to the template affects both pipelines. The move was not a pure move: the user name became a
   parameter (default `azureuser`) and is checked next to the address.
6. **`target_user` is a literal `"azureuser"` in `outputs.tf`.** *Cost:* it repeats the default of `modules/linux-vm`;
   if that default changes, the output goes stale without an error. A module output would touch a module that other
   roots use and need a new tag.

## Observed (2026-11-03, before the merge)

- **Apply identity:** `az role assignment list` for `app-ado-apply-shared` showed two assignments: Contributor at the
  subscription and Storage Blob Data Contributor on the `tfstate` container. The root creates no role assignment or
  lock (read from the code), so these two cover what it needs (reasoned).
- **Run `#20261103.1`** (branch `feat/e2e-pipeline`, root `workloads/ansible-target/dev`, Deploy unticked): Build 14 s
  and Plan 37 s green. The plan ended in `Changes to Outputs` with `+ resource_group_name`, `+ target_host =
  "10.10.1.11"` and `+ target_user = "azureuser"`, and Terraform's sentence that applying it saves the new output
  values without changing infrastructure. The address came from `module.vm.private_ip_address` of the live VM. The
  lines above the tail of the log were not read.
- **Same run:** the Deploy stage listed two jobs, `Apply the reviewed plan…` and `Configure the target with Ansible…`,
  both not started: the `${{ if }}` on the root produced the `configure` job.
- **Run `#20261103.2`** (`ado-ansible-run`, same branch, `targetHost` `10.10.1.11`): every step green in 52 s,
  including `Run site.yml twice…` (13 s, which ends with a grep for `changed=0 +unreachable=0 +failed=0`) and
  `Remove the key file…`. The pipeline now runs through the shared template. A `Pre-job: Read the pipeline SSH key`
  entry appears with a different icon from the other steps; the cause is not known.

## Reasoned (not tested)

- With root `workloads/pipeline-demo/dev` neither the output step nor `configure` is compiled, because both conditions
  are false; that run was not made.
- A missing output leaves `$(targetHost)` as literal text (the behaviour of an undefined macro, seen in ADR-0028) and
  the consumer's address check fails with a readable message.
- A value outside the `values:` list is refused when the run is queued; a typed value was not tried.

## Not tested (updated after the proof run from `main`)

That `deploy.targetOutputs.targetHost` resolves; that the agent registers output commands printed inside `AzureCLI@2`;
the permits for this pipeline on the pool and on `sc-azure-keyvault-shared`; the Deploy stage from `main`; the apply as
the apply identity creating the 7 resources; a second Deploy run; a failing `configure` after a successful `apply`.

## Consequences

- `ado-terraform-deploy` now holds the plan connection, the apply connection and, through `configure`, the Key Vault
  reader connection and the pool. Any pipeline permitted on `sc-azure-keyvault-shared` can read every secret in
  `kv-plat-shared-at01` (ADR-0029); this is the second one.
- `workloads/ansible-target/dev` stays in `SKIP_ROOTS` of `apply.yml`: the GitHub apply workflow still does not touch it.
- A new root that should be deployable from this pipeline is added to the `values:` list; if it also needs Ansible it
  must publish `target_host` and `target_user`, and its path must be added to both `${{ if }}` conditions.
- The target and the agent are ephemeral and bill until destroyed (a VM and a NAT Gateway each).
