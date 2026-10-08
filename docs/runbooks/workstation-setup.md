# Runbook: Engineer Workstation Setup (Windows + WSL2)

**Purpose:** Rebuild the engineering workstation from zero to a known, version-pinned baseline.
**Owner:** platform-team · **Last validated:** 2026-09-29 · **Time to rebuild:** ~45 min

Placeholders: `<linux-user>`, `<windows-user>`, `<github-user>`, `<Your Name>`, `<TENANT_ID>`,
`<SUBSCRIPTION_ID>`. Real values are never committed to this public repository.

## 0. Before wiping an existing distro (skip on a new machine)

Nothing that exists only on this disk may be lost. For every repo under `$HOME`:

```bash
git -C <repo> status --porcelain                        # uncommitted work
git -C <repo> log --branches --not --remotes --oneline   # commits on no remote
git -C <repo> ls-files --others --ignored --exclude-standard  # gitignored = not on GitHub
```

Archive the gitignored files (local state, tfvars, plan files) and `~/.ssh` with `tar` to a
**local-only** folder (e.g. `C:\wsl-backup-YYYYMMDD`), **not** a cloud-synced folder:
state and saved plan files can contain plaintext secrets (e.g. storage account keys).

## 1. Recreate the distro (Windows PowerShell)

```powershell
wsl --shutdown                     # release the ext4.vhdx lock
wsl --update                       # update the WSL platform (kernel, interop)
wsl --unregister Ubuntu            # DESTRUCTIVE: deletes the distro disk
wsl --install -d Ubuntu-24.04      # version-pinned name, never the moving "Ubuntu" alias
```

Create the Linux user (`<linux-user>`) at first launch.

**Validated baseline:** Ubuntu 24.04.5 LTS · kernel 6.18.33.2-microsoft-standard-WSL2

## 2. Base OS layer (Ubuntu-24.04)

Windows Terminal profile → Command line: `wsl.exe -d Ubuntu-24.04 --cd ~` (so shells start on the Linux filesystem, not `/mnt/c`). Remove stale profiles for unregistered distros.

```bash
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y git curl wget unzip jq rsync ca-certificates gnupg
sudo tee /etc/wsl.conf >/dev/null <<'CONF'
[boot]
systemd=true

[user]
default=<linux-user>

[interop]
enabled=true
appendWindowsPath=false
CONF
```

Apply from **PowerShell**: `wsl --shutdown`, then open a new Ubuntu-24.04 tab.

**Verify:** `pwd` → `/home/<linux-user>`; `echo "$PATH" | tr ':' '\n' | grep -c '^/mnt/c'` → `0`; `/mnt/c/Windows/System32/cmd.exe /c ver` prints the Windows version (interop still on).

### 2b. Whitelist VS Code's launcher (only Windows dir on PATH, lowest priority)

Append to `~/.bashrc`. The `case` guard makes it idempotent: re-sourcing `.bashrc`, nested shells and
VS Code terminals (which inherit PATH) never duplicate the entry.

```bash
cat >> ~/.bashrc <<'RC'

# VS Code CLI: the only whitelisted Windows dir (appendWindowsPath=false).
# Guarded so re-sourcing .bashrc never duplicates it.
VSCODE_BIN="/mnt/c/Users/<windows-user>/AppData/Local/Programs/Microsoft VS Code/bin"
case ":$PATH:" in
  *":$VSCODE_BIN:"*) ;;
  *) export PATH="$PATH:$VSCODE_BIN" ;;
esac
unset VSCODE_BIN
RC
```

Open a new Ubuntu tab, then `code ~`.

**Verify (validated 2026-09-29):**
- `which -a code` → exactly one line, `/mnt/c/Users/<windows-user>/AppData/Local/Programs/Microsoft VS Code/bin/code`
- `code --version` → same version/commit as the server installed under `~/.vscode-server/bin/`
- `echo "$PATH" | tr ':' '\n' | grep -c '^/mnt/c'` → `1`
- VS Code bottom-left reads `WSL: Ubuntu-24.04`
- Idempotency: `source ~/.bashrc; source ~/.bashrc` → `echo "$PATH" | tr ':' '\n' | grep -c 'Microsoft VS Code/bin'` unchanged

### 2c. PATH hygiene check (run after ANY installer touches shell profiles)

Installers (e.g. `pipx ensurepath`) append to `~/.profile` and/or `~/.bashrc` without checking.
Ubuntu's `~/.profile` already prepends `~/.local/bin` when the directory exists.

```bash
grep -n -E 'PATH|local/bin|pipx' ~/.profile ~/.bashrc
env -i HOME="$HOME" TERM="$TERM" bash -lic 'echo "$PATH" | tr ":" "\n" | sort | uniq -d; echo "---"; echo "$PATH" | tr ":" "\n" | grep -c -E "^/mnt/c|\.local/bin$"'
```

**Expect:** nothing above `---`, `2` below it (one VS Code entry, one `~/.local/bin`).
`env -i` = empty environment, `-l` = login shell, `-i` = interactive (Ubuntu's `.bashrc` returns early otherwise).
Do **not** test with `exec bash -l`: it inherits the current PATH and stacks duplicates.

## 3. Git identity + credential helper (GCM)

Git credentials live in **Windows Credential Manager** (DPAPI-encrypted, tied to the Windows login) via
Git Credential Manager, which ships with Git for Windows. Never `credential.helper store` or `cache`.

```bash
ls -l "/mnt/c/Program Files/Git/mingw64/bin/git-credential-manager.exe"
"/mnt/c/Program Files/Git/mingw64/bin/git-credential-manager.exe" --version
git config --global user.name  "<Your Name>"
git config --global user.email "<ID>+<username>@users.noreply.github.com"   # github.com/settings/emails
git config --global init.defaultBranch main
git config --global credential.helper "/mnt/c/Program\ Files/Git/mingw64/bin/git-credential-manager.exe"
```

**Verify:** `git config --global --list --show-origin` → exactly those four keys, all from `file:/home/<linux-user>/.gitconfig`.
(On disk the helper shows as `Program\\ Files`; Git's config format escapes the backslash, it reads back as `Program\ Files`.)
Do **not** test with `git credential fill` (prints the token). The real test is the first push.

## 4. GitHub CLI (`gh`) — GitHub's apt repo, not Ubuntu's

```bash
sudo mkdir -p -m 755 /etc/apt/keyrings
out=$(mktemp) && wget -nv -O"$out" https://cli.github.com/packages/githubcli-archive-keyring.gpg
gpg --show-keys --with-fingerprint "$out"
```

**STOP:** fingerprint must include `2C61 0620 1985 B60E 6C7A C873 23F3 D4EA 7571 6059`
(also published: `7F38 BBB5 9D06 4DBC B3D8 4D72 5612 B364 6231 3325`).

```bash
sudo install -m 644 "$out" /etc/apt/keyrings/githubcli-archive-keyring.gpg && rm "$out"
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update && sudo apt install -y gh
gh auth login --hostname github.com --git-protocol https --web
```

> ⚠️ Answer **No** to "Authenticate Git with your GitHub credentials?". Yes runs `gh auth setup-git`, which adds
> `[credential "https://github.com"] helper =` (empty value resets the helper list) + `!gh auth git-credential`,
> silently replacing GCM for github.com with the plaintext token.
> **Recovery:** `git config --global --remove-section 'credential.https://github.com'` and
> `git config --global --remove-section 'credential.https://gist.github.com'`.

**Verify:** `gh --version`; `gh auth status` → logged in, token in `~/.config/gh/hosts.yml`;
`git config --global --get-regexp credential` → **only** the GCM line.

**Credential note:** `gh` stores a non-expiring `gho_` OAuth token (scopes `repo`, `workflow`, `read:org`, `gist`) in
plaintext `~/.config/gh/hosts.yml`, mode 600 (no keyring in WSL). Kill switch: github.com/settings/applications →
Authorized OAuth Apps → GitHub CLI → Revoke. Tracked as a known residual in ADR-0002.

## 5. Azure CLI — Microsoft apt repo

```bash
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
curl -sLS https://packages.microsoft.com/keys/microsoft.asc -o /tmp/microsoft.asc
gpg --show-keys --with-fingerprint /tmp/microsoft.asc
```

**STOP:** must be `BC52 8686 B50D 79E3 39D3 721C EB3E 94AD BE12 29CF` (Microsoft (Release signing)).

```bash
gpg --dearmor < /tmp/microsoft.asc | sudo tee /etc/apt/keyrings/microsoft.gpg > /dev/null
sudo chmod go+r /etc/apt/keyrings/microsoft.gpg && rm /tmp/microsoft.asc
AZ_DIST=$(lsb_release -cs)
echo "Types: deb
URIs: https://packages.microsoft.com/repos/azure-cli/
Suites: ${AZ_DIST}
Components: main
Architectures: $(dpkg --print-architecture)
Signed-by: /etc/apt/keyrings/microsoft.gpg" | sudo tee /etc/apt/sources.list.d/azure-cli.sources
sudo apt-get update && sudo apt-get install -y azure-cli
```

**Verify:** `az version`; `which -a az` → `/usr/bin/az` and `/bin/az` are the **same file** (merged /usr:
`ls -ld /bin` → `/bin -> usr/bin`; `readlink -f /bin/az /usr/bin/az` identical). Post-install key check:
`gpg --show-keys --with-fingerprint /etc/apt/keyrings/microsoft.gpg`.

### 5b. Log in (v2 tenant only)

```bash
az login --tenant <TENANT_ID>
az account set --subscription <SUBSCRIPTION_ID>
az account show --query "{sub:name, tenant:tenantId, user:user.name}" -o table
```

> ⚠️ Do **not** use `--use-device-code`: Entra tenants created on/after 2026-07-01 block device code flow
> under security defaults (`AADSTS530035`). Do **not** disable security defaults to work around it.
> Interactive login works from WSL with `appendWindowsPath=false` (redirect reaches `localhost` via WSL2 forwarding).
> If a sign-in page shows `AADSTS900561` (GET vs POST), it was refreshed/reopened: close it and rerun `az login`.

Operator identity: the v2 tenant's account (not the v1 account). Tokens cached in `~/.azure/` (plaintext MSAL cache on Linux).
Local Terraform runs as this identity. After a subscription rename: `az account list --refresh`.
Code never references the subscription by **name**, only by ID.

## 6. Terraform — HashiCorp apt repo, pinned + held

```bash
wget -qO /tmp/hashicorp.asc https://apt.releases.hashicorp.com/gpg
gpg --show-keys --with-fingerprint /tmp/hashicorp.asc
```

**STOP:** must be `D55C 0D1A C78A 8D81 26CB 631C FC9C A96A CA02 6560` (key rotated 2026-09-10;
`798A EC65 …` is the previous key, `E8A0 32E0 …` is revoked). Source: hashicorp.com/trust/security.

```bash
gpg --dearmor < /tmp/hashicorp.asc | sudo tee /etc/apt/keyrings/hashicorp.gpg > /dev/null
sudo chmod go+r /etc/apt/keyrings/hashicorp.gpg && rm /tmp/hashicorp.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list > /dev/null
sudo apt-get update
apt-cache madison terraform | head -5
sudo apt-get install -y terraform=<version from engineering_standards §4>-1
sudo apt-mark hold terraform
```

**Verify:** `terraform version` → pinned version on `linux_amd64`; `apt-mark showhold` → `terraform`.
Upgrades only by a deliberate change that updates §4 (`apt-mark unhold` → install new pin → `hold`).

## 7. pipx + pre-commit

```bash
sudo apt-get install -y pipx
pipx ensurepath          # then run the §2c PATH hygiene check and remove pipx's lines (see below)
pipx install pre-commit==<version from §4>
```

`pipx ensurepath` appends `export PATH="$PATH:/home/<linux-user>/.local/bin"` to **both** `~/.profile` and `~/.bashrc`.
Ubuntu's `~/.profile` already handles `~/.local/bin`, so remove both blocks:

```bash
sed -i.bak '/# Created by `pipx`/,+1d' ~/.profile ~/.bashrc
```

Then run §2c in a fresh shell and delete the `.bak` files.
Never `sudo apt install pre-commit` (older distro build, outside the pin), even though `command-not-found` suggests it.

**Verify:** `pre-commit --version`; `which -a pre-commit` → exactly `/home/<linux-user>/.local/bin/pre-commit`.

## 8. tflint — GitHub release, provenance-verified

No vendor apt repo, so the trust chain is built explicitly: **attestation → checksums.txt → zip**.
The release workflow attests `checksums.txt` (not the zips); the zip is trusted via its hash in that manifest.

```bash
mkdir -p ~/tmp/tflint && cd ~/tmp/tflint
gh release download v<version> -R terraform-linters/tflint -p 'tflint_linux_amd64.zip' -p 'checksums.txt'
gh attestation verify checksums.txt -R terraform-linters/tflint
sha256sum --check --ignore-missing checksums.txt
```

**STOP unless:** `✓ Verification succeeded!` with signer workflow
`terraform-linters/tflint/.github/workflows/release.yml@refs/tags/v<version>`, then `tflint_linux_amd64.zip: OK`.
(`gh attestation verify` on the zip itself returns HTTP 404 — expected, zips are not attested.
`checksums.txt.keyless.sig`/`.pem` are deprecated cosign signatures; not used.)

```bash
command -v unzip || sudo apt-get install -y unzip
unzip -o tflint_linux_amd64.zip tflint
sudo install -m 755 -o root -g root tflint /usr/local/bin/tflint
cd ~ && rm -rf ~/tmp/tflint
```

**Verify:** `tflint --version` → pinned version + `ruleset.terraform (bundled)`; `which -a tflint` → `/usr/local/bin/tflint`.
The azurerm ruleset is **not** installed here: it is pinned per repo in `.tflint.hcl` and fetched by `tflint --init`.

## 9. VS Code extensions (WSL side)

Run from the VS Code integrated terminal with `WSL: Ubuntu-24.04` bottom-left:

```bash
code --install-extension hashicorp.terraform
code --install-extension redhat.vscode-yaml
code --install-extension github.vscode-github-actions
```

**Verify:** `ls ~/.vscode-server/extensions/` shows all three (Terraform is the `-linux-x64` build).
Extensions auto-update; the repo's `.vscode/extensions.json` defines the recommended set.
Phase 2 adds Ansible / Azure Pipelines extensions — install when needed, not before.

## 10. Validated baseline (2026-09-29)

| Component | Version | Source / trust chain |
|---|---|---|
| Ubuntu (WSL) | 24.04.5 LTS, kernel 6.18.33.2 | `wsl --install -d Ubuntu-24.04` |
| VS Code | 1.139.0 (`2242ebbb`) | Windows install; server in `~/.vscode-server` |
| Git Credential Manager | 2.6.1 | Git for Windows |
| gh | 2.101.0 | GitHub apt repo, key `2C61…6059` |
| Azure CLI | 2.90.0 | Microsoft apt repo, key `BC52…29CF` |
| Terraform | 1.16.4 (held) | HashiCorp apt repo, key `D55C…6560` |
| pre-commit | 4.6.2 | pipx (Python 3.12.3) |
| tflint | 0.64.0 | GitHub release, SLSA attestation on checksums.txt |
| VS Code ext. | terraform 2.40.0 · yaml 1.24.0 · github-actions 0.32.3 | WSL side, auto-update |

## 11. Credential inventory (what lives on this workstation, and how to kill it)

| Credential | Stored in | Protection | Kill switch |
|---|---|---|---|
| Git (GitHub HTTPS) | Windows Credential Manager via GCM | DPAPI, Windows login | Credential Manager → remove `git:https://github.com`; GitHub → Settings → Applications |
| `gh` OAuth token (`gho_`) | `~/.config/gh/hosts.yml` | plaintext, mode 600 | github.com/settings/applications → GitHub CLI → Revoke |
| Azure CLI tokens | `~/.azure/` (MSAL cache) | plaintext, user-only | `az logout`; Entra → user → Revoke sessions |
| Azure DevOps PAT | none (v2 uses workload identity federation) | — | — |

## 12. Known traps (found during the 2026-09-29 rebuild)

- **Files copied from `/mnt/c` are executable.** WSL's default drvfs mount has no Linux permission metadata, so every
  Windows file reports `rwx`, and `cp` preserves it. Git records the executable bit in the tree entry (mode `100755`),
  not in the blob. Copy into repos with `install -m 644 <src> <dest>` (or `-m 755` for scripts, deliberately).
  **Check:** `git ls-files -s <file>` → first field must be `100644` for non-scripts.
- **Backslash line continuations break when pasted as one line.** A trailing `\` escapes the newline; if the line
  gets joined, it escapes the following space instead and splits arguments (`accepts at most 1 arg(s), received 3`).
  Prefer single-line commands in runbooks, or paste multi-line blocks intact.
- **Heredoc blocks must be pasted whole**, from the command through the closing marker line (`JSON`, `MD`, `RC`).

## 13. Clone the platform repository and enable the hooks

```bash
cd ~ && git clone https://github.com/<github-user>/azure-platform-engineering.git
cd azure-platform-engineering
pre-commit install
tflint --init
pre-commit run --all-files
```

`pre-commit install` is needed after **every** clone: it writes `.git/hooks/pre-commit`, and `.git/hooks/`
is not versioned. `tflint --init` downloads the azurerm ruleset version pinned in `.tflint.hcl`.
The first `pre-commit run` builds the hook environments (1–2 minutes, once).

**Verify:** `pre-commit installed at .git/hooks/pre-commit`; `tflint --init` reports the pinned azurerm
version; every hook `Passed` or `Skipped`.

## 14. Terraform environment variables (`~/.bashrc`)

Values that are personal or change over time never go into tfvars in this public repository. They live in `~/.bashrc` as single literal lines. Each command below is safe to re-run and leaves exactly one line.

Idempotent (value never changes: append only if absent):

```bash
grep -q '^export ARM_SUBSCRIPTION_ID=' ~/.bashrc || echo 'export ARM_SUBSCRIPTION_ID="<SUBSCRIPTION_ID>"' >> ~/.bashrc   # azurerm 4.x requires it
grep -q '^export TF_VAR_operator_object_id=' ~/.bashrc || echo 'export TF_VAR_operator_object_id="<OBJECT_ID>"' >> ~/.bashrc  # az ad signed-in-user show --query id -o tsv
```

Convergent (value changes, e.g. ISP IP: delete any existing line, then append the current one):

```bash
sed -i '/^export TF_VAR_operator_ip_cidr=/d' ~/.bashrc && echo 'export TF_VAR_operator_ip_cidr="<YOUR_IP>/32"' >> ~/.bashrc
```

After changing the operator IP: open a new shell, then plan/apply every root that allows it (network spokes, storage-demo, `platform/security`).

Verify without printing values:

```bash
grep -c '^export TF_VAR_operator_object_id=' ~/.bashrc   # expect 1 (same check for each variable)
source ~/.bashrc && echo ${#TF_VAR_operator_object_id}   # expect 36
```

Traps:
- One Terraform session per state key at a time (a second session waits on, or breaks, the blob lease).
- `!` inside double quotes triggers Bash history expansion: use single quotes for literal commit and PR text.
- pre-commit "Failed ... files were modified by this hook": `git add -A` and commit again.
- Never work from `/mnt/c`; copy files in with `install -m`.
