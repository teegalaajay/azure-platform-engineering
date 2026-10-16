# ADR-0014: Plan on pull request for every Terraform root

- **Status:** Accepted
- **Date:** 2026-10-15
- **Deciders:** platform-team (@teegalaajay)
- **Implements:** the "plan shows what a change does to real infrastructure" half of ADR-0012; uses the plan identity from ADR-0013

## Context

ADR-0012 proves that the code is well-formed. It cannot say what a change will do to the real infrastructure, because it runs without an Azure identity or state access. A reviewer who approves a pull request needs that second answer before merge: for every Terraform root, what would change, and does the root still plan at all.

The plan runs on every pull request that touches `modules/`, `platform/`, `workloads/` or the workflow itself. It uses the read-only plan identity from ADR-0013 (`Reader` and `Storage Blob Data Reader`, federated to the `pull_request` event), so it can read real resources and state but cannot change either. The repository is public, so whatever the workflow prints is visible to anyone, and several inputs to the plan belong to the operator personally.

## Options considered

**Which directories are planned**
1. The same list as the validate workflow: every directory that contains `versions.tf`. Rejected: the three modules have a `versions.tf` but no backend and no state of their own, so there is nothing for `plan` to compare against. A module is exercised through the roots that call it.
2. Discovery by `backend.tf`: a first job finds every directory that declares the remote state backend, and the job fails if it finds fewer than 8. Chosen.
3. A static list written in the workflow. Rejected: a new root that nobody adds to the list is silently never planned, and the PR still shows green.

**Which event starts the workflow**
1. `pull_request`. Chosen. A pull request from a fork runs with a read-only `GITHUB_TOKEN` and no secrets, and the job cannot request an OIDC token. The plan job therefore fails at `terraform init`, closed, and nothing is exposed.
2. `pull_request_target`. Rejected. This event runs with the base repository's secrets and permissions. To plan the proposed change, the workflow would have to check out the pull request's code, and `terraform init` and `plan` execute what that code names: provider binaries, module sources, and `data "external"` programs run at plan time. The author of a fork PR would then run their own code on a runner that holds a working Azure login. Whether the OIDC subject claim for this event could even match the federated credential was not tested here, so no part of the decision rests on it. This event is not used anywhere in the repository.

**How operator-specific inputs reach the CI plan**
1. Commit the values in a `.tfvars` file. Rejected: the repository is public, and these are an operator's network address, email addresses and identity, which have no business in git history.
2. Repository variables. Rejected: variables are stored and displayed in plain text, so they offer no protection that a committed file would not.
3. Repository secrets, declared in `bootstrap/github-repo-settings.sh`. Chosen. The script sets every secret from the operator's `TF_VAR_*` environment and deletes any secret the script does not declare, so the set of secrets is code that goes through review.

**State locking during plan**
1. Plan with the default lock. Rejected: Terraform takes a lease on the state blob, and the plan identity holds only `Reader` and `Storage Blob Data Reader`, which cannot take a lease. The plan would fail before it read anything.
2. Give the plan identity write access to the state container so it can lock. Rejected: it removes the property that makes the identity safe to use on every pull request. Code from any pull request that passes review runs under it, and write access to state would let that code alter or corrupt the state of every environment.
3. `terraform plan -lock=false`. Chosen. The identity stays read-only. The cost is a possible stale read: if an apply is writing state while a plan reads it, the plan can describe a state that is about to change. That is acceptable because a plan on a pull request is advisory. The apply workflow (Day 6) plans again under a real lock before it changes anything. `-lock-timeout` is deliberately not set, because it has no effect when the lock is disabled; a successful run with no lock output confirms that.

**Permissions and who posts the comment**
1. One job that plans and also comments, holding both `id-token: write` and `pull-requests: write`. Rejected: the job that executes pull request code under an Azure login would also hold a token able to edit pull request comments.
2. Two jobs. Chosen. The plan jobs hold `contents: read` and `id-token: write` and cannot write to the pull request. A separate `comment` job holds `contents: read` and `pull-requests: write` and has no Azure login and no Terraform. A job-level `permissions` block replaces the workflow-level one, so every unlisted scope is none. Accepted risk: plan text contains names that a pull request author controls, and a crafted name could break out of the code fence in the comment. The consequence is cosmetic or a mention in a comment, not access to anything.

**Exit codes**
1. Plain `terraform plan`. Rejected: it exits 0 whether or not anything would change, so a green check says nothing about whether the change is empty.
2. `-detailed-exitcode`, with 0 and 2 both treated as success and 1 as failure. Chosen. 2 means "there are changes", which is the normal result of an intended change and must not turn the check red. 1 means the root could not be planned and does. The step turns off `-e` around the command, captures the code, and writes the output to a file instead of piping it, so the code is Terraform's own and not that of a later command in the pipe.

**Identifiers in the comment**
1. Rely on GitHub's log masking. Rejected, and this is not hypothetical: log masking applies to log output only, not to files or comments. The first version of the comment job posted a real subscription ID into a public pull request. The comment was deleted and the affected runs removed.
2. Two layers. Chosen. The plan step replaces every GUID-shaped string (subscription, tenant and object IDs among them) with `***` before the output is written to the artifact. The comment job then refuses to post if any GUID-shaped string is still present in the body. The gate fails closed. Masking by shape also covers identifiers that nobody thought to list.

**How Terraform signs in**
1. The `azure/login` action, then Terraform using the Azure CLI session. Rejected: it adds an action to the supply chain and a second sign-in path next to the one Terraform already has.
2. Terraform's own OIDC support (`ARM_USE_OIDC=true` with client, tenant and subscription IDs) for both the provider and the `azurerm` backend. Chosen. One path, and it was proven in CI. Its cost is a misleading failure: without `id-token: write` the job has no token, Terraform falls back to the Azure CLI, and the error says `Please run 'az login'`. That was observed by removing the permission on purpose; every leg failed at `terraform init`, closed, and the comment showed `NO RESULT` for all eight roots.

**Superseded runs**
1. Let every run finish. Rejected: pushes in quick succession pile up runs and the comment is rewritten by stale ones.
2. A concurrency group per pull request with `cancel-in-progress: true`. Chosen. It is safe here only because the plan holds no lock (see above), so cancelling cannot leave a lease behind. The apply workflow must not copy this setting.

## Decision

A workflow, `.github/workflows/plan.yml`, runs on `pull_request` only. A first job discovers the Terraform roots by `backend.tf` and fails if it finds fewer than 8. One matrix leg per root signs in as the plan identity through Terraform's native OIDC support and runs `terraform plan -lock=false -detailed-exitcode`; exit codes 0 and 2 are success and 1 is failure. Operator-specific inputs come from repository secrets declared in `bootstrap/github-repo-settings.sh`. GUID-shaped strings are masked before the output is written and checked again before it is posted. A separate comment job with write access only to pull requests posts one comment per pull request and updates it in place. A superseded run is cancelled.

## Consequences

- A reviewer sees the plan of all eight roots on the pull request, including a clear `ERROR` or `NO RESULT` row when a root cannot be planned.
- The floor of 8 is a hard-coded number. Deliberately adding or removing a root means editing it in the same pull request.
- The repository secrets are copies. A value changed in the operator's shell or in Azure does not change the copy until `bootstrap/github-repo-settings.sh` is rerun, and the failure mode is silent: a plausible but wrong plan, not an error. This produced a false diff of six notification blocks during this work.
- A plan can be stale if an apply writes state while it reads. It is advisory, not a gate on correctness.
- The comment is public. Resource names and structure in the plan are visible to anyone who can see the repository; only GUID-shaped strings are masked.
- A pull request from a fork gets no login and no secrets and fails closed. That behaviour follows from how GitHub treats forks and has not been exercised end to end here.

## Deferred

- A `plan-gate` job. Matrix leg names depend on the discovered directories, so they cannot be listed as required checks the way the validate workflow's gate is. Plan is not yet a required check on `main`.
- A pull request from a fork, tested end to end. It needs a second GitHub account.
- Cancellation of a superseded run was designed for but not exercised.
- The apply workflow, with its own identity, a protected environment and `cancel-in-progress: false` (Day 6).
