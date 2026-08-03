#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = []
# ///
"""Report which tool calls each skill made, from the Claude Code transcripts.

Claude Code stamps every assistant record with `attributionSkill`, naming the
skill whose instructions were loaded in that context when the model produced
the record. Tool calls live in those records as `tool_use` blocks, so the
field correlates a call to the skill that made it without any instrumentation
on our side.

That is what makes a preflight script measurable. A skill that hands its
agent the inputs up front should show a short, flat run: the preflight, then
the work. A skill that leaves the agent to gather its own inputs shows the
gathering, one `cat` and `grep` and `gh pr diff` at a time. Counting those
calls per run says whether a preflight earned its place, and comparing the
same skill on either side of the commit that added one says whether it
helped.

Two shapes of run exist and both are covered:

  - A forked skill (`context: fork`) runs as a subagent with its own
    transcript under `<session>/subagents/`. Its file is the run boundary, so
    per-run figures for these are exact.
  - An in-context skill loads into the calling session, and attribution is
    stamped there too. It flips on the first record after the `Skill` call and
    holds until another in-context skill loads or the user prompts again, so
    a run is the span between two flips. The start is exact and the end is
    not: work the session did after the skill's last step, but before
    anything displaced it, still carries the skill's name. Read per-run
    figures for these as an upper bound.

A session that was relocated (a renamed repository, say) appears under both
the old and the new project directory. Records are deduplicated on
(sessionId, uuid), so a relocated session counts once.

The field arrived in Claude Code 2.1.220. Records from earlier versions carry
no attribution at all and are reported as unattributed rather than guessed
at.
"""

import argparse
import json
import os
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Iterator

DEFAULT_PROJECTS = Path.home() / ".claude" / "projects"

# One tool call, flattened. Every value is a string so a row survives the
# JSON Lines round trip unchanged.
type Row = dict[str, str]
type Record = dict[str, object]

# Commands whose first argument is the real verb. `git log` says what a run
# was doing; `git` alone says nothing. Anything past the verb is an argument,
# and keeping it would split one shape across every revision range and file
# path a run happened to name. `gh` is the exception, taking a noun before
# its verb, so `gh pr diff` needs both words to mean anything.
SUBCOMMAND_HEADS = frozenset(
    {"apm", "cargo", "docker", "gh", "git", "go", "just", "mise", "npm", "uv"}
)
VERB_COUNT = {"gh": 2}

SCRIPT_CALL = re.compile(r"skills/(?P<skill>[\w-]+)/scripts/(?P<script>[\w.-]+)")
ENV_PREFIX = re.compile(r"^(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)+")
SKILL_BASE_DIR = re.compile(r"Base directory for this skill: \S*?/skills/([\w-]+)")


def as_mapping(value: object) -> dict[str, object]:
    """A JSON value as a mapping, or an empty one.

    Transcript records are whatever was written, so every lookup on one
    starts here rather than assuming a shape.
    """
    if not isinstance(value, dict):
        return {}
    pairs: list[tuple[object, object]] = list(value.items())
    return {str(key): item for key, item in pairs}


def command_shape(command: str) -> str:
    """Collapse a bash command to something comparable across runs.

    A skill script is reported by the skill that owns it, because that is the
    fact under assessment: whether the agent ran the script it was given.
    """
    command = command.strip()
    if match := SCRIPT_CALL.search(command):
        return f"<{match['skill']}/{match['script']}>"
    command = ENV_PREFIX.sub("", command)
    tokens = command.split()
    if not tokens:
        return "<empty>"
    head = tokens[0].rsplit("/", 1)[-1]
    if head in SUBCOMMAND_HEADS:
        wanted = VERB_COUNT.get(head, 1)
        verbs = [t for t in tokens[1:] if not t.startswith("-")][:wanted]
        return " ".join([head, *verbs])
    return head


def call_detail(name: str, tool_input: dict[str, object]) -> str:
    """The one field worth keeping per tool, for the per-skill breakdown."""
    match name:
        case "Bash":
            return command_shape(str(tool_input.get("command", "")))
        case "Skill":
            return str(tool_input.get("skill", ""))
        case "Agent":
            return str(tool_input.get("subagent_type", ""))
        case "Read" | "Edit" | "Write" | "NotebookEdit":
            return Path(str(tool_input.get("file_path", ""))).name
        case _:
            return ""


def read_records(path: Path) -> Iterator[Record]:
    """Yield the JSON records of one transcript, skipping unparsable lines.

    A transcript is appended to while a session runs, so the last line of a
    live one can be a partial write.
    """
    with path.open(encoding="utf-8", errors="replace") as handle:
        for raw in handle:
            line = raw.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                continue


def transcripts(projects: Path) -> Iterator[Path]:
    """Yield every transcript under the projects directory.

    A main transcript sits at `<project>/<session>.jsonl`. A subagent's sits
    under `<project>/<session>/subagents/`, beside a `.meta.json` naming the
    agent type it ran as.
    """
    yield from sorted(projects.glob("*/*.jsonl"))
    yield from sorted(projects.glob("*/*/subagents/*.jsonl"))


def agent_type(path: Path) -> str:
    meta = path.with_suffix(".meta.json")
    if not meta.is_file():
        return ""
    try:
        loaded: object = json.loads(meta.read_text(encoding="utf-8"))
    except OSError, json.JSONDecodeError:
        return ""
    return str(as_mapping(loaded).get("agentType", ""))


def fork_marker(path: Path) -> str:
    """The skill a forked subagent was launched as, from its opening prompt.

    A fork's first message names the skill's own base directory. That is an
    independent witness to the attribution field, and comparing the two is
    how this tool's reading of `attributionSkill` was checked.
    """
    for record in read_records(path):
        if record.get("type") != "user":
            continue
        content = as_mapping(record.get("message")).get("content")
        if isinstance(content, list):
            blocks: list[object] = list(content)
            content = " ".join(
                str(as_mapping(block).get("text", "")) for block in blocks
            )
        if match := SKILL_BASE_DIR.search(str(content or "")):
            return match[1]
        return ""
    return ""


def collect(projects: Path, since: str = "") -> list[Row]:
    """Every tool call in every transcript, tagged with its active skill.

    A fork's transcript is one run. In a main transcript a run is one
    attribution span, so the same skill invoked three times in a session
    counts as three runs rather than one.
    """
    rows: list[Row] = []
    seen: set[tuple[str, str]] = set()
    for path in transcripts(projects):
        is_fork = path.parent.name == "subagents"
        marker = fork_marker(path) if is_fork else ""
        kind = agent_type(path) if is_fork else "main"
        previous = object()
        span = 0
        for record in read_records(path):
            if record.get("type") != "assistant":
                continue
            timestamp = str(record.get("timestamp", ""))
            if since and timestamp < since:
                continue
            session = str(record.get("sessionId", ""))
            key = (session, str(record.get("uuid", "")))
            if key in seen:
                continue
            seen.add(key)
            skill = str(record.get("attributionSkill") or "")
            if skill != previous:
                span += 1
                previous = skill
            run = path.stem if is_fork else f"{path.stem}#{span}"
            content = as_mapping(record.get("message")).get("content")
            entries: list[object] = list(content) if isinstance(content, list) else []
            for entry in entries:
                block = as_mapping(entry)
                if block.get("type") != "tool_use":
                    continue
                name = str(block.get("name", ""))
                tool_input = as_mapping(block.get("input"))
                rows.append(
                    {
                        "skill": skill,
                        "fork_marker": marker,
                        "agent_type": kind,
                        "session": session,
                        "run": run,
                        "tool": name,
                        "detail": call_detail(name, tool_input),
                        "command": (
                            str(tool_input.get("command", "")) if name == "Bash" else ""
                        ),
                        "timestamp": timestamp,
                        "version": str(record.get("version", "")),
                    }
                )
    return rows


def summarize(rows: list[Row], top: int) -> str:
    """One line per skill, ordered by how much work carries its name."""
    runs: defaultdict[str, set[tuple[str, str]]] = defaultdict(set)
    tools: defaultdict[str, Counter[str]] = defaultdict(Counter)
    for row in rows:
        skill = row["skill"] or "(unattributed)"
        runs[skill].add((row["session"], row["run"]))
        tools[skill][row["tool"]] += 1

    lines = [f"{'skill':28} {'calls':>6} {'runs':>5} {'per run':>8}  tools"]

    def weight(name: str) -> int:
        return -sum(tools[name].values())

    order = sorted(tools, key=weight)
    for skill in order:
        calls = sum(tools[skill].values())
        count = len(runs[skill])
        breakdown = ", ".join(f"{n}:{c}" for n, c in tools[skill].most_common(top))
        lines.append(
            f"{skill:28} {calls:6} {count:5} {calls / count:8.1f}  {breakdown}"
        )
    return "\n".join(lines)


def detail(rows: list[Row], skill: str, top: int) -> str:
    """What one skill's runs actually did, command shape by command shape."""
    picked = [row for row in rows if row["skill"] == skill]
    if not picked:
        return f"no calls attributed to {skill}"
    runs = {(row["session"], row["run"]) for row in picked}
    count = len(runs)
    forked = any(row["fork_marker"] for row in picked)

    headline = (
        f"{skill}: {len(picked)} calls over {count} runs "
        f"({len(picked) / count:.1f} per run)"
    )
    lines = [headline]
    if not forked:
        lines.append(
            "  in-context skill: attribution is sticky, so these are an upper bound"
        )
    lines.append("")
    for tool, total in Counter(row["tool"] for row in picked).most_common():
        lines.append(f"  {total:5} {total / count:7.2f}/run  {tool}")
        shapes = Counter(
            row["detail"] for row in picked if row["tool"] == tool and row["detail"]
        )
        for shape, seen in shapes.most_common(top):
            lines.append(f"  {seen:5} {seen / count:7.2f}/run      {shape}")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Correlate transcript tool calls to the skill that made them."
    )
    parser.add_argument(
        "--projects-dir",
        type=Path,
        default=Path(os.environ.get("CLAUDE_PROJECTS_DIR", DEFAULT_PROJECTS)),
        help="Claude Code projects directory (default: ~/.claude/projects)",
    )
    parser.add_argument(
        "--skill",
        default="",
        help="report one skill's calls in detail instead of the summary",
    )
    parser.add_argument(
        "--since",
        default="",
        help="ignore records before this ISO timestamp, e.g. 2026-08-02",
    )
    parser.add_argument(
        "--top", type=int, default=12, help="entries to show per breakdown"
    )
    parser.add_argument(
        "--json", action="store_true", help="write the rows as JSON Lines instead"
    )
    args = parser.parse_args(argv)

    if not args.projects_dir.is_dir():
        print(f"no projects directory: {args.projects_dir}", file=sys.stderr)
        return 2

    rows = collect(args.projects_dir, args.since)
    if args.json:
        for row in rows:
            print(json.dumps(row))
        return 0
    if args.skill:
        print(detail(rows, args.skill, args.top))
        return 0
    print(summarize(rows, args.top))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
