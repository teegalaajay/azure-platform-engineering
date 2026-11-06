# ADR-0035: Container images: how Docker is installed, where image source lives, and the baseline every image follows

- **Status:** Accepted
- **Date:** 2026-11-05
- **Deciders:** platform-team (@teegalaajay)
- **Relates to:** ADR-0002 (no secrets in files); ADR-0025 (tool versions are recorded and checked); runbook
  `workstation-setup` section 6b

## Context

Week 8 of the build adds containers: images now, a registry and a Kubernetes cluster later. The repository has no place
for a Dockerfile and no rule for how an image is built, and the engineer workstation has no container engine. Four
choices have to be made before the first image is committed, and the first image sets the pattern for the rest.

## Options considered

1. **Container engine on the workstation:** (a) Docker Engine inside the Ubuntu WSL distribution, from Docker's apt
   repository; (b) Docker Desktop on Windows.
2. **Version handling:** (a) pin one version and hold it; (b) install whatever is newest.
3. **Access to the engine:** (a) add the engineer's user to the `docker` group; (b) use `sudo docker` every time.
4. **Where image source lives:** (a) a new top-level `containers/` folder; (b) `apps/`; (c) inside `workloads/`.

## Decision

1. **Docker Engine in WSL from Docker's apt repository (a).** The signing key is downloaded over HTTPS, its fingerprint
   is compared, and the repository is bound to that key with `Signed-By`. This is the same method as Terraform, the
   Azure CLI and `gh`, and it rebuilds from a terminal runbook. Cost: the engineer maintains updates and the service;
   WSL must run systemd (it did: PID 1 was `systemd`); Docker Desktop's graphical tools are not available.
2. **Pin 29.9.3 and hold `docker-ce` and `docker-ce-cli` (a).** Cost: no automatic security fixes for those two
   packages, so a newer version is a deliberate change that updates the runbook; `containerd.io`, `docker-buildx-plugin`
   and `docker-compose-plugin` are not held and can move with `apt upgrade`.
3. **`docker` group (a).** Cost: membership in that group is root-equivalent on the WSL machine, because the socket
   `/var/run/docker.sock` can start a container that mounts the host's filesystem. Accepted for a single-user personal
   workstation; it must not be copied to a shared server or a build agent without thought.
4. **`containers/` (a).** One folder per tool or layer is the existing pattern (`ansible/`, `pipelines/`). Cost: the
   documented layout changes (README, standards), and image lint and a build job are needed in CI later. `workloads/`
   was rejected because every folder under it is a Terraform root with a backend and some CI discovers roots by that
   shape; `apps/` was rejected because the name implies product code and this is a sample workload.
5. **Image baseline, applied to every image in `containers/`** (adopted with the first image; no alternatives were
   weighed in the session): a multi-stage Dockerfile; instructions ordered from least to most frequently changing so
   the build cache survives code edits; a numeric non-root user (`USER 10001`, numeric so Kubernetes `runAsNonRoot` can
   verify it); a `.dockerignore` next to every Dockerfile; Python dependencies pinned in `requirements.txt`. Costs:
   see "Reasoned" and "Unproven".

## Observed (2026-11-05)

- Docker's current install page does not print a key fingerprint. The key downloaded from
  `download.docker.com/linux/ubuntu/gpg` printed `9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88`, owner "Docker
  Release (CE deb)". That equals the value in older Docker documentation and third-party pages; the comparison is
  second-hand, not against Docker's current page.
- `apt-cache policy docker-ce`: candidate `5:29.9.3-1~ubuntu.24.04~noble` from
  `https://download.docker.com/linux/ubuntu noble/stable`. `docker version`: client and server 29.9.3, containerd
  v2.4.2, runc 1.5.2. Both held packages reported "set on hold".
- `usermod -aG docker` succeeded (`getent group docker` listed the user) but a new terminal did not have the group.
  `wsl --shutdown` left the distribution `Running`; after VS Code and every terminal were closed,
  `wsl --terminate Ubuntu-24.04` stopped it, and the next session listed `docker` in `groups`.
- A new PID namespace (`unshare`) showed `ps` as PID 1 with no other process. A container from `alpine` running
  `sleep 3600` appeared on the host as PID 1066 (`docker top`) and as PID 1 inside (`docker exec ... ps`).
- The first, naive Dockerfile (`COPY . .` before `pip install`) re-ran the install (6.3 s) after one edit to
  `app.py`. With `requirements.txt` copied and installed first, the same edit left the install `CACHED` and only
  `COPY app.py` ran (export 0.5 s against 2.9 s).
- The multi-stage image was 202 MB against 198 MB for the single-stage one (disk usage column); the content size was
  48.8 MB against 48.3 MB. The image ran as `uid=0(root)` until `USER 10001`; afterwards `id` printed
  `uid=10001(appuser)` and `curl localhost:8000` through a published port returned the page.
- The copy under `containers/hello-web` built with every step `CACHED` and the same manifest digest as the previous
  build, and the `.dockerignore` was read (80 B).

## Reasoned (not tested)

- The multi-stage image is larger by 4 MB because the virtual environment carries its own copy of `pip` on top of the
  one in the base image. The cause was not checked. Multi-stage pays off when a build stage needs compilers or sources
  that must not reach the final image; this application has none, so the pattern is adopted for the shape, not for
  size.
- Root inside a container is root on the host with a restricted capability set, because Docker does not remap users by
  default. `docker top` showed the container process owned by `root` on the host; the capability set was not inspected.
- The base image `python:3.12-slim` is a moving tag. The builds resolved it to one digest
  (`sha256:4840d514...`), but the Dockerfile does not pin that digest, so a rebuild after the tag moves can change the
  base.

## Unproven

- The application uses Flask's built-in development server, which is not meant for production; no production server
  (for example gunicorn) was tried. Flask's own dependencies are not pinned (no constraints file).
- No `HEALTHCHECK`, no read-only root filesystem, no dropped capabilities, no vulnerability scan, no Dockerfile lint.
- No pipeline builds the image and nothing is pushed to a registry; the image has not run on AKS or been checked
  against `runAsNonRoot`.
- Docker Desktop was not installed or compared hands-on; its licence terms were not checked.
- Rebuilding the workstation from section 6b alone was not tried end to end.

## Consequences

- `containers/<name>/` holds one image per folder: `Dockerfile`, application code, `requirements.txt` (or the
  language's equivalent), `.dockerignore`. The first is `containers/hello-web/`.
- The workstation runbook records the install and the pin; changing the Docker version means updating section 6b and
  the baseline table together.
- Week 8 Day 2 adds a registry and an identity-based pull; a CI job that builds, lints and scans the image is owed and
  not scheduled.
- The README layout table and the status table gain a row each.
