# ADR-0018: Ansible role layout, entry playbook and variable policy

- **Status:** Accepted (2026-10-22)
- **Date:** 2026-10-22
- **Deciders:** platform-team (@teegalaajay)
- **Relates to:** ADR-0016 (practice target); ADR-0017 (handler failure policy); runbook `ansible-control-node`

## Context

`web.yml` held the tasks, the handler, the variables and the play settings in one file, with the templates in a directory beside it. Reuse by a second play, and a stable list of settings a caller may change, need a role. Three facts observed in the sandbox on 2026-10-22 shaped the decisions below.

1. A play in `ansible/playbooks/web.yml` that named the role `web` (stored in `ansible/roles/web`) failed `ansible-playbook --syntax-check` with `The role 'web' was not found in` five paths: `ansible/playbooks/roles`, `~/.ansible/roles`, `/usr/share/ansible/roles`, `/etc/ansible/roles` and `ansible/playbooks`. `yamllint --strict` passed on the same file.
2. With `site_title` set at four levels, the template received them in this order, lowest to highest: role `defaults/main.yml`, play `vars`, role `vars/main.yml`, `-e`.
3. A `template` task inside a role looks for its source in six places, in this order: `roles/web/templates/`, `roles/web/`, `roles/web/tasks/templates/`, `roles/web/tasks/`, `<playbook dir>/templates/`, `<playbook dir>/`.

## Options considered

1. Role in `ansible/roles/web`, entry playbook `ansible/site.yml` beside it.
2. Same role, playbook left in `ansible/playbooks/`, with `ansible/ansible.cfg` setting `roles_path = roles`.
3. Role under `ansible/playbooks/roles/`.
4. Variables: all in `defaults/main.yml`; or split between `defaults/` and `vars/main.yml`; or all in `vars/main.yml`.

## Decision

- Option 1. Ansible always checks `roles/` next to the playbook it runs, so `ansible-playbook ansible/site.yml` works from any directory with no configuration file. Standalone playbooks such as `first.yml` stay in `ansible/playbooks/`.
- Option 2 rejected: Ansible reads `ansible.cfg` from the current directory, so it would work from `ansible/` and fail from the repository root or in CI (reasoned, not tested). Option 3 rejected: it hides roles under the playbooks.
- Variables: every setting a caller may change lives in `defaults/main.yml` (`web_root`, `web_owner`, `site_title`). The role has no `vars/main.yml`. Role `vars` outrank play `vars` (fact 2), so a setting there would be ignored silently when a play tries to override it. A constant that must not be overridden may be added to `vars/` later, with a reason recorded here.
- The handler `Reload nginx` lives in the role (`handlers/main.yml`). `force_handlers: true` stays on the play, as ADR-0017 states for `web.yml`: it is a play keyword, and the policy belongs to the caller.
- Galaxy identity in `meta/main.yml`: `namespace: teegalaajay`, `role_name: web`, lowercase, `license: MIT`, no `company`. `min_ansible_version` is the pinned `2.21`, quoted.
- Generated stubs removed: `tests/` (nothing runs it; Molecule arrives in Week 5 with its own layout), the empty `files/`, and `vars/`.

## Consequences

- `ansible-galaxy role info web` printed a record that belongs to a public Galaxy role with the same name, published by someone else, next to the local metadata. Roles here are referenced only from the repository's own `roles/` directory and are never installed from Galaxy. A bare `ansible-galaxy role install web` would fetch the other role.
- Role variables share one namespace with the whole play. `site_title` has no `web_` prefix and could collide with another role's variable. Renaming it is a breaking change for any caller that passes `-e site_title=...`, so it is deferred.
- Anything placed in `ansible/templates/` is searched before the play fails, so a stale file there can satisfy a role's `template` task and hide a missing role file (reasoned from fact 3; the shadowing itself was not run).
- The `license: MIT` field names a license the repository does not yet grant: there is no root `LICENSE` file. A follow-up PR adds it.
- The entry point moved from `ansible/playbooks/web.yml` to `ansible/site.yml`. Commands that use the old path fail with a missing-file error (reasoned). The runbook is updated in the same PR.
- A play in `ansible/playbooks/` cannot call the role without a configuration change (reasoned from fact 1).
- Not tested: role parameters (`roles: - role: web, site_title: x`), `include_role` and `import_role`, tags set on the role in the play, list and dictionary defaults, `validate: nginx -t` on a full `nginx.conf` (still deferred from ADR-0017), `ansible.cfg` as an alternative.
