#!/usr/bin/env bash
# go-ldflags — print the ldflags for a reproducible Go build.
#
# The build metadata lived in Justfile variables until the mise
# migration; build and install are mise tasks now, and this script is the
# single definition both read, so the two cannot drift.
#
# `date` is the *committer date* (UTC, ISO-8601), not build invocation
# time, so two builds of the same commit produce identical binaries.
# `--abbrev=7` / `--short=7` pin the abbreviated hash length so two
# checkouts of the same commit produce the same string; without this,
# git uses `core.abbrev=auto`, whose length depends on object count.
# 7 matches goreleaser's `.ShortCommit`.
#
# -buildid= clears the build ID for bit-for-bit reproducibility across
# toolchains; -s -w strips the symbol table and DWARF info; -X injects
# the buildmeta package vars.
set -euo pipefail

export LC_ALL=C
unset CDPATH GREP_OPTIONS

module="github.com/tbhb/repotools"

version=$(git describe --tags --abbrev=7 2>/dev/null || git rev-parse --short=7 HEAD 2>/dev/null || echo "DEV")
commit=$(git rev-parse --short=7 HEAD 2>/dev/null || echo "")
date=$(TZ=UTC git -c log.showSignature=false log -1 --format=%cd --date=format-local:%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")

printf -- '-s -w -buildid= -X %s/internal/buildmeta.Version=%s -X %s/internal/buildmeta.Commit=%s -X %s/internal/buildmeta.Date=%s\n' \
  "$module" "$version" "$module" "$commit" "$module" "$date"
