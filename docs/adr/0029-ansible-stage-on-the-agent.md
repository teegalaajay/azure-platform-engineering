# ADR-0029: Ansible stage on the self-hosted agent

- **Status:** Proposed (accepted on merge)
- **Date:** 2026-11-02
- **Deciders:** platform-team (@teegalaajay)
- **Relates to:** ADR-0016 (the platform target was deferred until an in-network control path exists); ADR-0024 (the
  agent and its Key Vault access); ADR-0007 (subnets and NSG rules); ADR-0020 (Vault); ADR-0021 (lint); ADR-0025 (drift
  checks); ADR-0026 (the pipelines and the public-repository rule); runbook `ansible-target`

## Context

ADR-0016 deferred a platform Ansible target in `snet-app` until something inside the network could reach it. The
self-hosted agent in `snet-mgmt` (ADR-0024) is that path. Week 6 Day 4 needs a pipeline job that runs the existing
`web` role against a VM with no public IP. The job must not hold a secret in the repository, must not be startable by a
pull request (the repository is public, ADR-0026), and must leave no key on the agent afterwards.

## Options considered

1. **Target:** (a) a new root `workloads/ansible-target/dev`; (b) reuse `workloads/vm-demo/dev`.
2. **Pipeline:** (a) a standalone `pipelines/ado-ansible-run.yml`; (b) a stage inside `ado-terraform-deploy`.
3. **Ansible on the agent:** (a) `python3-venv` in cloud-init, the venv and a pinned `ansible-core` built in each run;
   (b) the venv baked into cloud-init.
4. **Public key:** (a) committed in `dev.auto.tfvars`; (b) an environment variable on the workstation, in `plan.yml`
   and in the pipeline.
5. **Private key in Key Vault:** (a) the raw multi-line file; (b) base64 on one line.
6. **Host key:** (a) `StrictHostKeyChecking=accept-new` with a known-hosts file in the job's temp folder; (b) pin the
   key read from the VM.
7. **Vault script at startup:** (a) a pipeline-only config file without the vault settings; (b) sign in with
   `az login --identity` before every run.
8. **Lint scope:** (a) exclude `pipelines/` in `.ansible-lint`; (b) shorten the over-long lines.

## Decision

Option (a) in every case.

1. **New root `workloads/ansible-target/dev`**, built on the `vm-demo` pattern: a resource group, `modules/linux-vm`
   in `snet-app` at `10.10.1.11`, no public IP, and its own NAT Gateway (interim egress, ADR-0007). It is in
   `SKIP_ROOTS`: applied by hand until Day 5. *Cost:* about 70 lines that repeat the `vm-demo` NAT block; one more root
   with its own state key.
2. **A standalone pipeline `ado-ansible-run`:** manual only (`trigger: none`, `pr: none`), one job on
   `pool-platform-shared`, one required parameter `targetHost` that is written to an environment variable and checked
   against `10.10.1.x` before use. *Cost:* a second portal-built pipeline definition (an exception to "everything in
   code"), with a permit on the pool and one on `sc-azure-keyvault-shared`. It has no environment, so Branch control
   (ADR-0027) does not apply: a run from any branch can use the key. It is manual, and the agent exists only while it
   is applied.
3. **`python3-venv` in cloud-init** (one line after the shared block, so the drift check of ADR-0025 is unaffected) and
   a venv created per run from `ansible/requirements-pipeline.txt` under `ansible/constraints.txt`. The step fails
   unless the installed version equals the `ansible-core` pin in `requirements.txt`. *Cost:* install time and PyPI
   access through the NAT on every run; the version is named in two files and checked at run time, not at commit.
4. **The pipeline key's public half is committed** in `workloads/ansible-target/dev/dev.auto.tfvars`
   (`ansible_ssh_public_key`), so the workstation, CI and Azure DevOps read the same value. *Cost:* a key rotation is a
   pull request and replaces the VM; the public repository shows a line labelled `ansible-pipeline`. A public key is
   not a secret (the private half exists only in Key Vault). This replaces the first design of the variable
   (an environment variable, "never committed").
5. **The private half is the Key Vault secret `ansible-pipeline-ssh-key`,** stored from the file with
   `az keyvault secret set --file`, read by `AzureKeyVault@2` through `sc-azure-keyvault-shared`, written to a file
   under `umask 077` in the job's temp folder, checked with `ssh-keygen -y`, and removed by a step with
   `condition: always()` that also asserts the file is gone. The secret is created by CLI, not Terraform (an exception,
   like `ado-check-canary`). *Cost:* a multi-line secret; the test below is what showed it is safe in the logs.
6. **`accept-new`** with `UserKnownHostsFile` in the temp folder. *Cost:* trust on first use inside each run: whatever
   answers at the address on the first connection is trusted for that run. The path is agent, peering, an NSG that
   allows only `snet-mgmt`. The target is rebuilt every session, so a pinned key would change anyway.
   `ANSIBLE_HOST_KEY_CHECKING=False` is not used.
7. **`ansible/ansible-pipeline.cfg`** has no vault settings, and the Ansible step sets `ANSIBLE_CONFIG` to it, with
   `interpreter_python = /usr/bin/python3`. *Cost:* a second config that can drift from the root `ansible.cfg`; the
   vault settings must be added when a pipeline run needs encrypted data (Week 7).
8. **`pipelines/` is excluded** in `.ansible-lint` (amends ADR-0021). *Cost:* the Ansible hook no longer checks the
   Azure DevOps YAML; `yamllint` reports lines over 120 characters as warnings only, so nothing blocks them.

The role is run twice by one step; the second run is piped through `tee` and the step fails unless its recap contains
`changed=0 unreachable=0 failed=0`. No `--check` run is used (reasoned below).

## Observed (2026-11-02)

- **Target root:** `terraform apply` created 7 resources; the next `plan` said `No changes`. `az vm show -d`: VM running,
  private `10.10.1.11`, no public IP, zone 2. It was destroyed and rebuilt once; after the destroy
  `az group exists` was `false` and `snet-app` had no NAT Gateway attached.
- **Python on the image:** `az vm run-command` on the target: Python 3.12.3, and `python3 -m venv` failed with exit
  code 1 because `ensurepip` is missing (the message names `python3.12-venv`).
- **Agent:** rebuilt from the feature branch (7 added); cloud-init `done`, the bootstrap marker present, the service
  `active (running)`, the agent Online in the portal. `bash scripts/check-cloud-init-drift.sh`: identical, 9 lines.
- **Network:** from the agent, a TCP connection to `10.10.1.11:22` completed (`rc=0`).
- **Pipeline runs:** `#20261102.1`: a permit prompt for the pool `pool-platform-shared`; the venv was created and
  `ansible-core wanted: 2.21.5, installed: 2.21.5`. `#20261102.2`: a permit prompt for `sc-azure-keyvault-shared`.
- **Multi-line secret** (a made-up three-line canary `ado-multiline-canary`): length 50, 3 lines, `cat -A` showed
  three line ends; the log masked each line as `***` in the raw dump and in a plain `echo`. A hyphenated secret name
  worked as `$(name)` in an environment mapping.
- **Real key:** `#20261102.3`: `ssh-keygen -y` printed the fingerprint recorded at key generation; the removal step ran.
- **Failure 1** (`#20261102.4`): `ansible: error: argument --ssh-common-args: expected one argument`; the value began
  with a dash, so the parser took it for an option. Fixed with `--ssh-common-args="..."` (one token).
- **Failure 2** (`#20261102.5`): Ansible ran the vault client script of the root `ansible.cfg` at startup, before any
  connection, and it failed (`Please run 'az login'`). Fixed with `ANSIBLE_CONFIG` (decision 7).
- **Ping:** `ansible.builtin.ping` returned `pong` with the key from Key Vault; the host key was accepted; Ansible
  warned about interpreter discovery, which `interpreter_python` removed.
- **The role** (`#20261103.1`): run 1 `ok=6 changed=4`, run 2 `ok=5 changed=0 unreachable=0 failed=0`; `azureuser` had
  working `sudo`. `systemctl is-active nginx` printed `active`; `curl` from inside the VM returned `200 OK` with the
  rendered page and the header `X-Platform: Sandbox Reference Platform v3` (the ` v3` is literal text in
  `headers.conf.j2`, from Week 4).
- **Lint hook:** the first commit that touched `ansible/` failed with three findings: an empty `molecule/default/
  converge.yml` at the repository root (untracked, origin unknown, deleted), and lines of 133 and 122 characters in
  `pipelines/ado-agent-check.yml`.

## Reasoned (not tested)

- The two long lines had failed lint since PR #36. The hook runs the whole repository, but only on commits that touch
  `ansible/`, and this was the first such commit since the `pipelines/` folder existed.
- A `--check` run on a fresh target would fail at the service task, because the nginx unit does not exist yet.
- With the real key, the `BEGIN` and `END` lines would be masked separately. The real key was never printed, so this is
  not observed.
- Masking matches exact text: a transformed copy of a secret (for example base64) would not be masked (read).
- `ado-agent-check` got no permit prompt for `sc-azure-keyvault-shared` on 2026-10-30; this pipeline did. The cause of
  the difference is not known.

## Not tested

Secret names that contain dots; a run from `main` (Day 5); provisioning the target through a pipeline (Day 5); rotating
the key; an unset secret in this pipeline (the unset-macro behaviour was seen in ADR-0028, not here); another image.

## Consequences

- `sc-azure-keyvault-shared` is bound to `id-ado-agent-shared`, which has Key Vault Secrets User on the whole vault
  (ADR-0024). Any pipeline permitted on that connection can read every secret in `kv-plat-shared-at01`, including
  `ado-agent-pat` and the Vault password. The permit prompt is the control, and it is one click per pipeline.
- `ado-ansible-run` is built by hand in the portal, and the permits are per pipeline (documented in the runbook).
- The Key Vault secrets `ansible-pipeline-ssh-key` and `ado-multiline-canary` are created by CLI. The canary is a made-up
  value, kept as a test fixture like `ado-check-canary`.
- A commit that touches `ansible/`, `.ansible-lint` or `ansible.cfg` runs `ansible-lint` over the whole repository
  (`pass_filenames: false`), and needs `~/.venvs/ansible` active.
- The target address is typed per run until Day 5 takes it from a Terraform output.
- The target and the agent are ephemeral and bill until destroyed (a VM and a NAT Gateway each).
