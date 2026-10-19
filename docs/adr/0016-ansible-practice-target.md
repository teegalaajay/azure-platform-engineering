# ADR-0016: Ansible practice target outside the platform network

- **Status:** Accepted (2026-10-19)
- **Date:** 2026-10-19
- **Deciders:** platform-team (@teegalaajay)
- **Relates to:** ADR-0007 (spoke VMs have no public IP; Bastion is the Week 8 exit)

## Context

Week 4 starts the Ansible layer. A playbook needs a managed host it can reach over SSH from the control node (the operator workstation).

ADR-0007 gives every platform VM a private address only, with `deny-vnet-inbound` at priority 4000 and SSH allowed only from the operator /32 and `snet-mgmt`. The operator workstation is on the internet, so it has no network path to a platform VM until Bastion exists (Week 8). The in-network agent that could reach it (the ADO agent) arrives in Week 6.

## Options considered

1. A throwaway VM with a public IP, restricted to the operator /32, in the sandbox repo; playbooks stay in the platform repo.
2. Give the platform `ansible-target` a public IP.
3. Wait for Bastion (Week 8) or the ADO agent (Week 6).
4. Reach the platform VM through a NAT Gateway.

## Decision

Option 1. The target is Terraform in `azure-iac-sandbox` (`w4d1-ansible-target`): own resource group, own VNet (10.99.0.0/24), NSG with one SSH rule from the operator /32, Standard static public IP, trusted launch, SSH key only. It is destroyed after each session and rebuilt when needed. Playbooks, roles and the runbook live in `ansible/` in the platform repo; no inventory or IP is committed.

## Consequences

- ADR-0007 is not weakened: no platform NSG or VM changes.
- Option 2 rejected: it reverses ADR-0007 for a learning convenience.
- Option 3 rejected: it blocks Weeks 4 to 5 for no learning gain.
- Option 4 rejected: a NAT Gateway is outbound only and gives no inbound path.
- The public IP exists only while the sandbox VM exists; the SSH rule is the only exposure.
- Playbooks written now must work unchanged against the platform target later (the host is selected by inventory, not by playbook).

## Deferred

The platform `ansible-target` in `snet-app` is built when an in-network control path exists: the ADO agent (Week 5 Day 5 / Week 6 Day 4) or Bastion (Week 8, open item 30).
