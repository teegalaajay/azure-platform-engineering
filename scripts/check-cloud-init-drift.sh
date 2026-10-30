#!/usr/bin/env bash
# Fail if the shared cloud-init block differs between modules/runner-vm and modules/ado-agent-vm (ADR-0025).
# The block runs from the line `ARCH=$(dpkg ...)` to the line `apt-mark hold terraform`, inclusive. The markers are
# anchored to the start of an indented command, because a comment in a template also mentions "ARCH=" in prose.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

block() {                                          # print the shared block of one template
  awk '/^[[:space:]]+ARCH=\$\(/ && !seen {f=1; seen=1} f {print} /^[[:space:]]+apt-mark hold terraform$/ && f {exit}' "$1"
}

a=$(block modules/runner-vm/cloud-init.yaml.tftpl)
b=$(block modules/ado-agent-vm/cloud-init.yaml.tftpl)

# an empty block means a marker moved: that is a failure, not a pass
[ -n "$a" ] || { echo "FAIL runner-vm: shared block not found (markers moved?)"; exit 1; }
[ -n "$b" ] || { echo "FAIL ado-agent-vm: shared block not found (markers moved?)"; exit 1; }

if [ "$a" = "$b" ]; then
  echo "ok   shared cloud-init block identical ($(printf '%s\n' "$a" | wc -l) lines)"
else
  echo "FAIL shared cloud-init block differs between runner-vm and ado-agent-vm:"
  diff <(printf '%s\n' "$a") <(printf '%s\n' "$b") || true
  exit 1
fi
