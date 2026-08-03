"""Tests for skill_attribution.py.

Driven as a subprocess against a synthetic projects directory, the same way
test_fix_prose_replacements.py drives its subject. The contract worth
asserting is what the command reports, and the reporting is where the claims
live: a fork's transcript bounds one run, a main transcript's attribution
span bounds its own, a relocated session counts once, and a command collapses
to a shape that survives comparison across runs.

A real transcript can't be pinned to a fixture, so the records here are the
minimum an assistant record needs to reach the report.
"""

import json
import subprocess
import sys
from pathlib import Path

import pytest

# tests/tools/ mirrors tools/. See the note in
# tests/skills/resolve-rebase-conflicts/scripts/test_conflict_shape.py for
# why these sit outside the tree they test.
REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "tools/skill_attribution.py"
assert SCRIPT.is_file(), f"subject not found: {SCRIPT}"

MISSING_PROJECTS = 2


def stamp(minutes: int = 0) -> str:
    """A transcript timestamp, offset from a fixed origin."""
    return f"2026-08-03T12:{minutes:02d}:00.000Z"


def assistant(
    uuid: str,
    skill: str | None,
    commands: list[str],
    session: str,
    at: str = stamp(),
) -> str:
    """One assistant record carrying a bash call per command."""
    return json.dumps(
        {
            "type": "assistant",
            "uuid": uuid,
            "sessionId": session,
            "timestamp": at,
            "version": "2.1.220",
            **({"attributionSkill": skill} if skill else {}),
            "message": {
                "content": [
                    {"type": "tool_use", "name": "Bash", "input": {"command": command}}
                    for command in commands
                ]
            },
        }
    )


def question(uuid: str, session: str, at: str, skill: str) -> str:
    """An assistant record that puts a question to the operator."""
    return json.dumps(
        {
            "type": "assistant",
            "uuid": uuid,
            "sessionId": session,
            "timestamp": at,
            "attributionSkill": skill,
            "message": {
                "content": [
                    {"type": "tool_use", "name": "AskUserQuestion", "input": {}}
                ]
            },
        }
    )


def prompt(uuid: str, session: str, at: str, text: str = "do the thing") -> str:
    """A user record of the kind a person types."""
    return json.dumps(
        {
            "type": "user",
            "uuid": uuid,
            "sessionId": session,
            "timestamp": at,
            "message": {"role": "user", "content": text},
        }
    )


def tool_result(uuid: str, session: str, at: str) -> str:
    """A user record of the kind the harness writes back after a tool call."""
    return json.dumps(
        {
            "type": "user",
            "uuid": uuid,
            "sessionId": session,
            "timestamp": at,
            "toolUseResult": {"ok": True},
            "message": {
                "role": "user",
                "content": [{"type": "tool_result", "content": "done"}],
            },
        }
    )


@pytest.fixture
def projects(tmp_path: Path) -> Path:
    root = tmp_path / "projects"
    (root / "-repo").mkdir(parents=True)
    return root


def write_main(projects: Path, session: str, lines: list[str]) -> None:
    (projects / "-repo" / f"{session}.jsonl").write_text(
        "\n".join(lines) + "\n", encoding="utf-8"
    )


def write_fork(projects: Path, session: str, agent: str, lines: list[str]) -> None:
    forks = projects / "-repo" / session / "subagents"
    forks.mkdir(parents=True, exist_ok=True)
    (forks / f"{agent}.jsonl").write_text("\n".join(lines) + "\n", encoding="utf-8")
    (forks / f"{agent}.meta.json").write_text(
        json.dumps({"agentType": "Explore"}), encoding="utf-8"
    )


def run(projects: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--projects-dir", str(projects), *args],
        capture_output=True,
        text=True,
        check=False,
    )


def rows(projects: Path, *args: str) -> list[dict[str, str]]:
    result = run(projects, "--json", *args)
    assert result.returncode == 0, result.stderr
    return [json.loads(line) for line in result.stdout.splitlines()]


@pytest.mark.parametrize(
    ("command", "shape"),
    [
        ("gh pr diff 42 --color never", "gh pr diff"),
        ("git log --format=%h main..HEAD", "git log"),
        ("cat SQUASH_AGENTMSG", "cat"),
        ("REPO=/tmp gh pr view 7", "gh pr view"),
        ("/bin/grep -n foo bar.txt", "grep"),
        (
            "bash .claude/skills/merge-pr/scripts/preflight.sh",
            "<merge-pr/preflight.sh>",
        ),
    ],
)
def test_command_collapses_to_a_comparable_shape(
    projects: Path, command: str, shape: str
) -> None:
    write_main(projects, "s0", [assistant("u1", "commit", [command], "s0")])
    assert [row["detail"] for row in rows(projects)] == [shape]


def test_fork_transcript_is_one_run(projects: Path) -> None:
    write_fork(
        projects,
        "s1",
        "agent-a1",
        [
            assistant("u1", "review-squash-message", ["gh pr diff 3"], "s1"),
            assistant("u2", "review-squash-message", ["gh pr view 3", "cat X"], "s1"),
        ],
    )
    collected = rows(projects)
    assert len(collected) == 3
    assert {row["run"] for row in collected} == {"agent-a1"}
    assert {row["skill"] for row in collected} == {"review-squash-message"}
    assert {row["agent_type"] for row in collected} == {"Explore"}


def test_main_transcript_splits_runs_at_each_attribution_change(
    projects: Path,
) -> None:
    write_main(
        projects,
        "s2",
        [
            assistant("u1", None, ["ls"], "s2"),
            assistant("u2", "commit", ["git status"], "s2"),
            assistant("u3", "fix-prose", ["just lint-commit-msg"], "s2"),
            assistant("u4", "commit", ["git add x"], "s2"),
        ],
    )
    runs = {(row["skill"], row["run"]) for row in rows(projects)}
    # commit loaded twice around fix-prose, so it counts as two runs, not one.
    assert sorted(run for skill, run in runs if skill == "commit") == ["s2#2", "s2#4"]


def test_summary_counts_those_runs_separately(projects: Path) -> None:
    write_main(
        projects,
        "s2",
        [
            assistant("u1", "commit", ["git status"], "s2"),
            assistant("u2", "fix-prose", ["just lint-commit-msg"], "s2"),
            assistant("u3", "commit", ["git add x"], "s2"),
        ],
    )
    result = run(projects)
    assert result.returncode == 0, result.stderr
    line = next(x for x in result.stdout.splitlines() if x.startswith("commit "))
    calls, count = line.split()[1:3]
    assert (calls, count) == ("2", "2")


def test_relocated_session_counts_once(projects: Path) -> None:
    (projects / "-old-name").mkdir()
    line = assistant("u1", "commit", ["git status"], "s3")
    write_main(projects, "s3", [line])
    (projects / "-old-name" / "s3.jsonl").write_text(line + "\n", encoding="utf-8")
    assert len(rows(projects)) == 1


def test_since_drops_earlier_records(projects: Path) -> None:
    write_main(projects, "s4", [assistant("u1", "commit", ["git status"], "s4")])
    assert rows(projects, "--since", "2026-08-04") == []
    assert len(rows(projects, "--since", "2026-08-01")) == 1


def test_truncated_final_line_is_skipped(projects: Path) -> None:
    (projects / "-repo" / "s5.jsonl").write_text(
        assistant("u1", "commit", ["git status"], "s5") + '\n{"type": "user"',
        encoding="utf-8",
    )
    assert len(rows(projects)) == 1


def test_detail_names_a_skill_with_no_calls(projects: Path) -> None:
    write_main(projects, "s6", [assistant("u1", "commit", ["git status"], "s6")])
    result = run(projects, "--skill", "merge-pr")
    assert result.returncode == 0
    assert "no calls attributed to merge-pr" in result.stdout


def timing_rows(projects: Path, *args: str) -> list[dict[str, str | float]]:
    result = run(projects, "--timing", "--json", *args)
    assert result.returncode == 0, result.stderr
    return [json.loads(line) for line in result.stdout.splitlines()]


def test_a_fork_run_takes_the_skill_its_records_carry(projects: Path) -> None:
    # A fork opens with the launching prompt, which carries no attribution.
    write_fork(
        projects,
        "s7",
        "agent-a2",
        [
            prompt("u0", "s7", stamp(0), "Base directory for this skill: /x"),
            assistant("u1", "review-squash-message", ["gh pr diff 3"], "s7", stamp(2)),
        ],
    )
    rows = timing_rows(projects)
    assert [row["skill"] for row in rows] == ["review-squash-message"]


def test_waiting_on_an_operator_prompt_is_not_active_time(projects: Path) -> None:
    write_main(
        projects,
        "s8",
        [
            assistant("u1", "commit", ["git status"], "s8", stamp(0)),
            prompt("u2", "s8", stamp(30)),
        ],
    )
    entry = next(r for r in timing_rows(projects) if r["skill"] == "commit")
    assert entry["wall_seconds"] == 1800
    assert entry["idle_seconds"] == 1800
    assert entry["active_seconds"] == 0


def test_waiting_on_a_question_is_not_active_time(projects: Path) -> None:
    write_main(
        projects,
        "s9",
        [
            assistant("u1", "merge-pr", ["git status"], "s9", stamp(0)),
            question("u2", "s9", stamp(1), "merge-pr"),
            tool_result("u3", "s9", stamp(21)),
        ],
    )
    entry = next(r for r in timing_rows(projects) if r["skill"] == "merge-pr")
    assert entry["wall_seconds"] == 1260
    assert entry["idle_seconds"] == 1200
    assert entry["active_seconds"] == 60


def test_an_ordinary_tool_result_counts_as_active_time(projects: Path) -> None:
    write_main(
        projects,
        "s10",
        [
            assistant("u1", "rebase", ["git rebase main"], "s10", stamp(0)),
            tool_result("u2", "s10", stamp(5)),
        ],
    )
    entry = next(r for r in timing_rows(projects) if r["skill"] == "rebase")
    assert entry["idle_seconds"] == 0
    assert entry["active_seconds"] == 300


def test_timing_summary_names_what_it_cannot_see(projects: Path) -> None:
    write_main(projects, "s11", [assistant("u1", "commit", ["git status"], "s11")])
    result = run(projects, "--timing")
    assert result.returncode == 0, result.stderr
    assert "permission prompt" in result.stdout


def test_timing_marks_an_in_context_skill_as_an_upper_bound(
    projects: Path,
) -> None:
    write_main(projects, "s12", [assistant("u1", "commit", ["git status"], "s12")])
    write_fork(
        projects,
        "s12",
        "agent-a3",
        [assistant("u2", "review-commit-message", ["git diff"], "s12")],
    )
    result = run(projects, "--timing")
    assert result.returncode == 0, result.stderr
    rows = {
        line.split()[0]: line.split()[1]
        for line in result.stdout.splitlines()
        if line.startswith(("commit ", "review-commit-message "))
    }
    assert rows == {"commit": "in-ctx", "review-commit-message": "fork"}


def test_missing_projects_directory_is_an_error(tmp_path: Path) -> None:
    result = run(tmp_path / "absent")
    assert result.returncode == MISSING_PROJECTS
    assert "no projects directory" in result.stderr
