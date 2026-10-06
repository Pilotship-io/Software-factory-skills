#!/usr/bin/env bash
# factory-template-version: 1.2  (keep: factory-init.sh compares it on re-runs)
# factory-gate.sh — the software factory's entry gate, wired into the agent
# harness as hooks (see .claude/settings.json). Two modes:
#
#   session    SessionStart hook. Prints the "start here" checklist and the
#              current isolation status so every fresh session, in every
#              harness that supports a start hook, sees the contract before
#              it does anything, even a session opened on a stale checkout.
#
#   pre-tool   PreToolUse hook for file edits and shell commands. Reads the
#              tool call as JSON on stdin and refuses (exit 2) anything that
#              would write to the PRIMARY checkout while it sits on the
#              default branch. Work belongs in a worktree on a task branch;
#              that is beat 1.
#
# What pre-tool refuses, and from where:
#   - Edit / Write / MultiEdit / NotebookEdit whose target resolves inside
#     the primary checkout (and not inside a worktree directory), from ANY
#     session location. A session inside a worktree cannot reach over.
#   - Bash commands while the session's cwd is the primary checkout on the
#     default branch: mutating git subcommands (commit, merge, rebase,
#     cherry-pick, revert, reset, am, apply, stash pop/apply) in any segment
#     of the command, shell redirects into repo paths, and the usual
#     in-place writers (sed -i, tee, cp, mv, rm, touch, patch, ln, mkdir)
#     aimed at repo paths. Redirects to /dev/null, /tmp, .artifacts and
#     paths outside the repo pass.
#   - Bash commands from any session that point git at the primary checkout
#     (`git -C <primary> commit`, `cd <primary> && git commit`).
#   The Bash side is a tripwire for the common forms, not a sandbox; the
#   Edit/Write hook and the harness's own permission rules are the guards.
#
# Escape hatch for a human doing emergency work by hand: FACTORY_GATE=off in
# the environment skips the block (the checklist still prints). Agents must
# never set it.
set -uo pipefail

MODE="${1:-session}"
export FACTORY_DEFAULT_BRANCH="${FACTORY_DEFAULT_BRANCH:-main}"
# Branches no agent may push to directly, in any refspec spelling. The trunk
# plus main/master; add release lines here if the repo has them.
export FACTORY_PROTECTED_BRANCHES="${FACTORY_PROTECTED_BRANCHES:-$FACTORY_DEFAULT_BRANCH main master}"

# The harness hands the tool call (or session) as JSON on stdin and runs the
# hook with the PROJECT ROOT as its working directory, even when the session
# is inside a worktree. The session's real location is the `cwd` field, so
# every git question below is asked from there.
input="$(cat 2>/dev/null || true)"
hook_cwd="$(printf '%s' "$input" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("cwd") or "")
except Exception: print("")' 2>/dev/null)"
[ -n "$hook_cwd" ] && [ -d "$hook_cwd" ] && cd "$hook_cwd"

git_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$git_root" ] || exit 0   # not a git checkout: nothing to gate
branch="$(git branch --show-current 2>/dev/null || true)"
git_dir="$(cd "$(git rev-parse --git-dir 2>/dev/null)" 2>/dev/null && pwd -P || true)"
common_dir="$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P || true)"
in_worktree=no
[ -n "$git_dir" ] && [ -n "$common_dir" ] && [ "$git_dir" != "$common_dir" ] && in_worktree=yes
# The primary checkout is the parent of the shared .git directory.
primary_root="${common_dir%/.git}"
[ "$primary_root" = "$common_dir" ] && primary_root="$git_root"
primary_branch="$(git -C "$primary_root" branch --show-current 2>/dev/null || true)"
is_default() { [ "$1" = "$FACTORY_DEFAULT_BRANCH" ] || [ "$1" = "master" ]; }
on_default=no;         is_default "$branch"         && on_default=yes
primary_on_default=no; is_default "$primary_branch" && primary_on_default=yes

checklist() {
  cat <<'EOF'
[factory] Start here, every session (AGENTS.md, "Start here"):
  1. Fresh machine or fresh clone: npm run doctor, then follow its fix commands.
  2. Fresh session: you are reading the current AGENTS.md now. A session that
     started before it changed does not know the contract; do not carry one over.
  3. Every task begins with the new-feature skill: a worktree and branch off
     origin/main, then `bash scripts/worktree-env.sh` inside it. Never on main.
  4. Build, prove with evidence, open the PR from the template, then greploop
     until the reviewer reports 5/5 with zero unresolved comments.
  5. A human merges. Never below 5/5, never with an open thread.
EOF
}

status_line() {
  if [ "$in_worktree" = yes ]; then
    printf '[factory] Status: worktree on branch %s. Beat 1 done; build, prove, ship.\n' "${branch:-?}"
  elif [ "$on_default" = yes ]; then
    printf '[factory] Status: PRIMARY CHECKOUT on %s. File edits and commits are blocked here until you are in a worktree. Start with the new-feature skill.\n' "$branch"
  else
    printf '[factory] Status: primary checkout on branch %s (not a worktree). Prefer a worktree; the gate allows this branch.\n' "${branch:-?}"
  fi
}

case "$MODE" in
  session)
    checklist
    status_line
    exit 0
    ;;
  pre-tool)
    [ "${FACTORY_GATE:-on}" = off ] && exit 0
    # Nothing to protect unless the primary checkout sits on the default branch.
    [ "$primary_on_default" = yes ] || exit 0

    # The decision is one Python program so multi-line commands, git options
    # between `git` and its subcommand, and path resolution are handled once.
    # It prints a reason on stdout when the call must be refused, else nothing.
    # The program arrives on stdin (heredoc), so the tool call travels in an
    # environment variable rather than the pipe.
    # A function, not a $( ) around the heredoc: bash scans a substitution for
    # quotes and parentheses and the regexes below contain both.
    decide() {
    GATE_INPUT="$input" GATE_CWD="$PWD" GATE_PRIMARY="$primary_root" GATE_IN_WORKTREE="$in_worktree" GATE_ON_DEFAULT="$on_default" GATE_BRANCH="$branch" GATE_PROTECTED="$FACTORY_PROTECTED_BRANCHES" python3 - <<'PY'
import json, os, re, sys
try:
    d = json.loads(os.environ.get("GATE_INPUT") or "")
except Exception:
    sys.exit(0)
tool = d.get("tool_name") or ""
ti = d.get("tool_input") or {}
cwd = os.environ["GATE_CWD"]
primary = os.path.realpath(os.environ["GATE_PRIMARY"])
session_in_primary_on_default = os.environ["GATE_IN_WORKTREE"] == "no" and os.environ["GATE_ON_DEFAULT"] == "yes"
WORKTREE_DIRS = ("/.claude/worktrees/", "/.worktrees/")

def resolve(p):
    p = os.path.expanduser(p)
    if not os.path.isabs(p):
        p = os.path.join(cwd, p)
    return os.path.normpath(p)

def in_primary(p):
    """True when p lives in the primary checkout and not inside a worktree dir."""
    rp = resolve(p)
    if any(w in rp + "/" for w in WORKTREE_DIRS):
        return False
    return rp == primary or rp.startswith(primary + "/")

def refuse(what):
    print(what)
    sys.exit(0)

if tool in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
    target = ti.get("file_path") or ti.get("notebook_path") or ""
    if target and in_primary(target):
        refuse("editing %s" % resolve(target))
    sys.exit(0)

if tool != "Bash":
    sys.exit(0)
cmd = ti.get("command") or ""
flat = " ".join(cmd.split())   # newlines and runs of blanks become one space
# The primary checkout's path may contain spaces; fold every spelling of it
# into one token so the regexes below see a single word.
names_primary = primary in flat or "$CLAUDE_PROJECT_DIR" in flat
for spelling in ('"%s"' % primary, "'%s'" % primary, primary, "$CLAUDE_PROJECT_DIR", '"$CLAUDE_PROJECT_DIR"'):
    flat = flat.replace(spelling, "<PRIMARY>")

OPT = r"(?:\s+-[-\w=]+(?:\s+(?:\"[^\"]*\"|'[^']*'|\S+))?)*"
GIT_MUTATE = re.compile(r"(?:^|[;&|(]\s*|\s)git" + OPT + r"\s+(?:commit|merge|rebase|cherry-pick|revert|reset|am|apply|stash\s+(?:pop|apply))\b")
# git aimed at the primary checkout from anywhere.
if names_primary and GIT_MUTATE.search(flat):
    refuse("running `%s` (git write aimed at the primary checkout)" % flat[:160])

# Pushes to a protected branch are refused from ANY session and in ANY
# spelling: `git push origin phase-2`, `HEAD:phase-2`, `HEAD:refs/heads/phase-2`,
# `+feat:phase-2`, a delete (`:phase-2`), or a bare `git push` while the
# current branch is protected. Plain --force / -f is refused everywhere;
# --force-with-lease on a task branch is the contract's allowed form.
protected = set(os.environ.get("GATE_PROTECTED", "main master").split())
current_branch = os.environ.get("GATE_BRANCH", "")
PUSH = re.compile(r"(?:^|[;&|(]\s*|\s)git" + OPT + r"\s+push\b(?P<args>[^;&|]*)")
def dest_of(spec):
    spec = spec.lstrip("+")
    if ":" in spec:
        spec = spec.split(":", 1)[1]
    if spec.startswith("refs/heads/"):
        spec = spec[len("refs/heads/"):]
    return spec
for m in PUSH.finditer(flat):
    args = m.group("args").split()
    if any(a == "-f" or a == "--force" or a.startswith("--force=") for a in args):
        refuse("running `%s` (plain force push; use --force-with-lease on your own task branch)" % flat[:160])
    positional = [a for a in args if not a.startswith("-")]
    refspecs = positional[1:]            # positional[0] is the remote
    for spec in refspecs:
        if dest_of(spec) in protected:
            refuse("running `%s` (push to protected branch %s)" % (flat[:160], dest_of(spec)))
    if not refspecs and current_branch in protected:
        refuse("running `%s` (bare push while on protected branch %s)" % (flat[:160], current_branch))

if not session_in_primary_on_default:
    sys.exit(0)

if GIT_MUTATE.search(flat):
    refuse("running `%s`" % flat[:160])

SAFE_TARGET = re.compile(r"^(?:/dev/null|/tmp/|/private/tmp/|\.artifacts/|\$)")
def target_is_repo_path(tok):
    tok = tok.strip("'\"")
    if not tok or SAFE_TARGET.match(tok):
        return False
    return in_primary(tok)

# Redirects into repo paths: `> path`, `>> path`, `2> path`, `&> path`.
for m in re.finditer(r"(?:^|\s)[0-9]?&?>{1,2}\s*([^\s;&|]+)", flat):
    if target_is_repo_path(m.group(1)):
        refuse("running `%s` (redirect writes %s)" % (flat[:120], m.group(1)))

# In-place writers aimed at repo paths, checked per command segment. Which
# argument is the write target depends on the tool: cp and ln write their
# LAST argument, sed -i writes the files it is given (its script is not a
# path, so only arguments that exist as files count), the rest (mv, rm, tee,
# touch, patch, mkdir, ...) write or remove every path argument.
WRITERS = re.compile(r"^(?:sudo\s+)?(sed|tee|cp|mv|rm|touch|patch|ln|mkdir|rmdir|truncate|dd)\b")
for seg in re.split(r"\s*(?:\|\||&&|;|\|)\s*", flat):
    seg = seg.strip()
    m = WRITERS.match(seg)
    if not m:
        continue
    tool_name = m.group(1)
    words = seg.split()
    if tool_name == "sed" and not any(w == "-i" or w.startswith("-i") for w in words):
        continue   # sed without -i only reads
    args = [w for w in words[1:] if not w.startswith("-")]
    if tool_name in ("cp", "ln"):
        targets = args[-1:]          # mv also removes its source, so it stays in the "every path" group
    elif tool_name == "sed":
        targets = [a for a in args if os.path.exists(resolve(a.strip("'\"")))]
    else:
        targets = args
    if any(target_is_repo_path(t) for t in targets):
        refuse("running `%s` (%s writes into the repo)" % (seg[:120], tool_name))
sys.exit(0)
PY
    }
    reason="$(decide)"
    [ -n "$reason" ] || exit 0

    full="Refused: $reason on the primary checkout, branch $primary_branch. Work belongs in a worktree on a task branch (beat 1). Run the new-feature skill, then \`bash scripts/worktree-env.sh\` in the new worktree, and redo this in there. See AGENTS.md, \"Start here\"."
    # Exit 2 blocks the tool; stderr reaches the model, and the JSON on stdout
    # is the harness's structured form of the same decision.
    printf '[factory-gate] %s\n' "$full" >&2
    printf '%s' "$full" | python3 -c 'import json,sys
print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":sys.stdin.read()}}))' 2>/dev/null
    exit 2
    ;;
  *)
    echo "usage: factory-gate.sh session|pre-tool" >&2
    exit 2
    ;;
esac
