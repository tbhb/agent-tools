#!/usr/bin/env bash
# check-versions — assert every published version literal names the
# latest release tag.
#
# Six files carry the version: the APM manifest, the Python package, the
# pre-commit hook manifest's usage comment, two install pins in the
# README, and the uv lockfile's entry for the editable Python package.
# cog.toml's pre_bump_hooks rewrite all six during a bump, from the
# version cog is about to tag. This is the witness that they did.
#
# Hooks alone would have none. Before they existed, five of the six took
# a hand edit, no gate read them, and every one had fallen behind — the
# README's install pins named releases older than the payload the same
# README describes. A hook added for a seventh site and then quietly
# broken would reproduce that silently, so the gate lists the sites
# independently of cog.toml rather than deriving them from it.
#
# uv.lock is the exception worth knowing about. `uv lock --check` already
# fails the moment it disagrees with the Python package's version, so
# that site breaks a build rather than going stale quietly. It is here
# because the same bump has to move both, not because nothing else
# watched it.
#
# Between releases the literals correctly name the last released version
# rather than HEAD, so this holds at every commit and not only at release
# time. That is why it belongs in the lint aggregate.
#
# Adding a seventh site means a line here and a hook in cog.toml, in that
# order: add the check first and watch it go red.
#
# Findings print one per line in the shape the vale agent template uses,
# and silence means a clean run.
#
# Usage: check-versions.sh [X.Y.Z]
#   With no argument the expected version is the latest tag, which is
#   what the lint aggregate runs. An explicit version is for a caller
#   holding a tag of its own, such as the release postflight.
set -euo pipefail

export LC_ALL=C
unset CDPATH GREP_OPTIONS
IFS=$' \t\n'

root=$(command git rev-parse --show-toplevel)
cd "$root"

version=${1:-}
if [ -z "$version" ]; then
  # A shallow clone with no tags cannot answer the question. Say so and
  # fail rather than passing, because a gate that goes quiet where its
  # input is missing reports the same silence as a clean tree.
  if ! version=$(command git describe --tags --abbrev=0 2>/dev/null); then
    printf 'check-versions: no tag reachable from HEAD; fetch tags and unshallow before running this\n' >&2
    exit 1
  fi
fi
version=${version#v}

findings=0
report() {
  printf '%s:%s [error] version-literal-stale  %s\n' "$1" "$2" "$3"
  findings=$((findings + 1))
}

# Read `grep -n` style "<line>:<text>" records and report each one whose
# text does not carry $want. A here-string rather than a pipeline, so the
# loop runs in this shell and its report calls reach the counter.
compare() {
  local file=$1 want=$2
  local line number text

  while IFS= read -r line; do
    number=${line%%:*}
    text=${line#*:}
    case $text in
    *"$want"*) ;;
    *) report "$file" "$number" "expected \`$want\`, found \`$text\`" ;;
    esac
  done
}

# One single-line site: the file, an extended regular expression matching
# that site whatever version it names, and the exact text it has to carry
# at $version. Matching the shape separately from the value is what lets
# a site that has moved or been deleted read as a finding rather than as
# a pass, which is the failure a plain grep for the expected string gives.
check_site() {
  local file=$1 shape=$2 want=$3
  local hits

  if ! hits=$(grep -nE -- "$shape" "$file"); then
    report "$file" 1 "no line matching /$shape/; the site moved or was deleted, and whatever cog.toml hook rewrites it is now inert"
    return
  fi

  compare "$file" "$want" <<<"$hits"
}

# uv.lock needs its preceding line for context, because every package in
# the lockfile carries a `version =` line and only one of them belongs to
# the editable repotools package.
check_uv_lock() {
  local want=$1 hits

  hits=$(awk '/^name = "repotools"$/ { getline; print NR ":" $0 }' uv.lock)
  if [ -z "$hits" ]; then
    report uv.lock 1 "no package entry named repotools; the lockfile shape changed and the cog.toml hook that rewrites it is now inert"
    return
  fi

  compare uv.lock "$want" <<<"$hits"
}

check_site apm.yml '^version: ' "version: $version"
check_site packages/repotools/pyproject.toml '^version = ' "version = \"$version\""
check_site .pre-commit-hooks.yaml 'rev: v[0-9]' "rev: v$version"
check_site README.md 'tbhb/repotools#v[0-9]' "tbhb/repotools#v$version"
check_site README.md 'rev: v[0-9]' "rev: v$version"
check_uv_lock "version = \"$version\""

if [ "$findings" -gt 0 ]; then
  printf 'TOTAL: %s finding(s) against v%s\n' "$findings" "$version"
  exit 1
fi
