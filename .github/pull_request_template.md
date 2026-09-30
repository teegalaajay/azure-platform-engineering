## What
<!-- One or two sentences: what this change does. -->

## Why
<!-- The problem or requirement. Link the ADR if this PR makes a design decision. -->

## Plan output
<!-- Paste `terraform plan` for every root module touched, or write "N/A — no Terraform changes".
     From Week 3, CI posts the plan on the PR automatically. -->

## Risk
<!-- What could break, blast radius, and whether it touches a persistent layer (bootstrap / platform). -->

## Rollback
<!-- Exact undo steps: revert the squash commit, re-apply the previous module tag, restore a state version, etc. -->

## Checklist
- [ ] PR title is a Conventional Commit (`type(scope): summary`) — it becomes the squash-commit message on `main`
- [ ] `pre-commit run --all-files` passes
- [ ] No state, plan files, secrets, subscription/tenant IDs or personal IPs committed
- [ ] ADR added or updated for any design decision
- [ ] Runbook added or updated for any persistent component
- [ ] Mandatory tags on every new resource