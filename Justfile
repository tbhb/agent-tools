set unstable
set positional-arguments

# What is left in this file, and why.
#
# mise.toml and the drop-ins under .config/mise/conf.d/ hold the
# toolchain and every gate that runs a pinned binary. Three things could
# not move there:
#
#   1. The container-pinned gates below. They run from SHA-pinned images
#      rather than from a mise tool, and the shared Renovate preset tracks
#      their digests through a custom manager keyed on `^Justfile$`. Moving
#      the pins would silently drop them from Renovate's view.
#
#   2. The Go test and coverage recipes. The CI matrix runs them on
#      Windows, where `just` under Git Bash is proven and mise's handling
#      of bash-shebang task bodies is not.
#
#   3. The delegation recipes at the bottom. The APM primitives in
#      .claude/ spell their gates `just <recipe>`; three of them refuse
#      to run when the recipe is absent. Each one forwards to the mise
#      task of the same name through the committed bootstrap shim, so the
#      pinned mise runs even on a machine that has none.
#
# Everything else moved. Run `mise tasks` for the full set.

# Run [script] recipes under bash; dash lacks [[ ]], <<<, and pipefail.

set script-interpreter := ['bash', '-eu']

# The committed shim from `mise generate bootstrap`. It installs the
# pinned mise only if absent, then execs it with every argument, so these
# recipes run the pinned mise rather than whatever is on PATH.

mise := "tools/mise-bootstrap"

# golangci-lint version pin. golangci-lint is distributed as pre-built
# binaries with linter versions baked in, so we pin a Docker image by
# digest rather than `go install` it. Renovate's customManager
# (.github/renovate.json5) tracks the version + digest pair below via the
# comment marker.
#
# renovate: datasource=docker depName=golangci/golangci-lint

golangci_lint_version := "v2.12.2"
golangci_lint_image := "docker.io/golangci/golangci-lint:v2.12.2@sha256:5cceeef04e53efe1470638d4b4b4f5ceefd574955ab3941b2d9a68a8c9ad5240"

# Locate a Docker-compatible container runtime. Probe PATH first, then
# well-known install locations so the recipe still works inside agentic
# harnesses or sandboxes that strip /usr/local/bin from PATH. Override by
# setting CONTAINER_RUNTIME in the environment.
#
# The continuation lines of the `for` list below hang under the first
# candidate path rather than on a two-space grid, which is what shell
# style calls for and what `lint-editorconfig` would otherwise reject
# under this file's indent_size = 2. Exempt just that span rather than
# re-indent a block the sibling repos carry verbatim.
# editorconfig-checker-disable
container_runtime := env("CONTAINER_RUNTIME", `bash -c '
    docker_path=$(command -v docker 2>/dev/null || true)
    podman_path=$(command -v podman 2>/dev/null || true)
    for p in "$docker_path" \
             /usr/local/bin/docker \
             /opt/homebrew/bin/docker \
             /Applications/Docker.app/Contents/Resources/bin/docker \
             "$HOME/.orbstack/bin/docker" \
             "$HOME/.rd/bin/docker" \
             "$podman_path" \
             /opt/podman/bin/podman; do
        if [ -n "$p" ] && [ -x "$p" ]; then echo "$p"; exit 0; fi
    done
    echo docker
'`)

# editorconfig-checker-enable

# Container invocation prefix for golangci-lint. Mounts the working dir at
# /data and the host Go module cache so first-run resolution stays cheap.
# Shell substitutions evaluate at recipe-run time, not Justfile-parse time.
#
# DOCKER_CONFIG points at a fresh empty directory so docker skips the
# osxkeychain credential helper (public Docker Hub pulls don't need it,
# and sandboxed environments can't always reach the helper binary).
# PATH gets the runtime's directory prepended for cases where docker
# itself isn't on the calling shell's PATH.
#
# GOTOOLCHAIN=local pins the container to the Go version baked into
# the golangci-lint image, blocking the in-container toolchain
# auto-download triggered by go.mod's `toolchain` directive. The
# container has no write access to `/go/pkg/sumdb` for the download
# verifier and no need to match the host toolchain at point-release
# granularity — golangci-lint analyzers walk the AST, and point
# releases ship no syntax changes.

golangci_lint := 'DOCKER_CONFIG="$(mktemp -d)" PATH="$(dirname ' + container_runtime + '):$PATH" ' + container_runtime + ' run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e GOLANGCI_LINT_CACHE=/tmp/golangci-lint-cache -e GOTOOLCHAIN=local -v "$(go env GOMODCACHE):/go/pkg/mod" -v "$(pwd):/data" -w /data ' + golangci_lint_image + ' golangci-lint'

# go-arch-lint version pin. Same Docker-pin pattern as golangci-lint:
# the upstream image bundles the linter at a known version, and Renovate
# tracks the version + digest pair via the customManager in renovate.json5.
# Image is amd64-only; arm64 dev hosts run it via emulation.
#
# renovate: datasource=docker depName=fe3dback/go-arch-lint

go_arch_lint_version := "release-v1.15.0"
go_arch_lint_image := "docker.io/fe3dback/go-arch-lint:release-v1.15.0@sha256:5af4ee8cb2ea9b251b44a24e0df5f99bd4dd1005a2c4eb0fa0bc3e7d3fab9a9a"

# go-arch-lint invocation. Mounts project read-only since the linter only
# reads source. Does not set --user: the upstream image is built for root,
# and a read-only mount means root inside can't write to the host anyway.

go_arch_lint := 'DOCKER_CONFIG="$(mktemp -d)" PATH="$(dirname ' + container_runtime + '):$PATH" ' + container_runtime + ' run --rm -v "$(pwd):/app:ro" ' + go_arch_lint_image

# actionlint version pin. Same Docker-pin pattern as golangci-lint and
# go-arch-lint: the upstream image bundles actionlint (plus shellcheck) at
# a known version, and Renovate tracks the version + digest pair via the
# customManager in renovate.json5. This is the same image
# `.github/workflows/lint-workflows.yml` in this repo runs, so `just
# lint-workflows` and CI share one actionlint.
#
# renovate: datasource=docker depName=rhysd/actionlint

actionlint_version := "1.7.12"
actionlint_image := "docker.io/rhysd/actionlint:1.7.12@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667"

# actionlint invocation. Mounts the tree read-only since actionlint only
# reads source. The bundled shellcheck lints `run:` blocks, matching what
# the shared workflow applies in CI.

actionlint := 'DOCKER_CONFIG="$(mktemp -d)" PATH="$(dirname ' + container_runtime + '):$PATH" ' + container_runtime + ' run --rm -v "$(pwd):/repo:ro" -w /repo ' + actionlint_image

# shellcheck version pin. Same Docker-pin pattern as the linters above, and
# Renovate tracks the version + digest pair through the shared Justfile
# custom manager via the comment marker. This is a distinct gate from the
# shellcheck bundled inside the actionlint image: that copy only ever sees
# `run:` blocks embedded in workflow YAML, and never opens the standalone
# scripts under hooks/ and tools/ that `lint-shell` below covers.
#
# renovate: datasource=docker depName=koalaman/shellcheck

shellcheck_version := "v0.11.0"
shellcheck_image := "docker.io/koalaman/shellcheck:v0.11.0@sha256:61862eba1fcf09a484ebcc6feea46f1782532571a34ed51fedf90dd25f925a8d"

# shellcheck invocation. Mounts the tree read-only at /mnt since the linter
# only reads source; the recipe passes repo-relative paths, so the working
# directory has to be the mount point.

shellcheck := 'DOCKER_CONFIG="$(mktemp -d)" PATH="$(dirname ' + container_runtime + '):$PATH" ' + container_runtime + ' run --rm -v "$(pwd):/mnt:ro" -w /mnt ' + shellcheck_image

# bats version pin, backing `test-hooks`. Same Docker-pin pattern as the
# linters above, and Renovate tracks the version + digest pair through the
# comment marker. A container rather than a mise pin because the suites
# under test/ describe the shell hooks other repositories install, so the
# runner they pass under should be the same one everywhere rather than
# whichever bats a contributor happens to have.
#
# renovate: datasource=docker depName=bats/bats

bats_version := "1.14.0"
bats_image := "docker.io/bats/bats:1.14.0@sha256:5322b877351fda0cc435de8c6116de7d0a2ec79d7c680132a0ef329a633bc66f"

# bats invocation. The mount is writable because the suites write scratch
# files under BATS_TEST_TMPDIR, which the image places inside the mount.

bats := 'DOCKER_CONFIG="$(mktemp -d)" PATH="$(dirname ' + container_runtime + '):$PATH" ' + container_runtime + ' run --rm -v "$(pwd):/code" -w /code ' + bats_image

# Default recipe
default: lint-go test

# --- Container-pinned gates ---

# Format Go code (uses golangci-lint formatters via the pinned Docker image)
format-go *args:
    {{ golangci_lint }} fmt {{ args }}

# `go fix` (Go 1.26+) runs the modernizer analyzers; the blog post
# (https://go.dev/blog/gofix) recommends running it to a fixed point —
# usually one extra pass picks up fixes that became valid after the first
# round. golangci-lint fmt + --fix run afterward.

# Fix Go linting issues.
fix-go *args:
    go fix {{ if args == "" { "./..." } else { args } }}
    go fix {{ if args == "" { "./..." } else { args } }}
    {{ golangci_lint }} fmt {{ args }}
    {{ golangci_lint }} run --fix --modules-download-mode=vendor {{ args }}

# --modules-download-mode=vendor matches the build, so the linter sees
# exactly the dependency set the compiler does and never falls back to
# the module proxy.

# Run Go linters (golangci-lint via the pinned Docker image, vendor-mode).
lint-go *args:
    {{ golangci_lint }} run --modules-download-mode=vendor {{ args }}

# The compiler covers cycles and cross-module visibility; this catches
# the layer rules it can't (e.g., "cmd may depend on internal but not
# the reverse"). Pinned Docker image, same pattern as golangci-lint.

# Enforce intra-project layering rules from .go-arch-lint.yml.
lint-go-arch:
    {{ go_arch_lint }} check --project-path /app

# actionlint walks `.github/workflows/` by default, parses each workflow,
# and flags unknown actions, mis-typed expressions, shellcheck issues
# inside `run:` blocks, and SHA-pin drift. Complements the yamllint gate
# (which checks YAML structure) with workflow-shape rules yamllint can't
# see. Runs from the SHA-pinned Docker image above (which bundles
# shellcheck), the same image the reusable lint-workflows.yml in this
# repo runs, so this local entrypoint and the CI gate run one actionlint,
# both bumped by Renovate.

# Lint GitHub Actions workflow files via actionlint.
lint-workflows:
    {{ actionlint }}

# Covers the standalone scripts the actionlint image never opens
# (tools/fuzz.sh and its neighbors). `--others` puts a brand new script in
# the gate before anyone stages it, which is when its first shellcheck
# violation is cheapest to fix; without it a script escapes the gate for
# exactly as long as it is newest. `--exclude-standard` is what keeps a
# scratch script out, so a throwaway belongs in .gitignore rather than
# outside git's view. The `:!:vendor/**` pathspec drops the vendored
# upstream scripts, which are reviewed at vendor-tidy time rather than
# held to this project's style. The emptiness guard matters because
# shellcheck with no path arguments reads stdin and blocks. Runs from the
# SHA-pinned image above, so the shellcheck version advances by Renovate
# rather than by whatever the contributor happens to have on PATH.

# Lint every non-vendored *.sh git can see via the pinned shellcheck image.
[script]
lint-shell:
    files=$(git ls-files --cached --others --exclude-standard '*.sh' ':!:vendor/**' ':!:.claude/**')
    if [ -n "$files" ]; then {{ shellcheck }} $files; fi

# The shell hooks under scripts/ answer to bats rather than to `go test`,
# so they get a third suite alongside the two language ones. It joins the
# `test` aggregate because the commit-message gates every repository here
# installs are exactly the code a regression should stop, and the run
# costs seconds once the image is pulled.

# Run the bats suites for the shell hooks under scripts/.
test-hooks *args:
    {{ bats }} {{ if args == "" { "test" } else { args } }}

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
    {{ mise }} run prek-install

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

lint-shell-fmt:
    {{ mise }} run lint-shell-fmt

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
