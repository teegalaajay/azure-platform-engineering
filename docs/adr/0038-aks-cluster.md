# ADR-0038: AKS cluster: an ephemeral root, overlay networking in the reserved node subnet, a user-assigned control-plane identity, `AcrPull` owned by the cluster root

- **Status:** Accepted
- **Date:** 2026-11-10
- **Deciders:** platform-team (@teegalaajay)
- **Relates to:** ADR-0007 (network topology; the `snet-aks-nodes` reservation and the NSG baseline); ADR-0013 (the
  apply identity cannot assign these roles); ADR-0035 (image baseline); ADR-0036 (registry; role assignments are owned
  by consumers); runbook `platform-aks`

## Context

Week 8 needs a cluster that pulls `hello-web` from `crplatsharedat01` with a managed identity and no registry
credentials. A cluster bills by the hour, so it is built, used and destroyed in one session. The choices below were
made before the root was written; each states what it costs.

## Options considered and decisions

1. **Node subnet.** (a) The range ADR-0007 reserves, `snet-aks-nodes` `10.10.8.0/22`; (b) a new `snet-aks`
   `10.10.3.0/24`. **Decision: (a).** It carries out a recorded decision and needs no ADR amendment. Cost: 1,024
   addresses are set aside in a /16 that is mostly empty; address space is free. With Azure CNI Overlay only nodes
   take subnet addresses (three used, `10.10.8.4` to `.6`), so the size does not matter for capacity.
2. **Networking.** Azure CNI Overlay, pod range `10.244.0.0/16` (a /24 per node), service range `10.0.0.0/16`, DNS
   service `10.0.0.10`. Kubenet is retiring (read, 2028-03-31). Cost: pod addresses are not routable from the VNet;
   traffic leaving a node is translated to the node address.
3. **NSG for the node subnet.** The module's `deny-vnet-inbound` (4000) cannot be removed by a caller. (a) Two allow
   rules in the dev root, `allow-aks-nodes` (200, the node range) and `allow-aks-pods` (210, the pod range);
   (b) a module flag that skips the deny rule for one subnet. **Decision: (a).** `modules/network` stays unchanged and
   no tag is cut; (b) would also let the subnet accept traffic from every peered network, the hub included. Cost: the
   pod range is written in two roots (`aks_pod_cidr` in `platform/foundation/dev`, `pod_cidr` in `platform/aks`). The
   cluster root has a `precondition` that reads the NSG from Azure and fails the plan if no inbound Allow rule has the
   source `pod_cidr`, so a mismatch fails loudly (observed, below).
4. **Egress.** (a) `outbound_type = "loadBalancer"`, the AKS default; (b) `userAssignedNATGateway`. **Decision: (a).**
   Fewer resources, no ordering constraint with a subnet association, nothing to destroy first. Cost: the egress IP is
   created and owned by AKS in the node resource group, so it is not in our code and cannot be pinned; this differs
   from the NAT Gateway pattern in ADR-0007. Exit: the Week 8 firewall with a route table replaces whichever interim is
   used.
5. **Control-plane identity.** A user-assigned identity, `id-aks-dev`, with the built-in `Network Contributor` role on
   `snet-aks-nodes` only, assigned before the cluster is created. A system-assigned identity cannot be used because it
   does not exist until the cluster does (reasoned; creation with it was not tried). Option rejected: a custom role with
   only `subnets/join/action`, because it needs a role definition outside the apply path (ADR-0013) and may miss an
   action that is found only at apply. Cost: `Network Contributor` also allows changing the subnet's own settings; the
   scope limits that to one subnet, and the assignment is destroyed with the cluster.
6. **Image pull.** The kubelet identity (`<cluster>-agentpool`, created by AKS) gets `AcrPull` on the registry through
   an assignment in the cluster root (ADR-0036). `grant_acr_pull` is a variable committed as `true`; it is set to
   `false` once on the command line to observe the refusal first.
7. **Size and tier.** Free control plane; a system pool of two `Standard_D4s_v7` nodes with the `CriticalAddonsOnly`
   taint; a user pool of one `Standard_D2s_v7`. No zones and no pinned Kubernetes version. Costs: no financially
   backed SLA; no zone spread; the version is Azure's default at creation and can differ between builds (observed:
   cluster `1.36`, nodes `v1.36.5`). The regional vCPU quota was raised from 10 to 20 in the portal on 2026-11-10 (a
   documented exception to the no-hand-fix rule); the per-family limit for Dsv7 stayed at 10 and the three pools use
   exactly 10.
8. **Cluster access.** Local accounts are left enabled (`local_account_disabled = false`) and the API server is public
   with no authorized ranges. Cost: a static admin credential exists in the kubeconfig and the API endpoint is
   reachable from the internet (authentication still applies). Accepted for an hour-long cluster. Exit: Entra RBAC and
   authorized ranges before anything long-lived.
9. **Apply path.** The root is applied by hand from the workstation as Owner and is in `SKIP_ROOTS` of
   `.github/workflows/apply.yml`. The two role assignments are outside the apply identity's ABAC condition (reasoned
   from ADR-0013; the identity was not tried). The plan-on-PR floor is now 15 roots and the validate floor 20.

## Observed (2026-11-10)

- `Microsoft.ContainerService` was `Registered`. `Standard_D4s_v7` and `Standard_D2s_v7` have no restrictions in
  `eastus2` and are offered in zones 1 to 4.
- First plan `5 to add`; with a wrong `-var pod_cidr=10.250.0.0/16` the plan failed with exit 1 and the
  `precondition` message, after printing a partial `Plan: 3 to add` (a `Plan:` line is not a success signal; the exit
  code is).
- Apply `5 added`. Three nodes `Ready` within about six minutes, all `v1.36.5`, no external IP, internal
  `10.10.8.4` to `.6`; the system nodes carry the `CriticalAddonsOnly` taint, the user node has none. Pod IPs came from
  `10.244.0.x`, `.1.x` and `.2.x` (one /24 per node); host-network pods showed node IPs. CoreDNS ran on both system
  nodes; the OIDC issuer and the workload identity webhook pods were present.
- The first plan after the apply showed `2 to change`: AKS had filled in `upgrade_settings` (`max_surge` 10%,
  drain timeout 0, soak 0) on both pools and the code did not state them. Declaring the values removed the diff. This
  drift was found only because a plan was run before the AcrPull apply; a plan straight after the first apply, which
  was skipped, would have found it earlier.
- Without `AcrPull`, a pod on the user node ended in `ErrImagePull` then `ImagePullBackOff`, with
  `failed to fetch anonymous token ... 401 Unauthorized` from `crplatsharedat01.azurecr.io`. After the assignment (`1
  added`) the same pod, not recreated, reached `Running` with no restarts; it was still backing off at the apply and
  running about four minutes later, so the role took effect and the retry fired within that window (the split is not
  known).
- A lookup of `kubernetes.default.svc.cluster.local` from a pod on the user node returned `10.0.0.1` through CoreDNS on
  the system nodes. With `allow-aks-pods` deleted by hand, 0 of 12 lookups succeeded (each cut off by a 10 s timeout);
  after `terraform apply` restored the rule, 6 of 6 succeeded and the plan was `No changes`.
- A pod's source address on the internet equalled the public IP in the node resource group. The node resource group held
  a public IP, a load balancer, the kubelet identity, an NSG created by AKS, and two scale sets (object types read from
  names, not from the command).
- `terraform destroy`: `6 destroyed`; `az group exists` was `false` for both resource groups and `az aks list` was
  empty.

## Reasoned, not tested

- Without the role a system-assigned control-plane identity cannot join the subnet; `skip_service_principal_aad_check`
  avoids a lag in Entra for a new identity.
- The NSG, not another layer, dropped the lookups when rule 210 was missing (no flow logs were read).
- The CI apply identity cannot create these assignments.
- A node-pool upgrade needs a surge node and would exceed the Dsv7 family limit (10 of 10).

## Unproven

- A workload identity token exchange (federated credential, service account, a pod calling Azure).
- What the NSG that AKS created in the node resource group covers, and whether it interacts with the subnet NSG.
- The cost of the cluster: the estimate (about USD 0.66 per hour for the VMs, plus a load balancer and IP) was not
  compared with Cost Management.
- `apply` from `main`, the plan of this root in CI, and a rebuild from zero.
- Behaviour on an upgrade, with zones, and with local accounts disabled.
- `kubectl` 1.36.6 was installed from `dl.k8s.io` and checked against its published SHA-256 file from the same
  server; its cosign signature was not verified.

## Consequences

- `platform/aks` is destroyed after each use; `rg-aks-dev` and `rg-aks-nodes-dev` must both read `false`.
- The pod range lives in two roots; the `precondition` is the control that catches a mismatch.
- Anyone running the root needs `Owner` (or equivalent) because it creates role assignments.
- The cluster is destroyed before the registry is; the registry has no dependency on it.
- The tflint azurerm ruleset (v0.32.0) rejects `Standard_D4s_v7` and `Standard_D2s_v7` because its size list predates
  v7. The two `vm_size` lines carry an inline `tflint-ignore` for that one rule, with the reason beside it; the rule
  stays on for every other root and size. Azure accepted both sizes (observed at apply). Exit: remove the ignores when
  the pinned ruleset lists the sizes.
