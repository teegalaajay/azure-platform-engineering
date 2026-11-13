# ADR-0037: Image CI job: lint, build and scan `hello-web` on every pull request, tools pinned by SHA-256

- **Status:** Accepted
- **Date:** 2026-11-10
- **Deciders:** platform-team (@teegalaajay)
- **Relates to:** ADR-0012 (the required check); ADR-0032 (secret scan in the same gate); ADR-0035 (image baseline,
  which required lint and scan); ADR-0036 (the registry holds an image tagged `bootstrap-unscanned`); runbook
  `ci-validate`

## Context

ADR-0035 required a Dockerfile lint and a vulnerability scan, and ADR-0036 deferred the job to this session. Without
it the only image in the registry was built on a laptop and never scanned. Six choices had to be made, and each has a
cost that this record states.

## Options considered

1. **How the tools get onto the runner:** (a) a marketplace action; (b) a release binary downloaded in the job and
   checked against a SHA-256 written in the workflow; (c) `apt` or `pip`.
2. **Severity policy:** which findings fail the job.
3. **When the job runs:** on every pull request, or only when `containers/**` changes.
4. **What the scanner looks at:** vulnerabilities only, or also secrets and misconfiguration.
5. **How the failing finding in the first scan is handled:** pin the package, add an ignore entry, or loosen the rule.
6. **Whether the job is part of the required check.**

## Decision

1. **Release binaries checked by SHA-256 (b).** hadolint 2.15.1 and Trivy 0.76.2 are downloaded with `curl -f`
   and verified with `sha256sum --check -` before they are made executable; a mismatch stops the job. The Trivy
   actions were not used: in March 2026 Trivy's release and action tags were compromised (CVE-2026-33634), which is
   the case where a mutable tag runs attacker code in a job that can see the checkout. Cost: both versions are bumped
   by hand (new hash each time), and a hash proves "the same bytes as when I looked", not "the bytes are honest".
   The Trivy signature was checked once by hand with cosign 3.1.4 (`verify-blob --bundle`, with the certificate
   issuer and the exact workflow identity taken from Trivy's documentation); the job does not repeat it. hadolint
   publishes no signature, so its hash comes only from the release page: an accepted limit.
2. **`--severity HIGH,CRITICAL --ignore-unfixed --exit-code 1`.** A finding fails the job
   only if it is serious and a fix exists. Cost: MEDIUM and LOW findings and unfixed ones are not shown as failures,
   so a green job means "nothing serious that could be fixed today", not "no vulnerabilities". The vulnerability
   database changes daily, so an unrelated pull request can turn red with no code change; the fix is then in the
   image, not in the rule.
3. **Every pull request.** The image is cheap to build (observed: the job took 24 s) and the vulnerability list can change without
   a code change, so a path filter would hide exactly the failures the job exists for. Cost: runner minutes on pull
   requests that do not touch images.
4. **`--scanners vuln`.** Secrets are covered by gitleaks over the full history (ADR-0032), and misconfiguration by the
   hadolint step. Cost: Trivy's own secret and config checks are off, so a second opinion on those is missing.
5. **Pin the fixed package in the Dockerfile.** The first scan failed on `zlib1g` in the base image; the final stage
   now upgrades it to the fixed version (a block placed after `FROM python:3.12-slim`, before the user is created).
   The rule was not weakened and no ignore entry was added. Cost: the pin is a debt; remove it when the base image
   ships the fixed package, which a scan without the pin will show.
6. **The job is in `validate-gate`** (`needs` lists it and any result other than `success` blocks). Cost: a bad
   database day blocks every merge until the image is fixed.

## Observed (2026-11-10)

- hadolint 2.15.1: the binary matched the SHA-256 from the release page; a deliberately bad Dockerfile
  (`bad.Dockerfile`, local only) produced findings and a non-zero exit, and the real Dockerfile exited 0.
- Trivy 0.76.2: the tarball matched the published checksum and the cosign bundle verified (`Verified OK`).
- First local scan of the image: exit 1 with a fixable HIGH/CRITICAL finding in `zlib1g`. After the pin: exit 0.
- Pull request #53 (this change): the job ran green and `validate-gate` passed (23 checks succeeded, 1 skipped).
- Pull request #54 (throwaway, closed, branch deleted): the Dockerfile was made to fail; the job went red
  (run 42712945546) and `validate-gate` blocked the merge. This proves the gate reacts to the job, not only that the
  job exists.
- The base tag `python:3.12-slim` resolved to different digests between two pulls, and a transitive Python
  dependency moved (`click` 8.5.0 to 8.5.1) between builds.

## Reasoned

- Without the SHA-256 check, a replaced release asset would run on the runner with the repository checked out.
- Without the `always()` in the gate, a skipped `image` job would read as a pass; the `!= "success"` test is what
  makes skipped and cancelled count as failures.

## Consequences

- Every pull request builds and scans the image; the job needs Docker on the hosted runner, which `ubuntu-latest` has.
- A new image under `containers/` is not scanned until the job is extended; the job names `hello-web` only.
- The image in the registry is still tagged `bootstrap-unscanned`; this job scans a CI build, not that pushed copy.

## Unproven

- The Trivy database download failing: whether the job turns red (it should, by exit code) was not tested.
- The floating base tag and the unpinned Python dependencies: builds are not reproducible, and the scan result can
  differ between two runs of the same commit. A digest pin and a constraints file are not done.
- A scan of the image in the registry (registry-side scanning is planned for Week 9).
- One finding's title looked odd (CVE-2026-76844); it was not investigated.
- hadolint's authenticity beyond the release page.
