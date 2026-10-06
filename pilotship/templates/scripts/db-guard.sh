#!/usr/bin/env bash
# factory-template-version: 1.2  (keep: factory-init.sh compares it on re-runs)
# db-guard.sh — refuse to run a database command against the wrong database.
#
# Wire it in front of every command that migrates, seeds, or resets:
#     "db:migrate": "bash scripts/db-guard.sh && drizzle-kit migrate",
#     "db:seed":    "bash scripts/db-guard.sh && tsx src/db/seed.ts",
#     "db:reset":   "bash scripts/db-guard.sh && ...",
#
# Rule enforced:
#   primary checkout  -> DATABASE_URL must name exactly ${DB_PREFIX}
#   git worktree      -> DATABASE_URL must name exactly ${DB_PREFIX}_<branch-slug>
#                        (the database scripts/worktree-env.sh created)
# Anything else exits 1. This is what stops an agent that copied the wrong
# env file from resetting a teammate's database. Do not bypass it; fix the
# env file instead (bash scripts/worktree-env.sh).
#
# DB_PREFIX must match the value in scripts/worktree-env.sh.
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"   # resolved before any cd: package scripts call this as ../scripts/<name>.sh

DB_PREFIX="${DB_PREFIX:-app_dev}"
ENV_FILE="${ENV_FILE:-.env.local}"

fail() { printf '\033[1;31m[db-guard] %s\033[0m\n' "$*" >&2; exit 1; }

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "not inside a git checkout"
cd "$repo_root"

# Resolve DATABASE_URL: environment wins, else read it from the env file.
url="${DATABASE_URL:-}"
if [ -z "$url" ] && [ -f "$ENV_FILE" ]; then
  url="$(grep -E '^DATABASE_URL=' "$ENV_FILE" | tail -n1 | cut -d= -f2- | sed -E 's/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/')"
fi
[ -n "$url" ] || fail "DATABASE_URL is not set and not found in $ENV_FILE"

# Database name = last path segment, minus any query string.
db_name="$(printf '%s' "$url" | sed -E 's#\?.*$##; s#^.*/##')"
[ -n "$db_name" ] || fail "could not parse a database name from DATABASE_URL"

# Refuse anything that is obviously not local. Remote migrations follow the
# repo's operations runbook, not the local scripts.
host="$(printf '%s' "$url" | sed -E 's#^[a-z]+://##; s#^[^@]*@##; s#[:/].*$##')"
case "$host" in
  localhost|127.0.0.1|::1|postgres|db) ;;
  *) fail "DATABASE_URL points at '$host', not a local database. Local db scripts only run against local databases." ;;
esac

. "$script_dir/worktree-id.sh"   # one definition of the worktree identity, shared with worktree-env.sh

git_dir="$(cd "$(git rev-parse --git-dir)" && pwd -P)"
common_dir="$(cd "$(git rev-parse --git-common-dir)" && pwd -P)"
branch="$(git branch --show-current)"

if [ "$git_dir" = "$common_dir" ]; then
  expected="$DB_PREFIX"
  where="primary checkout"
else
  [ -n "$branch" ] || fail "detached HEAD in a worktree; check out a branch"
  expected="${DB_PREFIX}_$(worktree_id "$branch")"
  where="worktree on branch $branch"
fi

if [ "$db_name" != "$expected" ]; then
  fail "DATABASE_URL names '$db_name' but this is the $where, which must use '$expected'.
  Run: bash scripts/worktree-env.sh   (worktree)   or fix $ENV_FILE   (primary checkout)."
fi

printf '\033[1;32m[db-guard]\033[0m ok: %s -> %s\n' "$where" "$db_name"
