# Pilotship Software Factory

The repeatable, model- and harness-agnostic way we ship software at
[Pilotship](https://pilotship.io). Every task in every repo moves through four
beats, **isolate → build → prove → ship**, each backed by a markdown skill in
this repo. It works the same in Claude Code, Cursor, and Codex CLI, with any
model.

**v1.0** (2026-09-22): piloted on pilotship-web over three real features and
ten review rounds; see [`pilotship/PILOT_LOG.md`](pilotship/PILOT_LOG.md).

Forked from [michaelshimeles/skills](https://github.com/michaelshimeles/skills)
(the skills from the "software factory" walkthrough). Upstream skills stay
vendored and unmodified under their own folders; everything Pilotship-specific
lives under [`pilotship/`](pilotship/).

## Start here

| If you are... | Read |
|---|---|
| A developer joining a factory-enabled repo | [`pilotship/ONBOARDING.md`](pilotship/ONBOARDING.md), then [`pilotship/PATTERNS.md`](pilotship/PATTERNS.md) |
| About to build something | [`pilotship/PATTERNS.md`](pilotship/PATTERNS.md): six house patterns the review loop enforces |
| Rolling the factory out to a repo | [`pilotship/ROLLOUT_CHECKLIST.md`](pilotship/ROLLOUT_CHECKLIST.md), then run `pilotship/factory-init.sh` |
| Wondering why Greptile, and how to swap it | [`pilotship/REVIEW_BOTS.md`](pilotship/REVIEW_BOTS.md) |
| Logging what broke during the pilot | [`pilotship/PILOT_LOG.md`](pilotship/PILOT_LOG.md) |
| Seeing what merged here and whether it went through the factory | [`pilotship/MERGE_LOG.md`](pilotship/MERGE_LOG.md), written by the **Merge log** workflow (one Actions run per merge; red when a PR skipped the factory) |

### Set up a machine (once per laptop, not per repo)

```bash
brew install gh && gh auth login                    # PRs, review loop (apt/dnf on Linux and WSL2)
npm i -g @vercel/before-and-after agent-browser     # before/after screenshots for the Prove beat
```

These are global installs. The factory files you commit to a repo do not
carry them, so every developer and every new machine does this once. Without
the second line, UI changes ship marked UNTESTED because no screenshot can
be captured. Windows: run all of this inside WSL2 (see
[`pilotship/ONBOARDING.md`](pilotship/ONBOARDING.md), section 0).

### Install into a repo

```bash
git clone https://github.com/sema-solutions/Software-factory-skills.git ~/Software-factory-skills
cd <your-repo> && git checkout -b chore/software-factory
bash ~/Software-factory-skills/pilotship/factory-init.sh
```

The script installs the seven skills into `.agents/skills/` (canonical, read
by Cursor and Codex) with symlinks into `.claude/skills/` (Claude Code), pins
them in `skills-lock.json`, appends the factory block to `.gitignore`, and
drops in the `AGENTS.md`, `CLAUDE.md`, PR template, and the two database
isolation scripts. It never overwrites an existing file: where one exists it
writes a `*.factory.*` copy beside it for you to merge. Run it again any time
to pick up template changes. `npx skills update` refreshes the skills alone.

### First session of an agent in a factory repo

Whatever the harness, the agent's first move in a repo it has not seen is
the doctor:

```bash
npm run doctor        # or: bash scripts/doctor.sh
```

It checks Node, git, `gh` and its login, Docker and the database container,
the env file, the skills, and the screenshot tooling above, and prints the
exact fix command next to every miss. `AGENTS.md` step 1 tells the agent to
run it and follow the fix lines until it passes, and `scripts/worktree-env.sh`
runs it again before creating a worktree, so a missing tool stops the session
with a checklist rather than a half-built task. Steps 2 to 5 of the contract
(fresh session, worktree via `new-feature`, build/prove/ship, human merges)
follow from there.

### What `pilotship/` contains

| Path | What it is |
|---|---|
| `AGENTS.template.md` | The contract: start-here steps, four beats, multi-agent rules, shared-resource (database/port) rules, Pilotship house rules, a repo-specific section to fill |
| `CLAUDE.template.md` | Thin Claude Code pointer to AGENTS.md |
| `factory-init.sh` | Idempotent installer described above |
| `scripts/check-contract.sh` | Diffs a repo's `AGENTS.md` shared sections against the template; run before any PR that touches the contract |
| `templates/PULL_REQUEST_TEMPLATE.md` | PR body with a mandatory Proof section |
| `templates/gitignore.factory` | Worktree and evidence paths to ignore |
| `templates/scripts/doctor.sh` | `npm run doctor`: machine readiness with a fix command per miss; the worktree script runs it first |
| `templates/scripts/factory-gate.sh`, `templates/claude-settings.hooks.json` | The session gate: Claude Code hooks that print the five "Start here" steps at session start and refuse writes to the primary checkout on `main` |
| `templates/scripts/worktree-env.sh` | Gives each worktree its own database and port |
| `templates/scripts/db-guard.sh` | Refuses migrate/seed/reset against the wrong database |
| `../before-and-after/scripts/adapters/repo.sh` | Evidence upload adapter: pushes screenshots to an orphan `evidence` branch of the repo under review (Contents API, working tree untouched); the default `IMAGE_ADAPTER` |
| `templates/github/pr-agent.yml` | Optional open-source reviewer workflow (PR-Agent) |
| `ONBOARDING.md`, `ROLLOUT_CHECKLIST.md`, `REVIEW_BOTS.md`, `PILOT_LOG.md` | Team docs |

### Keeping up with upstream

```bash
git remote add upstream https://github.com/michaelshimeles/skills.git   # once
git fetch upstream && git checkout main && git merge upstream/main
```

Upstream folders (`new-feature/`, `code-structure/`, `evidence-driven-testing/`,
`before-and-after/`, `greploop/`, `greploop-apps/`, `unslop/`, `AGENTS.md`,
`tests/`) are left as upstream ships them so merges stay clean, with one
deliberate exception: `before-and-after/scripts/upload-and-copy.sh` defaults
`IMAGE_ADAPTER` to `repo` (a new adapter, `adapters/repo.sh`, that hosts
images on an orphan `evidence` branch of the repo itself) instead of the
public 0x0.st host, `before-and-after/scripts/adapters/gist.sh` creates secret
gists instead of public ones (text only: gists reject binaries), `greploop/SKILL.md` and `greploop-apps/SKILL.md` wait 60 s (not 5) after a
push before requesting a review and check the last-reviewed commit, and
`before-and-after/SKILL.md` names the installed uploader path
(`.agents/skills/before-and-after/scripts/...`) and the repo adapter wherever
upstream names its `--markdown` upload to 0x0.st. Re-check all of these after
every upstream merge. If a skill
needs Pilotship behavior, add a variant under `pilotship/skills/<name>/` rather
than editing the vendored one.

---

# Upstream skills reference

The rest of this file is upstream's README, kept for reference.

## Available skills

### [before-and-after](before-and-after/SKILL.md)

Captures before/after screenshots of web pages or elements and outputs a PR-ready markdown comparison table. It drives the `@vercel/before-and-after` CLI.

Use it when:

- A PR needs visual proof that a UI change does what it claims
- You want a `| Before | After |` table generated and uploaded in one step
- Comparing two URLs, two existing images, or a mix of both

> Vendored from [vercel-labs/before-and-after](https://github.com/vercel-labs/before-and-after) (PolyForm Shield 1.0.0, license included in the folder). Install the CLI with `npm i -g @vercel/before-and-after agent-browser`.

### [code-structure](code-structure/SKILL.md)

Service layer architecture guidance. Enforces a two-layer separation where **actions** orchestrate domain rules (the "why/when") and a **service layer** centralizes reusable operational mechanics (the "how").

Use it when:

- Multiple workflows duplicate the same operational logic
- You're deciding what belongs in actions vs. shared services
- A bug fix in one flow doesn't propagate to others doing the same thing
- Adding a feature that shares mechanics with existing ones

Includes a migration checklist for extracting shared logic safely and a table of anti-patterns to avoid (god services, leaky services, over-abstraction).

### [evidence-driven-testing](evidence-driven-testing/SKILL.md)

Records visual proof while testing UI behavior. The agent drives the app live via computer use (or [cua-driver](https://github.com/trycua/cua) when the harness has no computer-use tools) while the bundled recorder captures the session, then posts the video and a results summary to the PR and tracker issue. The recorder (`scripts/evidence.py`, Python 3 + FFmpeg) runs on Linux, macOS, and Windows and has `doctor`, `start`, `annotate`, and `stop` commands. It timestamps each annotation as the agent tests, burns them into `evidence.mp4` on stop, and summarizes them in a generated `report.md` and `manifest.json`. Headless environments swap the recorder for scripted screenshots and Playwright captures; non-UI changes still get evidence (measured numbers, output pairs, transcript excerpts).

Use it whenever a change needs verifiable evidence that it works, instead of prose claims.

> The recorder needs `ffmpeg`/`ffprobe` built with `libx264` and the `ass` filter, plus a screen-capture source: X11 (`DISPLAY`) or wlroots Wayland (`wf-recorder`; GNOME/KDE are not supported) on Linux, Screen Recording permission on macOS, any standard ffmpeg on Windows. `python3 scripts/evidence.py doctor` reports both. The raw capture is MPEG-TS, so a crashed or hard-killed recorder still yields usable evidence. The headless path needs only a running app and a scriptable browser (Playwright via npx). Posting evidence requires the `gh` CLI (or equivalent). `tests/test_evidence.py` smoke-tests the recorder end to end with a synthetic video source (`python3 -m pytest tests/ -q`).

### [greploop](greploop/SKILL.md)

Iteratively fixes a PR (GitHub), MR (GitLab), or shelved changelist (Perforce) until Greptile gives a perfect review: 5/5 confidence with zero unresolved comments. Triggers the review, fixes actionable comments, resolves threads, pushes, and repeats, up to `--max-iterations` cycles (default 10).

Use it to get a PR to a clean Greptile review before merge.

> Vendored from [greptileai/skills](https://github.com/greptileai/skills) (MIT, license included in the folder). Requires Greptile installed on the repo and an authenticated `gh`/`glab`/`p4` CLI.

### [greploop-apps](greploop-apps/SKILL.md)

The same loop as greploop, but it triggers reviews by tagging `@greptile-apps`, which bypasses Greptile's file-count limit on huge PRs that the plain `@greptile` mention refuses to review. When no check run appears, it falls back to polling Greptile's edited summary comment.

Use it when greploop's trigger gets "Too many files changed for review".

> Local variant derived from greptileai's greploop (MIT, license included in the folder); no separate upstream.

### [new-feature](new-feature/SKILL.md)

Starts every new task in an isolated Git worktree branched from `origin/main` so multiple agents can work on the same repo in parallel without conflicts. It covers unique task naming, a scope check against open PRs, fresh dependency installs, and cleanup after merge.

Use it when:

- Starting any new feature, fix, or task, before writing code
- Multiple agents (or sessions) work the same repository concurrently
- You need a consistent branch-per-task convention with safe cleanup

Includes harness deltas for Claude Code and Cursor, which manage worktrees themselves.

### [unslop](unslop/SKILL.md)

Edits prose to remove AI tells and put a human voice back in. It names 31 patterns to catch (puffery, filler, hedging, chatbot phrases, em dashes, colons as connectors, bold and emoji overuse, abstract metaphor nouns, passive voice) and a short checklist for adding opinion and rhythm, applied as a four-step loop: scan, rewrite, add soul, self-audit.

Use it when:

- Writing anything a person will read: commit messages, PR titles and bodies, docs, README edits, code comments, chat replies
- Cleaning up existing text that reads machine-made

> Vendored from [cursor/plugins (pstack)](https://github.com/cursor/plugins/tree/main/pstack/skills/unslop) (MIT, license included in the folder). The body matches upstream; the frontmatter has two edits so agents apply the skill on their own instead of waiting for a typed `/unslop`. We dropped the `disable-model-invocation: true` line, and the description now names the trigger (text you write or edit for a human reader) in place of upstream's "any writing. Must always apply.", so auto-invocation matches the scope `AGENTS.md` gives it. Restore the flag if you want slash-command-only behavior.

## Workflow

[`AGENTS.md`](AGENTS.md) ties the skills together into a four-beat workflow: isolate (`new-feature`) → build (`code-structure`) → prove (`evidence-driven-testing`) → ship (`before-and-after` + `greploop`), with `unslop` applied to everything written for humans along the way. Drop it into a repo alongside the skills and fill in the repo-specific callouts (checks, invariants, environment).

## Installation

Use `npx skills` to install skills to most coding agents:

```bash
npx skills add sema-solutions/Software-factory-skills
```

Claude Code picks up the skill automatically and invokes it when a task matches the skill's description. You can also invoke one explicitly with `/code-structure` or `/evidence-driven-testing`.

## Adding a new skill

1. Create a folder named after the skill (kebab-case).
2. Add a `SKILL.md` with `name` and `description` frontmatter. The description is what Claude uses to decide when the skill applies, so make it trigger-focused ("Use when...").
3. Keep instructions concise and actionable; link out to reference files in the folder if they get long.
