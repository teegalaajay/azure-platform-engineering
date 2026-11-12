# Runbook: platform-governance (management group, policy initiative and assignment)

- **Purpose:** Keep the management group `mg-platform`, the custom policy, the `platform-baseline` initiative and its
  assignment correct, change the effect between `Audit` and `Deny`, and prove a change. See ADR-0040 and ADR-0041.
- **Owner:** platform-team
- **Last validated:** 2026-11-11 (apply, audit proof, deny proof, move out and back; not rebuilt from zero since)
- **Persistent:** Yes. The root stays applied. It costs nothing.

## Layout

| Item | Value |
|---|---|
| Root | `platform/governance`, state key `platform/governance.tfstate` in the shared backend |
| Group | `mg-platform`, display name "Platform", under the Tenant Root Group |
| Definition | `storage-shared-key-disabled` (custom, `Indexed`, stored at `mg-platform`) |
| Initiative | `platform-baseline`: members `storage-shared-key-disabled` and `allowed-locations` (built-in `e56962a6-4747-49cd-b67b-bf8b01975c4c`) |
| Assignment | `platform-baseline` at `mg-platform`, no identity; parameters `effect` and `allowedLocations` (`eastus2`, `centralus`) |
| Placement | `association.tf` puts `sub-platform-shared-001` under `mg-platform`; removing it moves the subscription back to the root |
| Applied by | hand, as the creator-Owner of the group. The root is in `SKIP_ROOTS` of `apply.yml` |

## Before you start

1. `az account show --query name -o tsv` prints `sub-platform-shared-001` and the default subscription equals
   `ARM_SUBSCRIPTION_ID` (the CLI can also hold another account's subscription).
2. `az account management-group show --name mg-platform --expand --query "children[].displayName" -o tsv` lists the
   subscription.
3. `terraform plan` in `platform/governance` is `No changes`.
4. Mask GUIDs before pasting anything: the subscription ID appears in scope paths and in error text.

## Change the effect (Audit to Deny and back)

1. Edit the one value `effect = { value = "..." }` in `assignment.tf`. The definition and the initiative do not change.
2. `terraform plan`: expect `0 to add, 1 to change, 0 to destroy`, the assignment in place and not replaced. If it says
   `must be replaced`, stop.
3. `terraform apply`. Then wait a short time before testing; the delay was not measured.
4. Test with the request that should now be refused: `az storage account create` in `westus2` with
   `--allow-shared-key-access true`, in a throwaway resource group. Under `Deny` expect `RequestDisallowedByPolicy`
   naming both rules; under `Audit` expect success and a `NonCompliant` record after a scan.
5. Delete the throwaway resource group and check `az group exists` prints `false`.

Before switching to `Deny`, read the `NonCompliant` list: `az policy state list --filter "policyAssignmentName eq
'platform-baseline' and complianceState eq 'NonCompliant'"`. Our own pipelines are subject to the rule once it denies.

## Read the compliance state

- Start a scan: `az policy state trigger-scan --no-wait` (prints nothing). Wait several minutes.
- List the rows: `az policy state list --filter "policyAssignmentName eq 'platform-baseline'"`, with `--query` to
  limit the columns.
- Do not rely on `az policy assignment list --scope <subscription>` to prove inheritance: it showed only
  `SecurityCenterBuiltIn` while the policy state showed the baseline applying (ADR-0040, unproven why).

## Move the subscription out and back

Used once as the inheritance proof. While the subscription is out, nothing is enforced on it.

1. Remove `association.tf` and run `terraform plan`: expect `0 to add, 0 to change, 1 to destroy`, only the
   association. Apply.
2. Check the group has no children, then make the request that `Deny` refuses; it should succeed.
3. Restore with `git checkout -- association.tf`, plan (`1 to add`), apply, and check the group lists the subscription
   and `terraform plan` is `No changes`.

## The elevation (tenant root access)

Needed only to read or change the tenant root, which this root does not do after the group exists (reasoned for writes).

1. Run `az rest --method post --url "/providers/Microsoft.Authorization/elevateAccess?api-version=2016-07-01"`. The
   reply is empty. If the next call still fails with `AuthorizationFailed`, sign in again.
2. When finished, remove it:
   `az role assignment delete --assignee "$(az ad signed-in-user show --query id -o tsv)" --role "User Access Administrator" --scope "/"`.
3. Confirm: `az account management-group list -o table` no longer shows the Tenant Root Group. The assignment has no
   expiry of its own; leaving it is the failure to avoid.

## Failure signs

| Sign | Meaning | Action |
|---|---|---|
| `AuthorizationFailed` on `managementGroups/read` | No access at the root or the group | Elevate (above), or check you are the group's Owner |
| Plan warns that `management_group_id` is deprecated on `azurerm_policy_set_definition` | The old resource type | Use `azurerm_management_group_policy_set_definition` (ADR-0040) |
| `RequestDisallowedByPolicy` from a pipeline | A rule is denying a request | Read the evaluation details in the error; fix the request, or add an exemption with an expiry date |
| Assignment missing from the subscription-scope list | The list does not show inherited assignments, or propagation | Check the policy state rows instead |
| `terraform plan` wants to replace the assignment | A name or scope changed | Stop and read it; the assignment name is limited to 24 characters at group scope |
| CI plan leg for this root fails with an authorization error | The plan identity has Reader at the subscription only | See ADR-0040, Consequences |
| `apply.yml` guard fails with a root in neither list | The root was not classified | Add it to `SKIP_ROOTS` with a reason |

## Cost

Management groups, definitions, initiatives and assignments are free. The only cost is the operator time and the
risk that `Deny` blocks a legitimate request.
