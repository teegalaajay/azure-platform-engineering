# ADR-0022: Azure DevOps identity for Azure (workload identity federation, manual service connection)

- **Status:** Accepted (2026-10-28)
- **Date:** 2026-10-28
- **Deciders:** platform-team (@teegalaajay)
- **Relates to:** ADR-0002 (secrets and identity); ADR-0013 (GitHub Actions identities); runbook `ado-service-connections`

## Context

Azure DevOps pipelines need an Azure identity for plan and, later, apply work. ADR-0002 forbids stored
secrets, so the identity must use workload identity federation, as the GitHub identities do (ADR-0013).
The ADO organization is owned by a personal Microsoft account and is not connected to a Microsoft Entra
directory (the organization settings page offers only "Connect directory"). The Azure CLI, and the
subscription, belong to a different account and tenant.

Observed 2026-10-28 (portal and run logs):

1. The new Azure service connection dialog defaults to "App registration (automatic)". Its subscription
   dropdown listed a subscription of the portal's signed-in account, not the platform subscription.
2. The manual option is "App registration or managed identity (manual)" with credential "Workload identity
   federation". Step 1 (name, tenant) saves a **draft** connection when Next is clicked (banner: "saved as
   draft"). Step 2 then shows an **Issuer** (`https://login.microsoftonline.com/<tenant>/v2.0`) and an
   opaque **Subject identifier** (`/eid1/c/pub/t/<id>/a/<id>/sc/<guid>/<guid>`). The last GUID equals the
   connection ID on its overview page. The subject does not have the `sc://<org>/<project>/<name>` form.
3. "Verify and save" is one button; there is no separate verify. It saved the connection once Entra
   accepted the credential.
4. The New GitHub service connection dialog offers only OAuth and a personal access token. The pipeline
   wizard started from the portal opened an OAuth consent screen (admin on repository webhooks and
   services, public and private repositories). Installing the Azure Pipelines GitHub App from the GitHub
   Marketplace for one repository, then completing ADO's setup page and GitHub's "by Microsoft"
   authorization, reached the wizard without OAuth. The connection (type GitHub, authentication
   "Azure Pipelines App") appeared only after the pipeline was saved.
5. A connection created without "Grant access permission to all pipelines" stops the first run:
   "This pipeline needs permission to access a resource before this run can continue", job state
   "Waiting on checks". The Permit action adds the pipeline to that connection.
6. In the run log the task executes `az login --service-principal --federated-token` with
   `--allow-no-subscriptions`; the signed-in user type is `servicePrincipal` and the user name is masked.
   `az group list` succeeded; `az group create` failed with `AuthorizationFailed` for action
   `Microsoft.Resources/subscriptions/resourcegroups/write` (exit code 1).
7. `checkout: none` skipped the Checkout step ("Condition was not met").
8. The organization has one free Microsoft-hosted parallel job (1,800 minutes a month) for private
   projects and none for public projects.

## Options considered

Identity creation: (a) automatic, created by the ADO wizard; (b) manual, created by a script and
pasted into ADO; (c) a managed identity (listed by the portal, not evaluated).

GitHub link: (a) OAuth; (b) personal access token; (c) Azure Pipelines GitHub App scoped to one repository.

Identity sharing: (a) reuse the GitHub apps; (b) one app per pipeline system and purpose.

Role today: (a) none; (b) Reader on the subscription; (c) Contributor.

Federation values: (a) pinned in the script; (b) read from the environment at run time.

## Decision

- Manual connection (b). Observation 1 shows automatic mode cannot reach the platform subscription from
  this organization. `bootstrap/ado-oidc.sh` creates app registration `app-ado-plan-shared`, its service
  principal and the role; the federated credential `ado-sc-azure-plan-shared` is added from the issuer
  and subject the draft connection displays. The script converges and prunes: one credential, no secret.
- GitHub App (c), installed on one repository only. OAuth and PAT act as a person with wider reach
  (observation 4) and a PAT expires.
- One app per pipeline system and purpose (b). The apply identity is reachable only through the
  protected `production` environment (ADR-0013); sharing it would add a path around that approval.
- Reader on the subscription (b): the first pipeline only proves authentication. Write rights are added
  per day with a recorded reason (Day 4 adds read on the state container).
- Federation values from the environment (b): they identify the tenant and organization, and
  engineering standards section 11 (rule 7) keeps tenant and subscription IDs out of the repository.
- Connection names: `sc-azure-plan-shared` for Azure. The GitHub connection keeps the name ADO generated,
  `github.com_<account>`. "Grant access to all pipelines" stays off; each pipeline is permitted once.
- One pipeline definition per YAML file: `ado-auth-check` for `pipelines/ado-auth-check.yml`.

## Consequences

- The Azure Pipelines App holds read and write on code, checks, commit statuses, deployments, issues and
  pull requests for one repository (Microsoft fixes the set). The mitigation is `main` protection with
  an empty bypass list. **Not tested:** that the app cannot push to `main`.
- Entra holds three kinds of objects for this identity (app, service principal, credential) plus an ADO
  connection; the script is the only writer of the Entra side. It has no teardown mode yet.
- Recreating the connection produces a new connection ID, hence a new subject (inferred from
  observation 2); rerun the script with the new values.
- Run logs print the tenant and subscription IDs unmasked and mask the client ID. The ADO project is
  private; logs and screenshots must be redacted before they go into a public PR or document.
- `ensure_app` and `ensure_sp` are duplicated from `github-oidc.sh`; a shared library is owed.

## Unproven (to test, not assumed)

Whether renaming the Azure connection breaks authentication (the name is not in the subject, observation 2,
but the YAML refers to the connection by name); the error for a wrong subject; that a fork pull request
cannot reach the connection; the managed identity of the ADO agent (Week 5 Day 5); approvals and checks
on the connection; the app's behaviour against branch protection.

## Enterprise equivalent

An identity team would create the app, service principal, role and federated credential from a request
that carries the issuer and subject of a draft connection, in a reviewed Terraform identity layer
(Entra and Azure DevOps providers), using a tightly scoped Graph permission. Identity creation would
not run from a laptop. The roadmap revisits this at Week 9 Day 1.
