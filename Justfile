set positional-arguments

# What is left in this file, and why.
#
# mise.toml and the drop-ins under .config/mise/conf.d/ hold the
# toolchain and every gate that runs a pinned binary. What is left here
# is delegation and nothing else. The APM primitives in
# .claude/ spell their gates `just <recipe>`; three of them refuse to
# run when the recipe is absent. Each recipe below forwards to the mise
# task of the same name through the committed bootstrap shim, so the
# pinned mise runs even on a machine that has none.
#
# Everything else moved. The container-pinned gates went first: their
# images were a digest-pinning mechanism rather than an isolation
# choice, and mise.lock pins digests now. The Go test and coverage
# recipes went last, once a probe showed mise running a bash-shebang
# body on the Windows runner they were held back for. Run `mise tasks`
# for the full set.

# The committed shim from `mise generate bootstrap`. It installs the
# pinned mise only if absent, then execs it with every argument, so these
# recipes run the pinned mise rather than whatever is on PATH.

mise := "tools/mise-bootstrap"

# Default recipe
default: lint-go test

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
    {{ mise }} run repotools:gitleaks

# AGENTS.md and the rebase workflow spell these two by their just names.
skill-tokens *args:
    {{ mise }} run skill-tokens {{ args }}

fix-markdown-wrap:
    {{ mise }} run fix-markdown-wrap

# The apm-package workflow's failure message names this recipe as the fix.
apm-sync:
    {{ mise }} run apm-sync
