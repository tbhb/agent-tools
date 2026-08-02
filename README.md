# agent-tools

Shared agent tooling for tbhb repositories. The repo provides Go command-line tools for agent harnesses, plus the shared [APM](https://microsoft.github.io/apm) package of agent primitives.

## APM package

Repositories across tbhb install the shared primitives with the [APM CLI](https://microsoft.github.io/apm/quickstart/):

```bash
apm install tbhb/agent-tools#v0.1.0
```

The package deploys these primitives from [`.apm/`](.apm/):

| Primitive | Type | Purpose |
| --- | --- | --- |
| `commit` | skill | Group changes into one atomic commit, draft the message in `COMMIT_AGENTMSG`, review and lint it, confirm it, then commit and rebase. |
| `review-commit-message` | skill | Review a drafted message against the staged diff as an independent agent, for what linting can't see. |
| `worktree-wip` | instructions | Stash and work-in-progress rules for repos that run more than one agent worktree session. |
| `go-lint` | hook | Format on edit, lint per batch, and block the agent from finishing on an outstanding finding. |
| `guard-markdown` | hook | `PreToolUse` gate on `Write` and `Edit` that refuses Markdown whose paragraphs span more than one line. |

This repo dogfoods its own package: `apm install` deploys the primitives into the local harness layout, and CI rejects drift between `.apm/` sources and the deployed copies.

## Checks

A check is one rule enforced everywhere it matters. The same binary answers to all three callers, so the rule can't drift between them:

| Caller | Invocation |
| --- | --- |
| Claude `PreToolUse` | `guard-markdown --hook` reads the payload on stdin and denies the `Write` or `Edit` |
| pre-commit | `guard-markdown FILES` reports the offending line ranges and exits nonzero |
| verification stack | the same command from a `just` recipe, alongside the other linters |

[`.pre-commit-hooks.yaml`](.pre-commit-hooks.yaml) publishes the pre-commit leg:

```yaml
repos:
  - repo: https://github.com/tbhb/agent-tools
    rev: v0.1.1
    hooks:
      - id: guard-markdown
```

Note that the two legs install separately. prek builds its own copy from `language: golang`. The Claude hook instead resolves `guard-markdown` on PATH, which comes from `go install`. A consumer wanting both adds the hook and runs the install.

Pass `--fix` to collapse paragraphs someone already wrapped.

## Go tools

Each tool under [`cmd/`](cmd/) builds as a standalone binary:

- `agenthooks` manages shared agent hooks.
- `agentstore` stores shared agent state.
- `agentcontext` assembles shared agent context.
- `guard-markdown` refuses Markdown whose paragraphs span more than one line.

Install one directly:

```bash
go install github.com/tbhb/agent-tools/cmd/agenthooks@latest
```

Or build everything from a checkout:

```bash
just build
```

## Development

`just` drives the workflow: `just lint` runs the full lint suite, `just test` runs the tests, and `just build` compiles the binaries into `bin/`. See the [Justfile](Justfile) for the complete recipe list, and [AGENTS.md](AGENTS.md) for the agent-facing contributor guide.

## Releases

[cocogitto](https://github.com/cocogitto/cocogitto) cuts `vX.Y.Z` tags from the Conventional Commit history. One tag serves both consumer paths, with APM installs pinning `tbhb/agent-tools#vX.Y.Z` and Go installs pinning `@vX.Y.Z`.

## Python

[`packages/agent-tools-py`](packages/agent-tools-py) holds the Python side, kept deliberately small for now. Its gates run through `just lint-py-all` and `just cover-py`, which enforce ruff at its full ruleset, pyrefly's strict preset, and 100% branch coverage. `uv sync` provisions everything from `uv.lock`.

## License

Apache-2.0. See [LICENSE](LICENSE).
