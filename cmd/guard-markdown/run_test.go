// SPDX-License-Identifier: Apache-2.0
// Copyright Tony Burns

package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const wrapped = "This paragraph has been hard-wrapped by an agent at roughly column\n" +
	"seventy-two, which is exactly the behavior this hook exists to\n" +
	"refuse before it can ever reach the disk in the first place, and\n" +
	"it runs on long enough to give the sweep something to work with\n" +
	"and to clear the evidence floor the report needs to name a cause.\n"

const clean = "A single-line paragraph, exactly as the convention requires.\n"

// harness runs the command and captures what it wrote.
type harness struct {
	code   int
	stdout string
	stderr string
}

func exec(t *testing.T, stdin string, args ...string) harness {
	t.Helper()
	var out, errOut bytes.Buffer
	code := Run(args, streams{in: strings.NewReader(stdin), out: &out, err: &errOut})
	return harness{code: code, stdout: out.String(), stderr: errOut.String()}
}

func write(t *testing.T, name, body string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), name)
	require.NoError(t, os.WriteFile(path, []byte(body), 0o600))
	return path
}

func denyReason(t *testing.T, stdout string) string {
	t.Helper()
	var got struct {
		HookSpecificOutput struct {
			PermissionDecision       string `json:"permissionDecision"`
			PermissionDecisionReason string `json:"permissionDecisionReason"`
		} `json:"hookSpecificOutput"`
	}
	require.NoError(t, json.Unmarshal([]byte(stdout), &got))
	assert.Equal(t, "deny", got.HookSpecificOutput.PermissionDecision)
	return got.HookSpecificOutput.PermissionDecisionReason
}

func TestCheckMode(t *testing.T) {
	t.Parallel()

	t.Run("clean file passes", func(t *testing.T) {
		t.Parallel()
		got := exec(t, "", write(t, "a.md", clean))
		assert.Equal(t, exitOK, got.code)
		assert.Empty(t, got.stdout)
	})

	t.Run("wrapped file reports and fails", func(t *testing.T) {
		t.Parallel()
		got := exec(t, "", write(t, "a.md", wrapped))
		assert.Equal(t, exitFindings, got.code)
		assert.Contains(t, got.stdout, "guard-markdown:")
		assert.Contains(t, got.stdout, "join lines 1-5 into one line")
	})

	t.Run("non-markdown paths are skipped", func(t *testing.T) {
		t.Parallel()
		got := exec(t, "", write(t, "a.go", "alpha\nbeta\n"))
		assert.Equal(t, exitOK, got.code)
	})

	// A generator owns this file, so neither mode touches it.
	t.Run("generated changelog is skipped", func(t *testing.T) {
		t.Parallel()
		path := write(t, "CHANGELOG.md", wrapped)
		got := exec(t, "", path)
		assert.Equal(t, exitOK, got.code)
		assert.Empty(t, got.stdout)

		require.Equal(t, exitOK, exec(t, "", "--fix", path).code)
		body, err := os.ReadFile(path)
		require.NoError(t, err)
		assert.Equal(t, wrapped, string(body), "--fix leaves it as the generator wrote it")
	})

	t.Run("no paths is a pass", func(t *testing.T) {
		t.Parallel()
		assert.Equal(t, exitOK, exec(t, "").code)
	})

	t.Run("missing file is an error, not a finding", func(t *testing.T) {
		t.Parallel()
		got := exec(t, "", filepath.Join(t.TempDir(), "absent.md"))
		assert.Equal(t, exitError, got.code)
		assert.Contains(t, got.stderr, "guard-markdown:")
	})
}

func TestFixMode(t *testing.T) {
	t.Parallel()

	path := write(t, "a.md", wrapped)
	got := exec(t, "", "--fix", path)
	assert.Equal(t, exitOK, got.code)
	assert.Contains(t, got.stdout, "joined 1 wrapped paragraphs")

	assert.Equal(t, exitOK, exec(t, "", path).code, "re-check passes")

	body, err := os.ReadFile(path)
	require.NoError(t, err)
	assert.Equal(t, 1, strings.Count(string(body), "\n"), "paragraph is one line")
}

func TestFixPreservesMode(t *testing.T) {
	// Windows has no permission triplet for a rewrite to preserve. os.Stat
	// synthesizes 0o666 for every writable file, whatever mode created it, so
	// the fixture below reads 0o666 both before the fix and after, and the
	// assertion compares Go's stand-in against itself.
	if runtime.GOOS == "windows" {
		t.Skip("Windows synthesizes the permission bits os.Stat reports")
	}

	t.Parallel()

	// write() creates at 0o600. A rewrite that imposed its own mode would
	// land on 0o644, so an unchanged 0o600 is what proves preservation.
	path := write(t, "a.md", wrapped)
	require.Equal(t, exitOK, exec(t, "", "--fix", path).code)

	info, err := os.Stat(path)
	require.NoError(t, err)
	assert.Equal(t, os.FileMode(0o600), info.Mode().Perm())
}

func TestHookMode(t *testing.T) {
	t.Parallel()

	payload := func(tool, path, body string) string {
		p := map[string]any{
			"hook_event_name": "PreToolUse",
			"tool_name":       tool,
			"tool_input":      map[string]any{"file_path": path, "content": body},
		}
		b, err := json.Marshal(p)
		require.NoError(t, err)
		return string(b)
	}

	t.Run("wrapped write is denied", func(t *testing.T) {
		t.Parallel()
		got := exec(t, payload("Write", "a.md", wrapped), "--hook")
		assert.Equal(t, exitOK, got.code, "a deny is still a successful hook run")
		reason := denyReason(t, got.stdout)
		assert.Contains(t, reason, "a.md is hard-wrapped at column")
		assert.Contains(t, reason, "never hard-wrapped")
	})

	t.Run("clean write is silent", func(t *testing.T) {
		t.Parallel()
		got := exec(t, payload("Write", "a.md", clean), "--hook")
		assert.Equal(t, exitOK, got.code)
		assert.Empty(t, got.stdout)
	})

	t.Run("non-markdown path is silent", func(t *testing.T) {
		t.Parallel()
		got := exec(t, payload("Write", "a.go", "alpha\nbeta\n"), "--hook")
		assert.Equal(t, exitOK, got.code)
		assert.Empty(t, got.stdout)
	})

	t.Run("wrapped changelog write is allowed", func(t *testing.T) {
		t.Parallel()
		got := exec(t, payload("Write", "CHANGELOG.md", wrapped), "--hook")
		assert.Equal(t, exitOK, got.code)
		assert.Empty(t, got.stdout)
	})

	t.Run("unrelated tool is silent", func(t *testing.T) {
		t.Parallel()
		got := exec(t, `{"tool_name":"Bash","tool_input":{"command":"ls"}}`, "--hook")
		assert.Equal(t, exitOK, got.code)
		assert.Empty(t, got.stdout)
	})

	// A hook that can't parse its input must never block the tool call.
	t.Run("malformed json fails open", func(t *testing.T) {
		t.Parallel()
		got := exec(t, "not json at all", "--hook")
		assert.Equal(t, exitOK, got.code)
		assert.Empty(t, got.stdout)
	})

	t.Run("edit is judged against the file on disk", func(t *testing.T) {
		t.Parallel()
		path := write(t, "a.md", "# T\n\nalpha beta gamma delta.\n")
		p, err := json.Marshal(map[string]any{
			"tool_name": "Edit",
			"tool_input": map[string]any{
				"file_path":  path,
				"old_string": "alpha beta gamma delta.",
				"new_string": strings.TrimSuffix(wrapped, "\n"),
			},
		})
		require.NoError(t, err)

		got := exec(t, string(p), "--hook")
		assert.Contains(t, denyReason(t, got.stdout), "hard-wrapped at column")
	})

	t.Run("paths with --hook is a usage error", func(t *testing.T) {
		t.Parallel()
		got := exec(t, "", "--hook", "a.md")
		assert.Equal(t, exitError, got.code)
		assert.Contains(t, got.stderr, "reads stdin and takes no paths")
	})
}

func TestUnknownFlag(t *testing.T) {
	t.Parallel()

	got := exec(t, "", "--nope")
	assert.Equal(t, exitError, got.code)
	assert.Contains(t, got.stderr, "guard-markdown:")
}
