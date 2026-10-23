# Runbook: Ansible control node and playbooks

**Purpose:** Set up the Ansible control node, reach a target over SSH, and run the code in `ansible/` (ADR-0016, ADR-0018, ADR-0019): `playbooks/first.yml` (idempotency check) and `site.yml`, which calls the role `roles/web` (nginx web server). Hosts can be given inline (`-i "$IP,"`) or found in Azure by the dynamic inventory (section 5b).
**Owner:** platform-team · **Last validated:** 2026-10-22 (role-based `site.yml` against the sandbox target: baseline run, variable precedence, template search order, tag slice; dynamic inventory: `compose`, `keyed_groups`, empty-match and unparsed-source behaviour) · **Persistent:** no (the control node is the operator workstation; the target VM is destroyed after each session)

## 1. Layout

| Piece | Where | What it does |
|---|---|---|
| Pinned dependencies | `ansible/requirements.txt` | Exact `ansible-core` version, plus `-r requirements-azure.txt`; changed only through a PR |
| Azure SDK list | `ansible/requirements-azure.txt` | The collection's own Python dependency list, copied verbatim (ADR-0019) |
| Lock file | `ansible/constraints.txt` | `pip freeze` of the venv after `pip check` (Python 3.12); every package at an exact version |
| Collection pin | `ansible/requirements.yml` | `azure.azcollection` `==4.1.0` from public Galaxy; installs to `~/.ansible/collections`, outside the repository |
| Dynamic inventory | `ansible/inventory/sandbox.azure_rm.yml` | The query only: resource group, `auth_source: cli`, `compose`, `keyed_groups`. No hosts, IPs or credentials |
| Entry playbook | `ansible/site.yml` | Sets the target (`hosts: all`), `become`, fact gathering and `force_handlers`, then calls the role. It sits next to `roles/` on purpose (section 5) |
| Standalone playbooks | `ansible/playbooks/` | `first.yml`; the host is chosen by inventory at run time, never in the playbook |
| Role | `ansible/roles/web/` | `tasks/main.yml`, `handlers/main.yml`, `templates/`, `defaults/main.yml`, `meta/main.yml`, `README.md`; no `vars/` (ADR-0018) |
| Control node | Operator workstation (WSL2 Ubuntu) | Runs `ansible-playbook`; connects to targets over SSH |
| Target | Sandbox VM from `azure-iac-sandbox` (`w4d1-ansible-target`) | Public IP; SSH (22) and HTTP (80) allowed only from the operator /32 (ADR-0016) |

The inventory file is a query, not a host list. No IP address, host name or key is committed.

## 2. Build the control node

```bash
python3 -m venv ~/.venvs/ansible            # isolated Python environment (Ubuntu blocks system-wide pip, PEP 668)
source ~/.venvs/ansible/bin/activate        # puts this venv's ansible on PATH
ansible-galaxy collection install -r ansible/requirements.yml   # azure.azcollection 4.1.0 into ~/.ansible/collections
pip install -r ansible/requirements.txt -c ansible/constraints.txt   # direct pins, held to the lock file
pip check                                   # expect: No broken requirements found.
ansible --version                           # confirm the pinned ansible-core
ansible-galaxy collection list azure.azcollection   # confirm 4.1.0
```

Installing the Azure SDK list replaced `cryptography` 50.0.2 with 47.0.0 on 2026-10-22 (observed). To bump the collection: change the pin, install into a fresh venv, run `pip check`, copy the new `requirements.txt` from the collection into `requirements-azure.txt`, regenerate `constraints.txt`, and re-run the `site.yml` baseline.

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
ansible-playbook -i "$IP," -u azureuser ansible/site.yml --check --diff    # preview, writes nothing
ansible-playbook -i "$IP," ansible/site.yml --list-tags                    # labels only, contacts nothing
ansible-playbook -i "$IP," ansible/site.yml --list-tasks                   # tasks with their tags, contacts nothing
ansible-playbook -i "$IP," -u azureuser ansible/site.yml --tags content    # one slice; Gathering Facts still runs
ansible-playbook -i "$IP," -u azureuser ansible/site.yml                   # apply
```

The trailing comma after the IP makes Ansible read the value as a host list; without it the value is treated as an inventory file name.

`site.yml` calls the role `web`, which installs nginx (`apt`, with `cache_valid_time`), makes sure it is started and enabled (`service`), renders the landing page from `templates/index.html.j2` (`template`) and renders an nginx response-header snippet to `/etc/nginx/conf.d/headers.conf`. `become: true` is set on the play because every task changes system state. Ansible finds the role because `roles/` sits next to the playbook that runs. A play kept in `ansible/playbooks/` did not find it (observed: `The role 'web' was not found`, with the five searched paths listed); `yamllint` passed on that file, and only `--syntax-check` showed the error.

The snippet task notifies the handler `Reload nginx`, which runs once at the end of the play and only when the snippet changed. `force_handlers: true` is set on the play and makes an already notified handler run even if a later task fails (ADR-0017). Each task has one tag (`packages`, `service`, `content`, `config`); the role name is not a tag (observed in `--list-tags`). `--tags` selects tasks, and a task that notifies a handler must be selected for the handler to be notified: `--tags content` ran the page task and no handler (observed, `ok=2 changed=1`).

Gate before any run, in its own step: `yamllint --strict ansible/` and `ansible-playbook --syntax-check -i "$IP," ansible/site.yml`. Neither reads the `.j2` files, so an undefined variable inside a template is found only at run time (see section 7).

Expected results:

- Fresh VM: the `apt` and both `template` tasks report `changed`, and the handler runs once. The `service` task is expected to report `ok`, because the Ubuntu package starts and enables nginx itself (observed on the 24.04 image).
- Second run: `changed=0`, `ok=5`. A second run that still changes something is not idempotent and must be fixed.
- Check mode compares state and writes nothing, and it does not take the package lock, so it can pass without `become`. Only a real run proves privileges.

## 5a. Variables and precedence

The role's settings are in `roles/web/defaults/main.yml`: `web_root`, `web_owner`, `site_title`. They have the lowest precedence, so any caller can override them. Observed with `site_title` set at four levels, the template received them in this order, lowest to highest: role `defaults/main.yml`, play `vars`, role `vars/main.yml`, `-e`. Consequence: a variable placed in a role's `vars/main.yml` would be ignored silently when a play sets it in `vars:`, which is why the role has no `vars/` directory (ADR-0018). The role name `web` also exists as a public Galaxy role: `ansible-galaxy role info web` printed that other record next to the local metadata (observed). Do not install roles by bare name.

A `template` task inside a role looks for its source in this order (observed from the error message when the role's `templates/` was hidden): `roles/web/templates/`, `roles/web/`, `roles/web/tasks/templates/`, `roles/web/tasks/`, `ansible/templates/`, `ansible/`. A file placed in `ansible/templates/` could therefore satisfy the task in place of a missing role file (reasoned from the list, not run).

## 5b. Dynamic inventory (Azure)

The inventory plugin runs on the control node, as the operator, through the `az login` token cache (`auth_source: cli`, ADR-0019). It calls Azure Resource Manager (read-only) before any task and builds hosts and groups in memory for that run. Nothing is stored.

```bash
az account show                                                             # the login must be live; the plugin uses it
ansible-inventory -i ansible/inventory/sandbox.azure_rm.yml --graph        # hosts and groups; no SSH
ansible-inventory -i ansible/inventory/sandbox.azure_rm.yml --host <name>  # every variable the plugin set for one host
ansible-playbook -i ansible/inventory/sandbox.azure_rm.yml ansible/site.yml   # no -u: ansible_user comes from compose
ansible-playbook -i ansible/inventory/sandbox.azure_rm.yml ansible/site.yml --limit env_sandbox
```

Rules:

- The file name must end in `azure_rm.yml` and the file must start with `plugin: azure.azcollection.azure_rm`; both are checked (observed).
- Host names are the VM name plus a suffix from the resource ID (`vm-ansible-target_9b90`). A rebuilt VM gets a new suffix. Select hosts by group or `all`, never by name.
- `compose` values are Jinja expressions: a string literal needs inner quotes (`"'azureuser'"`).
- `keyed_groups` with a key missing on the VM needs a default (`tags.role | default('unset')`), otherwise it prints an `[ERROR]`.
- The exit code does not report most inventory problems. After every run, read the screen for `[WARNING]` and `[ERROR]` lines and check that the recap lists a host. In automation set `ANSIBLE_INVENTORY_UNPARSED_FAILED=true`.

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
| `Unable to parse ... as an inventory source` (inline host) | `-i` value has no trailing comma, so it is read as a file name | Write `-i "$IP,"` |
| `Could not open lock file /var/lib/dpkg/lock-frontend ... Permission denied`, `rc: 100` | Task ran as `azureuser`; `apt` needs root | Set `become: true` on the play |
| `curl: (7)` returned at once | Port 80 is open but nothing is listening | Install or start nginx (section 5) |
| `curl` waits until the timeout |  Expected, not yet reproduced: the NSG drops the packet; the port 80 rule is missing or the operator /32 changed | Apply the sandbox rule `allow-http-operator`; update `operator_ip_cidr` |
| Interpreter discovery warning | Python path not pinned | Informational for Ubuntu 24.04; pin `ansible_python_interpreter` later in inventory |
| `'site_owner' is undefined`, `changed: false`, `Origin:` points at a `.j2` file | A template uses a variable that is not defined. Rendering happens on the control node at run time; `--syntax-check` and `yamllint` do not read `.j2` files. Observed also with `--check` | Define the variable or fix the name. Nothing was written to the target (page unchanged, observed) |
| File on the target has the new value but nginx still serves the old one | A task after the notifying task failed and the handler was skipped; the next run reports `ok` and notifies nothing (observed) | Keep `force_handlers: true` (ADR-0017). To repair a host that is already stale, make the snippet report `changed` again |
| `The role 'web' was not found in: ...` (observed) | The playbook is not next to `roles/` and no `roles_path` points at it | Run `ansible/site.yml`; keep entry playbooks in `ansible/` |
| `Could not find or access 'index.html.j2'` followed by a `Searched in:` list (observed) | The template is missing from every place on the list in section 5a | Put the file in `roles/web/templates/` |
| A variable set in a play's `vars:` has no effect on the role | The variable is also defined in the role's `vars/main.yml`, which outranks play `vars` (observed order, section 5a) | Move it to `defaults/main.yml`, or pass it with `-e` |
| Empty graph, `Unable to parse ... as an inventory source`, `No inventory was parsed` | No plugin claimed the file: wrong suffix, wrong `plugin:` line, or a file that did not reach disk. Read the first per-plugin warning for the reason (observed) | `cat` the file; name it `*.azure_rm.yml` |
| `[ERROR] Exception in _populate ... 'azureuser' is undefined` and `exit=0` | A `compose` value is a bare word, read as a variable (observed) | Quote string literals inside the value |
| `[ERROR] Could not generate group ... has no attribute 'role'` and `exit=0` | `keyed_groups` key missing on this VM (observed) | Add `| default('unset')` |
| `Found variable using reserved name 'name'` / `'tags'` on `--host` | Seen with a correct file on `ansible-core` 2.21.5; cause not investigated | Informational so far |
| `skipping: no hosts matched` and `exit=0` | The play's `hosts:` names a group that does not exist (observed) | Check the group with `--graph`; in automation require a host in the recap |
| `no hosts to target`, `exit=1` | `--limit` left nothing (observed) | Check the group name |
| Inventory works from a terminal but not in a new shell or CI | The plugin needs a live `az login` and the venv's SDK; neither exists there | Log in; or use `msi` once the agent exists (ADR-0019) |

## 8. Teardown

`terraform destroy` in `w4d1-ansible-target` (sandbox repo). The target holds no state worth keeping; the playbooks and the role are the source of truth.
