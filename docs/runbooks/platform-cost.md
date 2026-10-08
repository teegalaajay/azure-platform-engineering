# Runbook: subscription cost budget (`platform/cost`)

**Purpose:** Deploy, verify and change the subscription budget (ADR-0011).
**Owner:** platform-team · **Last validated:** 2026-10-08 · **Persistent:** yes (an alerting guardrail; no resources to pay for)

Placeholders: `<ALERT_EMAIL>`. Real values are never committed to this public repository.

## 1. Layout

| Root | State key | Resources |
|---|---|---|
| `platform/cost` | `platform/cost.tfstate` | `budget-platform-shared-monthly` (subscription scope, USD 50 monthly, 6 alerts) |

No dependency on any other root. The billing-account budget `Overall` is not managed here (ADR-0011).

## 2. Deploy or converge (from `main` only)

Prerequisites: `az login --tenant <TENANT_ID>`; `ARM_SUBSCRIPTION_ID` exported; the recipients exported as a JSON list. One Terraform session per state key at a time.

```bash
export TF_VAR_budget_contact_emails='["<ALERT_EMAIL>"]'
cd platform/cost
terraform init
terraform plan -input=false
terraform apply
terraform plan -input=false   # expect: No changes
```

The plan prints the notification blocks as `(sensitive value)` and must never show the address. If the address appears anywhere in the output, stop and do not paste it into a PR.

Persist the variable with the same guarded-append pattern as the other `TF_VAR_` lines (workstation-setup section 14). Without it, a new shell makes `plan -input=false` fail with a missing-variable error.

## 3. Verify (Azure is the source of truth, not the plan)

The query below omits `contactEmails`, so its output is safe to paste.

```bash
az rest --method get --url "https://management.azure.com/subscriptions/$ARM_SUBSCRIPTION_ID/providers/Microsoft.Consumption/budgets?api-version=2023-05-01" --query "value[].{name:name, amount:properties.amount, grain:properties.timeGrain, start:properties.timePeriod.startDate, alerts:properties.notifications.*.{op:operator, pct:threshold, type:thresholdType, enabled:enabled}}"
```

Expected: one budget `budget-platform-shared-monthly`, amount 50, grain Monthly, start `2026-10-01T00:00:00Z`, six enabled alerts (Actual and Forecasted at 50, 80, 100). Alert order is not significant.

## 4. Change

| Change | How | Effect |
|---|---|---|
| Amount | `monthly_budget_usd` in `cost.auto.tfvars`, PR | in-place update |
| Thresholds | `alert_thresholds` in `cost.auto.tfvars`, PR | in-place update, notifications added or removed |
| Recipients | change `TF_VAR_budget_contact_emails`, then plan/apply | in-place update; the plan shows only `(sensitive value)`, verify the count in ARM |
| Name | do not | forces replacement; alerts are briefly missing |

## 5. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `No value for required variable` / missing `budget_contact_emails` | the `TF_VAR_` export was lost with the shell | export it again, or add the guarded line |
| Validation error on `budget_start_date` | not the first day of a month, or wrong format | use `YYYY-MM-01T00:00:00Z` |
| Apply rejects the start date | Azure refuses a start date it considers too old or invalid | use the first day of the current month |
| No alert emails although spend is high | cost data lags usage, or the recipient list is wrong | wait; check the recipients in the portal budget view |

## 6. Teardown

Do not destroy. Destroying removes the platform's only spend alert and leaves nothing in its place except the billing-account backstop. If it must go, replace it first.
