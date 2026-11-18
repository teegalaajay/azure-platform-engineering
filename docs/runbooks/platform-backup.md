# Runbook: platform backup (Recovery Services vault, backup policies, protection of a VM)

- **Purpose:** the vault that holds VM recovery points, two backup policies, and the steps for protecting, restoring and unprotecting a VM.
- **Owner:** platform-team
- **Last validated:** 2026-11-18 (applied by hand from the branch; first CI apply not yet run)
- **Persistent:** yes (vault has `prevent_destroy` and a `CanNotDelete` lock; the policies have `prevent_destroy`)
- **Decisions:** ADR-0045 (vaults, tiers, hand actions), ADR-0044 (workspace the vault logs to), ADR-0029 (the workload VM used for the proof)

## Layout

| Item | Root | Name |
|---|---|---|
| Resource group, vault, lock, diagnostic setting | `platform/backup` | `rg-backup-shared`, `rsv-plat-shared-at01` (eastus2) |
| Policies | `platform/backup` | `bkp-vm-standard` (daily), `bkp-vm-regulated` (every 4 hours) |
| Azure-created snapshot group | none (created by Azure) | `AzureBackupRG_eastus2_1` |

The vault reads the workspace ID from the `platform/management` state, so management is applied first.

## Before you start

1. `az login` as the operator; `ARM_SUBSCRIPTION_ID` set; default subscription equals it.
2. The VM to protect exists and is running.
3. Prices (list, not checked in Cost Management): USD 10 a month per protected instance, geo-redundant storage 0.0448 per GB-month.

## Apply

`cd platform/backup`, `terraform init`, `terraform plan -out=<file outside the repo>`, read it, apply it, then a second plan: expect `No changes`. The vault is applied by hand from the branch (a documented exception for persistent roots); the root is in `APPLY_ROOTS`, so CI will own it after the first approved apply.

## Hand actions (documented exception to the code-only rule)

Backup protection of a VM, on-demand backup and restore are done by CLI. They are not in Terraform. Each line below is a command shape taken from the Azure CLI; check `--help` for the exact flags before use (reasoned, not recorded from the session).

| Action | Command shape | Observed |
|---|---|---|
| Protect a VM with a policy | `az backup protection enable-for-vm` | worked 2026-11-18 |
| On-demand backup | `az backup protection backup-now` | worked |
| Restore the OS disk to a staging account | `az backup restore restore-disks` | first attempt `UserErrorInsufficientMSIPermissions` until the vault identity had Storage Account Contributor on the staging account; then completed (about 70 s) |
| Check the restored data | attach the restored disk to the live VM and mount it; read with `az vm run-command` | marker file absent on the restored disk, present on the live disk |
| Stop protection and delete the data | `az backup protection disable` with the **friendly** container and item names (`vm-ansible-target-dev`); read the delete-data flag from `--help` | the long-form names gave `BMSUserErrorContainerNameIncorrectFormat` |

The VM uses NVMe disks, so `/dev/disk/azure/scsi1/lunN` paths do not exist; find the disk with `lsblk` (observed).

## Remove protection (break glass, three steps and a restore)

The vault lock and the vault immutability both block deleting a protected item (observed 2026-11-18).

1. `az lock list` on the vault, then delete `lock-cannotdelete-rsv-plat-shared-at01`. Without this: `ScopeLocked`.
2. `az backup vault update --immutability-state Disabled`. Without this: `UserErrorDeleteBackupItemOnImmutableItem`. The value `Disabled` worked; it was not read in the documentation.
3. Stop protection with the data deleted. Read the job to `Completed`.
4. In the same session, `terraform apply` in `platform/backup`: expect `1 to add, 1 to change` (lock, immutability), then a second plan `No changes`. Read the vault back: lock present, immutability `Unlocked`.

Between steps 1 and 4 the vault is unprotected; the length of that window was not measured.

## After stopping protection

- The item is soft-deleted (flag `isScheduledForDeferredDelete`) and Azure deletes it 14 days later: 2026-12-02 for the 2026-11-18 teardown (derived).
- Azure leaves `AzureBackupRG_eastus2_1` and a `restorePointCollections` object in it. The delete-data job covered 7 recovery points (job `Completed`); the group stays, and what it still holds was not listed after the job. Check it around 2026-12-02. Whether deleting the collection by hand is supported was not read; leave it.
- Delete the staging resource group (`rg-w9d4-restore` on 2026-11-18). Check `az resource list --resource-type Microsoft.Compute/disks` for orphan disks.

## Symptoms

| Symptom | Cause | Status |
|---|---|---|
| Restore fails `UserErrorInsufficientMSIPermissions` | vault identity lacks a role on the staging account | observed |
| `BMSUserErrorContainerNameIncorrectFormat` | long-form names passed to `az backup protection disable` | observed |
| Item delete fails `ScopeLocked` | vault `CanNotDelete` lock is inherited by the item | observed |
| Item delete fails `UserErrorDeleteBackupItemOnImmutableItem` | vault immutability is `Unlocked`, not off | observed |
| `soft_delete_enabled` deprecation warning in plan | the provider always keeps soft delete on | observed |
| Plan shows the policies replaced | not tested; the code comment says `prevent_destroy` stops it | reasoned |

## Unproven

First CI apply of the root; the plan identity reading the management state in CI; snapshot cost in `AzureBackupRG_eastus2_1` and whether it ages out; soft-delete billing in the 14-day window; which of the two storage roles the restore needs; why the restore used the vault tier. See ADR-0045.
