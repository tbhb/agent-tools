set positional-arguments

# What is left in this file, and why.
#
# mise.toml and the drop-ins under .config/mise/conf.d/ hold the
# toolchain and every gate that runs a pinned binary. Two things could
# not move there:
#
#   1. The Go test and coverage recipes. The CI matrix runs them on
#      Windows, where `just` under Git Bash is proven and mise's handling
#      of bash-shebang task bodies is not.
#
#   2. The delegation recipes at the bottom. The APM primitives in
#      .claude/ spell their gates `just <recipe>`; three of them refuse
#      to run when the recipe is absent. Each one forwards to the mise
#      task of the same name through the committed bootstrap shim, so the
#      pinned mise runs even on a machine that has none.
#
# Everything else moved, the container-pinned gates last: their images
# were a digest-pinning mechanism rather than an isolation choice, and
# mise.lock pins digests now. Run `mise tasks` for the full set.

# The committed shim from `mise generate bootstrap`. It installs the
# pinned mise only if absent, then execs it with every argument, so these
# recipes run the pinned mise rather than whatever is on PATH.

mise := "tools/mise-bootstrap"

# Default recipe
default: lint-go test

# --- Go test and coverage ---
# These recipes run on the CI matrix, Windows included, where `just`
# under Git Bash is proven. The ported task bodies open with a bash
# shebang by the porting rule, and mise's handling of a bash shebang on
# a Windows runner is unverified, so this family stays put.

# Run the Go tests.
test-go *args:
    go test ./... "$@"

# Slower than plain `just test-go`; pairs with goroutine-bearing code as it
# lands. Native fuzz targets discovered by the nightly workflow rerun
# under `-race` automatically when their function-under-test is reached
# from `-race` builds; for ad-hoc local runs use this recipe.

# Run the Go tests with the race detector.
test-go-race:
    go test -race ./...

# The first argument names the ./cmd/<bin> package; the rest pass
# through to it. tools/go-ldflags.sh computes the reproducible build
# metadata the mise build task uses, so the two cannot drift.

# Run one binary by name, e.g. `just run agentstore version`.
run bin *args:
    go run -ldflags "$(bash tools/go-ldflags.sh)" ./cmd/{{ bin }} {{ args }}

# Run the Go tests with coverage, print the per-function breakdown, and enforce the `.testcoverage.yml` thresholds.
cover-go:
    go test -coverprofile=coverage.out ./...
    @echo
    go tool cover -func=coverage.out | tail -n 30
    @echo
    go tool go-test-coverage --config .testcoverage.yml

# Highlights covered and uncovered regions in source view so a
# contributor can find exactly where a new test should land. Wraps
# `go tool cover -html`.

# Open the HTML coverage report.
cover-go-html:
    go test -coverprofile=coverage.out ./...
    go tool cover -html=coverage.out

# Cobertura is the lingua franca format coverage dashboards accept. This
# is the quick local form; CI's per-slot and combined uploads flow
# through `cover-go-binary` and `cover-go-merge` below.

# Emit a Cobertura XML report from one local text profile.
cover-go-cobertura:
    go test -coverprofile=coverage.out ./...
    go tool gocover-cobertura < coverage.out > coverage.xml

# CI uploads the binary covdir per matrix slot so the downstream coverage
# job can merge the slots with `go tool covdata merge` (see `cover-go-merge`)
# into one combined report — a merge only the binary format supports
# losslessly. The covdir is absolute because `go test` runs each
# package's binary from that package's directory, which would scatter a
# relative path.

# Run the Go tests into [covdir] as binary coverage, then render Cobertura XML.
cover-go-binary covdir="coverage.covdata":
    rm -rf "{{ justfile_directory() }}/{{ covdir }}"
    mkdir -p "{{ justfile_directory() }}/{{ covdir }}"
    go test ./... -cover -args -test.gocoverdir="{{ justfile_directory() }}/{{ covdir }}"
    go tool covdata textfmt -i="{{ justfile_directory() }}/{{ covdir }}" -o=coverage.out
    go tool gocover-cobertura < coverage.out > coverage.xml

# Takes one subdirectory per slot under [slotsdir], merges them into a
# single profile, and renders the combined Cobertura XML to coverage.xml.
# CI runs this in the downstream coverage job after collecting every
# slot's uploaded covdata.

# Merge the per-slot binary coverage dirs into one report.
cover-go-merge slotsdir="coverage.covdata.slots":
    rm -rf coverage.covdata.merged
    mkdir -p coverage.covdata.merged
    go tool covdata merge -i="$(ls -d {{ slotsdir }}/*/ | paste -sd, -)" -o=coverage.covdata.merged
    go tool covdata textfmt -i=coverage.covdata.merged -o=coverage.out
    go tool gocover-cobertura < coverage.out > coverage.xml

# The bare check separates a CI step that runs tests itself from the
# threshold enforcement, and gives a contributor a way to re-check after
# editing `.testcoverage.yml` without rerunning the suite.

# Run only the threshold gate against an existing coverage.out.
cover-go-check:
    go tool go-test-coverage --config .testcoverage.yml

# --- APM compatibility and reproduction commands ---

# Each recipe below exists because a skill under .claude/ names it, or
# because fix-pr prints it as the local reproduction for a failing check.
# The definition lives in mise.toml or a conf.d drop-in; nothing here
# does work of its own.
#
# Preconditions the skills check and refuse to run without:

# commit — preflight verifies this recipe exists before drafting a message.
lint-commit-msg:
    {{ mise }} run lint-commit-msg

# pr — same check before publishing a description.
lint-pr-description:
    {{ mise }} run lint-pr-description

# merge-pr — same check before a squash merge.
lint-squash-msg:
    {{ mise }} run lint-squash-msg

# rebase — verifies the replayed tree against `just check`, falling back to
# `just lint` where a repo has no `check`.
check:
    {{ mise }} run check

# Recipes the skills invoke directly:

# write-prose-fix runs this before rewording anything by hand.
fix-prose-replacements file:
    {{ mise }} run fix-prose-replacements {{ file }}

# fix-prose takes this as the general-purpose gate for a whole document.
lint-draft file:
    {{ mise }} run lint-draft {{ file }}

# commit's preflight prints this by name when a git hook is missing, so the
# advice it gives has to resolve to something runnable.
prek-install:
    {{ mise }} run repotools:prek-install

# Recipes fix-pr prints as the local reproduction for a failing check. A
# name that resolves to nothing here sends the agent to a command that
# cannot run, so the diagnosis has to stay executable.
lint:
    {{ mise }} run lint

lint-prose *args:
    {{ mise }} run lint-prose {{ args }}

lint-spelling *args:
    {{ mise }} run repotools:lint-spelling {{ args }}

lint-markdown *args:
    {{ mise }} run repotools:lint-markdown {{ args }}

lint-markdown-wrap *args:
    {{ mise }} run lint-markdown-wrap {{ args }}

lint-yaml *args:
    {{ mise }} run repotools:lint-yaml {{ args }}

lint-toml:
    {{ mise }} run repotools:lint-toml

lint-editorconfig:
    {{ mise }} run lint-editorconfig

lint-shell:
    {{ mise }} run lint-shell

lint-shell-fmt:
    {{ mise }} run lint-shell-fmt

lint-workflows:
    {{ mise }} run repotools:lint-workflows

lint-go:
    {{ mise }} run lint-go

lint-go-arch:
    {{ mise }} run lint-go-arch

lint-go-deadcode:
    {{ mise }} run lint-go-deadcode

test:
    {{ mise }} run test

vuln:
    {{ mise }} run vuln

vendor-check:
    {{ mise }} run vendor-check

lock-check:
    {{ mise }} run lock-check

fuzz:
    {{ mise }} run fuzz

gitleaks:
    {{ mise }} run gitleaks

# AGENTS.md and the rebase workflow spell these two by their just names.
skill-tokens *args:
    {{ mise }} run skill-tokens {{ args }}

fix-markdown-wrap:
    {{ mise }} run fix-markdown-wrap

# The apm-package workflow's failure message names this recipe as the fix.
apm-sync:
    {{ mise }} run apm-sync
