# ADR-0001: Record architecture decisions

- **Status:** Accepted
- **Date:** 2026-09-29
- **Deciders:** platform-team (@teegalaajay)

## Context

This repository is a reference implementation of an Azure platform for a regulated
(GxP/SOX-style) pharmaceutical workload. In a regulated environment a reviewer or auditor
must be able to see not only what the platform is, but why each design choice was made,
which alternatives were rejected, and what the choice costs. Commit messages and PR
descriptions record individual changes, but they are hard to find later and do not
capture the reasoning behind a design as a whole.

## Options considered

1. **No formal record.** Rationale lives only in PR descriptions and commit messages.
2. **A wiki or external document.** Lives apart from the code, drifts, and is not reviewed
   with the change it describes.
3. **Architecture Decision Records in the repository** (`docs/adr/`), reviewed in the same
   pull request as the code they justify.

## Decision

Use option 3. Every significant design decision gets an ADR in `docs/adr/`, numbered
sequentially (`NNNN-short-title.md`), in the same pull request as the code it justifies.
Each ADR has Status, Context, Options considered, Decision and Consequences, and fits on
one page.

A decision is significant if it would be expensive to reverse, affects security or
compliance, or an auditor would reasonably ask "why was it done this way?"

An accepted ADR is never edited to change its meaning. A later ADR supersedes it, and both
are updated to link to each other (`Superseded by ADR-NNNN` / `Supersedes ADR-NNNN`).

## Consequences

- The reasoning is versioned with the code and goes through the same pull request
  controls as the code.
- The pull request template asks "Design decision made here? → ADR added or updated",
  so the practice is checked on every change.
- Each decision costs a small amount of writing time; the one-page limit keeps it small.
- Decisions taken before this ADR existed (initial repository and workstation setup) are
  recorded retrospectively in ADR-0002 onward.
