# Runbook: Azure DevOps Terraform pipeline (Build, Plan, manual Deploy)

**Purpose:** Create, run, extend and troubleshoot the `ado-terraform-deploy` pipeline (ADR-0026) and the two identities behind it.
**Owner:** platform-team · **Last validated:** 2026-10-31 (a Plan run, a run with Deploy skipped and a run with Deploy applied; see the ADR for what was observed).

## 1. Layout

| Piece | Where | What it does |
|---|---|---|
| Pipeline definition | Azure DevOps project `azure-platform-engineering`, name `ado-terraform-deploy` | one definition for `pipelines/ado-terraform-deploy.yml`; the YAML stays in GitHub |
| Triggers | `trigger: none`, `pr: none` | never starts from a push or a pull request (the repository is public); a person starts it |
| Parameter | `deploy` (boolean, default `false`) | unticked: Deploy is Skipped; ticked: Deploy applies the plan |
| Stages | `build`, `plan`, `deploy` | static checks without a backend; plan as the plan identity; apply the saved plan as the apply identity |
| Templates | `pipelines/templates/terraform-install.yml`, `pipelines/templates/terraform-azure-step.yml` | pinned Terraform install; native OIDC sign-in plus one Terraform command in the same step |
| Target root | `workloads/pipeline-demo/dev` (`rootDir` variable) | one resource group `rg-pipeline-demo-dev` |
| Plan identity | `app-ado-plan-shared`, connection `sc-azure-plan-shared` | Reader at the subscription; Storage Blob Data Reader on the `tfstate` container |
| Apply identity | `app-ado-apply-shared`, connection `sc-azure-apply-shared` | Contributor at the subscription; Storage Blob Data Contributor on the `tfstate` container |

## 2. Create or rebuild the pipeline

1. Pipelines, New pipeline, GitHub (YAML), the repository, Existing Azure Pipelines YAML file, the branch and `/pipelines/ado-terraform-deploy.yml`. Choose Save, not Run.
2. Rename it to exactly `ado-terraform-deploy`. Two definitions for one file break the one-definition rule.
3. The first run asks for a permit on `sc-azure-plan-shared` when the Plan stage starts, and a second on `sc-azure-apply-shared` when the Deploy stage starts (observed). Click View first and check that the dialog lists only that one connection.

## 3. Create or repair the two identities (two phases)

Phase 1 creates the app registrations, service principals and roles; phase 2 adds the federated credentials.

1. Phase 1: `bootstrap/ado-oidc.sh`. Both credential lines print `skipped` while the variable pairs are unset.
2. In the portal, create the service connection with the manual workload identity federation dialog: the name, the tenant ID, the subscription, the client ID of the app (print it with `az ad app list --display-name <app> --query "[].appId" -o tsv`). Keep the dialog open at the step that shows the issuer and the subject.
3. In the terminal, set only that connection's pair, run the script, then unset it:

```bash
export ADO_APPLY_FIC_ISSUER='<issuer>'
export ADO_APPLY_FIC_SUBJECT='<subject>'
bootstrap/ado-oidc.sh
unset ADO_APPLY_FIC_ISSUER ADO_APPLY_FIC_SUBJECT
```

Use `ADO_PLAN_FIC_*` for `sc-azure-plan-shared` and `ADO_KV_FIC_*` with `bootstrap/ado-agent-fic.sh` for the Key Vault connection. Expect `created credential ...`, or `unchanged` on a second run.

4. Back in the dialog: Verify and save. Never set a pair left over from another connection: the script treats the environment as the truth and overwrites the stored credential.

## 4. Add a new root (every new root, once)

1. Create the root with its `backend.tf` key.
2. From the workstation, in the new root: `terraform init -input=false`. The azurerm backend creates the empty state blob; the plan identity cannot (observed 2026-10-31).
3. Check: `az storage blob list --account-name stattfstate01 --container-name tfstate --prefix <folder> --auth-mode login --query "[].name" -o tsv` shows the key.
4. In `.github/workflows/apply.yml` add the root to `APPLY_ROOTS` or `SKIP_ROOTS` (the classification check fails otherwise). Raise `MIN_DIRS` in `plan.yml` (roots with a backend) and in `validate.yml` and `pipelines/ado-terraform-validate.yml` (Terraform directories).

## 5. Run it

- **Plan only:** Run pipeline, the branch, leave "Run the Deploy stage" unticked. Expect Build and Plan green, Deploy Skipped, and a `Plan:` line in the plan step.
- **Plan and apply:** tick the box. Plan runs first; Deploy applies the file that run just published.
- **Check afterwards:** from the workstation, `terraform plan` in the root prints `No changes` (observed). `az group exists --name rg-pipeline-demo-dev` prints `true`.

## 6. Symptoms

| Symptom | Cause | Action |
|---|---|---|
| Sign-in step fails with `AADSTS700213: No matching federated identity record found` (observed) | the stored credential's subject or issuer differs from the service connection's, for example after a script run with another connection's values | copy the issuer and subject from that connection and run `bootstrap/ado-oidc.sh` with its own pair; then run `ado-auth-check` |
| `terraform init` fails with `failed to lock azure state`, 403 `AuthorizationPermissionMismatch`, then 404 on the blob (observed) | the state blob for this root's key does not exist and the identity cannot create it | section 4, steps 2 and 3 |
| The run stops at a stage with "This pipeline needs permission to access a resource" (observed) | first use of a service connection by this pipeline | View, confirm the one listed connection, Permit |
| Deploy shows Skipped (observed) | `deploy` was not ticked | start a new run with the box ticked |
| `terraform apply` says the saved plan is stale (expected, not yet observed) | state changed between Plan and Deploy | run the pipeline again so a new plan is published |
| `idToken: unbound variable` in a sign-in step (expected, not yet observed) | the task did not expose the ID token | check the service connection type and the task's `addSpnToEnvironment` setting |
| `bootstrap/ado-oidc.sh` stops with `ADO_FIC_ISSUER is a retired name` (expected, not yet observed) | the old shared variables are still exported | `unset ADO_FIC_ISSUER ADO_FIC_SUBJECT`, then set the pair for the one connection |
| Plan leg of the GitHub plan workflow is red for a new root (expected, not yet observed) | the state blob does not exist yet | section 4, steps 2 and 3 |

## 7. Teardown

The demo root costs nothing, so it stays. To remove it: from the workstation, `terraform destroy` in `workloads/pipeline-demo/dev` (not run yet), then delete the pipeline, `sc-azure-apply-shared` and the two apps by hand (`bootstrap/ado-oidc.sh` has no teardown mode yet).
