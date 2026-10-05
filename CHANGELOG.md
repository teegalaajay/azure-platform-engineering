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
### Changed
- `modules/network`: subnets set `default_outbound_access_enabled = false` (private subnets, no
  implicit outbound IP). In-place update on all five foundation subnets, no replacement.
  ADR-0007 records the egress decision.
- `workloads/storage-demo/{dev,prod}`: mandatory tags built once with `locals` + `merge()`;
  per-environment values moved to `variables.tf` + committed `*.auto.tfvars` (no defaults, so a
  missing value fails `plan -input=false`); root `outputs.tf` exposes identifiers only.
  Completes the root file set (engineering_standards §2). No resource changes.

### Fixed
- `modules/storage` v1.0.1: `tags` validation rejects null or blank values for the six mandatory
  tags (it previously checked key presence only, so `owner = null` or `""` passed).
