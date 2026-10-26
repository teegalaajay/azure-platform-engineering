# ADR-0020: Ansible Vault strategy (password in Key Vault, client script, rotation)

- **Status:** Accepted (2026-10-26)
- **Date:** 2026-10-26
- **Deciders:** platform-team (@teegalaajay)
- **Relates to:** ADR-0002 (secrets and identity); ADR-0010 (platform Key Vault); ADR-0019 (inventory identity); runbook `ansible-control-node`

## Context

Playbooks will need secret values (database passwords, API tokens). The repository is public, so
secrets can be committed only as Ansible Vault ciphertext. Vault is symmetric: one password
encrypts and decrypts, so the security of every committed secret is the security of that password.
The password must therefore live outside the repository, readable only by identities that are
allowed to decrypt. The target VM never receives the password or the ciphertext; it receives the
decrypted values a task uses (read from the Ansible source, not tested).

Observed 2026-10-23 and 2026-10-26 on `ansible-core` 2.21.5:

1. A password source is run as a script only if the file is executable; its name must also end in
   `-client` for Ansible to pass `--vault-id <label>`. With the executable bit removed,
   `ansible-vault encrypt_string` succeeded with no error and no "client script" line, and the
   blob could not be decrypted afterwards with the real password (`Decryption failed`). A missing
   bit therefore fails open.
2. If the script cannot get the password (no `az` login), it exits non-zero, Ansible stops with the
   script's stderr in the message, and nothing is encrypted. Exit code 2 means "unknown label".
3. `ansible-vault rekey` on a YAML file with a plain part and an inline `!vault` value fails with
   `Input is not vault encrypted data`; the file is left byte-identical (checksum compared).
   `rekey` on a fully encrypted file works.
4. `ansible-vault edit` with no change leaves the file byte-identical. Decrypt then encrypt with the
   same password and content produces different bytes (random salt), so the diff shows a full rewrite.
5. `debug` prints a decrypted variable in plain text; `no_log: true` suppresses the result.
6. A disabled Key Vault secret answers `403 Forbidden`, inner code `SecretDisabled`.
7. A `pygrep` hook with `--negate` fails a `vault*.yml` file that lacks the `$ANSIBLE_VAULT;` header.
   `check-shebang-scripts-are-executable` passed with the bit off while the file was untracked and
   failed once the file was staged as `100644`: it judges the mode in Git's index.

## Options considered

Password location: (1) a file in the home directory or repository; (2) typed at a prompt;
(3) a Key Vault secret fetched by a client script.

Pattern: (a) whole-file `vault.yml` referenced from a plain `vars.yml` by `vault_*` names;
(b) inline `encrypt_string` values in plain files.

Rotation labels: (i) reuse one label and replace the secret's value; (ii) a new label per generation.

## Decision

- Password: option 3. One Key Vault secret per vault-id label in `kv-plat-shared-at01`, named
  `ansible-vault-<label>`, created by piping `openssl rand` into `az keyvault secret set --file
  /dev/stdin --query ...` so the value never reaches the terminal, shell history or Terraform state.
  Terraform does not manage these secrets; their existence is recorded in the runbook.
- Client script `ansible/scripts/vault-pass-client.sh`: allow-lists labels (a label comes from a
  file header, which a pull request controls), exits 2 for an unknown label, contains no secret.
- `ansible.cfg` at the repository root sets `vault_identity_list`, `vault_encrypt_identity` and
  `vault_id_match = True`, so a file labelled for one password is not opened by another.
- Default pattern (a): `vars.yml` plain, `vault.yml` encrypted, names prefixed `vault_`. Pattern (b)
  only for isolated values, because inline values are not rekeyed (observation 3).
- Rotation: option (ii). Current generation is label `platform2`; the next is `platform3`.
  Procedure: store the new secret; add the label to the allow-list; load both labels; `rekey` each
  whole file; decrypt each inline blob with the old label and re-encrypt it with the new one;
  verify; remove the old label from `ansible.cfg` and the allow-list; disable (not delete) the old
  Key Vault secret.
- Guards: the `ansible-vault-encrypted` local hook rejects an unencrypted `vault*.yml`;
  `check-shebang-scripts-are-executable` rejects a staged non-executable script.
- The Key Vault RBAC on the secret decides who can decrypt the repository: Secrets Officer for the
  operator today; Secrets User for the agent's managed identity from Week 5 Day 5.

## Consequences

- Anyone who can read the secret can decrypt every value labelled with it. Labels per environment
  would narrow this (reasoned; one generation exists today).
- Old ciphertext stays in Git history and opens with the old password. Rotating the vault password
  does not protect values already committed; only changing the underlying secrets does.
- Disabling the old secret is a manual change outside Terraform; the runbook must say so.
- A decrypted value is plain text in the run. Every task that handles one needs `no_log: true`;
  pipeline log masking has not been tested.
- A client script that loses its executable bit fails open (observation 1). The staged-mode hook
  covers commits; nothing covers a script copied without its mode onto a runner (reasoned).
- The `ansible-vault-encrypted` hook checks the header only; an empty file or a fake header passes.
- A `Forbidden` from the firewall or RBAC when the script reads the secret has not been tested
  through Ansible; expected to produce the same non-zero-exit message (reasoned).
- Not tested: `vault_id_match` default behaviour (read in source only); the agent's managed
  identity reading the secret; two labels with the same password.
