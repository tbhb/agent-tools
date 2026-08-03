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

`--timing` reads the same runs on the clock instead. Every record carries an
ISO timestamp, so a run's wall clock is its span, and the part of that span
spent blocked on the operator is subtractable: a turn ends and nothing moves
until someone types, and an `AskUserQuestion` sits until someone answers. A
permission prompt is the wait this cannot see, since it suspends a tool call
without writing a record, so it reads as a slow command.

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
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path
from statistics import median
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

MINUTE = 60
HOUR = 3600

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


def is_operator_prompt(record: Record) -> bool:
    """Whether this user record is a person typing rather than a tool result.

    A tool result carries `toolUseResult` and a list of result blocks. What
    a person typed arrives as plain string content, and the harness marks
    its own injected turns `isMeta`.
    """
    if record.get("type") != "user" or record.get("isMeta"):
        return False
    if "toolUseResult" in record:
        return False
    content = as_mapping(record.get("message")).get("content")
    return isinstance(content, str) and bool(content.strip())


def asks_operator(record: Record) -> bool:
    """Whether this assistant record ends by putting a question to the user."""
    content = as_mapping(record.get("message")).get("content")
    entries: list[object] = list(content) if isinstance(content, list) else []
    return any(as_mapping(entry).get("name") == "AskUserQuestion" for entry in entries)


def seconds_between(earlier: str, later: str) -> float:
    """The gap between two transcript timestamps, or zero if either is unusable."""
    try:
        start = datetime.fromisoformat(earlier)
        end = datetime.fromisoformat(later)
    except ValueError:
        return 0.0
    return max(0.0, (end - start).total_seconds())


@dataclass
class Run:
    """One run's span on the clock."""

    skill: str
    session: str
    run: str
    agent_type: str
    started: str
    ended: str
    idle_seconds: float = 0.0

    @property
    def wall_seconds(self) -> float:
        return seconds_between(self.started, self.ended)

    @property
    def active_seconds(self) -> float:
        return max(0.0, self.wall_seconds - self.idle_seconds)

    def as_row(self) -> dict[str, str | float]:
        return {
            **asdict(self),
            "wall_seconds": self.wall_seconds,
            "active_seconds": self.active_seconds,
        }


def collect_runs(projects: Path, since: str = "") -> list[Run]:
    """One entry per run, carrying its wall clock and the part spent waiting.

    Waiting means blocked on the operator, which happens two ways. A turn
    ends and nothing moves until someone types, and an `AskUserQuestion`
    sits until someone answers, its reply arriving as an ordinary tool
    result. Subtracting both leaves the time the run was working.

    A permission prompt is the wait this cannot see. It suspends a tool call
    with no record of its own, so it reads as a slow command and lands in
    the active figure.
    """
    runs: dict[tuple[str, str], Run] = {}
    seen: set[tuple[str, str]] = set()
    for path in transcripts(projects):
        is_fork = path.parent.name == "subagents"
        kind = agent_type(path) if is_fork else "main"
        previous: Record | None = None
        skill = ""
        span = 0
        for record in read_records(path):
            if record.get("type") not in ("assistant", "user"):
                continue
            timestamp = str(record.get("timestamp", ""))
            if not timestamp or (since and timestamp < since):
                continue
            session = str(record.get("sessionId", ""))
            key = (session, str(record.get("uuid", "")))
            if key in seen:
                continue
            seen.add(key)

            # Only an assistant record carries attribution. A user record
            # belongs to whichever span was already running.
            if record.get("type") == "assistant":
                current = str(record.get("attributionSkill") or "")
                if current != skill:
                    span += 1
                    skill = current

            name = path.stem if is_fork else f"{path.stem}#{span}"
            entry = runs.setdefault(
                (session, name),
                Run(skill, session, name, kind, timestamp, timestamp),
            )
            # A fork opens with the prompt that launches it, which carries no
            # attribution, so the run is created before its skill is known.
            # A main span never needs this: the span index changes with the
            # skill, so an entry's name already fixes which skill it holds.
            if not entry.skill:
                entry.skill = skill
            entry.ended = timestamp

            if previous is not None and (
                is_operator_prompt(record)
                or (asks_operator(previous) and "toolUseResult" in record)
            ):
                entry.idle_seconds += seconds_between(
                    str(previous.get("timestamp", "")), timestamp
                )
            previous = record

    return list(runs.values())


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


def duration(seconds: float) -> str:
    """A duration short enough to sit in a column."""
    total = int(seconds)
    if total < MINUTE:
        return f"{total}s"
    if total < HOUR:
        return f"{total // MINUTE}m{total % MINUTE:02d}s"
    return f"{total // HOUR}h{total % HOUR // MINUTE:02d}m"


def timings(entries: list[Run]) -> str:
    """How long each skill's runs take, with the operator's share removed.

    The `kind` column is the one to read first. A fork's figures are its own
    and nothing else's. An in-context skill's are an upper bound over a span
    that keeps running after the skill is done, and the overshoot is not
    small: measured against fix-prose, where the caller resumes and its work
    keeps carrying the skill's name, the span ran several times the length of
    the loop it was supposed to describe.
    """
    by_skill: defaultdict[str, list[Run]] = defaultdict(list)
    for entry in entries:
        by_skill[entry.skill or "(unattributed)"].append(entry)

    header = (
        f"{'skill':28} {'kind':>7} {'runs':>5} {'median':>8} {'p90':>8} "
        f"{'active':>9} {'waiting':>9}"
    )
    lines = [header]

    def weight(name: str) -> float:
        return -sum(e.active_seconds for e in by_skill[name])

    order = sorted(by_skill, key=weight)
    for skill in order:
        group = by_skill[skill]
        active = sorted(e.active_seconds for e in group)
        idle = sum(e.idle_seconds for e in group)
        kind = "fork" if all(e.agent_type != "main" for e in group) else "in-ctx"
        # p90 by index rather than interpolation: these are observed run
        # lengths, so the figure should be one of them.
        p90 = active[min(len(active) - 1, int(len(active) * 0.9))]
        lines.append(
            f"{skill:28} {kind:>7} {len(group):5} {duration(median(active)):>8} "
            f"{duration(p90):>8} {duration(sum(active)):>9} {duration(idle):>9}"
        )
    lines.append("")
    lines.append("active is wall clock less time blocked on the operator.")
    lines.append("A permission prompt has no record, so it counts as active.")
    lines.append("")
    lines.append("A fork's figures are exact. An in-ctx figure overstates,")
    lines.append("often several times over: the span runs until another")
    lines.append("in-context skill loads, so the caller's later work, and the")
    lines.append("forks it spawns, keep counting against the skill that ended.")
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
        "--timing",
        action="store_true",
        help="report how long each skill's runs take instead of what they called",
    )
    parser.add_argument(
        "--json", action="store_true", help="write the rows as JSON Lines instead"
    )
    args = parser.parse_args(argv)

    if not args.projects_dir.is_dir():
        print(f"no projects directory: {args.projects_dir}", file=sys.stderr)
        return 2

    if args.timing:
        entries = collect_runs(args.projects_dir, args.since)
        if args.skill:
            entries = [e for e in entries if e.skill == args.skill]
        if args.json:
            for entry in entries:
                print(json.dumps(entry.as_row()))
            return 0
        print(timings(entries))
        return 0

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
