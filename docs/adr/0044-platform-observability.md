# ADR-0044: Platform observability: one Log Analytics workspace, diagnostic settings enforced by policy, an alert on the daily cap

- **Status:** Accepted
- **Date:** 2026-11-13
- **Deciders:** platform-team (@teegalaajay)
- **Relates to:** ADR-0010 (platform Key Vault, 90-day soft delete); ADR-0011 (budget, same recipient list); ADR-0013 (apply
  identity condition); ADR-0040 (governance root, `Deny` assignment at `mg-platform`); ADR-0041 (identity design);
  ADR-0042 (resolver subnets, Private Link later)

## Context

The platform had no central place for resource logs. A Key Vault that holds the Ansible vault passwords and the pipeline
SSH key (ADR-0010, ADR-0020) wrote its audit events nowhere. This ADR records the workspace that receives them, how a
diagnostic setting reaches every vault without a human adding it, what notifies us when the workspace stops collecting,
and what Defender for Cloud does on this subscription today. Sources are the Azure Policy and Azure Monitor documentation
(read) and the observations of 2026-11-13 (observed). A workspace bills by ingestion, so the cost of each choice is named.

## Options considered and decisions

1. **Daily cap: 0.2 GB per day.** Ajay's reason: an alert will tell us and the cap can be raised later. Limit: raising the
   cap does not recover lost logs. At the 2.76 USD per GB list price (Retail Prices API, `eastus2`, 2026-11-13) the ceiling
   is about USD 16.56 a month. The Azure documentation says the cap does not stop collection at exactly the set level and
   excess data is billed (read), so the ceiling is soft. Cost: when the cap is reached, collection stops for every source
   until the daily reset, including the audit trail.
2. **Retention: 90 days.** Ajay's reason: it costs little and matches the 90-day Key Vault soft delete (ADR-0010). Retention
   beyond 31 days is priced at about USD 0.12 per GB-month (list price; the 31 free days come from one blog source). Cost:
   small at this volume.
3. **Diagnostic setting table mode.** Session 1 recorded resource-specific tables. The built-in policy used here does not
   set the destination type (read from both Key Vault built-ins), so the setting it creates writes to the legacy
   `AzureDiagnostics` table (observed). Accepted for now; the upgrade path is a custom policy definition that sets
   `Dedicated`, not built. Cost: Key Vault rows share a table with other resource types' rows.
4. **`platform/management` is in `APPLY_ROOTS`, with a `CanNotDelete` lock and `prevent_destroy`.** No reason recorded.
   Cost: a bad merge changes the workspace through CI with the `production` approval as the only gate, and the first CI
   apply of the root has not run.
5. **`data_classification = confidential`** on the workspace and its resource group: audit logs of platform resources, the
   same class as the vault.
6. **Local authentication off on the workspace.** Reason (reasoned): a leaked shared key could inject log lines. Observed:
   with it off, events from the vault's diagnostic setting arrived in the workspace.
7. **Both internet flags stay on** (ingestion and query) until Private Link exists (Week 10). Accepted risk; Entra
   authentication and RBAC are the controls meanwhile.
8. **Where the enforcing assignment lives.** A separate assignment `diag-keyvault-to-law` in `platform/governance`, with a
   system-assigned identity. Reason: the identity must exist before the roles that let it write, and the governance root
   already owns assignments at `mg-platform` and is applied by hand because role assignments sit outside the apply
   identity's condition (ADR-0013, ADR-0040). Cost: the root reads the workspace ID from the `platform/management` state
   (`terraform_remote_state`), so the management root must be applied first.
9. **Built-in definition `bef3f64c` (version 3.0.0)** over `951af2fa` (2.0.1). Reason: its existence test is stricter (read
   from the definition: the setting must carry an `AuditEvent` log entry and a metrics entry). Cost: the setting it creates
   also enables `AzurePolicyEvaluationDetails`, which we did not choose (observed); the category's volume is not yet known.
10. **`matchWorkspace = true`.** A vault whose setting points at another workspace does not satisfy the policy (reasoned).
    Cost: such a vault would receive a second setting from remediation (not tested).
11. **Roles for the assignment's identity.** Monitoring Contributor at `mg-platform`; Log Analytics Contributor on the
    workspace only. Reason: the setting must be writable on any vault under the group, including subscriptions added later,
    while the workspace is the single destination. Cost: Monitoring Contributor at the group is broad (it can write
    diagnostic settings and alert rules on everything below it).
12. **Alert on the cap: one rule.** A log search alert rule with the query documented for the daily cap, count greater than
    0, every 5 minutes, severity 2, notifying one action group. Alternative: a second, earlier warning rule. Reason for one
    rule: volume is unmeasured (observed: 2 rows in a day from one vault), and a threshold set before a measurement is a
    guess. Cost: the rule fires after collection has stopped, so it reports the loss and cannot prevent it. A 5-minute log
    rule is about USD 1.50 a month according to secondary sources; the official price was not read (the Retail Prices API
    returned no rows for two filters). Not compared with Cost Management.
13. **Recipients: a new variable, the existing secret.** `alert_contact_emails` (sensitive list, validated) is filled in CI
    from the repository secret `BUDGET_CONTACT_EMAILS`, and on the workstation from `TF_VAR_budget_contact_emails`.
    Reason: no new secret and no change to the settings script, and the variable name states its purpose. Cost: one secret
    feeds two purposes, so the two lists cannot differ without a later change. Only the count of recipients is made
    non-sensitive, so the addresses stay out of plans.
14. **Defender for Cloud: read only, nothing enabled.** All per-resource paid plans are `Free` (off). `FoundationalCspm`
    shows `Standard`; the documentation describes foundational CSPM as the free plan enabled by default (read). `Discovery`
    also shows `Standard` and is unexplained (below). Cost: no threat protection on vaults, storage, registry or AKS.

## Observed (2026-11-13)

- Workspace, resource group and lock applied by hand from the branch (`3 added`), second plan `No changes`.
- The assignment and its two role assignments applied by hand (`3 added`), second plan `No changes`; the role writes at
  `mg-platform` worked with the operator's login. Policy state for the platform vault was `NonCompliant` (evaluated
  20:31:16 UTC, not visible until between 20:36:48 and 20:40:08 UTC) with no diagnostic setting present.
- Remediation task `rem-kv-diag-001` created from the CLI at 20:41:26 UTC; read `Succeeded`, 1 of 1 deployments, 0 failed at
  20:51:12 UTC (the finish time was not captured). The deployment passed the `Deny` assignment of ADR-0040.
- At 20:52:51 UTC the platform vault had one setting, `setbypolicy_logAnalytics`, to the workspace: logs `AuditEvent` and
  `AzurePolicyEvaluationDetails` on, `AllMetrics` present and off, destination type `AzureDiagnostics`.
- A new vault in a throwaway group (created from the CLI, purge protection left at the default) finished creating at
  21:06:15 UTC with no setting at 21:06:33 and 21:07:15 UTC, and had the same setting at 21:13:30 UTC, with no remediation
  task. The window is about 1 to 7 minutes after creation, bounded by two reads. An explicit purge-protection value of
  `false` is refused by Azure (`BadRequest`); the property is left out, not set to false.
- The test group was deleted at 21:30:02 UTC and the vault purged at 21:35:02 UTC; at 21:37:51 UTC the group did not exist,
  the soft-deleted list was empty and the platform vault still had its setting. Soft delete retention is 90 days.
- The compliance report never showed a record after the setting existed: the policy state list for the assignment was empty
  at 20:53:46, 20:54:59, 20:57:20 and 21:15:53 UTC, after a subscription scan started at 21:17:29 UTC it was empty at
  21:23:43, and `summarize` was empty at 21:24:02. Not explained.
- Action group `ag-platform-shared` (location `global`) and rule `alert-law-daily-cap-reached` applied by hand (`2 added`) at
  22:09:15 UTC; second plan `No changes`. The `global` location passed the allowed-locations rule. No `identity` block was
  set on the rule and the apply succeeded.
- At 22:15:01 UTC the workspace held 2 `AuditEvent` rows from the last day, and the alert's own query ran against
  `_LogOperation` and returned no rows. The first events reached the workspace with local authentication off.
- Defender for Cloud (22:17 UTC): every per-resource plan is `Free`; `FoundationalCspm` and `Discovery` are `Standard`.
  `Discovery` has no enablement time, no sub-plan and no extensions, and its free-trial counter reads zero.

## Read, not tested

- A policy with `deployIfNotExists` deploys after a resource is created or updated, and reports existing resources as
  non-compliant until a remediation task runs (Azure Policy documentation).
- When the daily cap is reached an event is written to the workspace operation table; the documented alert is a log search
  rule on `_LogOperation` with `OverQuota` in the detail, and creating it needs `Monitoring Contributor`.
- Foundational CSPM is free and enabled by default; the paid Defender CSPM plan is priced per billable resource (about USD
  5 a month according to one secondary source).

## Unproven

- The first CI apply of `platform/management` (the runner is offline and the run waits for the `production` approval).
- The alert actually firing and the email arriving; what the cap loses when it is reached.
- That the lock blocks a delete from another client (not tried).
- The compliance report turning `Compliant`, and why it showed no record.
- Remediation or a new vault when a vault already has a setting to another workspace (decision 10).
- Whether the rule needs an `identity` block to read the workspace when it runs; the apply and the query test suggest not.
- A custom definition that sets `Dedicated`; the volume of `AzurePolicyEvaluationDetails`.
- Price figures against Cost Management (ingestion list prices, the alert rule, the workspace); what `Discovery` is and
  whether it bills.
- The assignment name limit at management group scope (the name is 20 characters).

## Consequences

- Every new Key Vault under `mg-platform` gets a setting to the workspace within minutes, with no human step. An existing
  vault needs a remediation task once; it is a CLI one-off and is in the runbook.
- Roots that create the destination (`platform/management`) must be applied before `platform/governance` is planned; the
  governance plan leg reads the workspace ID from state.
- `plan.yml` and `apply.yml` pass `TF_VAR_alert_contact_emails` from `BUDGET_CONTACT_EMAILS`; without it the management leg
  fails on a missing variable.
- The cap alert reports after the fact; an earlier warning is added when ingestion is measured over several days.
- Owed: Cost Management comparison; the custom `Dedicated` definition; diagnostic settings for other resource types
  (storage, registry, firewall) as separate assignments; Private Link for the workspace (Week 10).
