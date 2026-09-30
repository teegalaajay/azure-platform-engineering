#!/usr/bin/env bash
# Copy the repo (minus state, plans, provider caches, secrets) into the Claude
# project folder so the mentor can read the REAL files next session.
# Install: cp to ~/azure-platform-engineering/scripts/ && chmod +x
# Set PROJECT_DIR once in ~/.bashrc, e.g.:
#   export AZ_ROADMAP_PROJECT_DIR="/mnt/c/Users/<you>/OneDrive/Documents/Claude/Projects/<v2 project folder>"
set -euo pipefail

REPO_DIR="${REPO_DIR:-$HOME/azure-platform-engineering}"
PROJECT_DIR="${AZ_ROADMAP_PROJECT_DIR:?Set AZ_ROADMAP_PROJECT_DIR to the v2 project folder (WSL path)}"
DEST="$PROJECT_DIR/repo-snapshot"

command -v rsync >/dev/null || { echo "rsync missing: sudo apt install -y rsync"; exit 1; }

mkdir -p "$DEST"
# Filter order matters: rsync applies the FIRST matching rule, so the
# *.auto.tfvars include must come before the *.tfvars exclude.
rsync -a --delete \
  --exclude '.git/' \
  --exclude '.terraform/' \
  --exclude '*.tfstate' --exclude '*.tfstate.*' \
  --exclude '*tfplan*' \
  --include '*.auto.tfvars' --exclude '*.tfvars' \
  --exclude '.venv/' --exclude '__pycache__/' \
  --exclude '*.pem' --exclude '*.key' --exclude 'id_rsa' \
  --exclude '.env' --exclude '.env.*' \
  --exclude '*vault_pass*' --exclude '*vault-password*' \
  "$REPO_DIR/" "$DEST/"

# Record exactly which commit the snapshot is
git -C "$REPO_DIR" log -1 --format='%H %cd %s' > "$DEST/SNAPSHOT_COMMIT.txt"
git -C "$REPO_DIR" status -sb >> "$DEST/SNAPSHOT_COMMIT.txt"
echo "Synced $(find "$DEST" -type f | wc -l) files → $DEST"
cat "$DEST/SNAPSHOT_COMMIT.txt"
