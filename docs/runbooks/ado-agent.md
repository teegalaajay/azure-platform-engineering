# Runbook: Azure DevOps self-hosted agent

**Purpose:** Bring up, verify, use, take down and troubleshoot the self-hosted Azure DevOps agent (ADR-0024): a VM in `snet-mgmt` that registers into `pool-platform-shared` and reads Key Vault through a user-assigned managed identity.
**Owner:** platform-team · **Last validated:** 2026-10-29 (agent registered and showed Online after one VM replacement; destroyed the same evening; no job was run on it).

Statements marked *observed* were seen on 2026-10-29; *reasoned* means derived, not tested.

## 1. Layout

| Piece | Where | What it does |
|---|---|---|
| Identity (persistent) | `platform/agent-identity` (key `platform/agent-identity.tfstate`) | `id-ado-agent-shared` (user-assigned) and Key Vault Secrets User on `kv-plat-shared-at01`; hand-applied (ADR-0024) |
| Agent VM (ephemeral) | `platform/ado-agent` (key `platform/ado-agent.tfstate`), `modules/ado-agent-vm` | `vm-adoagent-shared` in `snet-mgmt` at `10.20.3.11`, own NAT Gateway and public IP; cloud-init installs the agent as the non-root user `agent` |
| Pool | Azure DevOps portal, `pool-platform-shared` | the self-hosted pool; created by hand |
| Registration token | Key Vault secret `ado-agent-pat` | personal access token, scope Agent Pools: Read & manage, 30 days; value set with `az`, never in Terraform |
| Organization URL | `TF_VAR_ado_organization_url` in `~/.bashrc` | `https://dev.azure.com/<organization>`; required, no default |

The agent root cannot be live together with `platform/runner` (one NAT Gateway per subnet; reasoned from ADR-0007).

## 2. Bring it up

Check first, each as its own command:

1. `echo "$TF_VAR_ado_organization_url"` prints the real URL, not a placeholder (a placeholder cost a full rebuild on 2026-10-29).
2. `az group exists --name rg-runner-shared` prints `false`.
3. `platform/agent-identity` is applied (plan shows `No changes`).
4. The token has not expired: Azure DevOps, User settings, Personal access tokens (expiry about 2026-11-28).

Then, in `platform/ado-agent`: `terraform plan -out=ado-agent.tfplan`, read it (expect 7 to add on a fresh bring-up), then `terraform apply ado-agent.tfplan`. Name saved plans with the `.tfplan` suffix; they hold sensitive values and the `.gitignore` rule covers only that suffix.

## 3. Verify

Wait about three minutes after the apply (cloud-init took about two minutes to finish; observed).

1. The pool's Agents tab shows `vm-adoagent-shared` as **Online**. Offline right after boot is normal until the listener connects (observed: Offline in a screenshot, Online later).
2. Cloud-init finished without an error: `az vm run-command invoke --resource-group rg-ado-agent-shared --name vm-adoagent-shared --command-id RunShellScript --scripts 'cloud-init status --long'` shows `status: done` and `errors: []`.
3. The service is running: the same command with the script `systemctl status 'vsts.agent.*' --no-pager` shows `active (running)` and, in the journal lines, `Listening for Jobs`.

Registered and Online are different states: `config.sh` only creates the record; Online needs the running listener.

## 4. Use it

Point a pipeline job at the pool with `pool: name: pool-platform-shared`. A new pipeline is not allowed to use the pool until someone permits it once (the run waits at a prompt; observed 2026-10-30): permit one pipeline at a time, never the whole project, because every permitted pipeline runs commands on the VM with its identity.

The check pipeline is `ado-agent-check` (`pipelines/ado-agent-check.yml`, manual runs only). It prints the user and uid and lists Key Vault secret names through the VM's identity. A green run on 2026-10-30 showed user `agent`, uid 1001, and three secret names. The Key Vault service connection of type Managed identity is not built (ADR-0024, Unproven).

## 5. Take it down (same day)

1. In `platform/ado-agent`: `terraform plan -destroy -out="$HOME/ado-agent-destroy.tfplan"` (outside the repository; a saved plan holds sensitive values, and `.gitignore` ignores only names containing `tfplan`: a file called `tfdestroy` was not ignored on 2026-10-29); expect `0 to add, 0 to change, 7 to destroy`.
2. `terraform apply ado-agent-destroy.tfplan`.
3. `az group exists --name rg-ado-agent-shared` prints `false` (observed 2026-10-29).
4. Delete both saved plan files. The agent's record in the pool stays listed as Offline; the next registration uses `--replace` and takes the name over (reasoned from the flag's purpose, observed only for the first boot).

`platform/agent-identity` stays: it is persistent and costs nothing.

## 6. Troubleshooting

The Agents tab says only that no registration arrived. Read the VM's own records without SSH: `az vm run-command invoke` runs a script as root through the Azure control plane. In this order, each result narrows the next:

| Step | Script to run on the VM | What it shows |
|---|---|---|
| 1 | `cloud-init status --long` | whether the boot script finished and which stage failed (`scripts_user` = a command in our script returned non-zero) |
| 2 | `tail -n 40 /var/log/cloud-init-output.log` | the failing command and its message |
| 3 | `tail -n 30 /opt/ado-agent/_diag/Agent_<timestamp>.log` | the agent's own stack trace; the first failing call names the cause |
| 4 | `grep -rIn -E "(--url\|--pool\|INPUT_URL\|INPUT_POOL)" /var/lib/cloud/instance/` then `grep -n -E "ORG_URL=\|POOL=\|AGENT_NAME=" /var/lib/cloud/instance/user-data.txt` | the values Terraform rendered into the boot script |

| Symptom | Observed or reasoned | Cause and fix |
|---|---|---|
| Agents tab empty; `>> Connect: The resource cannot be found`; stack trace `GetConnectionData(serverUrl)` | observed 2026-10-29 | the organization URL is wrong (a placeholder): set `TF_VAR_ado_organization_url`, plan (one VM replaced), apply |
| `E: Unable to locate package libicu76` in the boot log | observed | noise: Ubuntu 24.04 has `libicu74`, already installed; the dependency step finished |
| Tab shows Offline right after the apply | observed | the listener had not connected yet; refresh after a few minutes; then check `systemctl status` |
| Registration refused with an authorization error | reasoned | the token expired or lacks Agent Pools: Read & manage: create a new one and replace the Key Vault secret (section 7) |
| Boot script cannot read the secret | reasoned | role or firewall: the identity needs Secrets User on the vault and the VM must be in `snet-mgmt` |
| Plan wants to create the NAT Gateway but one exists | reasoned | `platform/runner` is live; destroy it first |
| `plan` or the state lock fails with 403 `AuthorizationPermissionMismatch` while reads (`az storage blob list --auth-mode login`) work | observed 2026-10-30 | the subscription is read-only: check `az rest --method get --url "https://management.azure.com/subscriptions/$ARM_SUBSCRIPTION_ID?api-version=2022-12-01" --query state`; the cause that day was an exhausted free credit (`ReadOnlyDisabledSubscription`), cleared by upgrading the subscription; the state field took about 5 minutes to read `Enabled`, and `az login` was needed to refresh the CLI's subscription list |

## 7. Change

- **Rotate the token:** create a new personal access token (scope Agent Pools: Read & manage), then replace the Key Vault secret `ado-agent-pat` with `az keyvault secret set` from a silent prompt, never as text in a file or chat. The exact command shape was not recorded on 2026-10-29.
- **Change the boot script:** edit `modules/ado-agent-vm`; the plan shows the VM as `forces replacement` because `custom_data` changed (observed 2026-10-29).
- **Bump the agent:** change `agent_version` and `agent_sha256` together; verify the hash against the release page before the apply.
- **Anything done by hand on the VM** must be folded back into Terraform or cloud-init before the day counts as done.
