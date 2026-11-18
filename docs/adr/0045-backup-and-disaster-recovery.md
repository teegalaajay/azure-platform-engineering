# ADR-0045: Backup and disaster recovery: a backup vault in the primary region, a Site Recovery vault in the paired region

- **Status:** Accepted
- **Date:** 2026-11-18
- **Deciders:** platform-team (@teegalaajay)
- **Relates to:** ADR-0007 (network ranges); ADR-0010 (platform Key Vault); ADR-0013 (apply identity condition); ADR-0029
  (`workloads/ansible-target/dev`); ADR-0044 (workspace the vault logs to)

## Context

The platform had no recovery path for a workload VM: no backups, and nothing in a second region. This ADR records two
vaults with different jobs, the proof that each works, and what was left outside Terraform. Sources are the Azure Backup
and Site Recovery documentation (read) and the runs of 2026-11-17 and 2026-11-18 (observed). Prices are list prices from
the Retail Prices API and were not compared with Cost Management.

- A **Backup vault** (`rsv-plat-shared-at01`, `eastus2`) holds recovery points. Cross Region Restore needs geo-redundant
  storage (read).
- A **Site Recovery vault** (`rsv-plat-dr-at01`, `centralus`) holds replication configuration and lives in the target
  region (read). Replica disks live in a target resource group.

## Options considered and decisions

1. **Two vaults, not one.** Reason (read): the two services have different vault roles and regions. Cost: two vaults to
   lock, log and recover.
2. **Workload for the proof: `workloads/ansible-target/dev`, rebuilt through `ado-terraform-deploy`.** Ajay's reason: it
   needs an agent rebuild but gives a richer proof. Cost: an agent VM and a pipeline run before any backup could start.
3. **Two backup tiers.** `bkp-vm-standard` (enhanced policy off, daily 02:00 UTC, 30 days, 12 weeks, 12 months, instant
   restore 2 days) and `bkp-vm-regulated` (enhanced policy, every 4 hours, 35 days, 12 weeks, 12 months, instant restore 5
   days). Reason: a daily backup leaves up to 24 hours of data at risk, and 4 hours is the shortest interval for VMs (read).
   Cost: more snapshots and a second policy type. Both policies carry `prevent_destroy`. The policy resource has no `tags`
   argument (provider schema), so it is an exception to the mandatory tags.
4. **Vault settings.** Geo-redundant storage with Cross Region Restore, immutability `Unlocked`, soft delete at the default
   (always on, 14 days, observed), public access Enabled, `CanNotDelete` lock with `prevent_destroy`,
   `data_classification = gxp-regulated`. No reason recorded for the redundancy, immutability, lock level or lifetime
   choices. `Locked` immutability is refused by variable validation: it cannot be undone. No reason recorded.
5. **Diagnostics: an explicit setting `diag-vault-to-law`** with six backup log categories in `Dedicated` mode, instead of a
   policy. Reason: one persistent vault, a policy adds no coverage. This departs from ADR-0044. The Site Recovery
   categories are not enabled here; they belong to the DR vault.
6. **Disaster recovery network ranges: `10.40.0.0/16` (`vnet-dr-dev`) and `10.41.0.0/16` (`vnet-drtest-dev`), no peering,
   no route to any other network.** They do not overlap 10.10, 10.11, 10.20 or 10.30. The test network is isolated so a
   test failover cannot reach production. No reason recorded.
7. **Replication policy `asr-policy-1d`:** one day of recovery points, no application-consistent points (frequency 0).
   Cost: a failover restores crash-consistent data only. Target availability zone 2, new target group
   `rg-dr-workload-dev`, recovery point `Latest processed`. No reason recorded.
8. **Two roles for the Site Recovery vault identity on the cache account `stdrcacheat01`:** Storage Blob Data Contributor
   and Contributor. Without Contributor the first enable failed with error 28143 (observed). Whether both are needed was
   not isolated. The backup vault identity holds Storage Account Contributor and Storage Blob Data Contributor on the
   staging account used for a restore; the first restore failed with `UserErrorInsufficientMSIPermissions` until the first
   was added (observed).
9. **Apply lists.** `platform/backup` is in `APPLY_ROOTS`. `platform/dr` (two role assignments on the cache account, outside
   the apply identity condition of ADR-0013, reasoned) and `platform/dr-replication` (ephemeral, bills while replication is
   on) are in `SKIP_ROOTS`. No reason recorded.
10. **Backup and restore actions are done by hand** (the documented exception, the runbook lists each step). No reason
    recorded for choosing hand CLI over a pipeline.

## Recovery objectives (observed, 2026-11-18)

| Tier | Data-loss window (RPO) | Time to a running copy (RTO) |
|---|---|---|
| Standard backup | up to 24 hours (policy interval, reasoned) | not measured |
| Regulated backup | up to 4 hours (policy interval, reasoned) | OS disk restored and attached in about 70 seconds (restore job only; a VM was not rebuilt from it) |
| Site Recovery | 47 seconds at the time of reading | test VM booted 3 min 11 s after the test failover started; job finished 3 min 36 s after start |

These are measurements of one idle VM, not targets. Targets per tier: not set; to be decided before any claim is made.

## Observed

- Vault read back from Azure after the first apply: `GeoRedundant`, storage type locked from creation, Cross Region Restore
  on, soft delete `AlwaysON` 14 days, immutability `Unlocked`, no Resource Guard.
- On-demand backup and restore of the OS disk into `rg-w9d4-restore`; the marker file was absent on the restored disk and
  present on the live disk.
- Instant-restore points live in `AzureBackupRG_eastus2_1`, created by Azure, as a `restorePointCollections` object.
- First Site Recovery enable failed (28143); after the Contributor assignment the apply passed in 55 min 22 s.
- Test failover by REST (no Terraform resource; the preview CLI extension has no test failover): started 17:06:01 UTC, test
  VM running in `vnet-drtest-dev` at 10.41.1.4, marker present; cleanup `Succeeded` in 1 min 11 s.
- **Teardown (2026-11-18):** disabling replication took 2 min 13 s and removed the replica disk and `rg-dr-workload-dev`. The
  protected item could not be deleted while the vault's `CanNotDelete` lock was on (`ScopeLocked`) and then while
  immutability was `Unlocked` (`UserErrorDeleteBackupItemOnImmutableItem`). Both were lifted by CLI, the item was stopped with
  data deleted, and `terraform apply` restored both (`1 added, 1 changed`, plan `No changes`). The item is soft-deleted:
  Azure permanently deletes it 14 days later (derived: 2026-12-02). The delete-data job read `Completed` for 7 recovery points; `AzureBackupRG_eastus2_1`
  was left in place. The target VM root was then destroyed (`7 destroyed`, its own seven resources). `rg-w9d4-restore` was deleted.
  `az group exists` was false for every ephemeral group; the regional quota for the D-family was 0 in both regions.

## Read, not tested

- Enhanced policy is the only one with sub-daily backups; instant restore days cannot exceed vault retention.

## Unproven

- How the provider deleted `rg-dr-workload-dev` while the replica disk was in it.
- Cost of the snapshots in `AzureBackupRG_eastus2_1` and whether they age out; re-check around 2026-12-02.
- Whether soft-deleted backup data is billed during the 14 days.
- Length of the unprotected window while the lock and immutability were off (not measured).
- That `Disabled` is the intended value for `--immutability-state` (it worked; it was not read in the documentation).
- Whether both storage roles are needed; why the restore used the vault tier.
- The first CI apply of `platform/backup`; the plan identity reading `platform/management` state in CI.
- Application-level recovery (DNS, identity, integrations): an idle single VM does not prove it. No recovery plan was built.
- A failover (not a test), failback, and the 180-day test cadence for Azure to Azure.

## Consequences

- A protected VM costs a per-instance fee (list USD 10 a month); a replicated VM costs about USD 25 a month plus replica
  disks. Both were destroyed the same day. The two persistent vaults bill only for what is protected or replicated.
- Removing protection takes three deliberate steps (lock, immutability, stop) and a Terraform apply to restore the controls.
  A break-glass change must be followed by `terraform apply` in the same session.
- Owed: Cost Management comparison; a recovery plan; targets per tier; moving backup protection into Terraform when the
  provider supports the chosen policy assignment for the workload.
