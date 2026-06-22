#!/usr/bin/env bash
#
# Update Beszel to the latest upstream while keeping macOS temperature support.
#
# Run this INSTEAD of `beszel-agent update`: it fetches upstream, rebases this
# feature branch onto the latest upstream/main, rebuilds & reinstalls the
# patched agent (via setup.sh), and pushes the branch — so you get the new
# version AND keep temperatures in a single step.
#
# Requirements: clean working tree, on the feature branch, with an `upstream`
# remote pointing at henrygd/beszel.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
err() { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

# --- preconditions -----------------------------------------------------------
git remote get-url upstream >/dev/null 2>&1 || \
  err "No 'upstream' remote. Add it:
    git remote add upstream https://github.com/henrygd/beszel.git"

[ -z "$(git status --porcelain)" ] || \
  err "Working tree is not clean. Commit or stash your changes first."

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" != "HEAD" ] || err "Detached HEAD — check out your feature branch first."
[ "$BRANCH" != "main" ]  || err "You are on 'main' — check out your feature branch (e.g. feat/macos-smctemp-temperatures)."

OLDVER="$(git describe --tags --abbrev=0 2>/dev/null || echo '?')"

# --- sync + rebase -----------------------------------------------------------
log "Fetching upstream..."
git fetch --tags upstream

log "Rebasing '$BRANCH' onto upstream/main..."
if ! git rebase upstream/main; then
  git rebase --abort
  err "Rebase hit conflicts (most likely agent/sensors_default.go). Resolve manually:
    git rebase upstream/main      # edit conflicts, then: git add <file> && git rebase --continue
  then re-run this script."
fi

# keep the fork's main fast-forwarded to upstream (tidy diff for a future PR)
log "Syncing fork 'main' with upstream/main..."
git branch -f main upstream/main
git push origin main 2>/dev/null || log "(could not fast-forward 'main' on origin — skipping)"

# --- rebuild, reinstall, push ------------------------------------------------
log "Rebuilding & reinstalling the patched agent..."
"$SCRIPT_DIR/setup.sh"

log "Pushing '$BRANCH' to origin..."
git push --force-with-lease origin "$BRANCH"

NEWVER="$(git describe --tags --abbrev=0 2>/dev/null || echo '?')"
log "Done. Beszel is now on upstream ${NEWVER} (was ${OLDVER}) with macOS temperature support."
