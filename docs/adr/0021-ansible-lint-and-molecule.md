# ADR-0021: ansible-lint (production profile) and Molecule tests for Ansible roles

- **Status:** Accepted (2026-10-27)
- **Date:** 2026-10-27
- **Deciders:** platform-team (@teegalaajay)
- **Relates to:** ADR-0016 (sandbox target); ADR-0018 (role layout; its deferred variable prefix is reversed here); ADR-0019 (pinning, zero-host runs exit 0); ADR-0012 (CI protects `main`, hooks can be skipped); runbook `ansible-control-node`

## Context

The `web` role had two kinds of check missing. Nothing read the Ansible code against a rule set, and nothing proved the role does what it claims on a real host (converge, second run changes nothing, the served result is correct). Both were wanted before Azure DevOps pipelines (Week 6) call the role.

Observed on 2026-10-27 with `ansible-core` 2.21.5, ansible-lint 26.10.1 and Molecule 26.10.0:

1. ansible-lint exits 2 on a violation. Its profiles are ordered min, basic, moderate, safety, shared, production, and a failure in a lower profile caps the result ("`production` was required, but `min` profile passed").
2. `var-naming[no-role-prefix]` flagged `site_title` in `roles/web/defaults/main.yml`. It also applies to files inside the role directory: the Molecule `verify.yml` was flagged for `register: index_file` and `headers_file`.
3. `fqcn[action-core]` (profile production) flagged `apt` written without `ansible.builtin.`; the result was "`shared` profile passed", 4/5 star.
4. A bare `ansible-lint` at the repository root discovered 205 items and linted `.github/workflows/oidc-smoke.yml` (six `yaml[line-length]` failures). With `exclude_paths: [.github/]` it discovered 198.
5. ansible-lint does not read inside `.j2` templates (debug output: "data set to None ... 'jinja2' kind"). A wrong variable name inside a template is invisible to it.
6. `role-name[path]` flagged `include_role` with a path (`"{{ playbook_dir }}/../.."`).
7. In Molecule 26.10.0 the only driver listed is `default`; there is no driver named `delegated`. `molecule init scenario` has no driver option and writes stub `create.yml` and `destroy.yml`. In `molecule.yml`, `playbooks:` belongs under `ansible:` (top level fails schema validation).
8. The generated inventory contains a host only for each entry under `platforms:`. With none declared, `converge` printed "skipping: no hosts matched" and returned code 0 (a false green); `verify` would do the same.
9. `molecule create`, `converge` and `destroy` run their own sequences (`create_sequence`, `converge_sequence`, `destroy_sequence`), separate from `test_sequence`. Defaults include `dependency` and `prepare`, which print "Missing" warnings here.
10. With the search path unset, `include_role: name: web` failed with `The role 'web' was not found`. Setting `ANSIBLE_ROLES_PATH` to `${MOLECULE_PROJECT_DIRECTORY}/..` in the `ansible.env` block of `molecule.yml` fixed it.
11. Molecule keeps its generated inventory and `instance_config.yml` in `~/.ansible/tmp/molecule.<id>.default/`, not in the repository.
12. Against the sandbox VM (Ubuntu 24.04): first converge `ok=7 changed=4`; second pass (idempotence) `ok=6 changed=0`; `verify` ran 9 tasks, all `ok`. With the title deliberately set to `Wrong Title`, converge succeeded (`ok=7 changed=3`) and verify failed on `'<h1>Sandbox Reference Platform</h1>' in web_page.content`, return code 2. With `platforms:` commented out, the guard play failed the run, return code 2. `molecule test` passed 6 of 6 twice on the final files. On a failed run, `destroy.yml` cleared the instance config and touched nothing in Azure.
13. Installing ansible-lint added 14 packages and Molecule 6 under the existing lock file; `pip check` was clean each time and no locked version changed.

## Options considered

Where the hook gets ansible-lint: (1) the upstream hook repository, pinned by `rev`, in its own isolated environment; (2) a local hook that runs the `ansible-lint` on the PATH, the venv's pinned copy.

Scope: (A) `exclude_paths` in `.ansible-lint` plus path-scoped commands; (B) always pass `ansible-lint ansible`.

Molecule target: (a) rebuild the sandbox VM from `azure-iac-sandbox/w4d1-ansible-target` and point the default driver at it; (b) the operator's WSL as target; (c) a container.

Role lookup in `converge.yml`: (i) a path in `include_role`; (ii) `name: web` plus a roles search path.

## Decision

- Pins: `ansible-lint==26.10.1` and `molecule==26.10.0` in `ansible/requirements.txt`; `ansible/constraints.txt` regenerated after `pip check`.
- `.ansible-lint`: `profile: production`, `exclude_paths: [.github/]` (option A). No `skip_list` or `warn_list`; any future skip needs a comment saying why.
- Hook: option 2, a local `ansible-lint` hook (`language: system`, `pass_filenames: false`, `files: ^(ansible/|\.ansible-lint$|ansible\.cfg$)`). One version source: `constraints.txt`.
- Rename `site_title` to `web_site_title`. This reverses the deferral in ADR-0018. `git grep` found no caller outside the role, its README and docs.
- Molecule: scenario `ansible/roles/web/molecule/default/`, option (a). Terraform owns the VM. `create.yml` reads the address from `MOLECULE_TARGET_ADDRESS` and writes the instance config (user `azureuser`, key `~/.ssh/azlab_ed25519`); no address is committed (ADR-0016). `destroy.yml` only clears the instance config and never touches Azure. `platforms:` declares one instance named `instance`.
- `converge.yml` and `verify.yml` start with a guard play that fails when the inventory has no host (observation 8). `converge.yml` uses `name: web` (option ii) with `ANSIBLE_ROLES_PATH` set in `molecule.yml`; option (i) breaks `role-name[path]`.
- `test_sequence`: syntax, create, converge, idempotence, verify, destroy. Per-command sequences list only the stages that exist.
- `verify.yml` writes the expected values out (heading, header, owner, mode) and does not read them from the role's variables, so a change in behaviour fails the test.
- `host_key_checking: false` in the scenario only: the target is a throwaway VM rebuilt with new host keys.

## Consequences

- No CI job runs ansible-lint or Molecule. The hook can be skipped (`git commit --no-verify`, ADR-0012), so `main` is not protected against a lint or role regression yet. Open item: an ansible-lint job in CI; Molecule needs a runner that can reach a target.
- Molecule needs a running VM, an `az login` and a Terraform apply and destroy by hand, plus `MOLECULE_TARGET_ADDRESS` and an SSH agent holding the key. An unset address fails at the `create.yml` assert (reasoned from the playbook; not run).
- If the venv is not active, the local hook cannot find `ansible-lint` (reasoned; not run).
- ansible-lint warned that `.yamllint` is incompatible with its own requirements (`comments.min-spaces-from-content` must be 1; the octal rules must be true) and that auto-fix is unavailable. `.yamllint` also drives CI validation, so it was not changed. Open item.
- `.github/workflows/oidc-smoke.yml` has six lines over 120 characters; yamllint reports them as warnings. Outside this PR.
- The lint output counts items "encountered" against "processed" (19 of 203 at the end); the role README was identified as unexamined, the rest were not identified one by one.
- The guard in `verify.yml` has the same condition as the one in `converge.yml` but was not triggered separately (reasoned).
- `host_key_checking: false` weakens host verification for this scenario. Acceptable for a throwaway VM reachable only from the operator /32 (reasoned).
- Not tested: another OS image, another `ansible-core`, the `prepare`, `side_effect` and `cleanup` stages, parallel scenarios, running the scenario from CI.
