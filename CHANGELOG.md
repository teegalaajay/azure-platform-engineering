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

### Changed
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

### Fixed
- `modules/storage` v1.0.1: `tags` validation rejects null or blank values for the six mandatory
  tags (it previously checked key presence only, so `owner = null` or `""` passed).
