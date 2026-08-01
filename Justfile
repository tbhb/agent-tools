set unstable
set positional-arguments

# Run [script] recipes under bash rather than the default sh. On Linux
# sh is dash, which lacks [[ ]], <<<, and set -o pipefail — constructs
# every [script] recipe below relies on. Under dash those recipes
# either hard-fail (fuzz, on set -o pipefail) or silently no-op (the
# deadcode and modernize gates, whose [[ test errors inside an if so
# set -e never trips and the failure branch is skipped). macOS sh is
# bash, which is why the breakage stayed hidden until CI ran on Linux.

set script-interpreter := ['bash', '-eu']

# Go project metadata

module := "github.com/tbhb/agent-tools"
bin_dir := "bin"

# golangci-lint version pin. golangci-lint is distributed as pre-built
# binaries with linter versions baked in, so we pin a Docker image by
# digest rather than `go install` it. Renovate's customManager
# (.github/renovate.json5, landing in a later commit) tracks the
# version + digest pair below via the comment marker.
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
# customManager in renovate.json5. This is the same image the reusable
# lint-workflows.yml in tbhb/github-actions runs, so `just
# lint-workflows` and CI share one actionlint.
#
# The tombi release this repo's config and committed formatting are
# verified against. tombi is brew-installed, so `check-tombi-version`
# compares the local binary with it: a mismatch means local formatting
# may differ from what the gate expects.

# renovate: datasource=github-releases depName=tombi-toml/tombi

tombi_version := "1.2.5"

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

# Build metadata. `date` is the *committer date* (UTC, ISO-8601),
# not build invocation time, so two builds of the same commit produce
# identical binaries. `source_date_epoch` exports the same instant as
# a unix timestamp for downstream tooling (BuildKit, archive tooling)
# that honors SOURCE_DATE_EPOCH for reproducibility.
#
# `--abbrev=7` / `--short=7` pin the abbreviated hash length so two
# checkouts of the same commit produce the same string. Without this,
# git uses `core.abbrev=auto`, whose length depends on object count
# (shallow clones, freshly-packed repos, and aged working copies all
# differ). 7 matches goreleaser's `.ShortCommit`.

version := `git describe --tags --abbrev=7 2>/dev/null || git rev-parse --short=7 HEAD 2>/dev/null || echo "DEV"`
commit := `git rev-parse --short=7 HEAD 2>/dev/null || echo ""`
date := `TZ=UTC git log -1 --format=%cd --date=format-local:%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown"`
source_date_epoch := `git log -1 --format=%ct 2>/dev/null || echo "0"`

# ldflags for build. -buildid= clears the build ID for bit-for-bit
# reproducibility across toolchains; -s -w strips the symbol table and
# DWARF info; -X injects the buildmeta package vars.

ldflags := "-s -w -buildid=" + " -X " + module + "/internal/buildmeta.Version=" + version + " -X " + module + "/internal/buildmeta.Commit=" + commit + " -X " + module + "/internal/buildmeta.Date=" + date

# Add GOPATH/bin to PATH for installed tools

export PATH := `go env GOPATH` + "/bin:" + env("PATH")

# Default recipe
default: lint-go test

# --- Setup ---
# New contributors run this once after cloning. Idempotent: re-running
# upgrades dependencies and refreshes Vale's synced style packages.

# Set up the development environment.
setup: install-brew install-tools prek-install

# Install Homebrew dependencies from Brewfile.
install-brew:
    brew bundle check || brew bundle install

# Today that means Vale's synced style packages; grows as new
# sync-style tools land.

# Refresh non-brew tooling.
install-tools:
    vale sync

# --- Build ---
# CGO_ENABLED=0 removes the host C toolchain as a build input.
# -buildvcs=false avoids stamping VCS state, relevant when building from
# a dirty tree or a tarball, and required for bit-for-bit matches against
# CI builds. Passing a directory to `go build -o` writes one executable
# per ./cmd/* package, each named after its directory (agentcontext,
# agenthooks, agentstore).

# Build every binary into the bin directory.
build:
    CGO_ENABLED=0 go build -trimpath -buildvcs=false -ldflags "{{ ldflags }}" -o {{ bin_dir }}/ ./cmd/...

# Install every binary to GOPATH/bin
install:
    CGO_ENABLED=0 go install -trimpath -buildvcs=false -ldflags "{{ ldflags }}" ./cmd/...

# The first argument names the ./cmd/<bin> package; the rest pass
# through to it.

# Run one binary by name, e.g. `just run agentstore version`.
run bin *args:
    go run -ldflags "{{ ldflags }}" ./cmd/{{ bin }} {{ args }}

# Clean build artifacts
clean:
    rm -rf {{ bin_dir }} dist coverage.out coverage.html coverage.txt coverage.xml coverage.covdata*

# --- Format ---

# Format Go code (uses golangci-lint formatters via the pinned Docker image)
format-go *args:
    {{ golangci_lint }} fmt {{ args }}

# Rewrites in place. Pair with `fix-markdown` for semantic lint fixes.

# Format Markdown files (whitespace, list markers, code fence styles).
format-markdown *args:
    rumdl fmt {{ if args == "" { "." } else { args } }}

# Format JSON / JS / TS files in place via biome's formatter.
format-config *args:
    biome format --write {{ if args == "" { "." } else { args } }}

# In-place TOML formatter (tombi 1.2.0) — the fixer paired with `lint-toml`'s --check
# gate. Rewrites whitespace/style only; key and array order are preserved (schema-driven
# reordering is disabled in tombi.toml). Excludes and lockfile skips come from tombi.toml.
format-toml:
    tombi format

# The in-place fixer paired with `lint-shell-fmt`'s -d gate. shfmt reads
# indent width and the final-newline setting from .editorconfig, so the
# formatter and the shell gate agree without a second config file. The
# vendor/ exclusion matches `lint-shell`: those scripts belong to upstream
# and are reviewed at vendor-tidy time, not reformatted to our style. The
# .claude/ exclusion is the same idea from the other direction: those
# scripts are byte copies that `apm install` deploys from .apm/ and
# hooks/, so formatting them here would put a second writer in a tree
# the installer owns, and the sources are already covered. The
# emptiness guard keeps shfmt from falling back to reading stdin (and
# hanging) if the tree ever carries no matching script.

# Format shell scripts in place via shfmt.
[script]
format-shell:
    files=$(git ls-files '*.sh' ':!:vendor/**' ':!:.claude/**')
    if [ -n "$files" ]; then shfmt -w $files; fi

# just's formatter is still an unstable subcommand upstream. The `set
# unstable` at the top of this file already unlocks it, but both this recipe
# and `lint-just` pass --unstable explicitly so neither breaks if that
# setting is ever narrowed or dropped. The formatter is opinionated and
# rewrites the whole file, so run it deliberately rather than on save.

# Reformat this Justfile in place via just's own formatter.
format-just:
    just --fmt --unstable

# --- Fix ---
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

# Complement to `format-markdown` (which only rewrites whitespace and
# ordering, not semantic lints).

# Apply rumdl's auto-fixable rules to Markdown files.
fix-markdown *args:
    rumdl check --fix {{ if args == "" { "." } else { args } }}

# --- Lint ---
# Covers golangci-lint, the modernizer gate, the deadcode reachability
# scan, go-arch-lint layering, and actionlint. Carved out so the
# `lint-go` job in `.github/workflows/ci.yml` invokes a single recipe
# rather than enumerate the Go gates in YAML. `just lint` below composes
# from this plus the prose, spelling, Markdown, config, and YAML gates
# whose CI install paths land in follow-up workflows.

# Aggregate every Go-flavored lint gate.
lint-go-all: lint-go lint-go-modernize lint-go-deadcode lint-go-arch lint-workflows

# Aggregates the Go gates (via `lint-go-all`), prose (vale), spelling
# (cspell), Markdown (rumdl), config / JS / TS (biome), YAML (yamllint),
# TOML (tombi), shell (shellcheck + shfmt), this Justfile's own formatting
# (just --fmt), and the .editorconfig whitespace contract
# (editorconfig-checker).

# Run every linter that operates on the source tree.
lint: lint-go-all lint-prose lint-spelling lint-markdown lint-config lint-yaml lint-toml lint-shell lint-shell-fmt lint-just lint-editorconfig

# --modules-download-mode=vendor matches `just build`, so the linter
# sees exactly the dependency set the compiler does and never falls back
# to the module proxy.

# Run Go linters (golangci-lint via the pinned Docker image, vendor-mode).
lint-go *args:
    {{ golangci_lint }} run --modules-download-mode=vendor {{ args }}

# Mirrors the vendor-drift check: contributors must run `just fix-go`
# before pushing.

# Fail if `go fix` would modernize the tree.
[script]
lint-go-modernize:
    diff_output=$(go fix -diff ./... 2>&1)
    if [[ -n "$diff_output" ]]; then
        echo "go fix would modernize the tree — run 'just fix-go' and commit:" >&2
        echo "$diff_output" >&2
        exit 1
    fi

# Whole-program reachability complements the package-scoped `unused`
# linter in golangci-lint. The tool prints findings but exits 0, so any
# output is treated as failure.

# Fail if `deadcode` finds unreachable functions from the binary entry points.
[script]
lint-go-deadcode:
    output=$(go tool deadcode ./cmd/... 2>&1)
    if [[ -n "$output" ]]; then
        echo "deadcode found unreachable code — remove or justify:" >&2
        echo "$output" >&2
        exit 1
    fi

# Noisier; intentionally not part of the default `lint` gate. Run before
# wholesale refactors to surface code only kept alive by tests.

# Like lint-go-deadcode but roots reachability at every test binary too.
[script]
lint-go-deadcode-tests:
    output=$(go tool deadcode -test ./... 2>&1)
    if [[ -n "$output" ]]; then
        echo "deadcode (with -test) found unreachable code:" >&2
        echo "$output" >&2
        exit 1
    fi

# The compiler covers cycles and cross-module visibility; this catches
# the layer rules it can't (e.g., "cmd may depend on internal but not
# the reverse"). Pinned Docker image, same pattern as golangci-lint.

# Enforce intra-project layering rules from .go-arch-lint.yml.
lint-go-arch:
    {{ go_arch_lint }} check --project-path /app

# The glob excludes the LICENSE (canonical Apache 2.0 text), the
# auto-generated changelog, vale's own style packages, scratch dirs,
# vendored code, the gitignored agent worktrees under .claude/worktrees/
# (whose nested vendor trees otherwise crash vale), and the
# COMMIT_AGENTMSG draft (the `lint-commit-msg` recipe owns that one under
# the stricter commit scope); the per-file-type rules in .vale.ini decide
# what else gets inspected.

# Lint prose in Markdown files and source comments via vale.
lint-prose *args:
    vale --output=project-agent.tmpl --glob='!{LICENSE,CHANGELOG.md,.vale/*,tmp/*,vendor/*,.claude/worktrees/*,COMMIT_AGENTMSG}' {{ if args == "" { "." } else { args } }}

# Checks against the project dictionary at .cspell-words.txt. cspell
# ignores binaries, generated files, and the vendor/ tree via the
# ignorePaths block in .cspell.jsonc. The COMMIT_AGENTMSG draft gets
# excluded here and checked by `lint-commit-msg` instead, so a
# work-in-progress message never trips the tree-wide spell check.

# Check spelling across the tree.
lint-spelling *args:
    cspell --config .cspell.jsonc --no-summary --no-progress --no-must-find-files --exclude COMMIT_AGENTMSG {{ if args == "" { "." } else { args } }}

# rumdl handles structural lints (heading style, list marker style, code
# fence style); vale handles prose.

# Lint Markdown files against the project's .rumdl.toml ruleset.
lint-markdown *args:
    rumdl check {{ if args == "" { "." } else { args } }}

# Recommended ruleset, biome's own formatter; covers config files
# (biome.json, package.json, tsconfig) and any future scripts under
# .github/actions/ or tools/.

# Lint JSON / JS / TS files via biome.
lint-config *args:
    biome check --files-ignore-unknown=true {{ if args == "" { "." } else { args } }}

# --strict treats warnings as errors so the gate matches CI behavior;
# per-rule tuning lives in .yamllint.yaml.

# Lint YAML files (config, workflows, action definitions).
lint-yaml *args:
    yamllint --strict {{ if args == "" { "." } else { args } }}

# actionlint walks `.github/workflows/` by default, parses each workflow,
# and flags unknown actions, mis-typed expressions, shellcheck issues
# inside `run:` blocks, and SHA-pin drift. Complements `lint-yaml` (which
# checks YAML structure) with workflow-shape rules yamllint can't see.
# Runs from the SHA-pinned Docker image above (which bundles shellcheck),
# the same image the reusable `.github/workflows/lint-workflows.yml`
# delegates to in tbhb/github-actions, so this local entrypoint and
# the CI gate run one actionlint, both bumped by Renovate.

# Lint GitHub Actions workflow files via actionlint.
lint-workflows:
    {{ actionlint }}

# tombi is the TOML gate (tombi 1.2.0): it lint-checks every tracked *.toml.
# Cargo.toml/pyproject.toml validate offline against embedded SchemaStore schemas;
# cog.toml, .rumdl.toml, REUSE.toml, deny.toml et al. get syntax + style checks. We run
# the format gate in --check --diff mode here as well, so an unformatted TOML file fails
# `just lint` without being rewritten (`just format-toml` is the in-place fixer).
# --offline keeps CI hermetic against SchemaStore; --error-on-warnings promotes warnings
# to hard failures (matching the -D-warnings / --max-warnings=0 posture). Scope
# (include/exclude, lockfile skips, schema.strict=false) lives in tombi.toml, so this
# recipe passes NO path args — tombi walks the tree per that config. This deliberately
# departs from the sibling `*args`-default-`.` idiom because tombi centralizes scoping in
# tombi.toml rather than on the CLI, keeping excludes in one place.
lint-toml:
    tombi format --check --diff
    tombi lint --offline --error-on-warnings

# Warn when the locally installed tombi differs from the verified
# release. Advisory rather than fatal: tombi comes from Homebrew and
# moves on its own schedule, and that is fine so long as it stays
# visible rather than silently reformatting a file the gate then
# rejects.
[script]
check-tombi-version:
    local=$(tombi --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [[ "${local}" != "{{ tombi_version }}" ]]; then
        echo "warning: local tombi ${local} != verified {{ tombi_version }}" >&2
        echo "         formatting may differ from what the gate expects" >&2
    else
        echo "tombi ${local} matches the verified release"
    fi

# Covers the standalone scripts the actionlint image never opens
# (hooks/go-lint.sh, tools/fuzz.sh). The file list comes from git rather
# than a glob so untracked scratch scripts stay out of the gate, and the
# `:!:vendor/**` pathspec drops the vendored upstream scripts, which are
# reviewed at vendor-tidy time rather than held to this project's style.
# The emptiness guard matters because shellcheck with no path arguments
# reads stdin and blocks. Runs from the SHA-pinned image above, so the
# shellcheck version advances by Renovate rather than by whatever the
# contributor happens to have on PATH.

# Lint every tracked non-vendored *.sh via the pinned shellcheck image.
[script]
lint-shell:
    files=$(git ls-files '*.sh' ':!:vendor/**' ':!:.claude/**')
    if [ -n "$files" ]; then {{ shellcheck }} $files; fi

# The check-only mirror of `format-shell`: -d prints a unified diff and
# exits non-zero when shfmt would rewrite anything, so the gate reports the
# exact edit to make instead of silently reformatting a contributor's tree.
# shfmt is a host tool from the Brewfile, not a container, because it also
# backs the local pre-commit hook where a per-file docker run would dominate
# the hook's runtime.

# Fail if shfmt would reformat any tracked non-vendored *.sh.
[script]
lint-shell-fmt:
    files=$(git ls-files '*.sh' ':!:vendor/**' ':!:.claude/**')
    if [ -n "$files" ]; then shfmt -d $files; fi

# --check makes the formatter a gate: it exits non-zero and prints the
# formatted text without touching the file, leaving `just format-just` as
# the only thing that rewrites it. Worth gating because nothing else in the
# toolchain reads Justfile syntax, so drift here is otherwise invisible
# until a reviewer notices it by eye.

# Fail if `just --fmt` would reformat this Justfile.
lint-just:
    just --fmt --check --unstable

# Enforces the whitespace contract in .editorconfig (charset, line endings,
# final newline, trailing whitespace, indentation) across every tracked
# file, catching the file types no other gate here reads: the Justfile
# itself, .gitignore, .editorconfig, the Brewfile, and plain text. With no
# path arguments the checker walks the git index, so scope lives entirely in
# .editorconfig-checker.json — whose Exclude list mirrors the top-level
# `exclude:` in .pre-commit-config.yaml (vendored code, Vale's synced style
# packages, and build output) plus CHANGELOG.md, which `cog changelog`
# regenerates wholesale and which the vale hook and the prose recipes
# already skip for the same reason. The single span that cannot meet the
# contract — the container-runtime probe, whose continuation lines hang
# under the first candidate path — carries inline disable/enable markers
# rather than a tree-wide Disable entry, so indent width stays enforced
# everywhere else. The binary is spelled out in full: upstream's own
# Makefile also installs a short `ec` alias, but the Homebrew formula builds
# only `editorconfig-checker`, and the Brewfile is how this repo provisions
# the tool.

# Check every tracked file against .editorconfig via editorconfig-checker.
lint-editorconfig:
    editorconfig-checker

# Surfaces message problems while iterating rather than at commit time.
# Reads the draft from the repo-root COMMIT_AGENTMSG file (gitignored;
# see AGENTS.md for the workflow) and runs the commit-msg stage through
# prek, which fires the four shared commit-message hooks:
# commit-trailers, commitlint, vale-commit-msg, and cspell-commit-msg. The
# real gate stays the prek commit-msg hook on .git/COMMIT_EDITMSG; this
# recipe only mirrors it. Commit the validated draft with `git commit -F
# COMMIT_AGENTMSG`.

# Pre-validate a drafted commit message against the commit-msg gates.
lint-commit-msg:
    prek run --stage commit-msg --commit-msg-filename COMMIT_AGENTMSG

# --- Test ---

# Run tests
test *args:
    go test ./... "$@"

# Slower than plain `just test`; pairs with goroutine-bearing code as it
# lands. Native fuzz targets discovered by the nightly workflow rerun
# under `-race` automatically when their function-under-test is reached
# from `-race` builds; for ad-hoc local runs use this recipe.

# Run tests with the race detector.
test-race:
    go test -race ./...

# Mutation-testing timeout coefficient. Gremlins gates each mutant's
# test run at `coefficient * baseline_test_time`. The upstream
# default of 3 leaves a budget of a few hundred milliseconds for
# this project's sub-second test suites, so legitimate assertion
# kills get reclassified as TIMED OUT under any noticeable system
# load. 100 keeps the per-mutation worst case under a minute while
# producing stable LIVED-versus-KILLED labels. Override by setting
# GREMLINS_TIMEOUT_COEFFICIENT or by passing `--timeout-coefficient`
# directly to a recipe (the last value wins under pflag).

gremlins_timeout_coefficient := env("GREMLINS_TIMEOUT_COEFFICIENT", "100")

# Gremlins mutates expressions in the source under [path] (default the
# current directory), rebuilds the package, and re-runs the tests against
# each mutation. Each mutant comes back as KILLED (a test failed, meaning
# the test suite caught the change), LIVED (no test failed, meaning the
# suite missed the change), NOT COVERED (no test reaches the mutated
# line), or NOT VIABLE (mutation broke the build). LIVED and NOT COVERED
# mutants point at assertion gaps that line-coverage metrics miss. This
# is the inner-loop form. Pass a sub-package path to scope the run for
# fast iteration, the same way `go test` accepts a package argument. Run
# without arguments to mutate the whole module from the current
# directory. A later workflow under `.github/workflows/` will invoke the
# full-module form on a nightly schedule. Pinned as a `go tool` dep in
# go.mod so the mutator catalog is reproducible across machines and bumps
# land as reviewable diffs.

# Run mutation testing via gremlins.
mutate *args:
    go tool gremlins unleash --timeout-coefficient {{ gremlins_timeout_coefficient }} {{ if args == "" { "." } else { args } }}

# The nightly form, factored out so the future `mutation-nightly.yml`
# workflow has a single recipe to invoke and contributors can run the
# same scan locally before opening a release-bound PR.

# Mutate the whole module from the repository root.
mutate-all:
    go tool gremlins unleash --timeout-coefficient {{ gremlins_timeout_coefficient }} .

# Runs via tools/fuzz.sh, which lists every Fuzz* function under each
# package and runs it for the FUZZ_TIME budget (default 30s); set
# FUZZ_TIME to widen the sweep, e.g. `FUZZ_TIME=5m just fuzz`. The nightly
# workflow under `.github/workflows/` calls the same script with a longer
# FUZZ_TIME, mirroring the gremlins / mutate-all shape where one entry
# point powers both the inner loop and the scheduled sweep.

# Run native Go fuzz targets under [path] (default the entire module).
fuzz path="./...":
    tools/fuzz.sh {{ path }}

# The inner-loop coverage gate. Pair with `just mutate <path>` when
# adding tests against survivor mutants. The total threshold remains
# intentionally lower than today's measured coverage so a contributor can
# land a feature with a few new uncovered lines and tighten coverage in a
# follow-up.

# Run tests with coverage, print the per-function breakdown, and enforce the `.testcoverage.yml` thresholds.
cover:
    go test -coverprofile=coverage.out ./...
    @echo
    go tool cover -func=coverage.out | tail -n 30
    @echo
    go tool go-test-coverage --config .testcoverage.yml

# Highlights covered and uncovered regions in source view so a
# contributor can find exactly where a new test should land. Wraps
# `go tool cover -html`.

# Open the HTML coverage report.
cover-html:
    go test -coverprofile=coverage.out ./...
    go tool cover -html=coverage.out

# Cobertura is the lingua franca format coverage dashboards accept. This
# is the quick local form; CI's per-slot and combined uploads flow
# through `cover-binary` and `cover-merge` below.

# Emit a Cobertura XML report from one local text profile.
cover-cobertura:
    go test -coverprofile=coverage.out ./...
    go tool gocover-cobertura < coverage.out > coverage.xml

# CI uploads the binary covdir per matrix slot so the downstream coverage
# job can merge the slots with `go tool covdata merge` (see `cover-merge`)
# into one combined report — a merge only the binary format supports
# losslessly. The covdir is absolute because `go test` runs each
# package's binary from that package's directory, which would scatter a
# relative path.

# Run tests into [covdir] as binary coverage, then render Cobertura XML.
cover-binary covdir="coverage.covdata":
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
cover-merge slotsdir="coverage.covdata.slots":
    rm -rf coverage.covdata.merged
    mkdir -p coverage.covdata.merged
    go tool covdata merge -i="$(ls -d {{ slotsdir }}/*/ | paste -sd, -)" -o=coverage.covdata.merged
    go tool covdata textfmt -i=coverage.covdata.merged -o=coverage.out
    go tool gocover-cobertura < coverage.out > coverage.xml

# The bare check separates a CI step that runs tests itself from the
# threshold enforcement, and gives a contributor a way to re-check after
# editing `.testcoverage.yml` without rerunning the suite.

# Run only the threshold gate against an existing coverage.out.
cover-check:
    go tool go-test-coverage --config .testcoverage.yml

# --- Security ---
# govulncheck walks the call graph and reports only vulnerabilities whose
# vulnerable symbols this module actually calls — quieter than
# module-level scans and a closer match for what would show up in
# production. Pinned as a `go tool` dep in go.mod so the scanner version
# is reproducible across machines; bumped via Renovate.

# Scan the module for known vulnerabilities reachable from the binary entry points.
vuln:
    go tool govulncheck ./...

# govulncheck exits 0 in SARIF mode whether or not it finds
# vulnerabilities — the report carries them — so this recipe surfaces
# findings through Code Scanning rather than failing the run, while a
# genuine scanner failure still exits non-zero.

# Emit the govulncheck results as SARIF to <file> for the security.yml upload.
vuln-sarif file:
    go tool govulncheck -format sarif ./... > "{{ file }}"

# `gitleaks git` walks every commit's diff against the bundled
# regular-expression and entropy rule set; findings name the file, line,
# commit, and matching rule so the offending change can be located
# without re-running the scan. Brew pins the binary in the Brewfile; the
# rule set advances with `brew upgrade gitleaks`. A later workflow under
# `.github/workflows/` re-runs the same scan on every PR.

# Scan the working tree and full git history for committed secrets.
gitleaks:
    gitleaks git --verbose .

# Uses the external gomodscan tool (extracted from this repo's former
# tools/depscan and tools/malscan) to flag two supply-chain concerns:
# dependencies that pkg.go.dev marks as retracted at the pinned version
# or deprecated at the latest version (S2C2F SCA-3), and dependencies the
# OSV malicious-package registry flags as malware under the MAL- ID prefix
# (S2C2F ING-3). gomodscan reads vendor/modules.txt for the module set, so
# run `just vendor` first when it is stale. Exits 1 on findings, 2 on tool
# failure. Tracked as a `go tool` dependency pinned to v0.1.0 in go.mod;
# bump it with `go get -tool` when a new gomodscan release lands.

# Scan each vendored module for supply-chain concerns in one pass.
gomodscan:
    go tool gomodscan

# Unlike the gomodscan gate recipe, a findings exit (1) does not fail
# this recipe — Code Scanning surfaces severity downstream — but a tool
# failure (exit 2) still propagates.

# Emit the gomodscan findings as SARIF to <file> for the security.yml upload.
gomodscan-sarif file:
    #!/usr/bin/env bash
    set -uo pipefail
    go tool gomodscan -format sarif > "{{ file }}"
    rc=$?
    if [ "$rc" -gt 1 ]; then exit "$rc"; fi

# --- Dependencies ---

# Tidy go.mod
tidy:
    go mod tidy

# Verify dependencies
verify:
    go mod verify

# Vendoring makes new transitive dependencies show up as a visible diff
# at PR review time, turning the trust decision on each addition into a
# human one. The same pattern Cilium uses for its open-source CI.

# Vendor dependencies into ./vendor.
vendor:
    go mod tidy
    go mod vendor

# CI runs this on every PR; contributors run `just vendor` and commit
# the result.

# Check that vendor/, go.mod, and go.sum are in sync.
vendor-check:
    #!/usr/bin/env bash
    set -euo pipefail
    go mod tidy
    go mod vendor
    if ! git diff --exit-code -- go.mod go.sum vendor/; then
        echo "vendor drift detected — run 'just vendor' and commit" >&2
        exit 1
    fi

# --- Aggregators ---
# Composed quality gates so a contributor hits one recipe instead of
# chaining the underlying single-purpose recipes from memory. Each
# aggregator names its dependencies and adds no extra logic, so any
# failure points at the actual gate that fired rather than at the
# wrapper. tidy normalizes go.mod / go.sum first so the rest of the gate
# sees the canonical dependency set; vendor-check at the end catches any
# drift the rest of the gate introduced.

# Fast quality bar for save-time and routine pre-push runs.
check: tidy verify lint test vuln vendor-check

# Layers the race detector, the inner-loop fuzz sweep (30 seconds per
# target by default; override via FUZZ_TIME), and the full-history
# gitleaks scan on top of `check`. Slower than `check` by minutes rather
# than seconds, so kept off the inner-loop path.

# Comprehensive quality bar for release-prep sweeps.
check-all: check test-race fuzz gitleaks

# Pairs govulncheck with the gomodscan and gitleaks scanners so a future
# `security.yml` workflow under `.github/workflows/` invokes one recipe
# rather than enumerate the scanner set in YAML.

# Security-only sub-aggregator.
security: vuln gomodscan gitleaks

# --- Utilities ---

# Print version information
version:
    @echo "Version: {{ version }}"
    @echo "Commit:  {{ commit }}"
    @echo "Date:    {{ date }}"

# Run once after cloning the repo, and whenever .vale.ini's Packages list
# changes. CI runs this before `just lint-prose`.

# Sync Vale styles and dictionaries.
vale-sync:
    vale sync

# Run pre-commit hooks on changed files (the everyday invocation).
prek:
    prek

# Useful after a hook config change or before a release sweep.

# Run pre-commit hooks on every file in the tree.
prek-all:
    prek run --all-files

# Installs the commit-msg, pre-commit, pre-push, and post-commit hooks.
# `just setup` runs this for new contributors; run it directly to
# reinstall the hooks without the rest of setup. Installing hooks
# modifies .git/.
#
# post-commit carries one hook, clear-commit-agentmsg, which removes the
# COMMIT_AGENTMSG draft once a commit lands. Skip that stage and drafts
# accumulate across commits, which is how an agent ends up committing a
# message it wrote for an earlier change.

# Install the project's pre-commit hooks.
prek-install:
    prek install -t commit-msg -t pre-commit -t pre-push -t post-commit

# `cog changelog` emits Markdown without an H1; the pipeline prepends one,
# writes the file, then lints it in place so the CHANGELOG.md
# per-file-ignores in .rumdl.toml apply (rumdl matches those globs against
# on-disk paths, not stdin). MD024 (duplicate headings) lives there.

# Generate the full CHANGELOG.md from Conventional Commit history.
generate-changelog:
    cog changelog | { echo "# Changelog"; cat; } > CHANGELOG.md
    rumdl check --fix CHANGELOG.md

# Useful during release prep to see what `cog changelog` will emit before
# committing the regeneration.

# Preview the changelog entries since the last tagged release.
preview-changelog:
    cog changelog --at $(git describe --tags)..HEAD -t full_hash | rumdl check -d MD041 --fix --stdin

# Pass a version, or omit it for HEAD. Output goes to stdout; pipe to a
# file or paste into the GitHub release body. MD041 is disabled for the
# heading-less fragment; without --isolated, MD013 stays off via
# .rumdl.toml so the full commit hashes are never wrapped.

# Generate release notes for a specific version.
[script]
generate-release-notes version="":
    v=$([[ -n "{{ version }}" ]] && echo "v{{ version }}" || echo "..$(git rev-parse HEAD)")
    cog changelog --at $v -t full_hash | rumdl check -d MD041 --fix --stdin
