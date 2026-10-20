# Runbook: Ansible control node and playbooks

**Purpose:** Set up the Ansible control node, reach a target over SSH, and run the playbooks in `ansible/` (ADR-0016): `first.yml` (idempotency check) and `web.yml` (nginx web server).
**Owner:** platform-team · **Last validated:** 2026-10-20 (venv build, ping, `first.yml` twice, `web.yml` task by task and drift repair against the sandbox target) · **Persistent:** no (the control node is the operator workstation; the target VM is destroyed after each session)

## 1. Layout

| Piece | Where | What it does |
|---|---|---|
| Pinned dependencies | `ansible/requirements.txt` | Exact `ansible-core` version; changed only through a PR |
| Playbooks | `ansible/playbooks/` | Playbooks; the host is chosen by inventory at run time, never in the playbook |
| Templates | `ansible/playbooks/templates/` | Jinja2 sources for `template` tasks; a relative `src` is looked up here |
| Control node | Operator workstation (WSL2 Ubuntu) | Runs `ansible-playbook`; connects to targets over SSH |
| Target | Sandbox VM from `azure-iac-sandbox` (`w4d1-ansible-target`) | Public IP; SSH (22) and HTTP (80) allowed only from the operator /32 (ADR-0016) |

No inventory file, IP address or key is committed.

## 2. Build the control node

```bash
python3 -m venv ~/.venvs/ansible            # isolated Python environment (Ubuntu blocks system-wide pip, PEP 668)
source ~/.venvs/ansible/bin/activate        # puts this venv's ansible on PATH
pip install -r ansible/requirements.txt     # installs the pinned versions
ansible --version                           # confirm the pinned ansible-core
```

## 3. Load the SSH key

The key has a passphrase, and Ansible cannot prompt for it, so load it into an agent first. An agent belongs to one shell: every new terminal needs this again.

```bash
eval "$(ssh-agent -s)"           # starts an agent for this shell
ssh-add ~/.ssh/azlab_ed25519     # asks for the passphrase once
```

## 4. First contact with a rebuilt target

A rebuilt VM has a new SSH host key. Ansible runs SSH without a terminal, so it cannot answer the "continue connecting?" prompt and fails with `Host key verification failed`. Connect once by hand and accept the key:

```bash
IP=$(terraform output -raw public_ip)   # run in the sandbox target folder
ssh azureuser@"$IP" hostname            # type yes when asked; the key is stored in known_hosts
```

This is trust on first use: the first connection trusts whatever answers on that IP, so an impostor on the path at that moment would go undetected. That is accepted for a throwaway VM created seconds earlier. Do not disable host key checking (`ANSIBLE_HOST_KEY_CHECKING=False`): that also hides a changed key on every later connection.

## 5. Check connectivity, then run

```bash
ansible all -i "$IP," -u azureuser -m ping                                  # ad-hoc reachability test
ansible-playbook -i "$IP," -u azureuser ansible/playbooks/first.yml        # idempotency check
ansible-playbook -i "$IP," -u azureuser ansible/playbooks/web.yml --check --diff   # preview, writes nothing
ansible-playbook -i "$IP," ansible/playbooks/web.yml --list-tags                   # labels only, contacts nothing
ansible-playbook -i "$IP," -u azureuser ansible/playbooks/web.yml --tags content   # one slice; Gathering Facts still runs
ansible-playbook -i "$IP," -u azureuser ansible/playbooks/web.yml          # apply
```

The trailing comma after the IP makes Ansible read the value as a host list; without it the value is treated as an inventory file name.

`web.yml` installs nginx (`apt`, with `cache_valid_time`), makes sure it is started and enabled (`service`), renders the landing page from `templates/index.html.j2` (`template`) and renders an nginx response-header snippet to `/etc/nginx/conf.d/headers.conf`. `become: true` is set on the play because every task changes system state.

Values come from the play's `vars:` (`web_root`, `web_owner`, `site_title`); `-e name=value` overrides them. A `template` task renders the `.j2` file on the control node, and the checksum comparison is between that rendered text and the file on the target. The snippet task notifies the handler `Reload nginx`, which runs once at the end of the play and only when the snippet changed. `force_handlers: true` makes an already notified handler run even if a later task fails (ADR-0017). Each task has one tag (`packages`, `service`, `content`, `config`); `--tags` selects tasks, and a task that notifies a handler must be selected for the handler to be notified.

Gate before any run, in its own step: `yamllint --strict ansible/` and `ansible-playbook --syntax-check -i "$IP," ansible/playbooks/web.yml`. Neither reads the `.j2` files, so an undefined variable inside a template is found only at run time (see section 7).

Expected results:

- Fresh VM: the `apt` and `copy` tasks report `changed`. The `service` task is expected to report `ok`, because the Ubuntu package starts and enables nginx itself (observed on the 24.04 image). The full first run on a fresh VM has not been observed end to end yet.
- Second run: `changed=0`. A second run that still changes something is not idempotent and must be fixed.
- Check mode compares state and writes nothing, and it does not take the package lock, so it can pass without `become`. Only a real run proves privileges.

## 6. Verify on the target, not from Ansible's report

```bash
ssh azureuser@"$IP" dpkg -s nginx                       # package installed
ssh azureuser@"$IP" systemctl is-active nginx           # running now
ssh azureuser@"$IP" systemctl is-enabled nginx          # starts at boot
curl -m 5 -I http://"$IP"                               # HTTP 200 from nginx
curl -s http://"$IP"/                                   # rendered page, hostname filled in
curl -sI http://"$IP"/                                  # X-Platform header: present only after nginx reloaded
ssh azureuser@"$IP" cat /etc/nginx/conf.d/headers.conf  # what is on disk (compare with the header served)
```

Drift repair: if the page is edited on the target, the next run reports `changed=1` and restores the repo version (in `--check --diff`, a `-` line exists only on the target, a `+` line only in the rendered output).

## 7. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Permission denied (publickey)` with `ssh_askpass` | Key has a passphrase and no agent holds it (new shell), or the login user is wrong | Section 3; pass `-u azureuser` |
| `Host key verification failed` with `ssh_askpass` | First contact with a rebuilt VM; no stored host key | Section 4 |
| `Unable to parse ... as an inventory source` | `-i` value has no trailing comma, so it is read as a file name | Write `-i "$IP,"` |
| `Could not open lock file /var/lib/dpkg/lock-frontend ... Permission denied`, `rc: 100` | Task ran as `azureuser`; `apt` needs root | Set `become: true` on the play |
| `curl: (7)` returned at once | Port 80 is open but nothing is listening | Install or start nginx (section 5) |
| `curl` waits until the timeout |  Expected, not yet reproduced: the NSG drops the packet; the port 80 rule is missing or the operator /32 changed | Apply the sandbox rule `allow-http-operator`; update `operator_ip_cidr` |
| Interpreter discovery warning | Python path not pinned | Informational for Ubuntu 24.04; pin `ansible_python_interpreter` later in inventory |
| `'site_owner' is undefined`, `changed: false`, `Origin:` points at a `.j2` file | A template uses a variable that is not defined. Rendering happens on the control node at run time; `--syntax-check` and `yamllint` do not read `.j2` files. Observed also with `--check` | Define the variable or fix the name. Nothing was written to the target (page unchanged, observed) |
| File on the target has the new value but nginx still serves the old one | A task after the notifying task failed and the handler was skipped; the next run reports `ok` and notifies nothing (observed) | Keep `force_handlers: true` (ADR-0017). To repair a host that is already stale, make the snippet report `changed` again |

## 8. Teardown

`terraform destroy` in `w4d1-ansible-target` (sandbox repo). The target holds no state worth keeping; the playbooks are the source of truth.
