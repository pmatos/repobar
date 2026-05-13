#!/usr/bin/env bash
# Rebase the current branch onto upstream/main.
#
# Contract:
#   - Run inside a working clone of pmatos/repobar with `upstream` configured
#     as a remote pointing at steipete/RepoBar.
#   - HEAD is the branch to rebase (typically `linux`).
#   - Side effects are local only: fetch upstream, attempt rebase. Pushing and
#     issue-creation are the caller's responsibility (the GitHub Actions
#     workflow).
#
# Output: a single `result=<value>` line on stdout, where <value> is one of:
#   up-to-date  HEAD already contains every upstream commit; no rebase done.
#   clean       Rebase succeeded; new commits applied on top of upstream/main.
#   conflict    Rebase produced conflicts; rebase aborted; tree clean.
#
# Exits 0 in all three normal cases. Non-zero only for environmental errors
# (missing `upstream` remote, fetch failure, unexpected git state).

set -euo pipefail

UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-upstream}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-main}"

if ! git remote get-url "$UPSTREAM_REMOTE" >/dev/null 2>&1; then
    printf 'upstream-sync: remote %q not configured\n' "$UPSTREAM_REMOTE" >&2
    exit 2
fi

git fetch --quiet "$UPSTREAM_REMOTE" "$UPSTREAM_BRANCH"

UPSTREAM_REF="${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}"
HEAD_SHA="$(git rev-parse HEAD)"
UPSTREAM_SHA="$(git rev-parse "$UPSTREAM_REF")"

# Already up to date: HEAD contains the upstream tip.
if git merge-base --is-ancestor "$UPSTREAM_SHA" "$HEAD_SHA"; then
    printf 'result=up-to-date\n'
    exit 0
fi

if git rebase --quiet "$UPSTREAM_REF"; then
    printf 'result=clean\n'
    exit 0
fi

# Rebase failed; leave the tree clean for the caller.
git rebase --abort
printf 'result=conflict\n'
exit 0
