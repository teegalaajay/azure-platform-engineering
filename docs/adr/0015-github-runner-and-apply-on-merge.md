# ADR-0015: Self-hosted GitHub Actions runner and apply on merge

- **Status:** Accepted (2026-10-16). Runner build, boot and isolation proven on the live VM; the approval pause and the first apply run are recorded in the runbook after merge (see Consequences)
- **Date:** 2026-10-16
- **Deciders:** platform-team (@teegalaajay)
- **Implements:** the apply half of ADR-0013 and the runner deferred by ADR-0005 (state firewall) and ADR-0010 (Key Vault network rules)
- **Supersedes:** the line "a managed identity for the self-hosted runner" in the Deferred section of ADR-0013: the runner gets no managed identity (decision 3)

## Context

Plan on pull request (ADR-0014) runs on GitHub-hosted runners. Apply has two needs a hosted runner cannot meet. Hosted runners have no fixed IP and sit outside the VNet, so they cannot reach resources that allow only `snet-mgmt` (the Key Vault since ADR-0010, and the state account once it is firewalled, open item 42). And apply holds the privileged identity (ADR-0013), so the machine it runs on matters.

This repository is public. Any workflow run is triggered by a pull request, and the author of a pull request chooses `runs-on` in the workflow file the run uses. A self-hosted runner is a machine we own, inside our network, that can outlive a job. GitHub's guidance is not to use self-hosted runners with public repositories because code from a pull request can then run on that machine.

A self-hosted runner has three secrets of different strength. The registration token is minted by someone with admin on the repository, expires after one hour (GitHub REST documentation) and only adds a runner. The runner's own credential files, written at registration, are long-lived and let the holder receive jobs, and with them the secrets and OIDC rights of those jobs. The per-job OIDC token is what Azure verifies.

## Options considered

**Which jobs run on the VM**
1. Apply only (the job on `main`, behind the `production` environment).
2. Plan and apply.
3. Two runners in two subnets, one per purpose.

**Lifecycle**
4. A standing runner.
5. An on-demand runner: brought up before a merge, destroyed afterwards.

**Azure identity of the VM**
6. A managed identity on the VM.
7. None; Azure access only through the per-job OIDC token.

**How the registration token reaches cloud-init**
8. A sensitive variable rendered into `custom_data`, minted just before apply.
9. Registered by hand over a run-command after boot.
10. A Key Vault secret read by a managed identity.

**Runner mode**
11. A persistent runner.
12. `--ephemeral`: one job, then it deregisters.

**Module shape**
13. Wrap `modules/linux-vm`, adding an optional `custom_data` input.
14. A standalone VM definition inside `modules/runner-vm`.

**Egress for a subnet with no default outbound access**
15. A standing NAT Gateway in the hub.
16. An interim NAT Gateway in the runner's own root (the ADR-0008 pattern).
17. A public IP on the NIC.

**What apply on merge applies**
18. Every root with a backend.
19. The roots changed by the merge.
20. A fixed allowlist of the persistent roots, in dependency order.

**Workflow shape**
21. A matrix of roots, like plan.
22. One job that applies the roots one after another.

## Decision

Options 1, 5, 7, 8, 12, 13, 16, 20 and 22.

- **Only the apply job runs on the VM (1).** Pull request code, including plan, stays on hosted runners. The VM runs code that has already been merged and approved. The state account therefore cannot be firewalled yet (open item 42 stays open).
- **On-demand (5).** A standing VM and NAT Gateway would exceed the USD 50 monthly budget on their own. The operator brings the runner up before a merge. Automated bring-up and teardown are deferred.
- **No managed identity (7).** A managed identity lets any process on the VM request a token from the instance metadata service, which skips the OIDC subject and the environment gate entirely. Proven: a request from the `runner` user returns `Identity not found`.
- **Token by sensitive variable (8).** `TF_VAR_registration_token` is minted inline for one command (`gh api -X POST .../actions/runners/registration-token`), never written to `.bashrc`. It reaches the VM as `custom_data`.
- **Ephemeral (12).** Registered with `--ephemeral`: the runner takes one job and deregisters, so its credential files are stale after that job.
- **Wrap `linux-vm` (13).** One VM baseline. The new `custom_data` input is optional (default null), sensitive, and documented as running as root at first boot.
- **Layout.** `modules/runner-vm` renders `cloud-init.yaml.tftpl` and calls `linux-vm`. The root `platform/runner` (state key `platform/runner.tfstate`, resource group `rg-runner-shared`) reads the hub's `mgmt_subnet_id` from remote state, creates the NAT Gateway (16) and attaches it to `snet-mgmt`.
- **cloud-init** installs everything: base packages; the Azure CLI and Terraform from vendor apt repositories, each key reduced to the single expected key and compared with its pinned fingerprint; Terraform pinned to 1.16.4 and held; a non-root `runner` user with no sudo group; the runner tarball at a pinned version checked against a pinned SHA-256; registration as that user; a systemd service.
- **Apply workflow `apply.yml`.** Trigger: `push` to `main` for the watched paths; never a pull request. One job (22) because the ephemeral runner takes exactly one job, so a second matrix leg would queue with no runner. `runs-on: [self-hosted, linux, x64, platform-apply]`, `environment: production`, `concurrency` group `apply` with `cancel-in-progress: false`. Signs in as the apply identity through Terraform's own OIDC support. Applies the allowlist (20) in dependency order: hub, dev, prod, security, cost, storage-demo prod. The ephemeral roots (`platform/runner`, both demos) are applied by hand. A step fails the run if a root with a backend is in neither list. A step fails the run if the runner's Terraform is not the pinned version.
- **actionlint** needs `.github/actionlint.yaml` to accept the custom label; it also catches label typos.

## Consequences

Proven on the live VM (2026-10-16):

- Apply created 7 resources; the runner registered with all four labels and reports `online`, not busy.
- `cloud-init status` is `done` with no errors; the service is `active running`.
- The `runner` user has one group and cannot read `user-data.txt`, `cloud-config.txt`, `ovf-env.xml` or `/opt/runner-bootstrap.sh`; the token file is deleted.
- A managed-identity token request from the `runner` user fails with `Identity not found`.
- The VM's outbound address equals the NAT Gateway's public IP.
- The hub root plans `No changes` after the NAT association was attached from another root.
- CI on the pull request: all validate legs green; the plan leg for `platform/runner` failed with `No value for required variable` until a plan-only placeholder was added, then went green. Changing `custom_data` is shown as `forces replacement` on the VM.

Reasoned, to be proven at or after merge:

- That the `production` approval pauses the apply run before any step runs, with no runner assigned and no token minted.
- That the runner takes one job and deregisters.
- Whether approval is requested once per run or once per job for jobs that share an environment (not needed by the single-job shape).
- How long GitHub keeps a queued job when no runner with the label exists.
- That the `runner` user has no route to root: the group list shows no `sudo`, but `sudo -l` was not run.

Costs accepted:

- **State account stays reachable (open item 42).** With plan on hosted runners it cannot be firewalled. It is protected by Entra authentication, RBAC, shared key access off and TLS only. This is accepted risk, to be revisited with a private path for plan.
- **Apply on merge only works while the runner is up.** A merge with no runner online leaves the job queued. Nothing prevents that merge.
- **The token is in state and in the VM's boot data.** It is dead after one hour, so exposure today is nil, but the pattern would persist anything more durable passed the same way. The protection on the VM is the OS user boundary, not encryption.
- **Plan noise.** CI plans `platform/runner` with a placeholder token. While that root is deployed, every pull request plan shows the VM as replaced because of `custom_data`.
- **A hand-maintained allowlist.** The classification step fails the run for an unlisted root, but someone must classify it.
- **The runner can read its own credential files, by design.** Isolation rests on `--ephemeral`.
- **Single maintainer.** The environment reviewer is the person who merged. The approval is a deliberate pause, not an independent control.
- **Public logs.** `terraform apply -auto-approve` prints plans into a public job log; only GitHub's secret masking and the repository's choice of secrets for identifiers protect it.
- **Fork pull requests** are still reasoned, not reproduced (open item 65).

## Deferred

- Automated bring-up and teardown of the runner.
- Firewalling the state account (item 42), with a private path for plan.
- The post-merge tests of the apply identity (item 64): Contributor fails role-assignment and lock writes, destroy of a locked resource, certificate deletion in the prune step, a from-zero rebuild of both bootstrap scripts.
- Just-in-time runner configuration instead of a registration token; `--disableupdate`.
- Replacing the interim NAT Gateway with the Week 8 firewall; Bastion for access.
- An ADO mode for the same module (Week 5).
- A `plan-gate` required check (item 71).
