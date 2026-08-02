// SPDX-License-Identifier: Apache-2.0
// Copyright Tony Burns

package hookio_test

import (
	"bytes"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/tbhb/repotools/internal/hookio"
)

// errUnreadable stands in for whatever the filesystem returns when the Edit
// replay fails to open its target.
var errUnreadable = errors.New("unreadable")

func TestDecode(t *testing.T) {
	t.Parallel()

	t.Run("full payload", func(t *testing.T) {
		t.Parallel()
		p, err := hookio.Decode(strings.NewReader(
			`{"hook_event_name":"PreToolUse","tool_name":"Write",` +
				`"tool_input":{"file_path":"a.md","content":"x"}}`))
		require.NoError(t, err)
		assert.Equal(t, "PreToolUse", p.HookEventName)
		assert.Equal(t, "Write", p.ToolName)
		assert.Equal(t, "a.md", p.ToolInput.FilePath)
		assert.Equal(t, "x", p.ToolInput.Content)
	})

	t.Run("malformed json is an error", func(t *testing.T) {
		t.Parallel()
		_, err := hookio.Decode(strings.NewReader("not json"))
		assert.Error(t, err)
	})

	t.Run("unknown fields are ignored", func(t *testing.T) {
		t.Parallel()
		p, err := hookio.Decode(strings.NewReader(`{"tool_name":"Write","future":1}`))
		require.NoError(t, err)
		assert.Equal(t, "Write", p.ToolName)
	})
}

func TestResolveWrite(t *testing.T) {
	t.Parallel()

	p := hookio.Payload{
		ToolName:  "Write",
		ToolInput: hookio.ToolInput{FilePath: "a.md", Content: "body"},
	}
	path, content, ok := p.Resolve(nil)
	assert.True(t, ok)
	assert.Equal(t, "a.md", path)
	assert.Equal(t, "body", content)
}

func TestResolveEdit(t *testing.T) {
	t.Parallel()

	read := func(string) ([]byte, error) { return []byte("x-x-x\n"), nil }

	t.Run("replaces once by default", func(t *testing.T) {
		t.Parallel()
		p := hookio.Payload{
			ToolName:  "Edit",
			ToolInput: hookio.ToolInput{FilePath: "a.md", OldString: "x", NewString: "y"},
		}
		_, content, ok := p.Resolve(read)
		assert.True(t, ok)
		assert.Equal(t, "y-x-x\n", content)
	})

	t.Run("honors replace_all", func(t *testing.T) {
		t.Parallel()
		p := hookio.Payload{
			ToolName: "Edit",
			ToolInput: hookio.ToolInput{
				FilePath: "a.md", OldString: "x", NewString: "y", ReplaceAll: true,
			},
		}
		_, content, ok := p.Resolve(read)
		assert.True(t, ok)
		assert.Equal(t, "y-y-y\n", content)
	})

	t.Run("unreadable file resolves to nothing", func(t *testing.T) {
		t.Parallel()
		p := hookio.Payload{
			ToolName:  "Edit",
			ToolInput: hookio.ToolInput{FilePath: "a.md", OldString: "x", NewString: "y"},
		}
		_, _, ok := p.Resolve(func(string) ([]byte, error) { return nil, errUnreadable })
		assert.False(t, ok)
	})
}

func TestResolveRejects(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name    string
		payload hookio.Payload
	}{
		{"missing path", hookio.Payload{ToolName: "Write"}},
		{"unrelated tool", hookio.Payload{
			ToolName:  "Bash",
			ToolInput: hookio.ToolInput{FilePath: "a.md"},
		}},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			_, _, ok := tc.payload.Resolve(nil)
			assert.False(t, ok)
		})
	}
}

// TestResolveEditDefaultReader covers the nil-reader path, which falls back
// to the real filesystem.
func TestResolveEditDefaultReader(t *testing.T) {
	t.Parallel()

	path := filepath.Join(t.TempDir(), "doc.md")
	require.NoError(t, os.WriteFile(path, []byte("alpha\n"), 0o600))

	p := hookio.Payload{
		ToolName:  "Edit",
		ToolInput: hookio.ToolInput{FilePath: path, OldString: "alpha", NewString: "beta"},
	}
	_, content, ok := p.Resolve(nil)
	assert.True(t, ok)
	assert.Equal(t, "beta\n", content)
}

func TestDeny(t *testing.T) {
	t.Parallel()

	t.Run("writes the decision envelope", func(t *testing.T) {
		t.Parallel()
		var buf bytes.Buffer
		require.NoError(t, hookio.Deny(&buf, "because reasons"))

		var got struct {
			HookSpecificOutput struct {
				HookEventName            string `json:"hookEventName"`
				PermissionDecision       string `json:"permissionDecision"`
				PermissionDecisionReason string `json:"permissionDecisionReason"`
			} `json:"hookSpecificOutput"`
		}
		require.NoError(t, json.Unmarshal(buf.Bytes(), &got))
		assert.Equal(t, "PreToolUse", got.HookSpecificOutput.HookEventName)
		assert.Equal(t, "deny", got.HookSpecificOutput.PermissionDecision)
		assert.Equal(t, "because reasons", got.HookSpecificOutput.PermissionDecisionReason)
	})

	t.Run("refuses an empty reason", func(t *testing.T) {
		t.Parallel()
		var buf bytes.Buffer
		require.ErrorIs(t, hookio.Deny(&buf, "   "), hookio.ErrNoReason)
		assert.Empty(t, buf.String())
	})
}
