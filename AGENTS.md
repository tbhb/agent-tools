# Agent instructions

Guidance for AI coding agents working in this repository. Read it alongside the per-tool documentation and any memory files the harness loads.

## Commit messages

Draft every commit message in the repo-root file `COMMIT_AGENTMSG` before you run `git commit`. A gitignore entry keeps that file out of history, so it serves purely as a scratchpad for iterating on the message.

1. Write the full message (subject, body, and trailers) to `COMMIT_AGENTMSG`.
2. Run `just lint-commit-msg` and resolve whatever it reports.
3. Commit the validated draft with `git commit -F COMMIT_AGENTMSG`.

`just lint-commit-msg` mirrors the commit-msg hook:

- vale under the commit scope, which catches AI commit tells via `ai-tells-commits`
- cspell with the commit dictionary
- commitlint for the Conventional Commits shape
- commit-trailers for trailer order

Running it while drafting surfaces problems early, rather than at the commit-msg hook where a late failure interrupts the commit.

The prek commit-msg hook on `.git/COMMIT_EDITMSG` stays the real gate. `COMMIT_AGENTMSG` and its recipe only preview that gate, so a clean recipe run predicts a clean commit but never replaces the hook.

## Prose lint output

`just lint-prose` and the prek vale hook already emit the agent output template, which this repository tracks at `.vale/config/templates/project-agent.tmpl` next to the `project` style rules. It prints one self-contained line per finding (location, severity, rule, the exact matched text, and the replacement when the rule carries one) plus a totals line, so you can fix every finding without follow-up searching. Pass `--output=project-agent.tmpl` yourself only when you invoke vale directly. Empty output means a clean run, and the exit code carries the result.

## Verifying Claude Code behavior

The public Claude Code docs don't always match the installed version. When the behavior of a hook or harness feature matters (which events fire, in what order, whether an event can block, what its stdin payload carries), confirm it against the installed `claude` binary rather than trusting the docs or prior memory.

Probe it with a throwaway project instead of reasoning about it:

1. Create a scratch project under a temporary path with its own `.claude/settings.json`.
2. Register a small logging hook on the events in question. Have it read stdin and append `hook_event_name` plus the fields you care about to a log file.
3. Drive it headless: `claude -p "<prompt that triggers the tools>" --permission-mode bypassPermissions --model haiku < /dev/null`.
4. Read the log to see what fired.

The preceding probe settled a question for this repo's hook: `PostToolUse` fires once per tool call and carries `tool_input.file_path`, while `PostToolBatch` fires once per batch (a lone call still counts as a batch) and carries no per-tool fields.
