#!/usr/bin/env bats
#
# Tests for tools/check-versions.sh, the witness on cog.toml's
# pre_bump_hooks.
#
# Each test builds a throwaway repository carrying the same six sites
# the real tree does, because the script asks git for the tag and reads
# the files relative to the toplevel. Running it against this repository
# instead would only ever prove the aligned case, and the cases worth
# holding are the failures: a literal left behind, and a site that has
# moved out from under its hook.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../../tools/check-versions.sh"
  REPO="${BATS_TEST_TMPDIR}/repo"

  # Cut the operator's configuration out entirely. An identity has to
  # come from somewhere once the global file is gone, and tag.gpgSign or
  # tag.forceSignAnnotated would otherwise turn the lightweight `git tag`
  # below into an annotated one and stop for a message.
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  export GIT_AUTHOR_NAME='Test' GIT_AUTHOR_EMAIL='test@example.com'
  export GIT_COMMITTER_NAME='Test' GIT_COMMITTER_EMAIL='test@example.com'

  mkdir -p "$REPO/packages/repotools"
  cd "$REPO"
  git init --quiet --initial-branch=main .
}

# The six sites at $1, laid out the way the real files carry them:
# apm.yml and pyproject.toml anchored at line start, the hook manifest's
# inside an indented comment, the README's two under surrounding prose,
# and uv.lock's under the package entry that names it. The lockfile gets
# a decoy package carrying its own version line, because that is what
# stops the check from matching the first `version =` it finds.
write_sites() {
  local v=$1
  printf 'name: repotools\nversion: %s\n' "$v" > apm.yml
  printf '[project]\nname = "repotools"\nversion = "%s"\n' "$v" > packages/repotools/pyproject.toml
  printf '# Reference it with:\n#\n#     rev: v%s\n' "$v" > .pre-commit-hooks.yaml
  printf '# repotools\n\n    apm install tbhb/repotools#v%s\n\nAnd:\n\n    rev: v%s\n' "$v" "$v" > README.md
  printf '[[package]]\nname = "pytest"\nversion = "9.9.9"\n\n[[package]]\nname = "repotools"\nversion = "%s"\nsource = { editable = "packages/repotools" }\n' "$v" > uv.lock
}

commit_at() {
  local v=$1
  write_sites "$v"
  git add -A
  git commit --quiet -m "release v$v"
  git tag "v$v"
}

@test "passes when every literal names the latest tag" {
  commit_at 1.2.3
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "fails naming the one literal left behind" {
  commit_at 1.2.3
  # The shape a half-applied bump leaves: four sites rewritten, one not.
  printf '[project]\nname = "repotools"\nversion = "1.2.2"\n' > packages/repotools/pyproject.toml

  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ $output == *"packages/repotools/pyproject.toml:3"* ]]
  [[ $output == *'expected `version = "1.2.3"`'* ]]
  [[ $output == *'found `version = "1.2.2"`'* ]]
  [[ $output == *"TOTAL: 1 finding(s)"* ]]
}

@test "reports both README sites independently" {
  commit_at 1.2.3
  printf '# repotools\n\n    apm install tbhb/repotools#v1.2.3\n\nAnd:\n\n    rev: v0.9.0\n' > README.md

  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ $output == *"README.md:7"* ]]
  [[ $output != *"README.md:3"* ]]
  [[ $output == *"TOTAL: 1 finding(s)"* ]]
}

@test "fails when a site is deleted rather than left stale" {
  commit_at 1.2.3
  # A grep for the expected string alone would read this as a pass, which
  # is the whole reason the shape is matched separately from the value.
  printf '# Reference it with:\n#\n#     see the README\n' > .pre-commit-hooks.yaml

  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ $output == *".pre-commit-hooks.yaml:1"* ]]
  [[ $output == *"no line matching"* ]]
}

@test "reads the lockfile version under the repotools package alone" {
  commit_at 1.2.3
  # The decoy still names 9.9.9 and the repotools entry falls behind. A
  # check reading the first version line in the file would report the
  # decoy instead, or miss this entirely.
  printf '[[package]]\nname = "pytest"\nversion = "9.9.9"\n\n[[package]]\nname = "repotools"\nversion = "1.2.2"\nsource = { editable = "packages/repotools" }\n' > uv.lock

  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ $output == *"uv.lock:7"* ]]
  [[ $output == *'found `version = "1.2.2"`'* ]]
  [[ $output == *"TOTAL: 1 finding(s)"* ]]
}

@test "fails when the lockfile drops the repotools package" {
  commit_at 1.2.3
  printf '[[package]]\nname = "pytest"\nversion = "9.9.9"\n' > uv.lock

  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ $output == *"uv.lock:1"* ]]
  [[ $output == *"no package entry named repotools"* ]]
}

@test "an explicit version overrides the tag" {
  commit_at 1.2.3

  run "$SCRIPT" 1.2.3
  [ "$status" -eq 0 ]

  run "$SCRIPT" 9.9.9
  [ "$status" -eq 1 ]
  [[ $output == *"TOTAL: 6 finding(s) against v9.9.9"* ]]
}

@test "an explicit version tolerates a leading v" {
  commit_at 1.2.3
  run "$SCRIPT" v1.2.3
  [ "$status" -eq 0 ]
}

@test "fails rather than passing where no tag is reachable" {
  write_sites 1.2.3
  git add -A
  git commit --quiet -m "no tag here"

  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ $output == *"no tag reachable from HEAD"* ]]
}
