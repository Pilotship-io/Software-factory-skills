#!/bin/bash
# Repo evidence-branch adapter - host images on an orphan branch of the
# current repository, so a private repo's PR can render them and nothing
# leaves the org.
#
# Usage: ./repo.sh <file>
# Output: URL the PR body can embed (stdout)
#
# Why not gist: gists reject binary files ("binary file not supported"), so
# the gist adapter can only ever hold text. Why not the public host: portal
# screenshots can show client data.
#
# Environment:
#   EVIDENCE_REPO    owner/name (default: the repo of the current checkout)
#   EVIDENCE_BRANCH  branch that holds evidence (default: evidence)
#   EVIDENCE_PREFIX  folder inside the branch (default: current git branch, sanitized)
#
# Requirements: gh CLI authenticated with push rights; python3 (base64 + JSON).
# The branch is created as an orphan on first use through the Git Data API;
# every upload is one Contents API call, so the working tree is never touched.
set -euo pipefail

FILE="${1:-}"
[[ -n "$FILE" ]] || { echo "Usage: $0 <file>" >&2; exit 1; }
[[ -f "$FILE" ]] || { echo "Error: File not found: $FILE" >&2; exit 1; }
command -v gh >/dev/null || { echo "Error: gh CLI not found" >&2; exit 1; }
command -v python3 >/dev/null || { echo "Error: python3 not found" >&2; exit 1; }

REPO="${EVIDENCE_REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
BRANCH="${EVIDENCE_BRANCH:-evidence}"
PREFIX="${EVIDENCE_PREFIX:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null | tr -c 'A-Za-z0-9._-\n' '-')}"
PREFIX="${PREFIX:-unsorted}"
NAME="$(basename "$FILE")"
DEST="$PREFIX/$NAME"
# Private temp file (mktemp: 0600), so another local user cannot read the
# screenshot body while it waits to upload.
TMP="$(mktemp "${TMPDIR:-/tmp}/evidence-put.XXXXXX")"
trap 'rm -f "$TMP"' EXIT

# 1. orphan branch on first use: blob -> tree -> parentless commit -> ref
if ! gh api "repos/$REPO/git/ref/heads/$BRANCH" >/dev/null 2>&1; then
  readme='# Evidence

Screenshots and captures referenced from pull requests. Written by the
before-and-after repo adapter, one folder per branch. Not part of the product.
'
  blob=$(printf '%s' "$readme" | gh api "repos/$REPO/git/blobs" -f encoding=utf-8 -F content=@- --jq .sha)
  tree=$(printf '{"tree":[{"path":"README.md","mode":"100644","type":"blob","sha":"%s"}]}' "$blob" \
    | gh api "repos/$REPO/git/trees" --input - --jq .sha)
  commit=$(printf '{"message":"evidence: start orphan branch","tree":"%s","parents":[]}' "$tree" \
    | gh api "repos/$REPO/git/commits" --input - --jq .sha)
  printf '{"ref":"refs/heads/%s","sha":"%s"}' "$BRANCH" "$commit" \
    | gh api "repos/$REPO/git/refs" --input - >/dev/null
  echo "Created orphan branch $BRANCH in $REPO" >&2
fi

# 2. create or update the file (an update must carry the current blob sha)
existing=$(gh api "repos/$REPO/contents/$DEST?ref=$BRANCH" --jq .sha 2>/dev/null || true)
python3 - "$FILE" "$DEST" "$BRANCH" "$existing" > "$TMP" <<'PY'
import base64, json, sys
f, dest, branch, sha = sys.argv[1:5]
body = {"message": f"evidence: {dest}", "branch": branch,
        "content": base64.b64encode(open(f, "rb").read()).decode()}
if sha:
    body["sha"] = sha
print(json.dumps(body))
PY
gh api -X PUT "repos/$REPO/contents/$DEST" --input "$TMP" >/dev/null

# github.com (not raw.githubusercontent.com) so a private repo's PR page can
# serve it to anyone who can see the PR.
echo "https://github.com/$REPO/blob/$BRANCH/$DEST?raw=true"
