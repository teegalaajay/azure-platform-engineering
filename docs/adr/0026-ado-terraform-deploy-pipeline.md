# ADR-0026: A multi-stage Terraform pipeline on Azure DevOps: Build, Plan and a manual Deploy

- **Status:** Proposed (accepted on merge)
- **Date:** 2026-10-31
- **Deciders:** platform-team (@teegalaajay)
- **Relates to:** ADR-0005 (state backend); ADR-0013 (GitHub identities); ADR-0014 (plan on pull request); ADR-0022 (ADO identity); ADR-0023 (ADO validate); ADR-0025 (version checks); runbook `ado-terraform-deploy`

## Context

ADR-0022 proved that an Azure DevOps run can sign in to Azure as a read-only identity. ADR-0023 validates Terraform
with no identity at all. Neither plans against real state or changes Azure. This pipeline does both, in stages that
must not share a machine or an identity.

Three facts shape it:

1. **Every job runs on its own agent.** A Microsoft-hosted agent is a fresh machine that is discarded after the job.
   Files, sign-ins and environment variables do not carry from one job, or from one step, to the next (documented;
   observed here: the Deploy job had to download the plan file and install Terraform again).
2. **Terraform signs in twice.** The `azurerm` provider calls Azure Resource Manager (checked by RBAC roles such as
   Reader or Contributor). The `azurerm` backend calls the state storage account's data plane (checked by a blob
   data role). Contributor or Owner does not cover the second call (ADR-0005).
3. **The repository is public.** A push or a pull request must never start a run that can hold a service connection.

The plan identity built under ADR-0022 held Reader at the subscription only, and there was no apply identity.

## Options considered

1. **How the plan reaches Deploy:** (a) publish the plan file as a pipeline artifact and apply exactly that file;
   (b) run a fresh `plan` then `apply` inside Deploy.
2. **Identities:** (a) two identities and two service connections; (b) one identity for both stages.
3. **How Terraform signs in:** (a) native OIDC, the same variables as `plan.yml`, set by one shared template;
   (b) Terraform uses the Azure CLI session that the task leaves open.
4. **What the pipeline deploys first:** (a) a new root `workloads/pipeline-demo/dev` with one resource group;
   (b) the existing `platform/cost` root, which has no changes.
5. **Where a new root's state blob comes from:** (a) a one-time `terraform init` from the workstation;
   (b) write access to the state container for the plan identity; (c) a first job that initializes the root as the
   apply identity.
6. **Roles of the apply identity:** (a) Contributor at the subscription plus Storage Blob Data Contributor on the
   state container; (b) the full set of the GitHub apply identity; (c) Contributor on a pre-created resource group.
7. **Variable names for the federated-credential values:** (a) one pair per connection; (b) keep the shared names
   and add a confirmation flag.
8. **What lets Deploy run:** (a) a runtime parameter `deploy`, default `false`, from any branch; (b) only runs from
   `main`.

## Decision

Option (a) in every case, plus the controls below. Each cost is the one we accept by choosing it.

1. **Plan file as an artifact.** Build runs static checks without a backend. Plan signs in as the plan identity, runs
   `terraform plan -lock=false -out=dev.tfplan` and publishes the file as artifact `tfplan`. Deploy downloads it and
   runs `terraform apply` on that file. What was planned is what is applied. *Cost:* the plan file can carry
   sensitive values and sits in Azure DevOps storage for the project's retention period; a state change between
   Plan and Deploy makes Terraform refuse the file; Deploy has to repeat `init`.
2. **Two identities.** `app-ado-plan-shared` (Reader at the subscription, Storage Blob Data Reader on the `tfstate`
   container) through `sc-azure-plan-shared`; `app-ado-apply-shared` through `sc-azure-apply-shared`. *Cost:* one
   more app registration, credential and connection to keep consistent with `bootstrap/ado-oidc.sh`.
3. **Native OIDC from one shared template.** `pipelines/templates/terraform-azure-step.yml` wraps `AzureCLI@2` with
   `addSpnToEnvironment: true`, maps the client ID, tenant ID and ID token to the `ARM_*` variables Terraform reads
   for provider and backend, and runs the command in the same step. `set -u` stops the step if the token is missing.
   *Cost:* the design depends on the task exposing the ID token; a fresh token is minted per step; two Terraform
   commands in the same job sign in separately.
4. **A new root `workloads/pipeline-demo/dev`** (one resource group, mandatory tags, two outputs, no sensitive input).
   *Cost:* one more root: `SKIP_ROOTS` in `apply.yml` (GitHub must never apply it), the plan floor, the validate
   floors, a backend key and this ADR's runbook.
5. **The first `init` of a new root is run by the operator.** The azurerm backend creates an empty state blob when
   the key does not exist, which is a write; the plan identity cannot do it. *Cost:* a manual step per new root,
   outside the pipeline and outside the apply identity's audit trail. A forgotten step fails loudly: the plan leg
   goes red.
6. **Apply identity: minimum for this root.** Contributor at the subscription (a resource group must be created
   before any narrower scope exists) and Storage Blob Data Contributor on the `tfstate` container. *Cost:*
   Contributor at subscription scope is broad; the protections are indirect (manual runs only; approvals and a
   branch check arrive with environments).
7. **One variable pair per connection:** `ADO_PLAN_FIC_ISSUER/SUBJECT`, `ADO_APPLY_FIC_ISSUER/SUBJECT`,
   `ADO_KV_FIC_ISSUER/SUBJECT` (`bootstrap/ado-agent-fic.sh`). `bootstrap/ado-oidc.sh` refuses to run while the old
   names `ADO_FIC_ISSUER` or `ADO_FIC_SUBJECT` are set. *Cost:* two scripts and two runbooks changed in the same
   change; anyone with the old names exported gets a clear error.
8. **Deploy runs only when `deploy` is ticked in the Run dialog.** Otherwise the stage is Skipped. The pipeline has
   `trigger: none` and `pr: none`. *Cost:* until a branch check and an approval exist, a person can apply unmerged
   code by ticking the box.

Controls that follow from the decisions:

- The plan stage runs with `-lock=false`: taking the state lease is a write, which the plan identity does not have.
- The Terraform version and its SHA-256 are variables of the pipeline, passed into `templates/terraform-install.yml`
  as parameters. The pipeline's version line is covered by `scripts/check-terraform-version.sh` (ADR-0025).
- The pipeline's definition and the apply service connection are portal-built objects (an exception to the rule
  that nothing is built by hand, recorded in the runbook).

## Observed (2026-10-31)

- Run of `ado-auth-check` (signs in as the plan identity) failed at sign-in with `AADSTS700213: No matching federated
  identity record found for presented assertion subject` after `bootstrap/ado-oidc.sh` printed `updated credential`
  where `skipped` was expected: shared variables still held the Key Vault connection's values from earlier work.
  Restored from the plan connection's own issuer and subject, the run was green again.
- First run of this pipeline: Build green (9 s), then the Plan stage paused with "This pipeline needs permission to
  access a resource before this run can continue to Plan"; after the permit, the sign-in step worked
  (`servicePrincipal`, subscription state `Enabled`) and `set -u` did not stop the script, so the task exposes the
  client ID, tenant ID and ID token to the script.
- `terraform init` then failed with `Error loading state: failed to lock azure state`, `403
  AuthorizationPermissionMismatch`, followed by `404 The specified blob does not exist`. A listing of the container
  showed no blob under `workloads/pipeline-demo`. After `terraform init` from the workstation the blob existed
  (`workloads/pipeline-demo/dev.tfstate`, 181 bytes) and the next run's plan printed `Plan: 1 to add, 0 to change,
  0 to destroy.`, with the log line "Uploading pipeline artifact ... dev.tfplan".
- A run with `deploy` unticked: Build and Plan green, Deploy and its job not started, no permit prompt for the apply
  connection. The checkbox is unticked by default.
- A run with `deploy` ticked: the Deploy stage showed "Checks and manual validations for Deploy" with one item, the
  service connection `sc-azure-apply-shared`, "Permission needed"; after the permit Deploy was green and `terraform
  apply` printed `Apply complete! Resources: 1 added, 0 changed, 0 destroyed.` from the downloaded plan file.
  A `terraform plan` from the workstation afterwards printed `No changes`.
- `bootstrap/ado-oidc.sh`: the first run created `app-ado-apply-shared`, its service principal and two roles and
  skipped both credentials; with the apply pair set it printed `created credential ado-sc-azure-apply-shared`
  and the evidence showed one credential on each app and no secrets or certificates.
- The version check printed nine `ok` lines after the pipeline's two lines were added.

## Consequences

- A saved plan file is secret-bearing in principle. This root has no sensitive values, but later roots may; shorten
  the artifact retention period before one does.
- Until environments, approvals and a branch check exist, anyone who can queue the pipeline can apply unmerged
  code with Contributor at the subscription.
- Plans with `-lock=false` can run next to an apply, so a plan may describe state that is about to change.
- Every new root costs a manual `init`, entries in `apply.yml`, and a floor bump.
- Each Terraform command signs in separately; the template costs a few seconds per command.
- The pipeline definition (`ado-terraform-deploy`) and `sc-azure-apply-shared` are built in the portal.
- The Terraform version is named in one more place (this pipeline's variables); the check covers it.

## Unproven (to test, not assumed)

- Whether Terraform signs in with the OIDC token or falls back to the Azure CLI session the task leaves open. Both
  are the same identity, so green runs look identical. Test: override `ARM_OIDC_TOKEN` with an invalid value in the
  Plan stage on a throwaway branch and see whether `init` fails.
- That a changed state between Plan and Deploy makes `apply` refuse the saved plan.
- The text of "Verify and save" for `sc-azure-apply-shared` (the dialog reported "saved successfully").
- The artifact's retention period (the project setting was not read).
- That the GitHub plan workflow's leg for the new root passes (read-only access to an existing blob is expected).
- That the version check fails when this pipeline's version line differs (only the pass was observed).
- That a fork or a pull request cannot start the pipeline (`trigger: none`, `pr: none`; not tested from a fork).
- The behaviour of the retired-name guard in `bootstrap/ado-oidc.sh` (never triggered; read only).
