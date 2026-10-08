# Onboarding: the Pilotship software factory

A software factory is not a product. It is a handful of markdown files that
make every task, in every repo, in every harness, move through the same four
beats: **isolate → build → prove → ship**. The model and the harness are
interchangeable. The workflow is not.

This doc gets a developer from zero to their first factory PR in about an
hour.

## 0. Which machines

- **macOS** and **Linux**: everything runs natively.
- **Windows**: run the factory inside **WSL2** (Ubuntu). The scripts are Bash
  plus Unix tools, and WSL2 is Linux, so nothing needs translating. Do the
  whole setup below *inside* the distro: Node, git, `gh`, the repo clone,
  and Docker Desktop with **WSL integration** switched on for that distro.
  Claude Code, Cursor and Codex all run there. A native Windows shell (Git
  Bash, PowerShell, cmd) is not supported: npm runs scripts through cmd.exe,
  the Claude skill links are git symlinks, and `lsof` does not exist; the
  doctor refuses it and points here.

  ```powershell
  wsl --install                # once, then reboot; opens Ubuntu
  ```

## 1. One-time machine setup (15 minutes)

```bash
# GitHub CLI, authenticated with the account you open PRs from
brew install gh && gh auth login

# screenshot tooling for the Prove beat
npm i -g @vercel/before-and-after agent-browser

# optional: annotated video evidence (needs Screen Recording permission for your terminal)
brew install ffmpeg
```

Node: use the version the repo pins (check `.nvmrc`, `engines`, or CI). Most
Pilotship repos pin Node 22.

All of this is per machine, not per repo: the two npm packages are global
installs that no repo carries, so a second laptop (or a WSL2 distro) needs
them again. Skip the screenshot line and every UI change you ship gets
marked UNTESTED, because the Prove beat has nothing to capture with.

Then, in any factory-enabled repo, run the doctor. It checks all of the above
plus Docker, the database container, the env file and the skills, and prints
the exact command for each miss. The worktree script runs the same checks
before it touches anything, so a fresh machine stops with a checklist instead
of a stack trace.

```bash
npm run doctor
```

Review bot access: ask Seth to add you to the Greptile org (see
`REVIEW_BOTS.md`). One seat per developer, all repos.

## 2. What is in a factory-enabled repo

| Path | Purpose |
|---|---|
| `AGENTS.md` | The contract. Four beats, multi-agent rules, house rules, repo-specific section. Every harness reads it. |
| `CLAUDE.md` | Thin Claude Code pointer to AGENTS.md. Cursor and Codex need nothing extra. |
| `.agents/skills/*` | The seven factory skills (canonical copies). `.claude/skills/*` are symlinks to them. |
| `skills-lock.json` | Pins skill versions. `npx skills update` bumps them. |
| `.github/PULL_REQUEST_TEMPLATE.md` | PR body with a mandatory Proof section. |
| `scripts/doctor.sh` | `npm run doctor`: is this machine ready? Every miss comes with its fix command. |
| `scripts/factory-gate.sh` + `.claude/settings.json` hooks | The session gate. Prints the five "Start here" steps when a Claude Code session opens and refuses edits or commits on `main` in the primary checkout. |
| `scripts/worktree-env.sh` | Gives a worktree its own database and port. Run first in every new worktree (it runs the doctor first). |
| `scripts/db-guard.sh` | Refuses migrate/seed/reset against the wrong database. |
| `.artifacts/` | Evidence captured while proving. Gitignored, uploaded, never committed. |

Before your first Build beat, read `PATTERNS.md` in this folder: six house
patterns the review loop enforces. Each cost a round the first time.

## 3. Your first task, beat by beat

Tell your agent what to build. The rest is what should happen; if a beat
gets skipped, say "use the factory" and it will pick the skills up. In Claude
Code the gate makes the first beat hard to skip: a session opened on `main`
sees the five steps and cannot write to the primary checkout. Open a fresh
session after the contract changes; an old session does not know it.

**Isolate.** The agent creates a worktree and branch off `origin/main`
(`feat/<name>-<suffix>`), then runs `scripts/worktree-env.sh`. That script
writes `.env.local` with a database named after the branch and a port
derived from it, creates the database, migrates, and seeds. Nothing it does
can touch another worktree's data.

- Claude Code: worktrees live under `.claude/worktrees/`, created by the harness.
- Cursor: uses its own worktree mode; keep the assigned branch.
- Codex CLI: follows the manual `git worktree add` steps in the `new-feature` skill.

**Build.** The agent writes code against `AGENTS.md`: the repo's own
architecture rules plus the `code-structure` skill's service-layer shape.
Before pushing it runs the repo's check gate (for example
`npm run check:all && npm run build`).

**Prove.** For a UI change: a before screenshot captured *before* the fix and
an after screenshot once it works, turned into a table with
`before-and-after before.png after.png --markdown` and uploaded through the
repo adapter (an orphan `evidence` branch in the same repo; gists reject
binaries, the public host is forbidden). Pages with a query string in the
URL: capture with `agent-browser open <url>` + `agent-browser screenshot`,
the CLI rejects them. For anything else: measured numbers or output pairs. Evidence
always names the commit it was captured on.

**Ship.** The agent opens the PR from the template with the proof embedded,
then runs `greploop`: request a review, fix every actionable comment, resolve
threads, push, repeat until the reviewer reports 5/5 with nothing open. It
ends by handing you the PR URL. **You merge.** Agents never do.

After the merge: `bash scripts/worktree-env.sh --drop`, then remove the
worktree and branch.

## 4. Reviewing a factory PR as a human

You are checking three things, in this order:

1. Does the Proof section show the change working, on the commit under review?
2. Did the review loop end at 5/5 with zero open comments, and do the fixes look sane?
3. Does the diff stay inside the task's scope?

If you find yourself reading every line, the Proof section was not good
enough. Ask for better evidence rather than doing the agent's job.

## 5. Rules that will save you a bad afternoon

- Never run `db:down`, `docker compose down`, or `db:push` from a worktree.
  The database container is shared.
- Never upload screenshots to the default public host. Gist adapter only.
- Never stack PRs. Independent branches off `main`, every time.
- Never merge from an agent session. Hand the URL over.
- When two agents want the same files, stop and pick one.

## 6. Keeping the factory current

Skills and templates live in
[Pilotship-io/Software-factory-skills](https://github.com/Pilotship-io/Software-factory-skills).
In a project repo, `npx skills update` pulls the latest skills. Template
changes (AGENTS, PR template, scripts) are re-applied by running
`factory-init.sh` again; it never overwrites, it writes `*.factory.*` files
next to yours for you to merge.

Found a problem or a better way? Log it in `PILOT_LOG.md` and open a PR on
the factory repo. Through the factory, naturally.
