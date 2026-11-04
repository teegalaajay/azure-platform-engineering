# ADR-0032: Secret exposure controls in CI and pipelines

- **Status:** Accepted
- **Date:** 2026-11-03
- **Deciders:** platform-team (@teegalaajay)
- **Relates to:** ADR-0002 (secrets and identity); ADR-0010 (platform Key Vault); ADR-0024 (agent identity);
  ADR-0029 (Ansible key from Key Vault); ADR-0030 (one-run pipeline)

## Context

The Week 7 Day 2 audit looked for plaintext secrets in the repository, the Terraform code and the pipeline logs.
Observed: a gitleaks scan of the full history (63 commits) found nothing; the two Key Vault tasks each name one
secret; no `set -x` and no `TF_LOG` appear in the pipelines. Also observed: Azure DevOps masks only the exact
registered value, and a base64 copy, a substring, a reversed copy and a split copy of a registered secret all
printed in clear text. Also observed: no workflow runs gitleaks or pre-commit, so CI had no secret scan, and the
pre-commit gitleaks hook scans only staged changes (`--staged`), so it would inspect nothing in a CI checkout.

## Options considered

1. **Where the secret scan runs:** (a) a CI job over the full history with a pinned binary; (b) only the local
   pre-commit hook; (c) a third-party scanning action.
2. **How to stop patterns that print secrets:** (a) a CI `git grep` step; (b) a local pre-commit hook; (c) review only.

## Decision

Option (a) in 1 and 2.

1. **Job `secrets` in `validate.yml`.** It checks out with `fetch-depth: 0`, installs gitleaks 8.30.0 (the version
   pre-commit pins) after a SHA-256 check, and scans the full history with `--redact`. The `validate-gate` job
   needs it, so a finding blocks the merge. *Cost:* scan time grows with history; detection is rule-based and finds
   known secret shapes only; each run downloads one file from GitHub (pinned by hash).
2. **A CI step in the same job** fails when `pipelines/` or `.github/workflows/` contain a wildcard
   `SecretsFilter`, shell tracing (`set -x` forms) or `TF_LOG`. Masking is exact-match, so the control is never
   to print or transform a secret. *Cost:* a regex misses variants (`bash -x`, `set -o xtrace`); it supplements
   review and does not replace it.
3. **The false comment in `.pre-commit-config.yaml` is corrected:** the file is advisory until CI runs it.

## Accepted costs and open items

- **Runner registration token in `custom_data` (F4):** `modules/runner-vm` passes `registration_token` into boot
  data, so it is in Terraform state and readable on the VM. GitHub documents registration tokens as short-lived
  (read, not tested here). `modules/ado-agent-vm` reads its token from Key Vault instead. Revisit if the runner
  becomes long-lived.
- **Key file until the cleanup step (F3):** the SSH key file exists on the agent from its write until the
  `always()` step; cleanup on a cancelled or killed run is not tested.
- **Placeholder token in `plan.yml` (F1):** a literal placeholder so `plan` can run; no apply path uses it.
- **`tfplan` artifact (F5):** safe because the two allowed roots take no sensitive inputs. A root with a sensitive
  input must not be added to the `terraform` root allowlist without a new decision.
- **Not done:** pre-commit is not run in CI (F7); masking of the real key's BEGIN and END lines; the claim that
  `TF_LOG=DEBUG` would print the Azure access token is reasoned, not observed.
