# ADR-0036: Container registry: a persistent Basic registry with a public endpoint, role assignments owned by consumers, images pushed from the workstation

- **Status:** Accepted
- **Date:** 2026-11-06
- **Deciders:** platform-team (@teegalaajay)
- **Relates to:** ADR-0007 (network topology; private endpoints later); ADR-0013 (the apply identity cannot assign
  registry roles); ADR-0035 (image baseline); runbook `platform-registry`

## Context

Week 8 adds a Kubernetes cluster that has to pull images, and ADR-0035 put the first image source in the repository.
The missing piece is a registry. Five choices have to be made before the first image is pushed, and each one has a
cost that this record states.

## Options considered

1. **Lifetime:** (a) a persistent root, `platform/registry`; (b) an ephemeral root built and destroyed with each use.
2. **SKU:** Basic, Standard or Premium.
3. **How images get in:** (a) `docker push` from the engineer's workstation; (b) `az acr build`, which builds in Azure.
4. **Where role assignments live:** (a) in the root of each consumer; (b) in the registry root.
5. **The build, lint and scan job required by ADR-0035:** (a) built in the same session as the registry; (b) built in
   the next session.

## Decision

1. **Persistent root (a).** Images are build outputs reused across several days and by the cluster; rebuilding the
   registry would mean re-pushing every image and re-checking the identity wiring each time. Cost: the registry bills
   every day whether or not it is used (the Basic price was not verified: Microsoft's pricing page rendered "$-"), and
   it becomes a leak if the project stalls; the subscription budget alerts are the guard.
2. **Basic.** This is a single-owner reference platform, the images hold no secrets (ADR-0035), a request without a
   token is refused (observed, below), and Basic is the cheapest SKU. Cost: IP access rules and private endpoints are
   Premium-only (read from Microsoft's tier page), so the registry's public endpoint, including its token endpoint,
   is reachable from the internet. This departs from the Deny plus allow-list pattern used for the Key Vault and the
   storage accounts. It is an accepted risk. Exit: in Week 10, raise the SKU to Premium for the private endpoint and
   IP rules, then decide whether to stay on Premium.
3. **Push from the workstation (a).** The image pushed is the one already built and tested locally, and no billable
   build service is added. Cost: the provenance of the first image is the engineer's laptop, with no tie to a commit
   or pipeline run. The CI build job replaces this path.
4. **Roles in the consumers' roots (a).** `platform/registry` creates the registry and exports its ID and login
   server; the root that creates a consumer (the cluster) assigns `AcrPull` to that consumer's identity. The CI apply
   identity can assign only Key Vault Secrets Officer (the condition in ADR-0013), so a registry root that held role
   assignments could not be applied by CI. As a result `platform/registry` is in `APPLY_ROOTS` of
   `.github/workflows/apply.yml`. Cost: "who can pull from this registry" is no longer answered from one file; the
   runbook lists every consumer and the command that lists the assignments.
5. **The CI job is built in the next session (b).** Cost: the first image in the registry was not scanned. It is
   tagged `bootstrap-unscanned`, and nothing should run it in a cluster until the CI job exists.

Fixed in code, not variables, so that a `-var` cannot change them: SKU `Basic`, admin user disabled,
public network access enabled. Names: resource group `rg-registry-shared`, registry `crplatsharedat01` (the registry
name is global, lowercase letters and digits only).

## Observed (2026-11-06)

- `az acr check-name --name crplatsharedat01` returned `nameAvailable: true` before the code was written.
- Plan: `2 to add, 0 to change, 0 to destroy` (the resource group and the registry), all six mandatory tags set.
  Apply: `2 added` (resource group 23 s, registry 18 s). A second plan: `No changes`.
- The plan showed `role_assignment_mode = "LegacyRegistryPermissions"`, the provider default; it was left unchanged.
- Read back from Azure (`az acr show`): SKU Basic, admin user disabled, anonymous pull disabled, public network access
  Enabled, zone redundancy Disabled.
- Owner at subscription scope pushed to the registry without an `AcrPush` assignment made by this repository.
- The first `docker push` ended after nine layers showed `Pushed`, with no digest line, and `az acr repository show`
  then reported that the tag did not exist. A second push of the same image printed
  `sha256:2d83b42b985049c38e7fa959491799e9f63163817c65cb8432110e95b086f8d7` with exit code 0, and the registry returned
  the same digest for the tag.
- Two builds of `containers/hello-web` gave images with the same eight layers, the same config and the same creation
  time, but different image IDs. The ID is the digest of an OCI image index (media type
  `application/vnd.oci.image.index.v1+json`, 856 bytes). The digest the registry returned equals the local ID of the
  image that was pushed.
- An unauthenticated `HEAD` request for the manifest returned `401 Unauthorized` with a `Www-Authenticate: Bearer`
  challenge that names the registry's token endpoint.

## Reasoned

- The image ID changes between builds because the index probably carries a per-build record; the content of the index
  was not read.
- Owner could push because, in the legacy permission mode, Owner includes push and pull.
- On Basic the control is authentication, not the network: anyone can reach the token endpoint and the manifest
  path, and no one can pull without a token.

## Consequences

- The registry bills daily while it exists; deleting it removes every image (no delete lock was added; that is a
  separate decision).
- Every consumer root must assign its own `AcrPull`; the first consumer is the cluster.
- The apply workflow now applies `platform/registry` after approval, and the plan-on-PR floor is 14 roots.

## Unproven

- Why the first push stopped without an error.
- The price of Basic (not verified) and of Premium.
- A managed identity pulling with `AcrPull` (planned for the cluster session); only an unauthenticated refusal was
  tested, not an authenticated identity without roles.
- Zone redundancy: Azure reported `Disabled`, while Microsoft's tier page says it is on by default in supported
  regions.
- The lifetime of the token that `az acr login` issues.
- The apply workflow applying this root from `main` (`No changes` is expected).
- The repository-level permission mode, which was not evaluated.
