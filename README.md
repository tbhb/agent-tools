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

This repo dogfoods its own package: `apm install` deploys the primitives into the local harness layout, and CI rejects drift between `.apm/` sources and the deployed copies.

## Go tools

Each tool under [`cmd/`](cmd/) builds as a standalone binary:

- `agenthooks` manages shared agent hooks.
- `agentstore` stores shared agent state.
- `agentcontext` assembles shared agent context.

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

## License

Apache-2.0. See [LICENSE](LICENSE).
