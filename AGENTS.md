# Agent instructions

Guidance for AI coding agents working in this repository. Read it alongside the per-tool documentation and any memory files the harness loads.

## Commit messages

Run the `commit` skill. It owns the whole sequence, from choosing the rebase base through the commit and the rebase that follows, and this section only summarizes it.

Draft every commit message in the repo-root file `COMMIT_AGENTMSG` before you commit. A gitignore entry keeps that file out of history, and the post-commit hook deletes it after the commit succeeds, so each commit starts from a blank scratchpad.

1. Group the outstanding work into atomic commits, and stage the paths for one of them by name. Never `git add -A` or `git add .`.
2. Write the full message (subject, body, and trailers) to `COMMIT_AGENTMSG`. The body explains why the change exists, because the diff already says what changed.
3. Review the draft with the `review-commit-message` skill, which runs as an independent agent.
4. Run `mise run lint-commit-msg` and resolve whatever it reports.
5. Confirm the message with the operator, then commit the validated draft through `.claude/skills/commit/scripts/commit.sh`.

`mise run lint-commit-msg` mirrors the commit-msg hook:

- vale under the commit scope, which catches AI commit tells via `ai-tells-commits`
- cspell with the commit dictionary
- commitlint for the Conventional Commits shape
- commit-trailers for trailer order

Running it while drafting surfaces problems early, rather than at the commit-msg hook where a late failure interrupts the commit.

The prek commit-msg hook on `.git/COMMIT_EDITMSG` stays the real gate. `COMMIT_AGENTMSG` and its recipe only preview that gate, so a clean recipe run predicts a clean commit but never replaces the hook.

That script is the only thing here that commits. It checks the review signature, records what the index holds, commits, then reads the commit back and prints any staged path missing from it. prek stashes and restores the worktree around the pre-commit hooks, so a failed attempt can leave a path unstaged that you staged before it, and without that comparison the retry commits part of the group and reports nothing.

The skill's frontmatter carries a pair of hooks, scoped to a commit workflow and inert outside one. Preflight arms them at the commit `HEAD` sits on, and the commit that ends the workflow moves `HEAD` past that mark and stands them down. One refuses whole-tree staging along with any `git commit` written out by hand, which is what keeps the script the only entry point. The other records which bytes `review-commit-message` signed off on. Editing the draft after the review means running the review again.

## Pull requests

Run the `pr` skill. It owns drafting the description, the review, and the publish, and it routes what follows to three sibling skills. This section only summarizes them.

Draft every pull request description in the repo-root file `PR_AGENTDESC.md`, which a gitignore entry keeps out of history. The commit draft dies at the commit. This one outlives the publish, remaining the working copy of the description for as long as the pull request stays open, and `merge-pr` removes it once the branch merges. A leftover draft that no open pull request stands behind has gone stale, so the `pr` preflight removes it rather than letting the next run inherit abandoned text.

The file carries three things the template can't. YAML frontmatter holds the pull request properties, a level 1 heading holds the title, and the rest fills in the sections from `.github/pull_request_template.md`.

1. Draft the description, with a title in the Conventional Commits shape. A squash merge turns that title into the commit subject on the default branch.
2. Review the draft with the `review-pr-description` skill, which runs as an independent agent.
3. Run `mise run lint-pr-description` and resolve whatever it reports.
4. Confirm with the operator, then publish through `.claude/skills/pr/scripts/create-pr.sh`.

`mise run lint-pr-description` runs a mechanical validator plus vale and cspell. The validator is offline and settles only what looking can settle:

- the frontmatter shape, its known keys, and a label the pull request actually carries
- the title's Conventional Commits form, its bounds, and whether its type appears among the commits that would land
- the template's sections, their order, and any left empty
- instructional comments that survived, unclosed fences, and links pointing nowhere
- whether every path the description puts in backticks exists in the tree or the branch diff

Each finding names a line and the fix, so resolving one means opening the draft at that point rather than searching it.

The rest of the lifecycle splits into three skills, each usable on its own:

- `watch-pr` waits for the checks. It streams one event per check through the `Monitor` tool, so a wait costs one turn rather than one per look.
- `fix-pr` diagnoses a red pull request. One call reads the failing logs and names the local task reproducing each failure.
- `merge-pr` squash merges under a message this toolchain writes. Its briefing script prints the published description, every commit the squash collapses, and the diffstat, then leaves a `SQUASH_AGENTMSG` skeleton whose body the agent writes. That message then goes through `review-squash-message` and `mise run lint-squash-msg`, and past a confirmation, before the merge clears both drafts. It also works on a pull request nobody here authored, a dependency bump being the usual case.

Left alone, GitHub writes the squash message by concatenating every commit on the branch. That text has never passed a commit-msg hook, and nothing lints it afterwards, so `merge-pr` writes the message instead.

Each of these skills carries guard hooks in its frontmatter, scoped to the workflow and inert outside one. The `gh pr` guards work by allowlist: reading through `list`, `view`, `diff`, `status`, and `checks` stays open, and everything that changes a pull request goes through the wrapping script. Naming the read-only verbs rather than the mutating ones means a verb `gh` grows later arrives already covered. `watch-pr` and `fix-pr` refuse the narrower set of forms their own scripts wrap.

A skill's hooks outlive the turn that invoked it, so more than one of these guards is often live at once. The `pr` and `merge-pr` guards share one allowlist so they agree wherever both run. `watch-pr` and `fix-pr` claim only the narrower forms their own scripts wrap, because a broader claim there would refuse a sibling's legitimate calls.

## Moving a branch onto its base

Run the `rebase` skill. It picks the base the way the commit preflight does, then replays the branch under pinned settings and checks what came out.

Conflicts route to `resolve-rebase-conflicts`, which classifies each path before anything edits it. The commit skill rebases at the end of its own run, and for a clean replay that's the whole story. Reach for these two when that rebase stops, when the branch needs moving without a commit in hand, or when `pr`, `fix-pr`, or `merge-pr` reports the branch behind its base.

A rebase that ends without complaint has proved that every commit applied and nothing else. A resolution can drop a hunk. The commit still applies under a message describing work it no longer does, and no gate notices. Comparing the branch against its pre-rebase self through `range-diff` is what catches it. Another failure mode leaves every commit intact and breaks the tree anyway: main adds a gate while the branch adds a file that gate rejects. Neither side was red alone. Since that combination first exists after the rebase, verification runs the gates against the finished tree.

Most conflicts here need no judgement. `.cspell-words.txt` and the vale vocabulary are append-only sorted lists where the union of both sides is the answer every time, so the skill settles them and then proves the result is exactly that union. Generated files declare themselves in `.gitattributes`:

```text
apm.lock.yaml rebase-resolve=regenerate
**/skills/*/tokens.json rebase-resolve=regenerate
```

A path marked that way resolves by taking one side whole, because the generator overwrites it afterwards. Once the rebase finishes, run `mise run skill-tokens` and then `apm install`, in that order. Measuring writes the token counts under `.apm/`, and installing deploys them and records their hashes, so the reverse order leaves the lockfile describing files that changed after it read them. Commit what the two of them rewrite.

`conflict-markers=documented` is the companion attribute, for a file carrying marker-shaped lines as its subject rather than its damage. The resolve skill's own `SKILL.md` carries a built-in exemption, so no consumer meets that false alarm.

Never a bare `git stash pop` around any of this. `.claude/rules/worktree-wip.md` explains why, and the guard hook refuses it.

## Prose lint output

`mise run lint-prose` and the prek vale hook already emit the agent output template, which arrives with the `ai-tells` package: `vale sync` writes it to `.vale/config/templates/ai-tells-agent.tmpl`. It prints one self-contained line per finding (location, severity, rule, the exact matched text, and the replacement when the rule carries one) plus a totals line, so you can fix every finding without follow-up searching. Pass `--output=ai-tells-agent.tmpl` yourself only when you invoke vale directly. Empty output means a clean run, and the exit code carries the result. An exit code higher than 1 marks a vale that failed rather than one that found nothing.

That template is a published interface rather than a convenience. The scoping probes in `fix-prose` and `write-prose-fix` count its finding lines with `grep -c '^[0-9]'`, and the replacement probe reads its `replace_with=` field, so reshaping either one is a breaking change for this repository and for every consumer reading the output. Nothing here should reintroduce a repo-local template under a different name. The earlier private copy resolved only in this tree, which left those probes broken wherever that name was absent.

## Never hard-wrap Markdown

Every Markdown paragraph in this repository occupies one line, leaving the renderer to decide where prose breaks. Hard wrapping belongs to commit messages and to comments in code or config, each with its own gate.

`cmd/guard-markdown` enforces it. A prek hook runs it over `*.md`. A Claude `PreToolUse` hook runs it against a `Write` or `Edit` and denies the call before wrapped prose reaches disk. `mise run lint-markdown-wrap` runs it in the verification stack, and `mise run fix-markdown-wrap` collapses paragraphs someone already wrapped.

A `CHANGELOG.md` is exempt in every one of those modes. The match is exact, on the base name alone, so a changelog under any directory qualifies and nothing else does. A generator writes it from commit messages, which are hard-wrapped under their own gate, so the wrapping arrives with the content and unwrapping it by hand holds only until the next release. `internal/markdown` holds the exemption in a constant, so it reaches every consumer repo and no repo can decline it. A second exception is the point at which that becomes declarative configuration instead. The vale gate already skips the same file through a glob in `mise run lint-prose`.

Copy this shape for the next rule.

`internal/markdown` holds the rule itself, `internal/hookio` the payload decoding and deny envelope every check shares, and `cmd/guard-markdown` a thin layer of glue over the two. Keep the glue thin for a concrete reason. `.testcoverage.yml` excludes `main.go` and nothing else, so logic placed there goes unmeasured. Shared plumbing living in its own package also means a second check writes only its own rule. Give each check a standalone binary, and `agenthooks` stays a dispatcher instead of accumulating one subcommand per rule.

APM can deploy a hook's executable. A package-root `hooks/` directory lands under `.claude/hooks/<package>/hooks/`, which a declaration then references through `${CLAUDE_PLUGIN_ROOT}`. Nothing here takes that route now, so the directory is absent. `guard-markdown` takes the other one: `go install` puts it on PATH, so the declaration names a bare command and no file has to travel beside it.

## Tasks

mise pins the toolchain and holds most task definitions. `mise.toml` has the repo-specific pins and tasks, and it selects the shared payload this repository dogfoods: the conf.d drop-ins plus the task files under `.repotools/tasks/`, which vendir syncs into every consumer at the same paths. The tree commits both lockfiles, and `repotools:check-toolchain` gates the installed set against them.

That selection runs in both directions. This repository publishes `vendir.toml` and `pins.toml` without including either, because both act on pins a consumer carries and the publisher has none. Nothing here declares a `vendir.yml` to sync or a `tbhb/repotools` reference to move. `pins.toml` holds the pair a consumer uses to change releases. `repotools:update-pins <version>`, aliased `repotools:update`, rewrites all nine sites and then runs the sync, the lockfile refresh, the install, and the APM redeploy. `repotools:check-pins` reads the nine sites and fails when they disagree. A consumer names the file in its own `[task_config] includes` and adds `check-pins` to its own `lint` task.

No Justfile survives. The last recipes to leave were the Go test and coverage family, held back because the CI matrix runs them on Windows and nobody had checked mise there. A probe on windows-2025 found it running a bash-shebang body under Git Bash and resolving its own go pin, which retired both the recipes and the `actions/setup-go` step feeding them. The delegation recipes went with them once the published skills learned to spell their gates `mise run <task>`. The committed `tools/mise-bootstrap` shim still stands in for mise wherever PATH has none, and the prek hooks run through it.

Tasks that operate on one source language carry a `-go` or `-py` suffix, and the bare name aggregates both: `mise run test` runs `test-go` and `test-py`, and so do `cover`, `mutate`, and `fuzz`. Reach for the suffixed form while iterating on one language, and the bare form before pushing. Lint gates follow the same shape through `lint-go-all` and `lint-py-all`, which `mise run lint` composes. A bare-name task lists its members in an ordered `run` array rather than in `depends`, because `depends` runs in parallel and interleaves the linters' findings, which defeats the one-line-per-finding output template.

Python tooling covers `packages/`. It came from `proofhouse/proofhouse-python-tool`, dropping the gates that need an installable package. Because `pyproject.toml` declares a virtual project (`package = false`), `import-linter` contracts, a wheel build, and a generated build stamp have nothing to act on here. `lint-reuse` is absent for a different reason. REUSE compliance spans every file type in the tree. Adopting it needs a whole-tree sweep plus a `REUSE.toml` and `LICENSES/`, so that work belongs in its own change.

The `[tool.pyrefly.errors]` table pins every diagnostic kind pyrefly knows. That catalog is version-specific, and an unknown name fails the entire config load, so regenerate the table on every pyrefly bump. Naming an unknown kind makes pyrefly print the full list of accepted values.

## Releases

The release happens in CI and nowhere else. `.github/workflows/release.yml` runs on dispatch. It mints an app token and runs `cog bump`, then SSH-signs the tag with a repository secret under the tagger identity GitHub verifies that key against.

No local command reproduces that, so this repository has no bump-version task and no local tagging path. Cocogitto owns the version and derives it inside CI, and a second bumper on a development box would be a second source for one number.

Three repo-local tasks stand around that workflow. They're primitives rather than a workflow of their own, and no orchestrator composes them yet: the sequencing stays with the operator until they have run against a few real releases. Each exits non-zero on failure. None prompts for anything, and none fixes anything. Readiness reports rather than cleaning the tree or moving a literal, because nobody can run a primitive that mutates on the way to an answer just to ask a question.

- `mise run check-repotools-release-readiness` runs before a dispatch. It checks that `HEAD` is on main, the working tree is clean, the branch is current with origin, the checks on `HEAD` are green, the version literals name the latest tag, and the changelog previews. `check-all` is deliberately absent from that list, because it reaches `tidy`, and a preflight composing `go mod tidy` would rewrite `go.mod` on its way to an answer. The checks-green probe covers the same gates by asking GitHub what they concluded about this exact commit, which is the better answer anyway: it came from a clean runner on every platform in the matrix. Run `check-all` by hand where a local sweep is what you want. Readiness also prints the version `cog bump --auto` would derive. That number comes from the Conventional Commit types since the last tag, so a run of fixes and chores yields a patch where the operator wanted a minor, and #25 exists because nobody saw that difference until after the tag.
- `mise run release-repotools [X.Y.Z]` dispatches the workflow and passes the version through, or omits it for the automatic path. It refuses where readiness fails. It stays thin deliberately. The target for release management here is a continuously updated release pull request whose merge tags and publishes. Under that model releasing is merging, so this is the piece that gets superseded while the other two survive.
- `mise run verify-repotools-release [vX.Y.Z]` runs after the workflow run finishes. Its sharp assertion is that the tag carries an annotation and a signature rather than merely existing, because cog drives libgit2 and can only make a lightweight tag, which `push --follow-tags` leaves behind silently. The workflow deletes and re-creates the tag signed to compensate, so a check asking only whether the tag exists would pass in exactly the case that workaround exists for. The bump also runs under `--skip-ci`, which leaves this task as the only thing reading the release commit before consumers pin it.

The tag is the whole release. Every consumer resolves the ref directly through apm, the Go module proxy, a `.pre-commit-config.yaml` rev, or a workflow pin, so this repository publishes no GitHub Release object, release assets, or built artifacts. Verification looks for none of those, and finding none is the correct answer rather than a gap.

`mise run check-versions` is the fourth piece and the only one `mise run lint` composes. `cog.toml`'s `pre_bump_hooks` rewrite six published version literals during a bump, and that task is the witness that they did. It carries no prefix because it gates a tree rather than releasing a product, which is what the `repotools` qualifier on the other three marks.

## Verifying Claude Code behavior

The public Claude Code docs don't always match the installed version. When the behavior of a hook or harness feature matters (which events fire, in what order, whether an event can block, what its stdin payload carries), confirm it against the installed `claude` binary rather than trusting the docs or prior memory.

Probe it with a throwaway project instead of reasoning about it:

1. Create a scratch project under a temporary path with its own `.claude/settings.json`.
2. Register a small logging hook on the events in question. Have it read stdin and append `hook_event_name` plus the fields you care about to a log file.
3. Drive it headless: `claude -p "<prompt that triggers the tools>" --permission-mode bypassPermissions --model haiku < /dev/null`.
4. Read the log to see what fired.

The preceding probe settled a question for this repo's hook: `PostToolUse` fires once per tool call and carries `tool_input.file_path`, while `PostToolBatch` fires once per batch (a lone call still counts as a batch) and carries no per-tool fields.

Against Claude Code 2.1.220, a later probe settled the questions the commit skill's guard hooks rest on. Frontmatter hooks in a `SKILL.md` file do fire, and `${CLAUDE_PROJECT_DIR}` expands inside the `command`. Exiting 2 from a `PreToolUse` hook blocks the call from that scope, same as from one configured in settings. For the Skill tool, the `PostToolUse` payload names the invoked skill at `tool_input.skill`, and carries no `tool_input.skill_name` of the kind the published reference describes.
