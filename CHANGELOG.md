# Changelog

All notable changes to this repository are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Modules are versioned separately with `modules/<name>/vX.Y.Z` tags.

## [Unreleased]

### Added
- Repository governance: protected `main` (pull request only, squash merge, linear history,
  empty bypass list), pull request template, CODEOWNERS.
- Quality gates: pre-commit hooks (formatting, Terraform validate, tflint, yamllint, gitleaks)
  frozen to commit SHAs; tflint with the pinned azurerm ruleset.
- Architecture Decision Records 0001–0004.
- README with scenario, target architecture and status; security policy.
- `bootstrap/github-repo-settings.sh` and the workstation-setup runbook.
- Remote state backend: `bootstrap/state-backend.sh` (resource group, GZRS storage account with
  shared key disabled, blob versioning and soft delete, `tfstate` container, operator data role),
  ADR-0005 and the state-backend runbook.
- Editor settings that match the whitespace pre-commit hooks.
- `modules/storage`: storage account with a fixed security baseline (shared key disabled, TLS 1.2,
  HTTPS only, no public blob access, versioning and 30-day soft delete) and validated inputs.
- Workload roots `workloads/storage-demo/{dev,prod}` with separate state keys; prod uses GRS and a
  `CanNotDelete` lock protected by `prevent_destroy`. ADR-0006.
- `modules/network`: one VNet with `for_each` subnets, one NSG per subnet with caller allow rules
  (priority 100-3999) and a hardcoded `deny-vnet-inbound` baseline at 4000, standalone
  subnet/NSG association resources, ID outputs keyed by subnet.
- Persistent root `platform/foundation/hub`: `vnet-hub-shared` (`10.20.0.0/16`) with `snet-mgmt`
  (Storage and Key Vault service endpoints, no inbound allow rules). ADR-0007 and the
  network-foundation runbook.
- Persistent roots `platform/foundation/{dev,prod}`: `vnet-spoke-dev` (`10.10.0.0/16`) and
  `vnet-spoke-prod` (`10.11.0.0/16`) with `snet-app` and `snet-data`, NSG rules per ADR-0007, and
  hub peering in both directions. The hub VNet and `snet-mgmt` prefix are read with data sources;
  the operator IP is a sensitive `TF_VAR_operator_ip_cidr` input, never committed.
- `modules/linux-vm`: private Linux VM and NIC with a fixed baseline (no public IP, SSH key only,
  trusted launch, Gen2 Ubuntu 24.04), required `size` and `zone`, optional static private IP,
  validated tags.
- Workload root `workloads/vm-demo/dev`: reads the dev spoke from the foundation state, deploys the
  VM with a static IP in `snet-app` and an interim NAT Gateway for explicit egress. ADR-0008.
- Runbook `storage-demo` (deploy, verify, 403 troubleshooting by error code, lock-out recovery).
- Persistent root `platform/security`: shared Key Vault `kv-plat-shared-at01` (RBAC authorization, purge protection, 90-day soft delete, firewall Deny with bypass None, allowed hub `snet-mgmt` and operator IP),`prevent_destroy` and a `CanNotDelete` lock, operator Key Vault Secrets Officer at vault scope, root outputs for consumers. ADR-0010 and the platform-security runbook.
- Workstation runbook: `TF_VAR_operator_object_id` guarded append.
- Persistent root `platform/cost`: subscription budget `budget-platform-shared-monthly` (USD 50 per
  month, Actual and Forecasted alerts at 50/80/100 percent) in its own state key. Recipients come
  from a sensitive `TF_VAR_budget_contact_emails`, never committed. Replaces the portal budget
  named `undefined`. ADR-0011 and the platform-cost runbook.
- `.github/workflows/validate.yml`: discovers every directory with a `versions.tf` (floor of 11) and
  runs `terraform fmt -check`, `init -backend=false`, `validate` and `tflint` in each, with no
  cloud credentials. A `validate-gate` job is the single required check. Terraform 1.16.4, tflint
  v0.64.0, third-party actions pinned by SHA. ADR-0012 and the ci-validate runbook.
- `modules/linux-vm`: optional, sensitive `custom_data` input for first-boot cloud-init (default null).
- `modules/runner-vm`: cloud-init that installs the Azure CLI and Terraform from vendor repositories
  with key-fingerprint checks, a non-root `runner` user, and a pinned, checksum-verified GitHub
  Actions runner registered with `--ephemeral`.
- Ephemeral root `platform/runner`: runner VM in `snet-mgmt` with an interim NAT Gateway; the
  registration token is supplied inline at apply time.
- `.github/workflows/apply.yml`: apply on merge, one job on the self-hosted runner behind the
  `production` environment, persistent roots in dependency order, with a check that every root is
  classified. `.github/actionlint.yaml` declares the custom runner label. ADR-0015 and the
  `github-runner` runbook.
- The plan workflow passes a plan-only placeholder for the runner's registration token.
- `ansible/`: pinned control-node dependencies (`ansible-core` 2.21.5) and a first playbook
  (`playbooks/first.yml`). ADR-0016 (practice target outside the platform network) and the
  `ansible-control-node` runbook.
- `ansible/playbooks/web.yml`: installs nginx (`apt` with `cache_valid_time`), ensures it is started
  and enabled (`service`), renders the landing page (`templates/index.html.j2`) and an nginx
  response-header snippet (`templates/headers.conf.j2`) with `template`, and reloads nginx through a
  handler only when the snippet changed. Values come from play `vars`; every task has a tag;
  `become` and `force_handlers` are set on the play. The target host is chosen by inventory at
  run time.
- Runbook `ansible-control-node`: web playbook run and verify steps, first contact with a rebuilt
  target (host key), troubleshooting by symptom; corrected the SSH key name.
- Runbook `ansible-control-node`: variables and templates, handlers, tags, the lint and syntax
  gate, and two new symptom rows (undefined template variable; file new but service stale).
- ADR-0017 (handler failure policy: `force_handlers`).
- `ansible/roles/web`: the nginx configuration as a role (tasks, handler `Reload nginx`, templates,
  `defaults/main.yml` with `web_root`, `web_owner` and `site_title`, Galaxy metadata
  `teegalaajay.web`, MIT). The role has no `vars/` directory.
- `ansible/site.yml`: entry playbook beside `roles/`; it sets the target, `become`, fact gathering
  and `force_handlers`, and calls the role.
- ADR-0018 (role layout, entry playbook, variable policy, observed precedence order).
- Runbook `ansible-control-node`: role layout, `site.yml` commands, variable precedence, the
  template search order, and symptom rows for a missing role and a missing template.
- Azure dynamic inventory: `ansible/requirements.yml` (`azure.azcollection` 4.1.0),
  `ansible/requirements-azure.txt` and `ansible/constraints.txt` (locked Python dependencies),
  `ansible/inventory/sandbox.azure_rm.yml` (`auth_source: cli`, `compose`, `keyed_groups`).
- ADR-0019 (Azure dynamic inventory, dependency pinning, inventory identity, observed failure
  behaviour) and runbook `ansible-control-node` section 5b with new symptom rows.
- Ansible Vault strategy (ADR-0020): vault password in Key Vault (`ansible-vault-<label>`), client
  script `ansible/scripts/vault-pass-client.sh` with a label allow-list, root `ansible.cfg`
  (`vault_identity_list`, `vault_encrypt_identity`, `vault_id_match`), `ansible-vault-encrypted`
  pre-commit hook, rotation procedure and six troubleshooting rows in the Ansible runbook (5c).
- ansible-lint 26.10.1 and Molecule 26.10.0, pinned in `ansible/requirements.txt` with `ansible/constraints.txt` regenerated; `.ansible-lint` (profile `production`, `.github/` excluded) and a local `ansible-lint` pre-commit hook that runs the venv's copy.
- Molecule scenario `ansible/roles/web/molecule/default/`: test sequence syntax, create, converge, idempotence, verify, destroy against the sandbox VM (Terraform owns the VM; the address comes from `MOLECULE_TARGET_ADDRESS`; no address committed). `verify.yml` asserts the package, service, landing page, `X-Platform` header, file owner and mode, and `nginx -t`. Guard plays fail the run if the inventory has no host.
- ADR-0021 (ansible-lint and Molecule, with the observed behaviour) and runbook `ansible-control-node` section 5d with new troubleshooting rows.
- Azure DevOps identity for Azure: `bootstrap/ado-oidc.sh` (app `app-ado-plan-shared`, Reader on the subscription, federated credential from environment values, no secret), manual workload identity federation service connection, the Azure Pipelines GitHub App on one repository, and the read-only `ado-auth-check` pipeline (`pipelines/ado-auth-check.yml`) with a denied-write step. ADR-0022 and the ado-service-connections runbook.
- Azure DevOps pipeline `ado-terraform-validate` (`pipelines/ado-terraform-validate.yml`): `fmt -check`, `init -backend=false` and `validate` on every Terraform directory (floor 13) on the pinned image `ubuntu-24.04`, with Terraform 1.16.4 downloaded into `$(Agent.TempDirectory)` and checked against a pinned SHA-256 taken from the signed `SHA256SUMS`. `trigger` on `main` and `pr` to `main` with a path filter. No service connection and no Azure identity. Informational: the GitHub `validate-gate` stays the required check. ADR-0023 and the `ado-terraform-validate` runbook.
- Self-hosted Azure DevOps agent: module `modules/ado-agent-vm` (wraps `linux-vm`; cloud-init installs a checksum-verified agent as the non-root user `agent` and registers it with a token read from Key Vault at first boot), persistent root `platform/agent-identity` (user-assigned identity `id-ado-agent-shared` with Key Vault Secrets User on the platform vault) and ephemeral root `platform/ado-agent` (VM in `snet-mgmt` with its own NAT Gateway, outputs for the resource group, VM, private IP and egress IP).
- ADR-0024 (identity, secret access and module structure for the agent) and runbook `ado-agent` with the boot-log diagnosis ladder.
- `.terraform-version` (single source for the Terraform version) and two consistency checks in `scripts/` (`check-terraform-version.sh`, `check-cloud-init-drift.sh`), run as pre-commit hooks and as a step of the `validate` workflow's `discover` job; ADR-0025; runbook `ci-validate` section 7.
- Azure DevOps pipeline `ado-agent-check` (`pipelines/ado-agent-check.yml`): manual runs on `pool-platform-shared`; proves the job runs as the non-root `agent` user and that the VM's managed identity lists Key Vault secret names (no values). Observed results added to ADR-0024; runbook `ado-agent` gains the permit step and a symptom row for a read-only subscription.
- Azure DevOps environment `pipeline-demo-dev` with an Approvals check (one approver, timeout 1 day) in front of the Deploy stage; ADR-0027. The environment is built in the portal and described in runbook `ado-terraform-deploy`.
- `bootstrap/ado-agent-fic.sh`: idempotent script that creates the federated credential on `id-ado-agent-shared` from the issuer and subject of the draft service connection (ADR-0024).
- `ado-agent-check` reads one test secret value through the service connection `sc-azure-keyvault-shared` and checks its length; runbook `ado-agent` section 6 and ADR-0024 record what was observed.
- `pipelines/ado-terraform-deploy.yml`: Azure DevOps multi-stage Terraform pipeline (Build, Plan, manual Deploy behind a `deploy` parameter) with a shared native-OIDC sign-in template and a pinned-Terraform install template; ADR-0026 and runbook `ado-terraform-deploy`.
- `workloads/pipeline-demo/dev`: one resource group with the mandatory tags, the target of that pipeline.
- `bootstrap/ado-oidc.sh`: apply identity `app-ado-apply-shared` (Contributor at the subscription, Storage Blob Data Contributor on the state container) and its federated credential.
- `pipelines/templates/terraform-setup.yml`: one steps template holding the checkout and the pinned Terraform install, used by the validate, plan and apply jobs of `ado-terraform-deploy`; ADR-0028.
- `pipelines/templates/failure-report.yml`: a failure-report step (`condition: failed()`, one `##vso[task.logissue type=error]` line built from fixed non-secret variables), the last step of the `validate`, `plan`, `apply` and `configure` jobs of `ado-terraform-deploy`; ADR-0033.
- `.github/workflows/validate.yml`: job `secrets` scans the full Git history with a pinned gitleaks 8.30.0 and fails on a wildcard `SecretsFilter`, shell tracing or `TF_LOG` in `pipelines/` and `.github/workflows/`; `validate-gate` needs it; ADR-0032 (PR #48).
- ADR-0034 and runbook `rebuild-drill`: the two ephemeral workload roots and the agent destroyed and rebuilt from the pipelines, timed; README decisions table and status table updated.
- ADR-0032 (item F3) and ADR-0033 amended with the observed cancel test and the failure report in the `plan` job.
- `containers/hello-web`: a sample Flask application packaged as a multi-stage image that runs as numeric user 10001, with a `.dockerignore`. Built and run locally; no pipeline builds it yet. ADR-0035.
- ADR-0035: Docker Engine installed from Docker's apt repository, pinned to 29.9.3 and held; the `docker` group; image source under `containers/`; the image baseline. README layout, decisions and status tables updated.
- Runbook `workstation-setup`: section 6b (Docker Engine), a Docker row in the validated baseline, and three known traps found while restarting WSL for the group change.
- `platform/registry`: persistent root with `rg-registry-shared` and a Basic container registry (`crplatsharedat01`): admin user off, public endpoint (Basic has no network rules), mandatory tags, outputs for consumer roots; added to `APPLY_ROOTS` in `.github/workflows/apply.yml`. ADR-0036 and runbook `platform-registry`; README decisions and status tables updated.
- `.github/workflows/validate.yml`: job `image` lints `containers/hello-web/Dockerfile` with hadolint 2.15.1, builds the image and scans it with Trivy 0.76.2 (both pinned by SHA-256); HIGH and CRITICAL fixable findings fail the job and `validate-gate` requires it. ADR-0037; runbook `ci-validate` section 8.
- `containers/hello-web/Dockerfile`: the final stage upgrades `zlib1g` to the fixed version after the first scan failed on it (a debt; see ADR-0037).
- `platform/aks`: ephemeral AKS root, applied by hand and destroyed after use. Resource group, user-assigned control-plane identity with `Network Contributor` on `snet-aks-nodes`, Azure CNI Overlay cluster (Free tier, two-node system pool tainted `CriticalAddonsOnly`), one-node user pool, and `AcrPull` for the kubelet identity on the registry (`grant_acr_pull`). A plan-time `precondition` fails if no inbound Allow rule on the node NSG has `pod_cidr` as its source. ADR-0038; runbook `platform-aks`.
- `platform/governance`: persistent root, applied by hand and listed in `SKIP_ROOTS` of `.github/workflows/apply.yml`. Management group `mg-platform` under the tenant root with the subscription associated, a custom policy definition for storage shared key access and the built-in allowed locations policy in the `platform-baseline` initiative, assigned at the group with Deny. ADR-0040; runbook `platform-governance`; README decisions, status and deploy tables updated.
- ADR-0041: identity design on paper (bootstrap scripts kept with an exit condition, PIM and Conditional Access as design only, direct role assignment for the one human); no Azure change.

### Changed
- `.github/workflows/plan.yml`: the root-count floor `MIN_DIRS` is 14 (the registry root is the fourteenth).
- `README.md`: decisions table lists ADR 0016 to 0025; status table and "Deploying from zero" brought up to date (the backend, CI identities and platform roots exist; Ansible and Azure DevOps are in place; the apply run succeeded on 2026-10-16); layout rows for `platform/`, `pipelines/` and `scripts/`.
- `.github/workflows/plan.yml`: the comment above the runner placeholder is indented like the keys around it (no behaviour change).
- `ansible/playbooks/web.yml` moved to `ansible/site.yml` and reduced to a play that calls the
  role; `ansible/playbooks/templates/` removed (the templates now live in the role). Run
  `ansible-playbook ansible/site.yml` instead of `ansible/playbooks/web.yml`.
- `modules/network`: subnets set `default_outbound_access_enabled = false` (private subnets, no
  implicit outbound IP). In-place update on all five foundation subnets, no replacement.
  ADR-0007 records the egress decision.
- `workloads/storage-demo/{dev,prod}`: mandatory tags built once with `locals` + `merge()`;
  per-environment values moved to `variables.tf` + committed `*.auto.tfvars` (no defaults, so a
  missing value fails `plan -input=false`); root `outputs.tf` exposes identifiers only.
  Completes the root file set (engineering_standards §2). No resource changes.
- **BREAKING** `modules/storage` v2.0.0: storage firewall hardcoded to default action Deny with
  bypass AzureServices and `public_network_access_enabled = true`. New required inputs
  `virtual_network_subnet_ids` and `ip_rules` (validated: subnet ID format, IPv4 format, no
  RFC 1918, no /31 or /32, not both empty). Callers must pass at least one allowed path. ADR-0009.
- `workloads/storage-demo/{dev,prod}`: allow the environment's spoke `snet-app`, the hub
  `snet-mgmt` (read from foundation state) and the operator IP (`TF_VAR_operator_ip_cidr`).
  Prod: in-place update of `stdemoprodat01`, no replacement.
- Pre-commit `yamllint` hook reads the repository `.yamllint` (relaxed, 120 columns) instead of an
  inline `-d relaxed`, so the hook and CI share one configuration.
- `bootstrap/github-repo-settings.sh`: ruleset `protect-main` now requires the `validate-gate`
  check from the GitHub Actions app, with the branch-up-to-date policy.
- **BREAKING** `ansible/roles/web`: variable `site_title` renamed to `web_site_title` (ansible-lint `var-naming[no-role-prefix]`). Callers that pass `site_title` must pass `web_site_title`. No caller exists in this repository. ADR-0018's deferral is reversed (ADR-0021).
- `modules/linux-vm` and `modules/runner-vm`: optional `user_assigned_identity_ids` (default empty, so existing callers plan with no identity block).
- `.github/workflows/apply.yml`: `platform/ado-agent` and `platform/agent-identity` added to `SKIP_ROOTS` (hand-applied; the apply identity's condition does not allow the Key Vault Secrets User assignment, ADR-0013, ADR-0024). `.github/workflows/plan.yml`: discovery floor `MIN_DIRS` 8 to 11 and a plan-only placeholder for the agent root's required organization URL.
- `README.md`: the architecture diagram label for the runner and the ADO agent no longer says both have no managed identity.
- `bootstrap/ado-oidc.sh`: the plan identity gains Storage Blob Data Reader on the `tfstate` container (it could not read state with Reader alone).
- **BREAKING** `bootstrap/ado-oidc.sh` and `bootstrap/ado-agent-fic.sh`: the federated-credential variables are named per connection (`ADO_PLAN_FIC_*`, `ADO_APPLY_FIC_*`, `ADO_KV_FIC_*`); the shared `ADO_FIC_ISSUER` and `ADO_FIC_SUBJECT` are refused by `ado-oidc.sh` and ignored by `ado-agent-fic.sh`.
- `.github/workflows/apply.yml`: `workloads/pipeline-demo/dev` added to `SKIP_ROOTS`.
- Discovery floors now equal the real counts: `plan.yml` 12 roots with a backend; `validate.yml` and `pipelines/ado-terraform-validate.yml` 17 Terraform directories.
- `scripts/check-terraform-version.sh`: covers `pipelines/ado-terraform-deploy.yml`.
- Runbooks `ado-service-connections` and `ado-agent`: variable names updated.
- `pipelines/ado-terraform-deploy.yml`: the Deploy stage is a `deployment:` job bound to environment `pipeline-demo-dev`, with an explicit `checkout: self` (a deployment job does not check out the repository on its own).
- ADR-0026: records the test with an invalid OIDC token (the backend rejects it, no fallback to the Azure CLI session) and narrows the unproven item to the provider path.
- Environment `pipeline-demo-dev` gets a Branch control check (`refs/heads/main` only) in front of the Approvals check, so a deploy can only start from `main`; ADR-0027 amended, runbook `ado-terraform-deploy` updated. Built in the portal.
- ADR-0026 records the stale saved plan refusal (`Saved plan is stale`) as observed and drops it from the unproven list.
- Workload root `workloads/ansible-target/dev`: `vm-ansible-target-dev` in `snet-app` (no public IP) with its own NAT Gateway; the pipeline key's public half is committed in `dev.auto.tfvars`. In `SKIP_ROOTS` (applied by hand). ADR-0029, runbook `ansible-target`.
- `pipelines/ado-ansible-run.yml`: manual pipeline on `pool-platform-shared`; installs a pinned `ansible-core` into a per-run venv, reads the SSH key from Key Vault, runs `ansible/site.yml` twice and fails unless the second run changes nothing, then removes the key file and checks it is gone. Built in the portal.
- `ansible/requirements-pipeline.txt` (the pin) and `ansible/ansible-pipeline.cfg` (no vault settings, so the pipeline needs no `az login`).
- `modules/ado-agent-vm`: cloud-init installs `python3-venv` (after the shared block; the drift check passes).
- `.ansible-lint` excludes `pipelines/`; ADR-0021 amended. ADR-0016 amended (the platform target is built). Runbook `ado-agent` gets section 9.
- Discovery floors raised to the new real counts: `plan.yml` 13 roots with a backend; `validate.yml` and `pipelines/ado-terraform-validate.yml` 18 Terraform directories. `workloads/ansible-target/dev` added to `SKIP_ROOTS` in `apply.yml`.
- `workloads/ansible-target/dev/outputs.tf`: `resource_group_name`, `target_host` and `target_user`; the Ansible job reads the last two instead of a typed address. ADR-0030.
- `pipelines/ado-terraform-deploy.yml`: parameter `terraformRoot` with a two-value allowlist feeding `rootDir`; for the Ansible root a step publishes `targetHost` and `targetUser` as job outputs and a `configure` job in the Deploy stage runs the Ansible steps on `pool-platform-shared`. Needs permits on the pool and on `sc-azure-keyvault-shared` (portal).
- `pipelines/templates/ansible-site-steps.yml`: the Ansible steps of `ado-ansible-run`, moved into a template with `targetHost` and `targetUser` (default `azureuser`, checked). `ado-ansible-run.yml` now calls it.
- `pipelines/templates/terraform-azure-step.yml`: optional `step_name` parameter, so a later job can read the step's output variables.
- Runbooks `ado-terraform-deploy` (section 4 step 5, new section 5a) and `ansible-target` (section 3 item 4) updated.
- `pipelines/ado-terraform-deploy.yml`: the target address and user reach the `configure` job as a pipeline artifact (`handoff`, a four-field JSON file) instead of two job output variables; the job output step and its addressing are removed. ADR-0031 (replaces option 2a of ADR-0030); runbook `ado-terraform-deploy` section 5a updated.
- `retryCountOnTaskFailure: 2` on the "Install pinned Terraform" step (`pipelines/templates/terraform-install.yml` and the inline copy in `pipelines/ado-terraform-validate.yml`) and on the `AzureKeyVault@2` read in `pipelines/templates/ansible-site-steps.yml`; none on plan, apply or the Ansible run. ADR-0033.
- `pipelines/ado-terraform-deploy.yml`: `timeoutInMinutes` 10, 10, 30 and 15 on the `validate`, `plan`, `apply` and `configure` jobs. ADR-0033.
- ADR-0031 amended with the proof run; README decisions table lists ADR-0032 and ADR-0033; runbook `ado-terraform-deploy` gets section 5b and three symptom rows.
- `platform/foundation/dev`: subnet `snet-aks-nodes` (`10.10.8.0/22`, the range reserved in ADR-0007) with its own NSG for the AKS node pool. Two inbound allow rules (`allow-aks-nodes` 200 from the node range, `allow-aks-pods` 210 from the overlay pod range `10.244.0.0/16`) sit above the module's `deny-vnet-inbound`; `modules/network` is unchanged. Variables `aks_subnet_prefix` and `aks_pod_cidr`. Prod is not changed. The pod range is repeated in the cluster root and must stay equal.
- `.github/workflows/apply.yml`: `platform/aks` added to `SKIP_ROOTS`. `plan.yml` root floor 14 to 15; `validate.yml` floor 18 to 20 (it was already one behind). ADR-0007 now records the NSG block and the pod-range mismatch as observed (0 of 12 cross-node DNS lookups without `allow-aks-pods`, 6 of 6 with it); README lists ADR-0038, the AKS status row and `platform/aks` among the hand-applied roots.
- Runbook `workstation-setup`: new section 6c for `kubectl` (v1.36.6, release binary checked by SHA-256, cosign not verified) and a baseline row in section 10; runbook `platform-aks` points to it. Runbook `plan-on-pr`: the `MIN_DIRS` floor is no longer written as 8 (it is 15); the symptom row quotes the real error text.
- Runbook `workstation-setup` section 6c and ADR-0038: the `kubectl` v1.36.6 signature was verified once with cosign (`Verified OK`); the baseline row and the `platform-aks` runbook say so, and the item is removed from the ADR-0038 unproven list.
- `platform/foundation/hub`: subnet `AzureFirewallSubnet` (`10.20.0.0/26`). `platform/foundation/dev`: `allow_forwarded_traffic = true` on both dev peerings; prod unchanged. ADR-0007 records the firewall result (dev to hub and in-VNet traffic are not inspected).
- Ephemeral root `platform/firewall`: Azure Firewall Standard (zones 1 to 3) with a policy (threat intelligence `Deny`, a deny rule from the dev range to the prod range, an application allow for `api.ipify.org` over HTTPS), the firewall created in the hub resource group because Azure requires it, and a route table with `0.0.0.0/0` and the prod range on dev `snet-app`. ADR-0039 and runbook `platform-firewall`. Applied by hand and destroyed the same day.
- `.github/workflows/apply.yml`: `platform/firewall` added to `SKIP_ROOTS`. `plan.yml` root floor 15 to 16. README lists ADR-0039, the firewall status row and `platform/firewall` among the hand-applied roots.
- `.github/workflows/apply.yml`: `platform/governance` added to `SKIP_ROOTS`. `plan.yml` root floor 16 to 17. `validate.yml` directory floor `MIN_DIRS` 20 to 22, the counted number of directories with a `versions.tf`. README lists ADR-0040 and ADR-0041, the governance status row and `platform/governance` among the hand-applied roots.

### Fixed
- `modules/storage` v1.0.1: `tags` validation rejects null or blank values for the six mandatory
  tags (it previously checked key presence only, so `owner = null` or `""` passed).
- Runbook `ado-service-connections`: the symptom row for the OAuth consent screen no longer says it means no GitHub connection exists; the wizard asks for OAuth for each new pipeline, also when the App connection exists (observed 2026-10-29).
- `pipelines/ado-terraform-deploy.yml`: the output step no longer ends silently when `terraform output -raw` prints no trailing newline (`read -r x < <(...) || [[ -n "$x" ]]`).
- `pipelines/ado-terraform-deploy.yml`, `pipelines/templates/ansible-site-steps.yml`: `configure` reads the outputs as `dependencies.apply.outputs['apply.targetOutputs.<name>']` (the `deploy.` form did not resolve), and the address and user checks print the value they received. ADR-0030 amended.
