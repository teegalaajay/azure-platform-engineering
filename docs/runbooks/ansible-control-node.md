# Runbook: Ansible control node and first playbook

**Purpose:** Set up the Ansible control node, reach a target over SSH, and run a playbook from `ansible/` (ADR-0016).
**Owner:** platform-team · **Last validated:** 2026-10-19 (venv build, ping, two-run idempotency check against the sandbox target) · **Persistent:** no (the control node is the operator workstation; the target VM is destroyed after each session)

## 1. Layout

| Piece | Where | What it does |
|---|---|---|
| Pinned dependencies | `ansible/requirements.txt` | Exact `ansible-core` version; changed only through a PR |
| Playbooks | `ansible/playbooks/` | Playbooks; the host is chosen by inventory at run time, never in the playbook |
| Control node | Operator workstation (WSL2 Ubuntu) | Runs `ansible-playbook`; connects to targets over SSH |
| Target | Sandbox VM from `azure-iac-sandbox` (`w4d1-ansible-target`) | Public IP, SSH allowed only from the operator /32 (ADR-0016) |

No inventory file, IP address or key is committed.

## 2. Build the control node

```bash
python3 -m venv ~/.venvs/ansible            # isolated Python environment (Ubuntu blocks system-wide pip, PEP 668)
source ~/.venvs/ansible/bin/activate        # puts this venv's ansible on PATH
pip install -r ansible/requirements.txt     # installs the pinned versions
ansible --version                           # confirm the pinned ansible-core
```

## 3. Load the SSH key

The key has a passphrase, and Ansible cannot prompt for it, so load it into an agent first.

```bash
eval "$(ssh-agent -s)"    # starts an agent for this shell
ssh-add ~/.ssh/id_ed25519 # asks for the passphrase once
```

## 4. Check connectivity, then run

```bash
ansible all -i "<target-ip>," -u azureuser -m ping                       # ad-hoc reachability test
ansible-playbook -i "<target-ip>," -u azureuser ansible/playbooks/first.yml   # run the playbook
```

Run the playbook twice. First run: `changed=1`. Second run: `changed=0`. A second run that still changes something is not idempotent and must be fixed.

## 5. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Permission denied (publickey)` with `ssh_askpass` | Key has a passphrase and no agent holds it | Section 3 |
| `Connection timed out` | Operator public IP changed; NSG rule allows the old /32 | Update `operator_ip_cidr` in the sandbox and apply |
| Interpreter discovery warning | Python path not pinned | Informational for Ubuntu 24.04; pin `ansible_python_interpreter` later in inventory |

## 6. Teardown

`terraform destroy` in `w4d1-ansible-target` (sandbox repo). The target holds no state worth keeping; the playbooks are the source of truth.
