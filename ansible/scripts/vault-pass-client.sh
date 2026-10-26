#!/usr/bin/env bash
# Ansible vault password client (ADR-0020). Invoked as: vault-pass-client.sh --vault-id <label>
# Prints the password for <label> on stdout and nothing else. Exit 2 = unknown label.
set -euo pipefail

KV_NAME="kv-plat-shared-at01"

if [[ "${1:-}" != "--vault-id" || -z "${2:-}" ]]; then
  echo "usage: $0 --vault-id <label>" >&2
  exit 1
fi

label="$2"
case "$label" in
  platform2) ;;                                  # allow-list: one entry per vault-id in use
  *) echo "unknown vault-id: ${label}" >&2; exit 2 ;;
esac

exec az keyvault secret show --vault-name "$KV_NAME" --name "ansible-vault-${label}" --query value -o tsv
