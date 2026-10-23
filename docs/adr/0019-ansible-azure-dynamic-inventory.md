# ADR-0019: Azure dynamic inventory, dependency pinning and inventory identity

- **Status:** Accepted (2026-10-22)
- **Date:** 2026-10-22
- **Deciders:** platform-team (@teegalaajay)
- **Relates to:** ADR-0002 (secrets and identity); ADR-0016 (practice target); ADR-0018 (role layout); runbook `ansible-control-node`

## Context

Every playbook run so far named its host inline (`-i "<ip>,"`). The address changes each time the sandbox target is rebuilt, and a second host would never be found. The host list should come from Azure at run time.

The `azure_rm` inventory plugin ships in the `azure.azcollection` collection, not in `ansible-core`. Observed on 2026-10-22:

1. `ansible-galaxy` installs the collection to `~/.ansible/collections`, outside the venv and the repository, and does not install its Python dependencies.
2. The collection's `requirements.txt` (4.1.0) has 72 lines. Most are exact pins; at least one is a range (`aiohttp>=3.13.0`). Transitive dependencies are not listed.
3. Installing that list into `~/.venvs/ansible` replaced `cryptography` 50.0.2 (pulled in by `ansible-core`) with 47.0.0. `pip check` reported no broken requirements and the `site.yml` baseline stayed `ok=5 changed=0`.
4. The list includes `azure-cli-core==2.75.0`. The workstation's `az` is 2.90.0 from the Microsoft apt repository. With `auth_source: cli` the plugin reads the token cache in `~/.azure/` through the venv's `azure-cli-core`, not by running `az`.
5. The collection also ships `azure_kql`, an inventory plugin backed by Azure Resource Graph.

## Options considered

Dependencies:

1. Install from the collection's file in `~/.ansible/collections` at install time.
2. Copy the collection's list into the repository and lock the whole venv with `pip freeze` into a constraints file.
3. Install a hand-picked subset of SDK packages.

Inventory identity (`auth_source`):

1. `cli`: the operator's `az login` session.
2. `credential_file` or `env`: a service principal with Reader on the sandbox resource group.
3. `msi`: the managed identity of the machine running Ansible.
4. `auto`: the plugin's credential chain.

Plugin: `azure_rm` (ARM per-resource calls) or `azure_kql` (Resource Graph).

## Decision

- Collection pinned in `ansible/requirements.yml`: `azure.azcollection` `==4.1.0`, source `https://galaxy.ansible.com`.
- Dependencies: option 2. `ansible/requirements-azure.txt` is the collection's list copied verbatim with a header; `ansible/requirements.txt` includes it with `-r`; `ansible/constraints.txt` is `pip freeze` of the venv after `pip check` passed (172 packages, Python 3.12). Install with `pip install -r ansible/requirements.txt -c ansible/constraints.txt`. All three files are regenerated together when the collection pin changes.
- Identity: `auth_source: cli`, set explicitly in the inventory file. `auto` is rejected because the identity that answered cannot be read from the configuration. A service principal secret is rejected by ADR-0002 (Tier 3). `msi` is the target once the control node is the agent VM in `snet-mgmt` (Week 5 Day 5); the inventory file then changes to `auth_source: msi` and the managed identity gets Reader on the scoped resource groups only.
- Plugin: `azure_rm`. `azure_kql` is not used; Resource Graph results can trail ARM, and one subscription does not need a cross-subscription query.
- The inventory file holds the query only (resource groups, host naming, groups, connection variables): no hosts, IP addresses or credentials.

## Consequences

- The inventory query runs with the operator's rights (Owner on the subscription), far more than the Reader it needs. Nothing enforces read-only on the laptop. Accepted for the sandbox; removed by the move to `msi`.
- Inventory works only where a person has run `az login`. It cannot run in CI or on the agent until `msi` is adopted.
- Adding the collection changed a package `ansible-core` uses (`cryptography` 50.0.2 to 47.0.0). Every collection bump can do the same; the constraints file makes it visible in the PR diff.
- `constraints.txt` is specific to Python 3.12 on x86_64 (the collection's list carries platform and Python markers). Another Python may need a new lock (reasoned).
- Two copies of Azure CLI code (system `az` 2.90.0, venv `azure-cli-core` 2.75.0) read the same `~/.azure/` cache. Observed 2026-10-22: the plugin read the cache and returned the VM (`ansible-inventory --host` showed `ansible_host`, `public_ipv4_address`, `private_ipv4_addresses`), with no MSAL error.
- Failures are loud on screen and quiet in the exit code. Observed 2026-10-22, all on `ansible-core` 2.21.5 with azcollection 4.1.0:
  - A source no plugin claims (wrong file-name suffix) prints per-plugin warnings, `No inventory was parsed, only implicit localhost is available`, an empty graph and exit 0. With `ANSIBLE_INVENTORY_UNPARSED_FAILED=true` the same run is `[ERROR]` and exit 1. Not tested: that setting against a correct file whose Azure call fails.
  - A failing `compose` expression (`ansible_user: azureuser`, undefined variable) prints `[ERROR] Exception in _populate`, keeps the host and exits 0.
  - A `keyed_groups` key that is missing on the VM (`tags.role`) prints `[ERROR] Could not generate group`, keeps the host in its other groups and exits 0. `tags.role | default('unset')` puts it in `role_unset` with no error.
  - A play with `hosts: role_web` and no such group prints a warning, `skipping: no hosts matched`, an empty recap and exits 0. `--limit role_web` with no such group is `[ERROR]` and exit 1.
  - CI must therefore set `ANSIBLE_INVENTORY_UNPARSED_FAILED=true` and check that the recap lists at least one host. Neither is done yet.
- Host names are the VM name plus a suffix from the resource ID (`vm-ansible-target_9b90`). A rebuild gives a new suffix, so no host name is written anywhere; plays use groups or `all`.
- `ansible-core` 2.21.5 prints `Found variable using reserved name 'name'` and `'tags'` when host variables are dumped (`--host`). Seen with a correct file; cause not investigated.
- `compose` pins `ansible_host` to the first public address and `ansible_user` to `azureuser`; both are stated in the file, not left to plugin defaults.
- Not tested: `azure_kql`; `msi`; a second subscription; Reader-only permissions for the plugin.
