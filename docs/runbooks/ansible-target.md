# Runbook: Ansible target and the Ansible pipeline

**Purpose:** Bring up, run, verify, rotate and take down the platform Ansible target (`workloads/ansible-target/dev`) and the
Azure DevOps pipeline `ado-ansible-run` that configures it from the self-hosted agent (ADR-0029).
**Owner:** platform-team · **Last validated:** 2026-11-02 (target and agent built from the feature branch; four pipeline
runs; the `web` role applied and then a second run changed nothing).

Statements marked *observed* were seen on 2026-11-02; *reasoned* means derived, not tested.

## 1. Layout

| Piece | Where | What it does |
|---|---|---|
| Target (ephemeral) | `workloads/ansible-target/dev` (key `workloads/ansible-target/dev.tfstate`), `modules/linux-vm` | `vm-ansible-target-dev` in `snet-app` at `10.10.1.11`, zone 2, no public IP; own NAT Gateway and public IP for outbound `apt`; in `SKIP_ROOTS`, applied by hand |
| Agent (ephemeral) | `platform/ado-agent` (runbook `ado-agent`) | runs the pipeline in `pool-platform-shared`; cloud-init installs `python3-venv` |
| Pipeline | Azure DevOps portal, name `ado-ansible-run`, YAML `pipelines/ado-ansible-run.yml` (portal-built) | install pinned Ansible, read the key, run `site.yml` twice, remove the key |
| Pipeline key, public half | `ansible_ssh_public_key` in `workloads/ansible-target/dev/dev.auto.tfvars` | the only login the target accepts; a public key is not a secret |
| Pipeline key, private half | Key Vault `kv-plat-shared-at01`, secret `ansible-pipeline-ssh-key` | created with `az keyvault secret set --file`; read through `sc-azure-keyvault-shared` |
| Test secret | Key Vault secret `ado-multiline-canary` | a made-up three-line value, kept as a fixture for the multi-line secret test |
| Ansible pin | `ansible/requirements-pipeline.txt` and `ansible/constraints.txt` | `ansible-core==2.21.5`, equal to `requirements.txt` (the pipeline asserts it) |
| Pipeline config | `ansible/ansible-pipeline.cfg` | no vault settings; `interpreter_python = /usr/bin/python3` |

## 2. Bring it up

1. Pre-flight, each as its own command: `git status -sb` clean and level; `az rest` on the subscription prints `Enabled`;
   `az group exists` is `false` for `rg-ansible-target-dev`, `rg-ado-agent-shared` and `rg-runner-shared`;
   `az network vnet subnet show ... -n snet-app --query natGateway.id -o tsv` prints nothing.
2. In `workloads/ansible-target/dev`: `terraform init`, `terraform plan` (expect 7 to add), `terraform apply`, then
   `terraform plan` again: `No changes`.
3. Bring up the agent (runbook `ado-agent`, section 2). `TF_VAR_ado_organization_url` must be the real URL.
4. Check the path, from the agent: `az vm run-command invoke -g rg-ado-agent-shared -n vm-adoagent-shared
   --command-id RunShellScript --scripts 'timeout 5 bash -c "</dev/tcp/10.10.1.11/22"; echo "rc=$?"'` prints `rc=0`.

## 3. Run it

1. First time only, in the portal: New pipeline, GitHub, the repository, Existing Azure Pipelines YAML file,
   `/pipelines/ado-ansible-run.yml`, Save (not Run), rename to `ado-ansible-run`.
2. Run pipeline, the branch, `targetHost` = the target's private address. The first run asks for a permit on the pool; the
   first run that reads Key Vault asks for one on `sc-azure-keyvault-shared` (both observed). Click View and check the
   dialog names only that item.
3. A green run means: Ansible installed at the pinned version; the key matched the recorded fingerprint; run 1 applied
   the role; run 2 reported `changed=0 unreachable=0 failed=0`; the key file was removed and checked.

## 4. Verify the result (from inside the VM)

`az vm run-command invoke -g rg-ansible-target-dev -n vm-ansible-target-dev --command-id RunShellScript --scripts
'systemctl is-active nginx; curl -si http://localhost/ | head -n 20'` prints `active`, `HTTP/1.1 200 OK`, the header
`X-Platform: Sandbox Reference Platform v3` and the page title (observed). The NSG allows HTTP only from the operator
address, so the check runs inside the VM.

## 5. Rotate the key

Generate a new pair, store the private half as a new version of `ansible-pipeline-ssh-key`, replace
`ansible_ssh_public_key` in `dev.auto.tfvars`, and merge through a pull request. The changed key replaces the VM
(reasoned from the `admin_ssh_key` argument; not tested). Check the stored key before deleting the local copy: derive the
public half with `ssh-keygen -y` from the secret and compare it with the `.pub` file (observed on 2026-11-02).

## 6. Take it down (same day)

1. In `workloads/ansible-target/dev`: `terraform destroy` (expect 7 to destroy); `az group exists -n rg-ansible-target-dev`
   prints `false`; `snet-app` has no NAT Gateway attached.
2. Take down the agent (runbook `ado-agent`, section 5).
3. The Key Vault secrets stay. The local private key file is deleted after the secret is stored.

## 7. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `ansible: error: argument --ssh-common-args: expected one argument` and the full usage text | a value starting with `-` after a space is read as the next option | write `--ssh-common-args="..."` (observed) |
| `Vault password client script ... returned non-zero ... Please run 'az login'` | Ansible runs the vault script of the root `ansible.cfg` at startup, even with nothing encrypted | the step sets `ANSIBLE_CONFIG` to `ansible/ansible-pipeline.cfg` (observed) |
| `Permission needed` on a pool or a service connection | permits are per pipeline | View, check the one item named, Permit |
| `python3 -m venv` fails, `ensurepip is not available` | `python3-venv` is not installed | it is in the agent's cloud-init; rebuild the agent (observed on the target image) |
| `Executable ansible-lint not found` at commit | the hook uses the venv copy and no venv is active | `source ~/.venvs/ansible/bin/activate` (observed) |
| `empty-playbook` for `molecule/default/converge.yml` at commit | a stray empty file in the working tree; lint reads untracked files | delete the file (observed) |
| The agent shows Offline | cloud-init still running, or the registration token expired | `ado-agent`, section 3 |

## 8. Change

Edits to the pipeline go through a pull request; the pipeline is not run from a branch on purpose, because it has no
environment and Branch control does not apply (ADR-0029). Adding vault data to a pipeline run means adding
`vault_identity_list` to `ansible/ansible-pipeline.cfg` and giving the agent a sign-in (Week 7).
