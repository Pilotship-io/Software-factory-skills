# AGENTS.md

Universal contract for any agent, human or AI, working in this repo. It applies
in every harness (Claude Code, Cursor, Codex CLI, anything else that reads
`AGENTS.md`) and with every model. Read it first.

<!-- factory-template-version: 1.2 (2026-09-25). Keep this line: factory-init.sh
     reads it to know whether this file needs a re-merge when the template
     changes. Keep "Start here", "The four beats", "Multi-agent rules" and
     "Pilotship house rules" intact so every repo behaves the same. Fill in "Repo-specific" at
     the bottom. Sync ritual: see the factory repo README. -->

## Start here, every session

Five steps, in order, before anything else. The harness hooks in
`scripts/factory-gate.sh` print this list at session start and refuse edits
and commits on the default branch in the primary checkout, so skipping step
3 is not possible by accident.

1. **Fresh machine or fresh clone.** Run the repo's doctor (`npm run doctor`
   or `bash scripts/doctor.sh`) and follow its fix commands until it passes.
2. **Fresh session.** You are reading the current contract now. A session
   that started before this file changed does not know it. Start a new
   session rather than carrying an old one over.
3. **Every task starts with the `new-feature` skill.** It creates a worktree
   and a branch off `origin/main`. Then run `bash scripts/worktree-env.sh`
   inside it (if the repo has it). Never build on `main`.
4. **Build, prove, ship.** Write the code, capture evidence, open the PR from
   the template, then `greploop` until the reviewer reports 5/5 with zero
   unresolved comments on the head commit.
5. **A human merges.** Never below 5/5, never with an open thread. Present
   the PR URL and stop.

The four beats below are the long form of steps 3 and 4.

## The four beats

Every task moves through the same four beats. Each is backed by a skill
installed under `.agents/skills/` (symlinked into `.claude/skills/`).

1. **Isolate — `new-feature`.** Every task starts in a fresh Git worktree
   branched from `origin/main`. Never build on `main`. Keep this repo's branch
   prefixes (`feat/`, `fix/`, `chore/`, `docs/`, `refactor/`) and add a short
   unique suffix, e.g. `feat/lead-notes-4f2a`. If the repo ships
   `scripts/worktree-env.sh`, run it once in the fresh worktree before
   anything else: it gives the worktree its own database and port.
2. **Build — `code-structure`.** Actions and boundaries orchestrate the
   "why/when"; a service layer owns the reusable "how", with explicit inputs
   and structured returns. This sits on top of the repo's own architecture
   rules below, it does not replace them.
3. **Prove — `evidence-driven-testing`.** Run the repo's checks, then capture
   runtime evidence. Capture the **before** state while reproducing the issue,
   prior to fixing it, and the **after** once the change works. Baseline
   evidence in Pilotship repos is screenshots plus measured numbers; annotated
   video is welcome but optional. A surface you cannot drive locally (a page
   behind a sign-in that has no local path) is marked **UNTESTED** with the
   reason and a named reviewer step, never described as verified; a server
   component still gets render-to-markup evidence for each of its states
   (pattern 5 in the factory's `PATTERNS.md`).
4. **Ship — `before-and-after`, then `greploop`.** Open the PR from
   `.github/PULL_REQUEST_TEMPLATE.md` with proof embedded: a Before | After
   table whenever the change has a visible surface, measured numbers or
   output pairs when it doesn't. Then run `greploop` (or `greploop-apps` when
   the PR exceeds the file-count limit) until the reviewer reports **5/5 with
   zero unresolved comments** on the **current head commit**. After every
   push, wait about a minute before requesting the next review, and confirm
   the summary's "last reviewed commit" is your head; a review of the
   previous commit does not count. Finish by presenting the PR URL. A human
   merges.

Before the Build beat, read the factory's `pilotship/PATTERNS.md` (in the
factory repo): six house patterns the review loop enforces, each of which
cost a round the first time.

Proof rules for Pilotship repos:

- Upload evidence through the repo adapter (`IMAGE_ADAPTER=repo`: an orphan
  `evidence` branch in the same repo, one folder per PR branch), never the
  default public host. Portal screenshots can show client names. Gists
  cannot hold images.
- Never capture real client or customer data. Use local seed data.
- Evidence lives in `.artifacts/<task-name>/` (gitignored) and is uploaded
  to the `evidence` branch by the repo adapter. It is never committed to a
  product branch: not to the PR, not to `main`.
- Carve-outs that need no Before | After: docs-only changes, dependency
  bumps, CI config. Say which carve-out applies in the PR's Proof section.

## Writing for humans

Run `unslop` over anything a person will read before you commit, post, or
send it: commit messages, the PR title and body, README and doc edits, code
comments, the closing reply. Apply it to text you wrote or changed, not to
prose you didn't touch.

## Multi-agent rules

- Never commit directly to `main`.
- One worktree and one branch per task and per agent. Never reuse or modify
  another agent's worktree, branch, or uncommitted work.
- **Scope check** before starting: skim open PRs' changed files
  (`gh pr list`, `gh pr diff <n> --name-only`) and look for uncommitted work
  in shared checkouts. On overlap, stop and ask for direction.
- Never force-push to `main`, and never plain `--force` anywhere; only
  `--force-with-lease`, only on your own task branch.
- Resolve lockfile conflicts by regenerating, never by hand-merging.
- If a conflict can't be resolved confidently, stop and report instead of
  guessing.

### Shared local resources: databases and ports

Worktrees isolate files. They do **not** isolate the local database server,
dev-server ports, or Docker containers. These rules keep parallel agents from
wiping each other's data.

- **One database per worktree.** A worktree's database is named
  `<db-prefix>_<branch-slug>` and is created by `scripts/worktree-env.sh`.
  The slug is a readable prefix of the branch plus 8 hex characters of a
  hash of the full branch name (`scripts/worktree-id.sh`), so two branches
  can never share a database.
  Never point a worktree at the primary checkout's database.
- **One port per worktree.** The port is derived from the branch name
  (`PORT_BASE + hash(slug) % PORT_RANGE`) and written to the worktree's env
  file. Before trusting a URL, confirm the process on that port is yours:
  `lsof -i :<port>`.
- **Schema changes go through migrations only:** `db:generate` → committed
  migration file → `db:migrate` against **your worktree database**. Never
  `db:push`, never ad-hoc DDL typed at a database, never run schema
  experiments against a database you did not create for this worktree.
  Statements the generator cannot emit (row-level security policies,
  grants) are hand-appended to the *generated* migration file with a
  comment; say so here if that is your repo's practice, because the
  reviewer enforces these words literally.
- **Never stop, recreate, or wipe the shared database container or its
  volume** (`db:down`, `docker compose down`, `docker volume rm`). Other
  agents are using it.
- `scripts/db-guard.sh` runs before every migrate, seed, and reset and refuses
  when the database in `DATABASE_URL` does not match the current worktree.
  Do not bypass it.
- Cleanup after merge removes the worktree database too:
  `scripts/worktree-env.sh --drop`.

## Pilotship house rules

- **Branch every PR off `main`. Do not stack PRs.** A stacked PR merges into
  its base branch, not `main`; unless you merge strictly bottom-up and wait
  for GitHub to retarget each child, the upper PRs silently land in the wrong
  place. Split bigger work into independent PRs off `main`. If a hard
  dependency truly forces stacking, set the PR base to `main` from the start
  and rebase onto it.
- **Humans merge.** Agents never merge a PR. End by presenting the PR URL.
- Conventional commit messages: `feat(scope): summary`, `fix(scope): summary`.
  Squash merge. Aim under 400 changed lines per PR.
- Never commit `.env*` (except `.env.example`), API keys, service-account
  JSON, or large binaries.
- Don't add a dependency without saying why in the PR description.
- After any merge, verify `main` actually contains the PR's content.

## Completing a task

1. Keep changes limited to the assigned task.
2. Run the repo's checks (listed under **Commands and checks** below).
3. Assemble the evidence captured along the way into before/after pairs.
4. Commit with a clear message, rebase onto the latest `origin/main`, rerun
   the checks.
5. Push (`git push -u origin <branch>`; after rebasing an already-pushed
   branch, `--force-with-lease`).
6. Open the PR from the template. Every claim in the test plan is backed by
   evidence. Run the title and body through `unslop` before posting.
7. Run `greploop` (or `greploop-apps`) until **5/5 with zero unresolved
   comments**.
8. End by presenting the PR URL. Do not merge. Keep the worktree until the PR
   is merged or closed, then clean up (worktree, branch, worktree database).

<!-- ===================== REPO-SPECIFIC BELOW THIS LINE ===================== -->

## Repo-specific

### Project at a glance

_(what this repo is, stack, the two or three docs to read next)_

### Setup

```bash
# runtime version, install, env file, local services, first run
```

### Commands and checks

```bash
# dev server (must honor $PORT), tests, typecheck, lint, build
# the exact "before pushing" gate, e.g. `npm run check:all && npm run build`
```

### Hard invariants

_(security and architecture rules that must never be broken; link ADRs)_

### Environment quick reference

_(env vars, where secrets live, staging/prod URLs, deploy flow)_

### Shared local resources

| Resource | Value |
|---|---|
| Database container | _(e.g. `pilotship-postgres-dev`)_ |
| Primary database (main checkout only) | _(e.g. `pilotship_dev`)_ |
| Worktree database pattern | _(e.g. `pilotship_dev_<slug>`)_ |
| Port base / range | _(e.g. `3100` / `800`)_ |
| Dev server command | _(e.g. `npm run dev`, honors `$PORT`)_ |

### What can't be tested locally

_(third-party webhooks, prod-only integrations, and how to prove those instead)_
