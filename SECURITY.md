# Security policy

## Reporting a vulnerability

Please report suspected vulnerabilities **privately** through GitHub:
*Security* tab → *Report a vulnerability*. Do not open a public issue.
Reports are acknowledged within 5 working days.

## Supported versions

Only the `main` branch is maintained.

## How this repository handles secrets

- No secrets, subscription IDs, tenant IDs or personal IP addresses are committed.
  `gitleaks` scans every commit through pre-commit.
- Automation authenticates with federated identity (OIDC / workload identity federation /
  managed identity). Unavoidable secrets are stored in Azure Key Vault. See
  [ADR-0002](docs/adr/0002-secrets-and-identity.md).
- Terraform state and saved plan files are treated as secrets: they live only in the
  access-controlled state backend and are never committed.
- If a secret is ever committed, it is **revoked first**, then removed from history.
  Removing it from history alone is not enough, because clones and forks keep a copy.
