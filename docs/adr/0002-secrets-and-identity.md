# ADR-0002: Secrets and identity

- **Status:** Accepted
- **Date:** 2026-09-29
- **Deciders:** platform-team (@teegalaajay)

## Context

The platform is deployed by people (from a workstation) and by automation (GitHub Actions,
Azure DevOps agents, Ansible). Each needs to authenticate to Azure, to the Terraform state
backend and sometimes to third-party services. Long-lived secrets (client secrets, storage
account keys, personal access tokens) leak through files, logs, chat and backups, and must be
rotated by hand. In a regulated environment every credential must have a known location, an
owner and a way to revoke it.

## Options considered

1. **Secrets in CI secret stores and tfvars files.** Simple, but every consumer holds a
   long-lived copy and rotation touches many places.
2. **Everything in Key Vault.** One store, but Key Vault itself must be reached with a
   credential, and it cannot exist before the platform is bootstrapped.
3. **Identity first, Key Vault for what remains, never in files.**

## Decision

Option 3, as three tiers applied in order.

**Tier 1 — no secret at all (preferred):**
- GitHub Actions → Azure: OpenID Connect federation, with credentials scoped by subject; a
  plan-only identity for pull requests and a separate apply identity reachable only through a
  protected environment.
- Azure DevOps → Azure: workload identity federation service connections.
- VMs and self-hosted agents → Azure: managed identity.
- Terraform → state storage: Entra ID auth (`use_azuread_auth = true`, Storage Blob Data
  Contributor); storage account keys are not used.

**Tier 2 — unavoidable secrets go to Key Vault:** e.g. the Ansible Vault password or an agent
registration token. Key Vault uses RBAC authorisation, soft-delete and purge protection, and a
network ACL allowing only the operator IP and `snet-mgmt`. Consumers read secrets at runtime with
their own identity. Bootstrap does not depend on Key Vault because it is identity-based.

**Tier 3 — never:** committed files, plain `terraform.tfvars`, plaintext pipeline variables,
logs or chat. Non-secret values go in committed `*.auto.tfvars`; secrets reach Terraform only
through `TF_VAR_*` environment variables or Key Vault.

**Terraform state and saved plan files are secret-bearing.** Both contain resource attributes
and variable values in plaintext (`sensitive = true` only hides them from output), so they are
stored only in the access-controlled state backend or short-lived protected pipeline storage,
never committed or published as public artifacts.

## Consequences

- Most credentials are short-lived tokens issued at runtime; there is nothing to rotate or leak
  for Tier 1 consumers.
- Enforcement: `.gitignore` excludes state, plans and tfvars; pre-commit runs `gitleaks` on
  every commit.
- **Known workstation residuals (accepted, revocable):** the GitHub CLI token is stored in
  plaintext in `~/.config/gh/hosts.yml` (mode 600) and the Azure CLI token cache in `~/.azure/`.
  Git credentials are stored in the OS credential manager, not in a file. Each credential is
  listed with its revocation step in the workstation runbook.
- Key Vault becomes a persistent dependency for Tier 2 consumers and needs its own runbook
  (recovery, access review).
