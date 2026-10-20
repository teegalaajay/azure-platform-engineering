# ADR-0017: Handler failure policy for playbooks (`force_handlers`)

- **Status:** Accepted (2026-10-20)
- **Date:** 2026-10-20
- **Deciders:** platform-team (@teegalaajay)
- **Relates to:** ADR-0016 (practice target); runbook `ansible-control-node`

## Context

`web.yml` renders an nginx configuration snippet and reloads nginx through a handler. A handler runs only when a task that names it reports `changed`, and it runs at the end of the play. By default, if a later task fails on a host, the play stops for that host and the handlers that were already notified do not run.

Observed in the sandbox on 2026-10-20: with the default policy, the snippet task changed the file on the target and a later task failed. The file said `v2`, nginx kept serving `v1`, and the handler was skipped. The next run reported the snippet task as `ok`, so nothing notified the handler and nginx stayed stale. A plain rerun did not repair it.

## Options considered

1. Default policy: handlers are skipped when a later task fails.
2. `force_handlers: true` on the play: a handler that was already notified runs even if a later task fails.
3. `meta: flush_handlers` after the configuration tasks: pending handlers run at that point in the play.
4. Reload nginx unconditionally on every run.

## Decision

Option 2 for `web.yml`, as a play keyword. Option 2 was proven in the sandbox: with the failing task present, the handler ran, the recap showed it, and the header served the new value.

## Consequences

- A stale service after a failed run is the worse failure here, because it is silent and a rerun does not repair it.
- Cost: the handler can run against a half-applied play. If the snippet written earlier is invalid, the forced reload acts on a configuration that the rest of the play never got to check. A failed reload would be a second failure on top of the first. Not tested: what nginx does on a reload with an invalid configuration.
- Mitigation not yet in place: validating the configuration before it lands. `validate: nginx -t -c %s` needs a complete `nginx.conf`, not a snippet, so it is deferred to the role work (Week 4 Day 4).
- Option 3 not tested. Option 4 rejected: it reloads a running service on every run without a change.
- Scope: this ADR covers `web.yml` only. Other playbooks decide for themselves, and a role that manages a service should state its policy.
