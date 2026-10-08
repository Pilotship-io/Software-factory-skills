#!/usr/bin/env bash
# factory-init.sh — install the Pilotship software factory into a repo.
#
# Usage (from the root of the target repo):
#     bash /path/to/Software-factory-skills/pilotship/factory-init.sh [options]
#
# Options:
#     --agents "claude-code cursor codex"   harnesses to link skills into (default: those three)
#     --source <owner/repo>                 skills source for `npx skills add` (default: Pilotship-io/Software-factory-skills)
#     --skip-skills                         don't run the skills installer
#     --with-db-scripts | --no-db-scripts   force copying (or skipping) scripts/worktree-env.sh + db-guard.sh
#                                           (default: copy when a docker-compose file exists)
#     --dry-run                             print what would happen, change nothing
#
# What it does, idempotently:
#     1. installs the factory skills into .agents/skills/ (+ harness symlinks) and writes skills-lock.json
#     2. appends the factory block to .gitignore
#     3. drops AGENTS.md / CLAUDE.md templates in (as *.factory.md when a file already exists)
#     4. drops .github/PULL_REQUEST_TEMPLATE.md in (same rule)
#     5. copies scripts/doctor.sh (machine readiness, every repo) and, when the
#        repo runs a local database, scripts/worktree-env.sh + scripts/db-guard.sh
#     6. reports which tools are missing on this machine
# It never overwrites an existing file. Merging a template into an existing
# AGENTS.md is a human job; the script prints the diff command.
set -euo pipefail

AGENTS="claude-code cursor codex"
SOURCE="Pilotship-io/Software-factory-skills"
SKIP_SKILLS=0
DB_SCRIPTS="auto"
DRY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --agents) AGENTS="$2"; shift 2 ;;
    --source) SOURCE="$2"; shift 2 ;;
    --skip-skills) SKIP_SKILLS=1; shift ;;
    --with-db-scripts) DB_SCRIPTS="yes"; shift ;;
    --no-db-scripts) DB_SCRIPTS="no"; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

factory_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
tpl="$factory_dir/templates"

log()  { printf '\033[1;34m[factory]\033[0m %s\n' "$*"; }
skip() { printf '\033[1;33m[factory]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[factory] %s\033[0m\n' "$*" >&2; exit 1; }
run()  { if [ "$DRY" = 1 ]; then echo "  would: $*"; else "$@"; fi; }

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "run this from inside the target repo"
repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"
log "target repo: $repo_root"
[ "$DRY" = 1 ] && log "dry run: nothing will be written"

# Every template carries a line "factory-template-version: X.Y". A repo file
# that already carries the current version is left alone silently (it was
# merged or customized on purpose). One that carries an older version, or
# none, gets a <name>.factory.<ext> copy beside it to merge by hand.
TEMPLATE_VERSION="$( { grep -hoE 'factory-template-version: [0-9.]+' "$factory_dir/AGENTS.template.md" || true; } | head -1 | awk '{print $2}')"
[ -n "$TEMPLATE_VERSION" ] || fail "AGENTS.template.md has no factory-template-version marker"

place() { # place <template-path> <dest-path>
  local src="$1" dest="$2" alt have
  if [ ! -e "$dest" ]; then
    run mkdir -p "$(dirname "$dest")"
    run cp "$src" "$dest"
    log "created $dest"
    return
  fi
  # `|| true`: an unmarked file must read as "no version", not abort under pipefail
  have="$( { grep -hoE 'factory-template-version: [0-9.]+' "$dest" 2>/dev/null || true; } | head -1 | awk '{print $2}')"
  if [ "$have" = "$TEMPLATE_VERSION" ]; then
    skip "$dest is on template v$TEMPLATE_VERSION; left alone"
    return
  fi
  alt="${dest%.*}.factory.${dest##*.}"
  [ "$dest" = "${dest%.*}" ] && alt="$dest.factory"
  if [ -e "$alt" ] && cmp -s "$src" "$alt"; then
    skip "$dest is on template v${have:-none}; $alt (v$TEMPLATE_VERSION) already written, merge by hand"
  else
    run cp "$src" "$alt"
    skip "$dest is on template v${have:-none}; wrote $alt (v$TEMPLATE_VERSION). Merge by hand: diff $alt $dest, then keep the version line"
  fi
}

# 1. skills
if [ "$SKIP_SKILLS" = 1 ]; then
  skip "skills install skipped (--skip-skills)"
else
  log "installing skills from $SOURCE for: $AGENTS"
  # shellcheck disable=SC2086
  run npx -y skills@latest add "$SOURCE" -a $AGENTS -s '*' -y
fi

# 2. gitignore
if grep -q 'pilotship software factory' .gitignore 2>/dev/null; then
  skip ".gitignore already has the factory block"
else
  if [ "$DRY" = 1 ]; then echo "  would: append factory block to .gitignore"; else cat "$tpl/gitignore.factory" >> .gitignore; fi
  log "appended factory block to .gitignore"
fi

# 3. agent contracts
place "$factory_dir/AGENTS.template.md" "AGENTS.md"
place "$factory_dir/CLAUDE.template.md" "CLAUDE.md"

# 4. PR template
place "$tpl/PULL_REQUEST_TEMPLATE.md" ".github/PULL_REQUEST_TEMPLATE.md"

# 5a. machine readiness (every repo; the db checks inside it switch on when DB_CONTAINER is set)
place "$tpl/scripts/doctor.sh" "scripts/doctor.sh"
[ "$DRY" = 1 ] || chmod +x scripts/doctor.sh 2>/dev/null || true
log "doctor placed. Fill its settings block, add \"doctor\": \"bash scripts/doctor.sh\" to package.json (or the repo's task runner), and point AGENTS.md → Setup and CONTRIBUTING at it."

# 5b. the session gate (every repo): the hook script plus the Claude Code hooks block
place "$tpl/scripts/factory-gate.sh" "scripts/factory-gate.sh"
[ "$DRY" = 1 ] || chmod +x scripts/factory-gate.sh 2>/dev/null || true
if [ ! -e .claude/settings.json ]; then
  run mkdir -p .claude
  if [ "$DRY" = 1 ]; then echo "  would: create .claude/settings.json with the factory hooks"; else python3 - "$tpl/claude-settings.hooks.json" > .claude/settings.json <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d.pop("_comment", None)
print(json.dumps(d, indent=2))
PY
  fi
  log "created .claude/settings.json with the factory hooks"
elif grep -q 'factory-gate.sh' .claude/settings.json 2>/dev/null; then
  skip ".claude/settings.json already wires factory-gate.sh"
else
  log "merge the hooks block from $tpl/claude-settings.hooks.json into .claude/settings.json (SessionStart + PreToolUse → scripts/factory-gate.sh)"
fi

# 5. db isolation scripts
if [ "$DB_SCRIPTS" = "auto" ]; then
  DB_SCRIPTS="no"
  for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do [ -e "$f" ] && DB_SCRIPTS="yes"; done
fi
if [ "$DB_SCRIPTS" = "yes" ]; then
  place "$tpl/scripts/worktree-id.sh" "scripts/worktree-id.sh"
  place "$tpl/scripts/worktree-env.sh" "scripts/worktree-env.sh"
  place "$tpl/scripts/db-guard.sh" "scripts/db-guard.sh"
  [ "$DRY" = 1 ] || chmod +x scripts/worktree-id.sh scripts/worktree-env.sh scripts/db-guard.sh 2>/dev/null || true
  log "db scripts placed. Edit the settings block in scripts/worktree-env.sh (DB_PREFIX, DB_CONTAINER, DB_USER/PASSWORD) and set the same DB_PREFIX in scripts/db-guard.sh."
  log "then wire db-guard in package.json: \"db:migrate\": \"bash scripts/db-guard.sh && <migrate>\" (same for seed/reset) and make the dev script honor \$PORT."
else
  skip "no compose file found; db isolation scripts not copied (use --with-db-scripts to force)"
fi

# 6. tooling report
log "machine tooling:"
check() { # check <cmd> <required|optional> <hint>
  if command -v "$1" >/dev/null 2>&1; then printf '   ✓ %-18s %s\n' "$1" "$(command -v "$1")"
  else printf '   ✗ %-18s %s — %s\n' "$1" "$2" "$3"; fi
}
check git required "install git"
check gh required "brew install gh && gh auth login"
check node required "install Node (nvm use <repo version>)"
check npx required "comes with npm"
check python3 required "needed by evidence-driven-testing scripts"
check before-and-after required "npm i -g @vercel/before-and-after agent-browser"
check agent-browser required "npm i -g agent-browser"
check ffmpeg optional "brew install ffmpeg (only for annotated video evidence)"
check lsof optional "port ownership checks"
if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then echo "   ✓ gh authenticated"; else echo "   ✗ gh not authenticated — gh auth login"; fi
fi

cat <<EOF

Next steps
  1. Review AGENTS.md (or merge AGENTS.factory.md into your existing one) and fill the "Repo-specific" section.
  2. Same for CLAUDE.md and .github/PULL_REQUEST_TEMPLATE.md if *.factory.* files were written.
  3. Install the review bot on this repo (see pilotship/REVIEW_BOTS.md) and confirm it comments on a test PR.
  4. Commit .agents/, .claude/skills/ symlinks, skills-lock.json, and the files above on a branch. Open the PR through the factory itself.
  5. Log what broke in pilotship/PILOT_LOG.md in the factory repo.
EOF
