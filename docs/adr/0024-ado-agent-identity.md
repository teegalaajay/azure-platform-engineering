# ADR-0024: Self-hosted Azure DevOps agent: identity, secret access and module structure

- **Status:** Proposed (2026-10-29); becomes Accepted when this pull request merges
- **Date:** 2026-10-29
- **Deciders:** platform-team (@teegalaajay)
- **Relates to:** ADR-0002 (secrets and identity); ADR-0007 (network topology); ADR-0010 (Key Vault); ADR-0013 (GitHub OIDC identities); ADR-0015 (runner and apply on merge); ADR-0022 (ADO identity for Azure); ADR-0023 (ADO validate pipeline); runbook `ado-agent`

## Context

Azure DevOps pipelines need to read secrets from `kv-plat-shared-at01`. The vault denies by default and
allows only the operator IP and the hub `snet-mgmt` service endpoint (ADR-0010), so a pipeline can reach
it only from an agent in `snet-mgmt`. A Microsoft-hosted agent would need its published IP ranges added
to the firewall (documented by Microsoft; not tested here).

Facts read from the repository before this change:

1. `modules/linux-vm` had no `identity` block and no variable for one, so no VM built from it carried a
   managed identity.
2. `modules/runner-vm` installs the GitHub Actions runner through cloud-init. It has no mode for an Azure
   DevOps agent.
3. The vault is owned by `platform/security` (persistent, `prevent_destroy`, purge protection); its
   `key_vault_id` output is the scope for role assignments in other roots.
4. `platform/runner` is ephemeral: the VM, NAT Gateway and public IP are destroyed after each session. A
   subnet takes one NAT Gateway, so a second ephemeral VM in `snet-mgmt` cannot share it.
5. `app-ado-plan-shared`, behind `sc-azure-plan-shared`, holds Reader only (ADR-0022). Reader has no data
   action on secrets.
6. The apply identity can write or delete a role assignment only when the role is Key Vault Secrets
   Officer (ABAC condition, ADR-0013). Key Vault Secrets User is outside that condition.
7. Terraform 1.16.4 is written in five places; `required_version` accepts 1.9.0 up to, not including, 2.0.0.

## Options considered

- Identity kind: (a) system-assigned managed identity; (b) user-assigned managed identity.
- Where the identity lives: (a) inside `platform/security`; (b) a new persistent root
  `platform/agent-identity`; (c) inside the ephemeral agent root.
- Module structure: (a) a mode flag in `runner-vm`; (b) a copy of `runner-vm`; (c) a new sibling module
  `ado-agent-vm` that wraps `linux-vm` and shares the cloud-init setup block with `runner-vm`.
- Where the agent VM lives: (a) inside `platform/runner`; (b) a new ephemeral root `platform/ado-agent`
  with its own NAT Gateway.
- Which `apply.yml` list holds `platform/agent-identity`: (a) `APPLY_ROOTS`; (b) `SKIP_ROOTS` (applied by
  hand); (c) `APPLY_ROOTS` after widening the ADR-0013 condition to Key Vault Secrets User.
- Registration credential: (a) a personal access token read from Key Vault at first boot; (b) a token
  passed in boot data; (c) a service principal.
- Agent package: (a) the standard Linux package; (b) the alternate package without the old Node runtimes.
- How `AzureKeyVault@2` signs in: (a) `sc-azure-plan-shared` with Secrets User added; (b) a new
  "Managed identity" service connection backed by the user-assigned identity.

## Decision

- User-assigned managed identity (b). The role assignment exists before the VM, so the role has
  propagated by first boot (the agent registered with the token from the vault, so the read worked; the
  boot log line for the read was not inspected and the role-race window was not measured). It survives a VM destroy and rebuild.
- The identity and its Key Vault Secrets User role live in a new persistent root `platform/agent-identity`
  (b), using `key_vault_id` from the security root.
- Module structure (c): `modules/ado-agent-vm` wraps `linux-vm` (which gained an optional
  `user_assigned_identity_ids`, default empty); the apt and key-fingerprint block of the cloud-init is
  identical to `runner-vm` and a drift check is owed.
- The agent VM lives in a new ephemeral root `platform/ado-agent` (b) with its own NAT Gateway; it cannot
  be live together with `platform/runner`.
- `platform/agent-identity` goes into `SKIP_ROOTS` (b): hand-applied from the workstation. The CI apply
  identity cannot create its role assignment (fact 6), and widening the condition would add a second role
  to that identity's residual privilege.
- The registration token is a personal access token (a) with the scope Agent Pools: Read & manage, stored
  as the Key Vault secret `ado-agent-pat`, set with `az` so the value never enters Terraform. Cloud-init
  reads it with the managed identity and passes it to `config.sh` through `VSTS_AGENT_INPUT_TOKEN`.
- The agent package is the alternate Linux package (b), checksum-verified; the agent runs as the non-root
  user `agent` as a systemd service.
- `AzureKeyVault@2` is intended to sign in through a "Managed identity" service connection (b);
  `app-ado-plan-shared` stays Reader-only. Not built yet (see Unproven).
- The organization URL is a required root variable with no default, supplied as
  `TF_VAR_ado_organization_url` from the workstation, never committed.
- A single `.terraform-version` file plus a CI check over the five places is decided but built in its own
  pull request.

## Observed (2026-10-29)

- First boot failed at registration: the organization URL used was a placeholder exported by hand in one
  terminal; `validate`, `plan` and `apply` accepted it because the module checks only the URL's shape.
  The agent's first request answered 404. After the value was stored and the VM replaced through
  Terraform, the agent registered, `systemctl` showed `active (running)` and the journal showed
  `Listening for Jobs`; the portal showed Online.
- Registration worked against an organization owned by a personal Microsoft account.
- `config.sh` honoured `VSTS_AGENT_INPUT_TOKEN`; no `--token` flag was used.

## Observed (2026-10-30)

- The first job ran on the agent: the manual pipeline `ado-agent-check` (`pipelines/ado-agent-check.yml`).
  The pipeline had to be permitted once on the pool before it could start. The job ran on `vm-adoagent-shared`
  as user `agent`, uid 1001 (non-root). The step is written to fail when the uid is 0; that failing branch
  was not tested.
- In the same job, `az login --identity` (Azure CLI 2.91.0 on the agent) succeeded and `az keyvault secret
  list` returned three secret names from the platform vault. Which identity signed in was not printed; the
  VM has only the user-assigned one attached (reasoned). That shows the
  role, the network path from `snet-mgmt` and the identity attachment work together. Names only: no secret
  value was requested, so reading a value is still unproven.
- The "New Azure service connection" dialog lists these identity types (the list scrolls; the last one seen
  was Publish profile): App registration (automatic), App registration or managed identity (manual),
  Managed identity (workload identity federation on an existing managed identity), Managed identity
  (agent-assigned: the agent's system-assigned identity, marked not recommended) and Publish profile. The
  agent-assigned type does not fit a user-assigned identity. No connection was created.

## Consequences

Costs of the user-assigned identity:

- It needs a persistent root: a new state key, and the plan matrix floor moves from 8 to 11 roots with a
  backend.
- The Secrets User role stays in place while no VM exists, a standing permission with no user.
- Two VMs attached to it would share every permission.

Cost of the rejected system-assigned identity: the role is recreated with every rebuild and races the
first boot.

Costs of the other decisions:

- `platform/agent-identity` is persistent but hand-applied: CI never corrects drift in it; only the plan
  on a pull request shows it.
- A new sibling module duplicates the shared cloud-init block; without a drift check the two copies can
  diverge.
- The agent root needs its own NAT Gateway and public IP while it exists (interim, ADR-0007).
- The registration token is a personal access token that expires (30 days; about 2026-11-28). It is the
  weakest link: a person's credential, not a managed identity, and rotated by hand.
- The pool, the token and the service connection are built in the portal, outside Terraform (exception
  to the repository rule, listed with the other portal-built Azure DevOps objects).
- A value known only to one terminal reached `apply` once. The variable has no default so an unset value
  stops Terraform, but a wrong value still passes; the check is the Agents tab and the VM's boot logs
  (runbook `ado-agent`).

## Unproven (to test, not assumed)

- That a "Managed identity" service connection can be created and used. The portal offers the type (observed
  2026-10-30) but none was created. It needs a federated credential on `id-ado-agent-shared`; whether the
  portal creates it or Terraform must is not confirmed, and a portal-made credential would have to be added
  to `platform/agent-identity`. If the connection cannot be made, the fallback is an app registration with
  workload identity federation scoped to Key Vault Secrets User, which weakens the reason for that decision.
- That a pipeline using that connection runs as the managed identity: one secret readable, a second denied.
- That the personal access token is used only during registration, and what the agent does after it expires.
- That the alternate package runs tasks that need Node 16 (the agent ships Node 24).
- That the service starts again after a reboot (the unit is enabled; no reboot was done).
- That the apply identity is refused the Secrets User assignment, as ADR-0013's condition implies.
- What `DownloadSecureFile@1` or a multi-line key read through `AzureKeyVault@2` does to a private key.
- That the version check fails on a deliberately wrong version (not built yet).

## Enterprise equivalent

An identity team would own the managed identity and its role assignments in a reviewed Terraform layer,
with the Azure DevOps service connection created through the Azure DevOps provider, so no object is built
by hand, and registration would use a managed identity or a workload identity instead of a personal token.
