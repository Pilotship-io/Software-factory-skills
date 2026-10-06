# CLAUDE.md

<!-- factory-template-version: 1.1 -->

Claude Code specific notes. **The universal contract is [`AGENTS.md`](./AGENTS.md).**
Read that first; everything in it applies here. This file only covers what
differs in Claude Code.

## Skills

Factory skills live in `.agents/skills/` and are symlinked into
`.claude/skills/`, so Claude Code loads them on demand like any project skill:
`new-feature`, `code-structure`, `evidence-driven-testing`, `before-and-after`,
`greploop`, `greploop-apps`, `unslop`. Repo-specific skills sit alongside them.

## Worktrees

Claude Code creates and manages worktrees itself under `.claude/worktrees/`.
Per the `new-feature` skill, skip the manual `git worktree add` steps and keep
the harness-assigned branch name. Still run `scripts/worktree-env.sh` (if the
repo has it) as the first command in a fresh worktree.

## Permissions

`.claude/settings.json` denies pushes to `main` (in every refspec spelling;
`scripts/factory-gate.sh` refuses the same by destination from any session),
force pushes, and destructive SQL, and asks before anything that stops or wipes the shared database
container (`db:down`, `docker compose down`, `db:push`). These mirror the
rules in AGENTS.md; the script guards in `scripts/` enforce the same rules in
every other harness.

## Hooks: the factory gate

Two hooks in `.claude/settings.json` run `scripts/factory-gate.sh`
(`templates/claude-settings.hooks.json` is the block to merge in):

- **SessionStart** prints the "Start here, every session" checklist from
  AGENTS.md plus the current isolation status, so a session that opened on a
  stale checkout still sees the contract.
- **PreToolUse** on Edit, Write, MultiEdit, NotebookEdit and Bash refuses
  writes to the primary checkout while it sits on the default branch. File
  edits whose target resolves inside the primary checkout are refused from
  any session, including one inside a worktree; targets under a worktree
  directory or outside the repo pass. Bash commands are checked when the
  session's cwd is the primary checkout on the default branch: mutating git
  subcommands (commit, merge, rebase, cherry-pick, revert, reset, am, apply,
  stash pop or apply) anywhere in the command, redirects into repo paths, and
  in-place writers (`sed -i`, `tee`, `cp`, `mv`, `rm`, `touch`, `patch`, `ln`,
  `mkdir`) aimed at repo paths. Git commands that name the primary checkout
  are refused from any session. Redirects to `/dev/null`, `/tmp` or
  `.artifacts/` pass. The Bash check is a tripwire for the common forms, not
  a sandbox; the Edit/Write hook and the permission rules above are the
  guards. Every refusal names the fix: start the `new-feature` skill and redo
  the change in the worktree.

Hooks run with the project root as their working directory even inside a
worktree, so the script reads the session's real location from the `cwd`
field the harness passes on stdin. A human doing emergency work by hand can
set `FACTORY_GATE=off` for that shell. Agents must never set it.

## Plan mode

For any non-trivial change (new feature, refactor, anything touching a
kernel or shared module), plan first, get approval, then build. Trivial fixes
can proceed directly.

## What NOT to do (Claude-specific additions)

- Don't merge PRs. Hand the URL to a human.
- Don't run cloud IAM, secret, or database-instance mutations without explicit
  approval. Read-only operations are fine.
