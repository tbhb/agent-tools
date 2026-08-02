# Agent instructions

Guidance for AI coding agents working in this repository. Read it alongside the per-tool documentation and any memory files the harness loads.

## Commit messages

Run the `commit` skill. It owns the whole sequence, from choosing the rebase base through the commit and the rebase that follows, and this section only summarizes it.

Draft every commit message in the repo-root file `COMMIT_AGENTMSG` before you run `git commit`. A gitignore entry keeps that file out of history, and the post-commit hook deletes it after the commit succeeds, so each commit starts from a blank scratchpad.

1. Group the outstanding work into atomic commits, and stage the paths for one of them by name. Never `git add -A` or `git add .`.
2. Write the full message (subject, body, and trailers) to `COMMIT_AGENTMSG`. The body explains why the change exists, because the diff already says what changed.
3. Review the draft with the `review-commit-message` skill, which runs as an independent agent.
4. Run `just lint-commit-msg` and resolve whatever it reports.
5. Confirm the message with the operator, then commit the validated draft with `git commit -F COMMIT_AGENTMSG`.

`just lint-commit-msg` mirrors the commit-msg hook:

- vale under the commit scope, which catches AI commit tells via `ai-tells-commits`
- cspell with the commit dictionary
- commitlint for the Conventional Commits shape
- commit-trailers for trailer order

Running it while drafting surfaces problems early, rather than at the commit-msg hook where a late failure interrupts the commit.

The prek commit-msg hook on `.git/COMMIT_EDITMSG` stays the real gate. `COMMIT_AGENTMSG` and its recipe only preview that gate, so a clean recipe run predicts a clean commit but never replaces the hook.

The skill's frontmatter carries a pair of guard hooks, scoped to a commit workflow and inert outside one. One refuses whole-tree staging, an inline `-m` message, and `--no-verify`. The other records which bytes `review-commit-message` signed off on, and blocks the commit when the draft has changed since. Editing the draft after the review means running the review again.

## Prose lint output

`just lint-prose` and the prek vale hook already emit the agent output template, which this repository tracks at `.vale/config/templates/project-agent.tmpl` next to the `project` style rules. It prints one self-contained line per finding (location, severity, rule, the exact matched text, and the replacement when the rule carries one) plus a totals line, so you can fix every finding without follow-up searching. Pass `--output=project-agent.tmpl` yourself only when you invoke vale directly. Empty output means a clean run, and the exit code carries the result.

## Never hard-wrap Markdown

Every Markdown paragraph in this repository occupies one line, leaving the renderer to decide where prose breaks. Hard wrapping belongs to commit messages and to comments in code or config, each with its own gate.

`cmd/check-markdown` enforces it. A prek hook runs it over `*.md`. A Claude `PreToolUse` hook runs it against a `Write` or `Edit` and denies the call before wrapped prose reaches disk. `just lint-markdown-wrap` runs it in the verification stack, and `just fix-markdown-wrap` collapses paragraphs someone already wrapped.

Copy this shape for the next rule.

`internal/markdown` holds the rule itself, `internal/hookio` the payload decoding and deny envelope every check shares, and `cmd/check-markdown` a thin layer of glue over the two. Keep the glue thin for a concrete reason. `.testcoverage.yml` excludes `main.go` and nothing else, so logic placed there goes unmeasured. Shared plumbing living in its own package also means a second check writes only its own rule. Give each check a standalone binary, and `agenthooks` stays a dispatcher instead of accumulating one subcommand per rule.

APM can deploy a hook's executable. A package-root `hooks/` directory lands under `.claude/hooks/<package>/hooks/`, which a declaration then references through `${CLAUDE_PLUGIN_ROOT}`. The `go-lint` hook reaches consumers that way. `check-markdown` takes the other route on purpose: `go install` puts it on PATH, so the declaration names a bare command and no file has to travel beside it.

## Recipe naming

Recipes that operate on one source language carry a `-go` or `-py` suffix, and the bare name aggregates both: `just test` runs `test-go` and `test-py`, and so do `cover`, `mutate`, and `fuzz`. Reach for the suffixed form while iterating on one language, and the bare form before pushing. Lint gates follow the same shape through `lint-go-all` and `lint-py-all`, which `just lint` composes.

Python tooling covers `packages/`. It came from `proofhouse/proofhouse-python-tool`, dropping the gates that need an installable package. Because `pyproject.toml` declares a virtual project (`package = false`), `import-linter` contracts, a wheel build, and a generated build stamp have nothing to act on here. `lint-reuse` is absent for a different reason. REUSE compliance spans every file type in the tree. Adopting it needs a whole-tree sweep plus a `REUSE.toml` and `LICENSES/`, so that work belongs in its own change.

The `[tool.pyrefly.errors]` table pins every diagnostic kind pyrefly knows. That catalog is version-specific, and an unknown name fails the entire config load, so regenerate the table on every pyrefly bump. Naming an unknown kind makes pyrefly print the full list of accepted values.

## Verifying Claude Code behavior

The public Claude Code docs don't always match the installed version. When the behavior of a hook or harness feature matters (which events fire, in what order, whether an event can block, what its stdin payload carries), confirm it against the installed `claude` binary rather than trusting the docs or prior memory.

Probe it with a throwaway project instead of reasoning about it:

1. Create a scratch project under a temporary path with its own `.claude/settings.json`.
2. Register a small logging hook on the events in question. Have it read stdin and append `hook_event_name` plus the fields you care about to a log file.
3. Drive it headless: `claude -p "<prompt that triggers the tools>" --permission-mode bypassPermissions --model haiku < /dev/null`.
4. Read the log to see what fired.

The preceding probe settled a question for this repo's hook: `PostToolUse` fires once per tool call and carries `tool_input.file_path`, while `PostToolBatch` fires once per batch (a lone call still counts as a batch) and carries no per-tool fields.

Against Claude Code 2.1.220, a later probe settled the questions the commit skill's guard hooks rest on. Frontmatter hooks in a `SKILL.md` file do fire, and `${CLAUDE_PROJECT_DIR}` expands inside the `command`. Exiting 2 from a `PreToolUse` hook blocks the call from that scope, same as from one configured in settings. For the Skill tool, the `PostToolUse` payload names the invoked skill at `tool_input.skill`, and carries no `tool_input.skill_name` of the kind the published reference describes.
