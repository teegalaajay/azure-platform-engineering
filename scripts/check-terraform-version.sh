#!/usr/bin/env bash
# Fail if any place that names the Terraform version differs from .terraform-version (ADR-0025).
# Detects drift only: it does not install anything and it cannot verify the SHA-256 in the ADO pipeline.
set -euo pipefail                                  # stop on error, unset variable, or a failure inside a pipe
cd "$(git rev-parse --show-toplevel)"              # run from the repository root wherever it is called from

want=$(tr -d '[:space:]' < .terraform-version)     # the single source of truth, whitespace removed
printf '%s' "$want" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' \
  || { echo "FAIL .terraform-version: '$want' is not MAJOR.MINOR.PATCH"; exit 1; }   # reject a malformed source first

fail=0
check() {                                          # $1 file, $2 pattern for the one line that names the version
  local file=$1 pattern=$2 found n
  found=$(grep -E "$pattern" "$file" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)   # version numbers on matching lines
  n=$(printf '%s\n' "$found" | grep -c . || true)  # how many were found: 0 means the pattern drifted
  if [ "$n" != "1" ]; then
    echo "FAIL $file: expected one match for /$pattern/, found $n"; fail=1
  elif [ "$found" != "$want" ]; then
    echo "FAIL $file: has $found, .terraform-version says $want"; fail=1
  else
    echo "ok   $file"
  fi
}

check .github/workflows/apply.yml            'test "\$have" = "'
check .github/workflows/plan.yml             '^[[:space:]]+terraform_version:'
check .github/workflows/validate.yml         '^[[:space:]]+terraform_version:'
check pipelines/ado-terraform-validate.yml   '^[[:space:]]+terraformVersion:'
check pipelines/ado-terraform-validate.yml   'Hash of terraform_[0-9.]+_linux_amd64\.zip'
check pipelines/ado-terraform-deploy.yml     '^[[:space:]]+terraformVersion:'
check pipelines/ado-terraform-deploy.yml     'Hash of terraform_[0-9.]+_linux_amd64\.zip'
check platform/runner/runner.auto.tfvars     '^terraform_version[[:space:]]*='
check platform/ado-agent/ado-agent.auto.tfvars '^terraform_version[[:space:]]*='

exit "$fail"                                       # non-zero when any place failed
