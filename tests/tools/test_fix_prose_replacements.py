"""Tests for fix_prose_replacements.py.

Driven as a subprocess, with a stub `vale` on PATH emitting canned findings
in the repo-local template's format. Stubbing at the process boundary keeps
the parser, the span check, and the right-to-left ordering under test
together, which is where the safety argument for applying an edit unattended
actually lives.
"""

import subprocess
import sys
import textwrap
from pathlib import Path

import pytest

# tests/tools/ mirrors tools/. See the note in
# tests/skills/resolve-rebase-conflicts/scripts/test_conflict_shape.py for
# why these sit outside the tree they test.
REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "tools/fix_prose_replacements.py"
assert SCRIPT.is_file(), f"subject not found: {SCRIPT}"

OK = 0
SKIPPED = 1
MISUSE = 2


@pytest.fixture
def workspace(tmp_path: Path) -> tuple[Path, Path]:
    """A git repo with a stub vale on PATH, since the script cds to the root."""
    subprocess.run(["git", "init", "-q"], cwd=tmp_path, check=True)
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    return tmp_path, bin_dir


def install_vale(bin_dir: Path, findings: str) -> None:
    stub = bin_dir / "vale"
    stub.write_text(
        textwrap.dedent(f"""\
            #!{sys.executable}
            import sys
            sys.stdout.write({findings!r})
            sys.exit(1 if {findings!r} else 0)
        """),
        encoding="utf-8",
    )
    stub.chmod(0o755)


def run(
    workspace: tuple[Path, Path], target: Path, findings: str
) -> subprocess.CompletedProcess[str]:
    root, bin_dir = workspace
    install_vale(bin_dir, findings)
    return subprocess.run(
        [sys.executable, str(SCRIPT), str(target)],
        capture_output=True,
        text=True,
        check=False,
        cwd=root,
        env={"PATH": f"{bin_dir}:/usr/bin:/bin"},
    )


class TestApplying:
    def test_a_replacement_is_applied_and_reported(
        self, workspace: tuple[Path, Path]
    ) -> None:
        root, _ = workspace
        target = root / "doc.md"
        target.write_text("We do not ship it.\n", encoding="utf-8")
        findings = (
            '1:4-9 [error] Google.Contractions match="do not" replace_with="don\'t"\n'
        )
        proc = run(workspace, target, findings)
        assert proc.returncode == OK
        assert target.read_text(encoding="utf-8") == "We don't ship it.\n"
        assert "[fixed] Google.Contractions" in proc.stdout

    def test_two_edits_on_one_line_apply_right_to_left(
        self, workspace: tuple[Path, Path]
    ) -> None:
        root, _ = workspace
        target = root / "doc.md"
        target.write_text("do not go and do not stop\n", encoding="utf-8")
        findings = (
            '1:1-6 [error] Contractions match="do not" replace_with="don\'t"\n'
            '1:15-20 [error] Contractions match="do not" replace_with="don\'t"\n'
        )
        proc = run(workspace, target, findings)
        assert proc.returncode == OK
        assert target.read_text(encoding="utf-8") == "don't go and don't stop\n"

    def test_a_finding_with_no_replacement_is_left_alone(
        self, workspace: tuple[Path, Path]
    ) -> None:
        root, _ = workspace
        target = root / "doc.md"
        target.write_text("This is passive.\n", encoding="utf-8")
        findings = '1:1-4 [warning] Vale.Passive match="This"\n'
        proc = run(workspace, target, findings)
        assert proc.returncode == OK
        assert target.read_text(encoding="utf-8") == "This is passive.\n"


class TestRefusing:
    def test_a_moved_span_is_skipped_and_named(
        self, workspace: tuple[Path, Path]
    ) -> None:
        root, _ = workspace
        target = root / "doc.md"
        target.write_text("Totally different text.\n", encoding="utf-8")
        findings = '1:4-9 [error] Contractions match="do not" replace_with="don\'t"\n'
        proc = run(workspace, target, findings)
        assert proc.returncode == SKIPPED
        assert "span-mismatch" in proc.stdout
        assert target.read_text(encoding="utf-8") == "Totally different text.\n"

    def test_a_contraction_after_a_preposition_is_refused(
        self, workspace: tuple[Path, Path]
    ) -> None:
        root, _ = workspace
        target = root / "doc.md"
        target.write_text("a verdict from that is narrower\n", encoding="utf-8")
        findings = (
            '1:16-22 [error] Contractions match="that is" replace_with="that\'s"\n'
        )
        proc = run(workspace, target, findings)
        assert proc.returncode == SKIPPED
        assert "context-sensitive" in proc.stdout
        assert "breaks the clause" in proc.stdout
        assert target.read_text(encoding="utf-8") == "a verdict from that is narrower\n"

    def test_the_same_contraction_applies_when_not_after_a_preposition(
        self, workspace: tuple[Path, Path]
    ) -> None:
        root, _ = workspace
        target = root / "doc.md"
        target.write_text("The gate that is red blocks it\n", encoding="utf-8")
        findings = (
            '1:10-16 [error] Contractions match="that is" replace_with="that\'s"\n'
        )
        proc = run(workspace, target, findings)
        assert proc.returncode == OK
        assert target.read_text(encoding="utf-8") == "The gate that's red blocks it\n"

    def test_unparsable_quoting_is_reported_not_guessed_at(
        self, workspace: tuple[Path, Path]
    ) -> None:
        root, _ = workspace
        target = root / "doc.md"
        target.write_text("We do not ship it.\n", encoding="utf-8")
        findings = '1:4-9 [error] Contractions match="do not" replace_with="\\q"\n'
        proc = run(workspace, target, findings)
        assert "unparsable-quoting" in proc.stdout
        assert target.read_text(encoding="utf-8") == "We do not ship it.\n"


class TestInvocation:
    def test_no_argument_exits_two(self, workspace: tuple[Path, Path]) -> None:
        root, bin_dir = workspace
        proc = subprocess.run(
            [sys.executable, str(SCRIPT)],
            capture_output=True,
            text=True,
            check=False,
            cwd=root,
            env={"PATH": f"{bin_dir}:/usr/bin:/bin"},
        )
        assert proc.returncode == MISUSE

    def test_a_missing_file_is_reported_as_a_finding(
        self, workspace: tuple[Path, Path]
    ) -> None:
        root, _ = workspace
        proc = run(workspace, root / "nope.md", "")
        assert proc.returncode == SKIPPED
        assert "missing-file" in proc.stdout

    def test_a_clean_document_exits_zero_and_prints_nothing(
        self, workspace: tuple[Path, Path]
    ) -> None:
        root, _ = workspace
        target = root / "doc.md"
        target.write_text("Clean prose.\n", encoding="utf-8")
        proc = run(workspace, target, "")
        assert proc.returncode == OK
        assert proc.stdout == ""


class TestScriptHeader:
    def test_the_shebang_runs_it_through_uv(self) -> None:
        first = SCRIPT.read_text(encoding="utf-8").splitlines()[0]
        assert first == "#!/usr/bin/env -S uv run --script"
