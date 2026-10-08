#!/usr/bin/env bash
# factory-template-version: 1.2  (keep: factory-init.sh compares it on re-runs)
# doctor.sh — is this machine ready to run the software factory on this repo?
#
#   npm run doctor            full report, exit 1 if anything required is missing
#   bash scripts/doctor.sh --for-worktree
#                             called by worktree-env.sh before it touches
#                             anything: same checks, only failures printed
#
# Every miss prints the exact command that fixes it. Fill the settings block
# for your repo. Human onboarding: pilotship/ONBOARDING.md in the factory repo.
set -uo pipefail

# ------------------------------------------------------------- settings ----
NODE_MAJOR_WANTED="${NODE_MAJOR_WANTED:-22}"   # what CI runs; empty to skip the Node check
DB_CONTAINER="${DB_CONTAINER:-}"               # docker container running the local database; empty = no local database
DB_PORT_IN_CONTAINER="${DB_PORT_IN_CONTAINER:-5432}"
ENV_FILE="${ENV_FILE:-.env.local}"             # env file the app reads (empty to skip)
DB_UP_CMD="${DB_UP_CMD:-npm run db:up}"          # how THIS repo starts the database container (compose may live in a package directory)
DB_PORT_ENV_FILE="${DB_PORT_ENV_FILE:-.env}"        # where PGPORT_HOST is persisted for compose (the .env next to the compose file)
EXPECTED_SKILLS="${EXPECTED_SKILLS:-before-and-after code-structure evidence-driven-testing greploop greploop-apps new-feature unslop}"
FACTORY_REPO="https://github.com/Pilotship-io/Software-factory-skills"
# ---------------------------------------------------------------------------

quiet=0; [ "${1:-}" = "--for-worktree" ] && quiet=1
fails=0; warns=0
ok()   { [ $quiet = 1 ] || printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { warns=$((warns+1)); [ $quiet = 1 ] || printf '  \033[33m!\033[0m %s\n      fix: %s\n' "$1" "$2"; }
fail() { fails=$((fails+1)); printf '  \033[31m✗\033[0m %s\n      fix: %s\n' "$1" "$2"; }

# --- operating system: the factory's scripts are bash + Unix tools. macOS and
# Linux run them natively; Windows runs them inside WSL2 (Ubuntu), which is
# Linux. A native Windows shell (Git Bash, MSYS, Cygwin, PowerShell) is not
# supported: npm runs scripts through cmd.exe there, symlinks need extra
# setup, and lsof does not exist. DOCTOR_UNAME overrides detection for tests.
uname_s="${DOCTOR_UNAME:-$(uname -s 2>/dev/null || echo unknown)}"
case "$uname_s" in
  MINGW*|MSYS*|CYGWIN*|Windows*)
    printf '  \033[31m✗\033[0m native Windows shell detected (%s): the factory runs on Windows inside WSL2, not in Git Bash / PowerShell\n' "$uname_s"
    printf '      fix: install WSL2 with Ubuntu (wsl --install), then inside it: install Node %s, git, gh, Docker Desktop with WSL integration enabled for the distro, clone the repo there, and run npm run doctor again.\n' "${NODE_MAJOR_WANTED:-22}"
    printf '      setup guide: pilotship/ONBOARDING.md (Windows section) at %s\n' "$FACTORY_REPO"
    exit 1 ;;
  Linux)
    os=linux
    if grep -qi microsoft /proc/version 2>/dev/null; then wsl=1; else wsl=0; fi
    # Package-manager-aware hints; distro-neutral wording when none is recognised.
    if command -v apt-get >/dev/null 2>&1; then pkg() { echo "sudo apt install $1"; }
    elif command -v dnf >/dev/null 2>&1; then pkg() { echo "sudo dnf install $1"; }
    elif command -v pacman >/dev/null 2>&1; then pkg() { echo "sudo pacman -S $1"; }
    elif command -v zypper >/dev/null 2>&1; then pkg() { echo "sudo zypper install $1"; }
    else pkg() { echo "install $1 with your distribution's package manager"; }; fi
    HINT_GH="$(pkg gh) (or https://cli.github.com), then gh auth login"
    if [ "$wsl" = 1 ]; then
      HINT_DOCKER_INSTALL="install Docker Desktop on Windows and enable WSL integration for this distro (Settings → Resources → WSL integration)"
      HINT_DOCKER_START="start Docker Desktop on Windows (WSL integration on for this distro), then start the database (see AGENTS.md → Setup)"
    else
      HINT_DOCKER_INSTALL="install Docker Engine per https://docs.docker.com/engine/install/ for your distribution, add yourself to the docker group, then start the database (see AGENTS.md → Setup)"
      HINT_DOCKER_START="start the Docker service (systemd: sudo systemctl start docker; otherwise your init system's equivalent), then start the database (see AGENTS.md → Setup)"
    fi
    HINT_LSOF="$(pkg lsof)" ;;
  Darwin)
    os=mac; wsl=0
    HINT_GH="brew install gh && gh auth login"
    HINT_DOCKER_INSTALL="install Docker Desktop, then start the database (see AGENTS.md → Setup)"
    HINT_DOCKER_START="open -a Docker, wait for it, then start the database (see AGENTS.md → Setup)"
    HINT_LSOF="lsof ships with macOS; check your PATH" ;;
  *)
    os=other; wsl=0
    HINT_GH="install the GitHub CLI (https://cli.github.com) && gh auth login"
    HINT_DOCKER_INSTALL="install Docker, then start the database (see AGENTS.md → Setup)"
    HINT_DOCKER_START="start the Docker daemon, then start the database (see AGENTS.md → Setup)"
    HINT_LSOF="install lsof" ;;
esac
if [ $quiet = 0 ]; then
  case "$os" in
    mac) ok "macOS" ;;
    linux) [ "$wsl" = 1 ] && ok "Linux inside WSL2 (supported; Docker Desktop must have WSL integration on for this distro)" || ok "Linux" ;;
    *) warn "unrecognised OS ($uname_s); the scripts assume macOS or Linux" "use macOS, Linux, or WSL2 on Windows" ;;
  esac
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || { fail "not inside a git checkout" "cd into the repo"; exit 1; }
common_dir="$(git rev-parse --git-common-dir)"
primary_root="$(cd "$common_dir/.." && pwd -P)"
[ $quiet = 1 ] || echo "software factory doctor — $(basename "$primary_root") on $(hostname -s)"

# --- toolchain
if [ -n "$NODE_MAJOR_WANTED" ]; then
  if command -v node >/dev/null 2>&1; then
    major="$(node -v | sed -E 's/^v([0-9]+).*/\1/')"
    if [ "$major" = "$NODE_MAJOR_WANTED" ]; then ok "node $(node -v) (CI runs $NODE_MAJOR_WANTED)"
    elif [ "$major" -ge 20 ]; then warn "node $(node -v); CI runs $NODE_MAJOR_WANTED, so a build that passes here can still fail there" "install Node $NODE_MAJOR_WANTED (nvm install $NODE_MAJOR_WANTED && nvm use $NODE_MAJOR_WANTED)"
    else fail "node $(node -v) is too old" "install Node $NODE_MAJOR_WANTED"; fi
  else fail "node not found" "install Node $NODE_MAJOR_WANTED"; fi
fi
for t in git npm npx python3; do command -v "$t" >/dev/null 2>&1 && ok "$t" || fail "$t not found" "install $t"; done
if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then ok "gh authenticated as $(gh api user -q .login 2>/dev/null || echo '?')"
  else fail "gh is installed but not signed in (PRs, reviews and the merge loop need it)" "gh auth login"; fi
else fail "gh (GitHub CLI) not found" "$HINT_GH"; fi
command -v lsof >/dev/null 2>&1 && ok "lsof" || warn "lsof not found (port ownership checks are skipped)" "$HINT_LSOF"

# --- repo state
if [ $quiet = 0 ] && [ -f "$repo_root/package.json" ]; then
  [ -d "$repo_root/node_modules" ] && ok "node_modules present" || fail "dependencies not installed in $(basename "$repo_root")" "npm install"
fi
missing=""
for s in $EXPECTED_SKILLS; do [ -d "$repo_root/.agents/skills/$s" ] || missing="$missing $s"; done
if [ -z "$missing" ]; then ok "factory skills installed (.agents/skills)"; else fail "factory skills missing:$missing" "npx skills add Pilotship-io/Software-factory-skills -a claude-code cursor codex -s '*' -y"; fi
[ -L "$repo_root/.claude/skills/greploop" ] && ok "skills linked for Claude Code" || warn "Claude Code skill links missing (.claude/skills)" "re-run: npx skills add Pilotship-io/Software-factory-skills -a claude-code cursor codex -s '*' -y"

# --- local database (only when the repo has one)
if [ -n "$DB_CONTAINER" ]; then
  if ! command -v docker >/dev/null 2>&1; then
    fail "docker not found" "$HINT_DOCKER_INSTALL"
  elif ! docker info >/dev/null 2>&1; then
    fail "Docker daemon is not running" "$HINT_DOCKER_START"
  else
    if docker ps --format '{{.Names}}' | grep -qx "$DB_CONTAINER"; then
      hostport="$(docker port "$DB_CONTAINER" "$DB_PORT_IN_CONTAINER/tcp" 2>/dev/null | head -1 | sed -E 's/.*:([0-9]+)$/\1/')"
      ok "database container $DB_CONTAINER up on host port ${hostport:-?}"
      if [ -n "$ENV_FILE" ] && [ -f "$primary_root/$ENV_FILE" ]; then
        # Compare only when the file actually sets DATABASE_URL (a worktree
        # generates its own URL from DB_PORT, so an absent line is not a mismatch).
        # Port = the explicit host:PORT/ segment; a URL without one means the default.
        envurl="$( { grep -E '^DATABASE_URL=' "$primary_root/$ENV_FILE" || true; } | tail -1)"
        envport=""
        if [ -n "$envurl" ]; then
          envport="$(printf '%s' "$envurl" | { grep -oE '@[^/:@]+:[0-9]+/' || true; } | grep -oE '[0-9]+' | tail -1)"
          [ -n "$envport" ] || envport="$DB_PORT_IN_CONTAINER"
        fi
        if [ -n "$hostport" ] && [ -n "$envport" ] && [ "$envport" != "$hostport" ]; then
          fail "$ENV_FILE points at port $envport but the container listens on $hostport" "edit DATABASE_URL in $primary_root/$ENV_FILE to use :$hostport (or DB_PORT=$hostport bash scripts/worktree-env.sh in a worktree)"
        fi
      fi
    elif docker ps -a --format '{{.Names}}' | grep -qx "$DB_CONTAINER"; then
      fail "database container $DB_CONTAINER exists but is stopped" "docker start $DB_CONTAINER"
    elif lsof -nP -iTCP:"$DB_PORT_IN_CONTAINER" -sTCP:LISTEN >/dev/null 2>&1; then
      fail "database container $DB_CONTAINER is not running and port $DB_PORT_IN_CONTAINER is taken by something else" "pick a free port, write PGPORT_HOST=<port> to $DB_PORT_ENV_FILE (gitignored; compose reads it every time), run $DB_UP_CMD from the primary checkout, and use that port in DATABASE_URL / DB_PORT for worktree-env.sh"
    else
      fail "database container $DB_CONTAINER is not running" "start it from the primary checkout: $DB_UP_CMD (AGENTS.md → Setup)"
    fi
  fi
fi
if [ -n "$ENV_FILE" ]; then
  if [ -f "$primary_root/$ENV_FILE" ]; then ok "$ENV_FILE present in the primary checkout (worktrees copy it)"
  else warn "no $ENV_FILE in the primary checkout; worktrees fall back to .env.example" "cp .env.example $ENV_FILE in $primary_root and fill in the keys (see AGENTS.md → Setup)"; fi
fi

# --- evidence tooling
if command -v before-and-after >/dev/null 2>&1 && command -v agent-browser >/dev/null 2>&1; then ok "before-and-after + agent-browser (screenshot evidence)"
else warn "before-and-after / agent-browser not installed; visible changes need screenshots, other changes use output pairs" "npm i -g @vercel/before-and-after agent-browser"; fi
command -v ffmpeg >/dev/null 2>&1 && ok "ffmpeg (optional video evidence)" || { [ $quiet = 1 ] || printf '  \033[2m·\033[0m ffmpeg not installed (optional: video evidence)\n'; }

# --- verdict
if [ $quiet = 1 ]; then
  [ $fails = 0 ] && exit 0
  echo "doctor: $fails required item(s) missing on this machine (npm run doctor for the full report; setup: pilotship/ONBOARDING.md at $FACTORY_REPO)"; exit 1
fi
echo
if [ $fails = 0 ] && [ $warns = 0 ]; then echo "ready: everything the factory needs is here."
elif [ $fails = 0 ]; then echo "ready with $warns warning(s): the factory runs; fix the warnings for full evidence and CI parity."
else echo "not ready: $fails required item(s) missing ($warns warning(s)). Fix the ✗ lines, then run npm run doctor again. Onboarding: pilotship/ONBOARDING.md at $FACTORY_REPO"; fi
echo "The review bot cannot be checked from here: ask the repo owner for access if your PRs get no review."
[ $fails = 0 ]
