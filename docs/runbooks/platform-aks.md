# Runbook: platform-aks (ephemeral AKS cluster)

- **Purpose:** Build an AKS cluster in the dev network, prove a managed-identity image pull from `crplatsharedat01`, and
  destroy it in the same session. See ADR-0038.
- **Owner:** platform-team
- **Last validated:** 2026-11-10 (apply, pull proof, DNS proof, destroy; not rebuilt from zero since)
- **Persistent:** No. The root is destroyed after each use. Nothing in it is meant to survive a day.

## Layout

| Item | Value |
|---|---|
| Root | `platform/aks`, state key `platform/aks.tfstate` in the shared backend |
| Resource groups | `rg-aks-dev` (ours), `rg-aks-nodes-dev` (created and owned by AKS) |
| Nodes | `snet-aks-nodes` `10.10.8.0/22` (from `platform/foundation/dev`, ADR-0007) |
| Pod / service range | `10.244.0.0/16` overlay / `10.0.0.0/16`, DNS `10.0.0.10` |
| Pools | system 2 x `Standard_D4s_v7` (tainted `CriticalAddonsOnly`), user 1 x `Standard_D2s_v7` |
| Identities | `id-aks-dev` (control plane, `Network Contributor` on the node subnet), kubelet identity (`AcrPull` on the registry) |
| Applied by | hand, as Owner. The root is in `SKIP_ROOTS` of `apply.yml`. The CI plan on a PR shows it as all-to-add |

The pod range is set in two places: `aks_pod_cidr` in `platform/foundation/dev` and `pod_cidr` in `platform/aks`. A
`precondition` fails the plan if no inbound Allow rule on the node subnet NSG has that source.

## Deploy

1. On `main`, confirm the network exists: `terraform -chdir=platform/foundation/dev plan` reports `No changes`, and the
   `snet-aks-nodes` subnet and the `allow-aks-nodes` / `allow-aks-pods` rules are present.
2. Confirm quota: `az vm list-usage -l eastus2 -o table | grep -i dsv7`. The family needs 10 vCPUs free (8 system, 2
   user). A surge node during an upgrade would need more.
3. Confirm the provider is registered: `az provider show -n Microsoft.ContainerService --query registrationState -o tsv`
   prints `Registered`.
4. `cd platform/aks`, then `terraform init`, then `terraform plan -out="$HOME/scratch/aks.tfplan"` (the plan file stays
   outside the repo). Expect 5 to add. Read it; pipe any excerpt through
   `sed -E 's#/subscriptions/[0-9a-f-]+#/subscriptions/***#'` before pasting it anywhere.
5. `terraform apply "$HOME/scratch/aks.tfplan"`, then run `terraform plan` again and expect `No changes`.
6. Credentials: `az aks get-credentials -g rg-aks-dev -n <cluster_name> --overwrite-existing`, then
   `kubectl get nodes -o wide`. Three nodes `Ready` took about six minutes on 2026-11-10.

`kubectl` is installed on the workstation at v1.36.6, checked against its published SHA-256 file from the same server (install steps: `workstation-setup` section 6c).
The cosign signature has not been verified. `kubectl` must be within one minor version of the cluster (1.36).

## Verify

- **Image pull:** a pod on the user pool (`nodeSelector: kubernetes.azure.com/mode: user`) with the `hello-web` image
  reaches `Running`. With `-var grant_acr_pull=false` the same pod ends in `ImagePullBackOff` with a `401` from the
  registry. This is a test only; the committed value is `true`.
- **DNS across nodes:** from a pod on the user node, resolve `kubernetes.default.svc.cluster.local`; the answer is
  `10.0.0.1`. A timeout means the pod range is not allowed on the node subnet NSG.
- **Egress:** a pod's public address equals the public IP in `rg-aks-nodes-dev`.

## Destroy

1. `terraform destroy` in `platform/aks`; expect 6 destroyed.
2. `az group exists -n rg-aks-dev` and `az group exists -n rg-aks-nodes-dev` must both print `false`.
3. `az aks list -o table` is empty. Remove the stale kubeconfig context:
   `kubectl config delete-context <name>` and the matching cluster and user entries.

If `rg-aks-nodes-dev` still exists after the destroy, stop and look at it before deleting anything: it belongs to AKS.

## Failure signs

| Sign | Meaning | Action |
|---|---|---|
| Plan fails with the pod-range `precondition` message | `pod_cidr` has no matching Allow rule on the node NSG | Align the two roots and apply `platform/foundation/dev` first |
| `Provisioning` fails on vCPU quota | Dsv7 family limit is 10 | Free cores or raise the family quota; a regional raise alone is not enough |
| Pod in `ImagePullBackOff`, `401` anonymous token | `AcrPull` missing or not yet effective | Check the assignment exists; allow a few minutes for the retry |
| Lookups time out from a pod on another node | NSG drops pod traffic between nodes | Check `allow-aks-pods` exists on the node NSG |
| Plan shows `upgrade_settings` changes | AKS filled in defaults not stated in code | Declare them (done on 2026-11-10) |
| Apply from CI is attempted for this root | It must not run there | `SKIP_ROOTS` in `apply.yml`; cancel the run |

## Cost

The estimate is about USD 0.66 per hour for the VMs, plus a load balancer and public IP (reasoned). It has not been
compared with Cost Management. Do not leave the cluster up overnight.
