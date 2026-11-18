# Runbook: platform disaster recovery (Site Recovery vault, DR networks, replication, test failover)

- **Purpose:** the persistent Site Recovery setup in `centralus`, the ephemeral replication of one workload VM, and the steps for a test failover and for tearing replication down.
- **Owner:** platform-team
- **Last validated:** 2026-11-18 (applied by hand from the branch; first CI plan not yet run)
- **Persistent:** `platform/dr` yes (vault `prevent_destroy` and `CanNotDelete` lock; cache account `prevent_destroy`); `platform/dr-replication` no (destroy after each exercise)
- **Decisions:** ADR-0045 (vaults, objectives, hand actions), ADR-0007 (DR network ranges), ADR-0013 (why `platform/dr` is not applied by CI)

## Layout

| Item | Root | Name |
|---|---|---|
| Resource group, vault, lock | `platform/dr` | `rg-dr-shared`, `rsv-plat-dr-at01` (centralus) |
| DR and test networks | `platform/dr` | `vnet-dr-dev` 10.40.0.0/16, `vnet-drtest-dev` 10.41.0.0/16, no peering |
| Cache account and its roles | `platform/dr` | `stdrcacheat01` (vault identity: Storage Blob Data Contributor and Contributor) |
| Fabrics, containers, policy, mappings | `platform/dr` | policy `asr-policy-1d` (1 day of points, no app-consistent points) |
| Target group, replicated VM | `platform/dr-replication` | `rg-dr-workload-dev`, item `repl-vm-ansible-target-dev`, target zone 2 |

`platform/dr` and `platform/dr-replication` are both in `SKIP_ROOTS` of `apply.yml`. CI plans them; a human applies them.

## Before you start

1. `az login` as the operator; `ARM_SUBSCRIPTION_ID` set; default subscription equals it.
2. The source VM exists, is running, and has one disk (the replication root has a precondition for exactly one disk in the source group).
3. Cost (list, not checked in Cost Management): replication about USD 25 a month per instance plus replica disks and the cache account; a test VM bills as a normal VM while it runs. Replication stays on until it is disabled, so decide the teardown before the apply.
4. The preview CLI extension `site-recovery` is installed on the workstation (add it to the baseline).

## Apply

1. `platform/dr`: init, saved plan outside the repo, read, apply, second plan `No changes`. Applied once; no need to repeat unless the code changes.
2. `platform/dr-replication`: same sequence. Observed 2026-11-18: the first apply failed with error 28143 (vault had no permission on the cache account); after the Contributor assignment in `platform/dr` the apply passed in **55 min 22 s**, because the apply waits for the whole enable job. Plan for about an hour. Read the protected item afterwards: `Protected` and `Normal`; RPO 47 seconds at the time of reading.

## Test failover (hand action, REST)

Terraform has no test failover resource and the preview CLI extension has no test failover command (observed 2026-11-18).

1. Start: the `testFailover` operation on the replicated item, with the test network `vnet-drtest-dev` as the target network and the recovery point `Latest processed`. The request path and body come from the REST reference for Replication Protected Items; the exact body used on 2026-11-18 was not recorded.
2. Observed: started 17:06:01 UTC; the test VM booted 17:09:12 (3 min 11 s after the start); the job finished 17:09:37. The VM was in zone 2, size `Standard_D2als_v6`, at 10.41.1.4, and the marker file was present.
3. Check with `az vm run-command` (reasoned: the test network has no peering, so there is no path to it from the workstation).
4. Clean up: the `testFailoverCleanup` operation. Observed: `Succeeded`, 17:48:51 to 17:50:02 (1 min 11 s). The test VM and its disks are removed from the target group.

## Tear replication down

1. Read the plan first: `terraform plan -destroy -out=<file>` in `platform/dr-replication`, then `terraform show -no-color <file>`. Expect 2 to destroy (the replicated item and the target group).
2. Apply it. Observed: **2 min 13 s**, versus 55 min 22 s to enable.
3. Confirm `az group exists -n rg-dr-workload-dev` is `false` and that no `-ASRReplica` disk remains (`az resource list --resource-type Microsoft.Compute/disks`). How the provider deleted the group while the replica disk was in it was not examined.
4. Check the regional vCPU quota for the D family: used 0 in both regions.

## Hand actions (documented exception to the code-only rule)

Backup protection and restore (see `platform-backup`); two Site Recovery REST calls (test failover and its cleanup); the preview CLI extension; the Azure-created `AzureBackupRG_eastus2_1`; the two Site Recovery extensions the service put on the source VM (a later plan of the VM's root may show drift: not checked).

## Symptoms

| Symptom | Cause | Status |
|---|---|---|
| Enable fails with error 28143 | the vault identity has no permission on the cache account | observed |
| Apply runs about an hour | the apply waits for the enable job | observed |
| `/dev/disk/azure/scsi1/lunN` missing in the VM | the VM uses NVMe disks; use `lsblk` | observed |
| `PlannedFailover` not offered | not explained | observed |
| Replication plan fails the disk precondition | source group holds more or fewer than one disk | reasoned |

## Unproven

How the provider deleted the target group with the replica disk inside; whether both cache-account roles are needed; the split of the 55 minutes; app-consistent points (frequency is 0); `Latest` against `Latest processed` timing; the cost of the test VM; a real failover and failback; a recovery plan; application-level recovery (DNS, identity, integrations) on a network with no peering. A successful test failover every 180 days is from the on-premises documentation and is not confirmed for Azure to Azure. See ADR-0045.
