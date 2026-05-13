#!/usr/bin/env bash
# Tests for Scripts/upstream-sync.sh.
#
# Each test creates a temporary directory with a synthetic "upstream" bare repo
# and a "fork" working clone whose `linux` branch tracks `origin/linux`. The
# script under test is run inside the fork clone and inspected via its stdout
# and exit code.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/upstream-sync.sh"

PASS=0
FAIL=0
FAILED_NAMES=()

note() { printf '%s\n' "$*"; }

# new_fixture <name>
#   Creates a temp dir containing:
#     - upstream.git: bare repo with one commit on `main`
#     - origin.git:   bare repo with one commit on `linux` (same as upstream)
#     - fork/:        non-bare clone of origin.git checked out on `linux`,
#                     with `upstream` remote pointing at upstream.git
#   Prints the temp dir path on stdout. Caller cd's into "$dir/fork".
new_fixture() {
    local name="$1"
    local dir
    dir="$(mktemp -d -t "upstream-sync-${name}.XXXXXX")"

    git init --bare -q "$dir/upstream.git"
    git init --bare -q "$dir/origin.git"

    git -c init.defaultBranch=main init -q "$dir/seed"
    (
        cd "$dir/seed"
        git config user.email test@example.com
        git config user.name test
        printf 'a\n' >file.txt
        git add file.txt
        git commit -q -m "initial commit"
        git remote add upstream "$dir/upstream.git"
        git remote add origin "$dir/origin.git"
        git branch -M main
        git push -q upstream main
        # seed origin's linux at the same commit as upstream main
        git branch linux
        git push -q origin linux
    )

    git clone -q -b linux "$dir/origin.git" "$dir/fork"
    (
        cd "$dir/fork"
        git config user.email test@example.com
        git config user.name test
        git remote add upstream "$dir/upstream.git"
        git fetch -q upstream
    )

    printf '%s\n' "$dir"
}

add_upstream_commit() {
    local fixture="$1" content="$2" file="${3:-file.txt}"
    git -C "$fixture/seed" fetch -q upstream main
    git -C "$fixture/seed" checkout -q upstream/main -B main
    printf '%s\n' "$content" >>"$fixture/seed/$file"
    git -C "$fixture/seed" add "$file"
    git -C "$fixture/seed" commit -q -m "upstream: $content"
    git -C "$fixture/seed" push -q upstream main
}

add_linux_commit() {
    local fixture="$1" content="$2" file="${3:-file.txt}"
    (
        cd "$fixture/fork"
        printf '%s\n' "$content" >>"$file"
        git add "$file"
        git commit -q -m "linux: $content"
    )
}

run_test() {
    local name="$1" expected_result="$2"
    shift 2

    local dir
    dir="$(new_fixture "$name")"
    # Test-specific setup runs in the fork clone.
    (
        cd "$dir/fork"
        "$@"
    )

    local output
    if ! output="$(cd "$dir/fork" && "$SCRIPT" 2>&1)"; then
        FAIL=$((FAIL + 1))
        FAILED_NAMES+=("$name (script exited non-zero)")
        printf 'FAIL %s\n%s\n' "$name" "$output"
        rm -rf "$dir"
        return
    fi

    if ! grep -q "^result=${expected_result}$" <<<"$output"; then
        FAIL=$((FAIL + 1))
        FAILED_NAMES+=("$name (expected result=$expected_result, got: $output)")
        printf 'FAIL %s\nexpected result=%s\noutput:\n%s\n' "$name" "$expected_result" "$output"
        rm -rf "$dir"
        return
    fi

    # Working tree must be clean after the script runs — no leftover rebase
    # state and no uncommitted edits.
    if [ -d "$dir/fork/.git/rebase-merge" ] || [ -d "$dir/fork/.git/rebase-apply" ]; then
        FAIL=$((FAIL + 1))
        FAILED_NAMES+=("$name (rebase state left behind)")
        printf 'FAIL %s (rebase state left behind)\n' "$name"
        rm -rf "$dir"
        return
    fi
    if [ -n "$(git -C "$dir/fork" status --porcelain)" ]; then
        FAIL=$((FAIL + 1))
        FAILED_NAMES+=("$name (dirty working tree)")
        printf 'FAIL %s (dirty working tree)\n' "$name"
        rm -rf "$dir"
        return
    fi

    PASS=$((PASS + 1))
    note "PASS $name"
    rm -rf "$dir"
}

# --- cases ---

test_up_to_date() {
    : # no extra commits; linux already matches upstream/main
}

test_clean_rebase() {
    local dir; dir="$PWD/.."  # caller is fork/, fixture root is one up
    add_upstream_commit "$dir" "upstream-new-1"
}

test_clean_rebase_with_local_commit() {
    local dir; dir="$PWD/.."
    add_upstream_commit "$dir" "upstream-new-2" newfile-upstream.txt
    add_linux_commit "$dir" "linux-new-1" newfile-linux.txt
}

test_conflict() {
    local dir; dir="$PWD/.."
    add_upstream_commit "$dir" "upstream-edit"
    add_linux_commit "$dir" "linux-edit"
}

# --- runner ---

if [ ! -x "$SCRIPT" ]; then
    printf 'SCRIPT NOT FOUND OR NOT EXECUTABLE: %s\n' "$SCRIPT" >&2
    exit 2
fi

run_test up-to-date              up-to-date test_up_to_date
run_test clean-rebase            clean      test_clean_rebase
run_test clean-rebase-local      clean      test_clean_rebase_with_local_commit
run_test conflict                conflict   test_conflict

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
    printf 'failures:\n'
    for n in "${FAILED_NAMES[@]}"; do printf '  - %s\n' "$n"; done
    exit 1
fi
