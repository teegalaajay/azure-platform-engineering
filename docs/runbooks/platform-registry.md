# Runbook: container registry (`platform/registry`)

**Purpose:** Deploy, verify, use and change the container registry (ADR-0036).
**Owner:** platform-team · **Last validated:** 2026-11-06 · **Persistent:** yes (bills daily while it exists)

## 1. Layout

| Root | State key | Resources |
|---|---|---|
| `platform/registry` | `platform/registry.tfstate` | `rg-registry-shared`, registry `crplatsharedat01` (Basic, admin user off, public endpoint) |

No dependency on any other root. Outputs: `resource_group_name`, `registry_id`, `registry_name`, `login_server`.
The root has no role assignments (ADR-0036); it is in `APPLY_ROOTS`, so CI applies it after approval.

## 2. Deploy or converge

The first apply was made by hand from the feature branch; afterwards CI applies from `main`.

```bash
cd platform/registry
terraform init
terraform plan -input=false
terraform apply
terraform plan -input=false   # expect: No changes
```

Before choosing a new name, `az acr check-name --name <NAME>`: the name is global and a plan cannot check it.

## 3. Verify (Azure is the source of truth)

```bash
az acr show --name crplatsharedat01 --query "{sku:sku.name, admin:adminUserEnabled, publicNetwork:publicNetworkAccess, anonymousPull:anonymousPullEnabled, loginServer:loginServer}" -o json
```

Expected (observed 2026-11-06): `Basic`, admin `false`, public network `Enabled`, anonymous pull `false`.

A request without credentials must be refused:

```bash
curl -sI https://crplatsharedat01.azurecr.io/v2/hello-web/manifests/bootstrap-unscanned
```

Expected (observed): `401 Unauthorized` and a `Www-Authenticate: Bearer` header.

## 4. Push an image

Prerequisite: the image was built from the committed source under `containers/` and follows ADR-0035.

```bash
az acr login --name crplatsharedat01
docker tag <LOCAL_IMAGE> crplatsharedat01.azurecr.io/<REPOSITORY>:<TAG>
docker push crplatsharedat01.azurecr.io/<REPOSITORY>:<TAG>; echo "exit=$?"
az acr repository show --name crplatsharedat01 --image <REPOSITORY>:<TAG> --query digest -o tsv
```

A push has succeeded only when the last line of `docker push` is `<TAG>: digest: sha256:... size: ...` with
`exit=0` and the `az` command returns the same digest. Until the CI job scans images (ADR-0036), use a tag that
says so, for example `bootstrap-unscanned`. The image ID shown by `docker images` changes with each build; compare
digests, not IDs.

## 5. Who can pull

Roles are assigned in the consumer's own root, never here (ADR-0036). Consumers at the time of writing: none.

```bash
cd platform/registry
terraform output -raw registry_id
az role assignment list --scope <REGISTRY_ID> --query "[].{role:roleDefinitionName, type:principalType}" -o table
```

This listing command has not been run yet.

## 6. Change

| Change | How | Effect |
|---|---|---|
| SKU (for example Premium in Week 10) | edit `sku` in `main.tf`, PR with an ADR amendment | expected in-place; not yet tested |
| Admin user | do not enable | shared password; ADR-0036 |
| Name | do not | forces replacement; every image is lost |

## 7. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `docker push` stops after the layers, no digest line | observed once; cause unknown | run the push again and read the exit code; check the digest with `az acr repository show` |
| `az acr repository show` says the tag does not exist | the manifest was never written | push again |
| Pull or push returns 401 | not logged in, or the token expired (lifetime not verified) | `az acr login --name crplatsharedat01` |
| Apply fails on the registry name | the name is taken globally | `az acr check-name`, then choose another |

## 8. Teardown

Do not destroy casually: destroying the registry deletes every image in it, and there is no delete lock. If it must
go, re-push the images from their source afterwards.
