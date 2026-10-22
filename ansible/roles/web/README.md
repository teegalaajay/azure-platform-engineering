# Role: web

Installs nginx on Ubuntu, makes sure it is started and enabled, renders a landing page and an nginx response-header snippet from Jinja2 templates, and reloads nginx when the snippet changes.

Part of the reference platform in this repository. Design decisions: ADR-0017 (handler failure policy) and ADR-0018 (role layout and variable policy). Operating steps: runbook `ansible-control-node`.

## Requirements

- Target: Ubuntu 24.04 with Python available (the tested image).
- Privilege: the tasks change system state, so the calling play must set `become: true`.
- Control node: `ansible-core` 2.21 (pinned in `ansible/requirements.txt`).

## Variables

All settings are in `defaults/main.yml`, the lowest precedence, so a play, an inventory or `-e` can override any of them.

| Variable | Default | Meaning |
|---|---|---|
| `web_root` | `/var/www/html` | Directory that holds the rendered landing page |
| `web_owner` | `root` | Owner of the landing page (the group is always `root`) |
| `site_title` | `Sandbox Reference Platform` | Heading on the landing page and value of the `X-Platform` response header |

The role has no `vars/main.yml`. A variable there would outrank a caller's play `vars:` and be ignored silently (ADR-0018).

## Tasks, tags and handler

| Task | Tag | Notifies |
|---|---|---|
| Ensure nginx is installed | `packages` | |
| Ensure nginx is started and enabled | `service` | |
| Ensure the landing page is rendered | `content` | |
| Ensure the response header snippet is rendered | `config` | `Reload nginx` |

The handler `Reload nginx` runs once at the end of the play, only when the snippet changed. Set `force_handlers: true` on the calling play so that an already notified handler still runs if a later task fails (ADR-0017). `--tags` selects tasks, so a run that skips the `config` task never runs the handler.

## Dependencies

None.

## Example

```yaml
- name: Web server - install nginx
  hosts: all
  become: true
  force_handlers: true
  roles:
    - web
```

Override a setting from the play: `vars: { site_title: Example }`, or from the command line: `-e site_title=Example`.

## License

MIT
