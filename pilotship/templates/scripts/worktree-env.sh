#!/usr/bin/env bash
# factory-template-version: 1.2  (keep: factory-init.sh compares it on re-runs)
# worktree-env.sh — give this git worktree its own database and dev-server port.
#
# Run ONCE in a fresh worktree, before installing deps or starting anything:
#     bash scripts/worktree-env.sh
# Cleanup after the PR merges (drops the worktree database):
#     bash scripts/worktree-env.sh --drop
#
# Why: worktrees isolate files, not the local Postgres server or port 3000.
# Two agents sharing one database wipe each other's data the first time one
# of them runs a reset. This script derives a database name and a port from
# the branch name so every worktree is self-contained. scripts/db-guard.sh
# enforces the same mapping before every migrate / seed / reset.
#
# Repo-specific settings live in the block below. Every value can also be
# overridden by an environment variable of the same name.
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"   # resolved before any cd: package scripts call this as ../scripts/<name>.sh

# ---------------------------------------------------------------- settings --
DB_PREFIX="${DB_PREFIX:-app_dev}"                 # primary checkout's DB name; worktree DBs are ${DB_PREFIX}_<slug>
DB_CONTAINER="${DB_CONTAINER:-}"                  # docker container running postgres (e.g. pilotship-postgres-dev); empty = use local psql
DB_USER="${DB_USER:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-postgres}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
PORT_BASE="${PORT_BASE:-3100}"                    # worktree dev-server ports land in [PORT_BASE, PORT_BASE+PORT_RANGE)
PORT_RANGE="${PORT_RANGE:-800}"
ENV_FILE="${ENV_FILE:-.env.local}"                # env file the app reads; copied from the primary checkout, then patched
INSTALL_CMD="${INSTALL_CMD-npm install}"         # set to an empty string to skip (VAR="" ...)
MIGRATE_CMD="${MIGRATE_CMD-npm run db:migrate}"  # set to an empty string to skip (VAR="" ...)
SEED_CMD="${SEED_CMD-npm run db:seed}"           # set to an empty string to skip (VAR="" ...)
DB_BOOTSTRAP_SQL="${DB_BOOTSTRAP_SQL-}"           # optional SQL file applied once to a freshly created database (roles, grants, extensions); receives -v dbname=<db>
# -----------------------------------------------------------------------------

log()  { printf '\033[1;34m[worktree-env]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[worktree-env] %s\033[0m\n' "$*" >&2; exit 1; }

command -v git >/dev/null || fail "git not found"
# Machine readiness first: on a fresh machine this stops with the exact fix
# commands instead of a raw docker or psql error further down. Not for
# --drop: cleanup needs only git and the database, and must not be held
# hostage by an expired gh login or a missing screenshot tool.
if [ "${1:-}" != "--drop" ] && [ -f "$script_dir/doctor.sh" ]; then
  bash "$script_dir/doctor.sh" --for-worktree || fail "this machine is not ready for the factory yet (see the ✗ lines above; npm run doctor for the full report)"
fi
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "not inside a git checkout"

repo_root="$(git rev-parse --show-toplevel)"
git_dir="$(git rev-parse --git-dir)"
common_dir="$(git rev-parse --git-common-dir)"
cd "$repo_root"

# Primary checkout: .git dir == common dir. Worktree: .git dir is <common>/worktrees/<name>.
if [ "$(cd "$git_dir" && pwd -P)" = "$(cd "$common_dir" && pwd -P)" ]; then
  fail "this is the primary checkout, not a worktree. It keeps the default database (${DB_PREFIX}) and port. Nothing to do."
fi
primary_root="$(cd "$common_dir/.." && pwd -P)"

branch="$(git branch --show-current)"
[ -n "$branch" ] || fail "detached HEAD; check out a branch first"
case "$branch" in main|master) fail "refusing to run on '$branch'. Create a task branch first." ;; esac

. "$script_dir/worktree-id.sh"   # one definition of the worktree identity, shared with db-guard.sh
slug="$(worktree_id "$branch")"
db_name="${DB_PREFIX}_${slug}"
# Port: start from the branch hash, but never hand out a port another worktree
# already recorded in its env file or that something is already listening on.
# A port already written in THIS worktree's env file is kept, so re-runs are
# stable. Probes forward through the range; fails loudly if the range is full.
port_listening() { command -v lsof >/dev/null 2>&1 && lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }
ports_claimed_by_siblings() {
  git worktree list --porcelain | awk '/^worktree /{sub(/^worktree /,""); print}' | while IFS= read -r wt; do
    [ "$wt" = "$repo_root" ] && continue
    [ -f "$wt/$ENV_FILE" ] && grep -hE '^PORT=[0-9]+$' "$wt/$ENV_FILE" | cut -d= -f2
  done
}
own_port="$( [ -f "$repo_root/$ENV_FILE" ] && grep -hE '^PORT=[0-9]+$' "$repo_root/$ENV_FILE" | tail -n1 | cut -d= -f2 || true)"
claimed="$(ports_claimed_by_siblings | tr '\n' ' ')"
start=$(( 16#$(hash_hex "$branch") % PORT_RANGE ))
port=""
if [ -n "$own_port" ]; then
  port="$own_port"
else
  for try in $(seq 0 $(( PORT_RANGE - 1 ))); do
    cand=$(( PORT_BASE + (start + try) % PORT_RANGE ))
    case " $claimed " in *" $cand "*) continue ;; esac
    port_listening "$cand" && continue
    port="$cand"; break
  done
  [ -n "$port" ] || fail "no free port in [$PORT_BASE, $((PORT_BASE + PORT_RANGE))). Free one or raise PORT_RANGE."
fi

# --- psql helper: docker exec when a container is named, local psql otherwise
psql_admin() {
  if [ -n "$DB_CONTAINER" ]; then
    docker exec -i -e PGPASSWORD="$DB_PASSWORD" "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -v ON_ERROR_STOP=1 -qtA "$@"
  else
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -v ON_ERROR_STOP=1 -qtA "$@"
  fi
}

# same as psql_admin but connected to the worktree database itself
psql_db() {
  if [ -n "$DB_CONTAINER" ]; then
    docker exec -i -e PGPASSWORD="$DB_PASSWORD" "$DB_CONTAINER" psql -U "$DB_USER" -d "$db_name" -v ON_ERROR_STOP=1 -qtA "$@"
  else
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$db_name" -v ON_ERROR_STOP=1 -qtA "$@"
  fi
}

db_exists() { [ "$(psql_admin -c "SELECT 1 FROM pg_database WHERE datname='${db_name}'" | tr -d '[:space:]')" = "1" ]; }

if [ "${1:-}" = "--drop" ]; then
  if db_exists; then
    log "dropping database ${db_name}"
    psql_admin -c "DROP DATABASE \"${db_name}\" WITH (FORCE)"
  else
    log "database ${db_name} does not exist; nothing to drop"
  fi
  exit 0
fi

log "branch   : $branch"
log "database : $db_name"
log "port     : $port"
log "primary  : $primary_root"

# --- env file: copy from primary checkout (secrets live there), then patch
if [ -f "$primary_root/$ENV_FILE" ]; then
  src="$primary_root/$ENV_FILE"
elif [ -f "$repo_root/.env.example" ]; then
  src="$repo_root/.env.example"
  log "no $ENV_FILE in primary checkout; starting from .env.example (fill in secrets yourself)"
else
  fail "no $ENV_FILE in $primary_root and no .env.example here; cannot build an env file"
fi

db_url="postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${db_name}"
{
  grep -vE '^(DATABASE_URL|PORT|FACTORY_WORKTREE_DB)=' "$src" || true
  printf '\n# --- written by scripts/worktree-env.sh for branch %s ---\n' "$branch"
  printf 'DATABASE_URL=%s\n' "$db_url"
  printf 'PORT=%s\n' "$port"
  printf 'FACTORY_WORKTREE_DB=%s\n' "$db_name"
} > "$repo_root/$ENV_FILE"
log "wrote $ENV_FILE"

# --- database
if db_exists; then
  log "database ${db_name} already exists; reusing"
else
  log "creating database ${db_name}"
  psql_admin -c "CREATE DATABASE \"${db_name}\""
  if [ -n "$DB_BOOTSTRAP_SQL" ] && [ -f "$DB_BOOTSTRAP_SQL" ]; then
    log "bootstrapping ${db_name} from $DB_BOOTSTRAP_SQL"
    psql_db -v dbname="$db_name" -f - < "$DB_BOOTSTRAP_SQL"
  fi
fi

# --- deps, migrate, seed (all run with the new env so DATABASE_URL points at the worktree DB)
export DATABASE_URL="$db_url" PORT="$port" FACTORY_WORKTREE_DB="$db_name"
if [ -n "$INSTALL_CMD" ] && [ ! -d node_modules ]; then log "installing dependencies"; eval "$INSTALL_CMD"; fi
if [ -n "$MIGRATE_CMD" ]; then log "migrating";  eval "$MIGRATE_CMD"; fi
if [ -n "$SEED_CMD" ];    then log "seeding";    eval "$SEED_CMD";    fi

# --- port sanity (a re-used own_port may have been taken by an unrelated process since)
if port_listening "$port"; then
  log "WARNING: something already listens on $port. Confirm it is yours (lsof -i :$port) before trusting http://localhost:$port"
fi

cat <<EOF

Worktree ready.
  database : $db_name
  port     : $port   (dev server must honor \$PORT, e.g. next dev -p \${PORT:-3000})
  env file : $ENV_FILE

When the PR is merged: bash scripts/worktree-env.sh --drop, then remove the worktree and branch.
EOF
