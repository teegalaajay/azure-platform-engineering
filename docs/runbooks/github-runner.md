# Runbook: self-hosted GitHub Actions runner and apply on merge

**Purpose:** Bring the runner up, use it for the apply-on-merge workflow, take it down, and troubleshoot it (ADR-0015).
**Owner:** platform-team · **Last validated:** 2026-10-16 (build, boot, registration, isolation checks on the live VM; the approval pause and the first apply run are validated after merge) · **Persistent:** no (the runner root is ephemeral; the workflow and its secrets are persistent)

## 1. Layout

| Piece | Where | What it does |
|---|---|---|
| Module | `modules/runner-vm` | Renders `cloud-init.yaml.tftpl` and calls `modules/linux-vm` |
| Root | `platform/runner` (state key `platform/runner.tfstate`) | Resource group `rg-runner-shared`, the VM `vm-runner-shared` in `snet-mgmt`, an interim NAT Gateway for egress |
| Workflow | `.github/workflows/apply.yml` | On a push to `main`: one job on the runner, behind the `production` environment, applies the persistent roots in order |
| Label config | `.github/actionlint.yaml` | Declares the custom runner label for actionlint |
| Identity | `app-gh-apply-shared` (ADR-0013) | Reached only through the `production` environment subject |

The runner has no inbound path, no public IP and no managed identity. It registers with `--ephemeral`: it takes one job, then deregisters.

## 2. Bring it up (before a merge)

The registration token is minted for this one command and expires after an hour. Do not put it in `.bashrc`.

```bash
cd platform/runner
TF_VAR_registration_token=$(gh api -X POST repos/<owner>/<repo>/actions/runners/registration-token --jq .token) terraform apply
```

Expected: `7 to add` on a fresh apply. The VM and the NAT Gateway bill by the hour from now.

## 3. Verify

```bash
gh api repos/<owner>/<repo>/actions/runners --jq '.runners[] | {name, status, busy, labels: [.labels[].name]}'
az vm run-command invoke -g rg-runner-shared -n vm-runner-shared --command-id RunShellScript \
  --scripts 'cloud-init status --long; ls -l /var/lib/runner-bootstrap.done' --query 'value[0].message' -o tsv
```

Expected: one runner `vm-runner-shared`, `online`, not busy, with labels `self-hosted`, `Linux`, `X64`, `platform-apply`; `cloud-init` `status: done` with no errors and the marker file present. The run-command is read-only.

## 4. Use it

Merge a pull request that touches a path watched by `apply.yml`. The run waits at the `production` environment until the reviewer approves. After approval the job runs on the runner, and the runner deregisters when the job ends. A second merge needs a new runner (section 2): the next apply replaces the VM, because a new token changes `custom_data`.

## 5. Take it down (same day)

The token variable is required even for destroy; any value works.

```bash
cd platform/runner
TF_VAR_registration_token=unused terraform destroy
```

Expected: 7 destroyed. Afterwards `platform/foundation/hub` still plans `No changes`. If the runner was never used, delete the stale registration in repository settings, Actions, Runners.

## 6. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| No runner listed after apply | `cloud-init` still running, or it failed | Run the run-command in section 3; read `cloud-init status --long` |
| `cloud-init` ended in `error` | A step in `/opt/runner-bootstrap.sh` failed (key fingerprint, checksum, package) | The run-command output names the failing step; fix the template and re-apply (replaces the VM) |
| Runner never registers, cloud-init is `done` | The token was minted more than an hour before cloud-init ran | Mint a new token and re-apply |
| Apply job stays queued | No online runner with the label `platform-apply`, or the single runner was already used | Section 2 |
| Run fails at the Terraform version step | The runner's Terraform is not the pinned version | Rebuild the VM from the module; do not upgrade in place |
| Run fails at the classification step | A root with a `backend.tf` is in neither `APPLY_ROOTS` nor `SKIP_ROOTS` | Add it to the right list in the same pull request |
| actionlint rejects `runs-on` | A label is missing from `.github/actionlint.yaml` | Add it, or fix the typo |
| CI plan of `platform/runner` shows the VM replaced | The CI placeholder token differs from the one in state | Expected while the root is deployed (ADR-0015) |

## 7. Change

- A new persistent root: add it to `APPLY_ROOTS` in the dependency order, or to `SKIP_ROOTS`.
- Bumping the runner version: change `runner_version` and `runner_sha256` in `runner.auto.tfvars` together; get the digest from the release asset and drop the `sha256:` prefix.
- Bumping Terraform: change `terraform_version` here and the version check in `apply.yml` in the same pull request.
