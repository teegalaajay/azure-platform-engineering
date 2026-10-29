# Runbook: Azure DevOps service connections and the ADO Azure identity

**Purpose:** Create, verify and troubleshoot the Azure DevOps identity for Azure (ADR-0022) and the two service connections the first pipeline uses.
**Owner:** platform-team · **Last validated:** 2026-10-28 (token exchange, read, write denial and the permission pause, run `#20261028.2`) · **Persistent:** yes (Entra objects and the ADO connections stay; the pipeline runs on demand and costs nothing between runs)

## 1. Layout

| Piece | Where | What it does |
|---|---|---|
| ADO project | `azure-platform-engineering` (private) | holds the pipeline and both connections. Boards, Repos, Test Plans and Artifacts are switched off |
| Azure identity | app registration and service principal `app-ado-plan-shared` | Reader on the subscription. No secret or certificate |
| Federated credential | `ado-sc-azure-plan-shared` on that app | matches the issuer and subject of the Azure connection and audience `api://AzureADTokenExchange` |
| Azure connection | `sc-azure-plan-shared` (Azure Resource Manager, workload identity federation, manual) | gives a pipeline a federated token for the app. Not usable by all pipelines |
| GitHub connection | `github.com_<account>` (GitHub, "Azure Pipelines App") | lets ADO read the YAML from GitHub. The app is installed on one repository |
| Pipeline | `ado-auth-check` for `pipelines/ado-auth-check.yml` | one definition; proves sign-in, a read, and a denied write |
| Script | `bootstrap/ado-oidc.sh` | converges the Entra and Azure side |

## 2. Create or rebuild the identity

Prerequisites: `az` logged in to the platform tenant with rights to create app registrations and role assignments; `jq`; `ARM_SUBSCRIPTION_ID` exported (workstation-setup).

1. Run the script with no federation values. It creates the app, service principal and Reader role and prints `federated credentials: 0`.

```bash
cd ~/azure-platform-engineering && git switch main && git pull --ff-only
bootstrap/ado-oidc.sh
```

2. In the ADO project: Project settings, Service connections, New service connection, Azure Resource Manager. Choose identity type "App registration or managed identity (manual)" and credential "Workload identity federation". Step 1: name `sc-azure-plan-shared`, environment Azure Cloud, the tenant ID. Click Next. This saves a **draft**.
3. Step 2 shows the Issuer and the Subject identifier. Copy both. Do not put them in the repository.
4. Run the script again with both values:

```bash
export ADO_FIC_ISSUER='<issuer from step 2>'
export ADO_FIC_SUBJECT='<subject from step 2>'
bootstrap/ado-oidc.sh
```

   Expect `created credential ado-sc-azure-plan-shared` and `federated credentials: 1`, `secrets or certificates: 0`.
5. Back in the draft: scope Subscription, the subscription ID and name, the application (client) ID printed by the script. Leave "Grant access permission to all pipelines" **unchecked**. Click Verify and save.
6. First run of a pipeline: ADO pauses with "This pipeline needs permission to access a resource". Open View and read the resource name. Permit only `sc-azure-plan-shared`.

The GitHub connection is created when the pipeline is first saved, after the GitHub Azure Pipelines App is installed for one repository only and ADO's setup page is completed. Starting the pipeline wizard from the portal first opens an OAuth consent screen (admin on webhooks, all repositories): cancel it and use the app route.

## 3. Verify

```bash
az ad app list --all --query "[?starts_with(displayName,'app-ado')].[displayName, appId]" -o tsv
az role assignment list --assignee <service-principal-object-id> --all --query "[].[roleDefinitionName, scope]" -o tsv
az ad app federated-credential list --id <client-id> --query "[].name" -o tsv
```

Expect one app, exactly Reader at the subscription, and `ado-sc-azure-plan-shared`. Then run `ado-auth-check`: the identity step prints user type `servicePrincipal` and the resource groups; the second step must end `write denied as expected`.

## 4. Symptoms

| Symptom | Cause | Action |
|---|---|---|
| Run stops: "needs permission to access a resource", job "Waiting on checks" (observed) | the connection is not permitted for this pipeline | View, read the resource, Permit |
| Step 2 log shows `AuthorizationFailed` for `...resourcegroups/write` (observed, expected) | the identity is read-only | none; this is the proof |
| Wizard opens "Authorize Azure Pipelines (OAuth)" with admin on webhooks (observed 2026-10-28, and again 2026-10-29 when the App connection already existed) | the wizard started from the portal asks for OAuth when a pipeline is created; an existing GitHub connection did not prevent it | cancel; install or configure the GitHub App for the one repository and complete ADO's setup page; the wizard then skips OAuth (observed) |
| Service connections list is empty after installing the GitHub App (observed) | the app connection is created when the pipeline is saved | continue the wizard and save |
| Run is rejected in under 1 second: "references service connection X which could not be found" (observed) | no connection with that exact name is authorized for the pipeline; the observed cause was a rename, and the same text also covers a deleted, disabled or unauthorized connection | compare `azureSubscription:` in the YAML with the name under Project settings, Service connections; fix the name through a PR. The federated credential does not need to change after a rename (observed) |
| Verify and save fails at sign-in (expected, not yet observed) | the credential on the app does not match the draft's issuer or subject | compare both strings with `az ad app federated-credential list`; rerun the script |

## 5. Teardown

There is no teardown mode in `bootstrap/ado-oidc.sh` yet. To remove the identity: delete the ADO connection, delete the app registration `app-ado-plan-shared` (this removes its service principal and credential), and confirm with `az role assignment list --all` that no assignment remains. Owed: a script mode for this.
