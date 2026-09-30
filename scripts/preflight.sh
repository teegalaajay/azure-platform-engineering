#!/usr/bin/env bash
# End-of-day definition-of-done check. Paste the output to Claude.
# Install: cp to ~/azure-platform-engineering/scripts/ && chmod +x
set -uo pipefail
REPO_DIR="${REPO_DIR:-$HOME/azure-platform-engineering}"
cd "$REPO_DIR" || exit 1
fail=0

echo "== git =="
git fetch -q origin 2>/dev/null
git status -sb | head -1
if [ -n "$(git status --porcelain)" ]; then echo "FAIL: uncommitted changes"; git status --short; fail=1; fi
if git status -sb | head -1 | grep -q 'ahead'; then echo "FAIL: commits not pushed"; fail=1; fi
git log --oneline -3

echo "== local state anywhere in the repo (RC1) =="
stray=$(find . -name 'terraform.tfstate*' -not -path '*/.terraform/*')
if [ -n "$stray" ]; then echo "FAIL:"; echo "$stray"; fail=1; else echo "ok"; fi

echo "== root modules missing backend.tf (RC1) =="
for d in platform/*/ workloads/*/; do
  [ -d "$d" ] || continue
  [ -f "$d/backend.tf" ] || { echo "FAIL: $d has no backend.tf"; fail=1; }
done
echo "checked"

echo "== machine-dependent paths (RC3) =="
if grep -rnE 'file\("~|pathexpand\(|/home/|/mnt/c/' --include='*.tf' . 2>/dev/null; then
  echo "FAIL: config reads laptop paths"; fail=1
else echo "ok"; fi

echo "== terraform fmt =="
if command -v terraform >/dev/null; then
  terraform fmt -check -recursive >/dev/null && echo "ok" || { echo "FAIL: run terraform fmt -recursive"; fail=1; }
fi

echo "== YAML lint =="
if command -v actionlint >/dev/null && [ -d .github/workflows ]; then actionlint && echo "actionlint ok" || fail=1; fi

echo
[ $fail -eq 0 ] && echo "DEFINITION OF DONE: PASS" || echo "DEFINITION OF DONE: FAIL — fix before calling the day done"
exit $fail
