#!/usr/bin/env bash
# test-guards — regression tests for the fix-prose hook scripts.
#
# The retrospective that produced this skill counted five guard blocks
# in one session and found four of them wrong. A guard that refuses
# legitimate work costs more than the shortcut it prevents, and nothing
# catches that drift once the script stops being new. These cases turn
# each behavior into something a later edit has to keep.
#
# Every case runs against a scratch git repository built here, never
# against the working tree. The checks compare file hashes and walk
# .vale/, so exercising them in place would mean mutating this
# repository's own linter configuration to see them fire, and a failed
# run would leave that mutation behind. A throwaway repository also
# gives the gitignored-style case somewhere honest to live.
#
# Out of `just lint` on purpose. It writes to a temporary directory,
# spawns git, and takes long enough to notice, so it belongs with the
# out-of-band recipes rather than in the gate every commit runs.
#
# Usage: test-guards.sh
set -uo pipefail

# --- environment hardening -------------------------------------------
# LC_ALL pins collation for the git calls below, and CDPATH is unset
# because it makes a relative path resolve somewhere else entirely.
export LC_ALL=C
unset CDPATH GREP_OPTIONS
IFS=$(printf ' \t\n')

root=$(git rev-parse --show-toplevel)
SCRIPTS="$root/.apm/skills/fix-prose/scripts"

pass=0
fail=0

check() {
  if [ "$1" = "$2" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL  %s\n      expected exit %s, got %s\n' "$3" "$2" "$1"
  fi
}

# payload builds a hook stdin document. jq keeps the quoting correct for
# a path containing anything a temporary directory might carry.
payload() {
  jq -nc --arg cwd "$1" --arg skill "$2" --arg args "$3" --arg fp "$4" \
    '{cwd: $cwd, tool_input: {skill: $skill, args: $args, file_path: $fp}}'
}

# --- scratch repository ----------------------------------------------
repo=$(mktemp -d)
trap 'rm -rf "$repo"' EXIT

git -C "$repo" init --quiet
git -C "$repo" config user.email test@example.invalid
git -C "$repo" config user.name test

mkdir -p "$repo/.vale/ai-tells" "$repo/.vale/config/vocabularies/project"
printf 'StylesPath = .vale\n' >"$repo/.vale.ini"
printf '{}\n' >"$repo/.cspell.jsonc"
printf 'widget\n' >"$repo/.cspell-words.txt"
printf 'default:\n' >"$repo/Justfile"
printf 'extends: existence\n' >"$repo/.vale/ai-tells/VerbTricolon.yml"
printf 'alpha\n' >"$repo/.vale/config/vocabularies/project/accept.txt"

# The same exclusion this repository uses, which is what makes the
# synced style packages invisible to git status.
printf '.vale/*\n!.vale/config/\n' >"$repo/.gitignore"

printf '# Draft\n\nSome settled prose.\n' >"$repo/target.md"
printf '# Other\n\nUnrelated.\n' >"$repo/other.md"

git -C "$repo" add -A
git -C "$repo" commit --quiet -m "initial"

git_dir=$(git -C "$repo" rev-parse --absolute-git-dir)
lock="$git_dir/fix-prose.lock"
base="$git_dir/fix-prose.baseline"

arm() { payload "$repo" "$1" "$2" "" | bash "$SCRIPTS/arm-guard.sh"; }
guard() { payload "$repo" "" "" "$1" | bash "$SCRIPTS/guard-target.sh" >/dev/null 2>&1; }
verify() { (cd "$repo" && bash "$SCRIPTS/check-suppressions.sh" --verify >/dev/null 2>&1); }

# --- cases -----------------------------------------------------------

verify
check $? 1 "a missing baseline reports rather than passing"

guard "$repo/target.md"
check $? 0 "no lock leaves the guard silent"

arm commit "target.md just lint-draft target.md"
[ -f "$lock" ]
check $? 1 "another skill's invocation does not arm the guard"

arm fix-prose "nonexistent.md just lint-draft nonexistent.md"
[ -f "$lock" ]
check $? 1 "an absent target does not arm the guard"

arm fix-prose "target.md just lint-draft target.md"
[ -f "$lock" ] && [ -d "$base" ]
check $? 0 "fix-prose records the target and the baseline"

verify
check $? 0 "an untouched tree verifies clean"

guard "$repo/target.md"
check $? 2 "the guard refuses the caller's edit to the target"

guard "target.md"
check $? 2 "a relative payload path resolves and still refuses"

guard "$repo/other.md"
check $? 0 "the guard allows a path nobody is fixing"

# The lock outlives its document. A commit draft is deleted once the
# commit lands, and the next commit writes a new one at the same path, so
# a lock matching on the path alone refuses a document its run never saw.
mv "$repo/target.md" "$repo/target.md.away"
guard "$repo/target.md"
check $? 0 "an absent target releases the lock rather than refusing"
[ -f "$lock" ]
check $? 1 "the released lock is gone rather than left to match again"
mv "$repo/target.md.away" "$repo/target.md"

guard "$repo/target.md"
check $? 0 "a target restored after the release stays unguarded"

arm fix-prose "target.md just lint-draft target.md"
guard "$repo/target.md"
check $? 2 "re-arming after a release refuses the caller again"

printf 'More settled prose.\n' >>"$repo/target.md"
verify
check $? 0 "editing the target itself stays clean"

printf '# tampered\n' >>"$repo/.vale/ai-tells/VerbTricolon.yml"
verify
check $? 1 "a gitignored style file edit is caught"
git -C "$repo" checkout -- .vale/ai-tells/VerbTricolon.yml 2>/dev/null ||
  printf 'extends: existence\n' >"$repo/.vale/ai-tells/VerbTricolon.yml"

printf 'bravo\n' >>"$repo/.vale/config/vocabularies/project/accept.txt"
verify
check $? 1 "a vocabulary addition is caught"
printf 'alpha\n' >"$repo/.vale/config/vocabularies/project/accept.txt"

printf 'MinAlertLevel = suggestion\n' >>"$repo/.vale.ini"
verify
check $? 1 "a .vale.ini change is caught"
printf 'StylesPath = .vale\n' >"$repo/.vale.ini"

printf 'bravo\n' >>"$repo/.cspell-words.txt"
verify
check $? 1 "a dictionary addition is caught"
printf 'widget\n' >"$repo/.cspell-words.txt"

printf 'stray\n' >>"$repo/other.md"
verify
check $? 1 "an edit to another file is caught"
git -C "$repo" checkout -- other.md

printf 'x\n' >"$repo/appeared.md"
verify
check $? 1 "a newly created file is caught"
rm -f "$repo/appeared.md"

verify
check $? 0 "reverting everything verifies clean again"

printf '\n<!-- vale off -->\n' >>"$repo/target.md"
verify
check $? 1 "an inline vale suppression is caught"

# The baseline records what the target already carried, so re-arming on
# a file holding a directive must not report that directive afterwards.
arm fix-prose "target.md just lint-draft target.md"
verify
check $? 0 "a directive present at baseline is not a finding"

printf '\n<!-- cspell:ignore widget -->\n' >>"$repo/target.md"
verify
check $? 1 "a directive added after the baseline is caught"

printf '\n<!-- vale ai-tells.VerbTricolon = NO -->\n' >>"$repo/target.md"
verify
check $? 1 "a per-rule vale override is caught"

# --- report ----------------------------------------------------------
if [ "$fail" -gt 0 ]; then
  printf 'TOTAL: %s passed, %s failed\n' "$pass" "$fail"
  exit 1
fi
printf 'ok: %s guard cases passed\n' "$pass"
