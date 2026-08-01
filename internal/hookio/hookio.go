// SPDX-License-Identifier: Apache-2.0
// Copyright Tony Burns

// Package hookio decodes Claude Code hook payloads and writes decisions.
//
// No rule of its own lives here. Every check binary gating a tool call needs
// the same two pieces: recovering the file content that call would produce,
// then answering with an allow or a deny.
//
// Both live here, so a new cmd/check-* binary supplies only its rule.
package hookio

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"
)

// Event names the lifecycle event a payload belongs to.
const preToolUse = "PreToolUse"

// ErrNoReason rejects a deny with nothing for the agent to act on. Refusing
// in terms the agent can't interpret is worse than not refusing at all.
var ErrNoReason = errors.New("hookio: refusing to deny without a reason")

// ToolInput holds the fields of the tool call under inspection. The set is
// the union across Write and Edit; a field absent from the incoming payload
// decodes to its zero value.
type ToolInput struct {
	FilePath   string `json:"file_path"`
	Content    string `json:"content"`
	OldString  string `json:"old_string"`
	NewString  string `json:"new_string"`
	ReplaceAll bool   `json:"replace_all"`
}

// Payload is a decoded PreToolUse hook payload.
type Payload struct {
	HookEventName string    `json:"hook_event_name"`
	ToolName      string    `json:"tool_name"`
	ToolInput     ToolInput `json:"tool_input"`
}

// ReadFileFunc reads a file's contents. Injected so the Edit replay below
// stays testable without touching the filesystem.
type ReadFileFunc func(string) ([]byte, error)

// Decode reads one JSON payload.
func Decode(r io.Reader) (Payload, error) {
	var p Payload
	if err := json.NewDecoder(r).Decode(&p); err != nil {
		return Payload{}, fmt.Errorf("hookio: decoding payload: %w", err)
	}
	return p, nil
}

// Resolve recovers the file content the tool call would produce.
//
// Write supplies the whole document, which needs no reconstruction.
//
// Edit supplies only a fragment, which may begin mid-paragraph and tells
// you nothing on its own. The edit replays against the file on disk instead.
// What comes out of that replay is the thing worth judging.
//
// A false third result means the call produced nothing worth checking.
// Callers must read that as an allow, because a hook that failed to read its
// own input has no business blocking the tool.
func (p Payload) Resolve(read ReadFileFunc) (string, string, bool) {
	if read == nil {
		read = os.ReadFile
	}
	path := p.ToolInput.FilePath
	if path == "" {
		return "", "", false
	}

	switch p.ToolName {
	case "Write":
		return path, p.ToolInput.Content, true
	case "Edit":
		current, err := read(path)
		if err != nil {
			return "", "", false
		}
		count := 1
		if p.ToolInput.ReplaceAll {
			count = -1
		}
		return path, strings.Replace(string(current), p.ToolInput.OldString, p.ToolInput.NewString, count), true
	default:
		return "", "", false
	}
}

// hookSpecificOutput is the decision envelope Claude Code reads on stdout.
type hookSpecificOutput struct {
	HookEventName            string `json:"hookEventName"`
	PermissionDecision       string `json:"permissionDecision"`
	PermissionDecisionReason string `json:"permissionDecisionReason"`
}

type decision struct {
	HookSpecificOutput hookSpecificOutput `json:"hookSpecificOutput"`
}

// Deny refuses the tool call, giving the agent a reason it can act on.
func Deny(w io.Writer, reason string) error {
	if strings.TrimSpace(reason) == "" {
		return ErrNoReason
	}
	err := json.NewEncoder(w).Encode(decision{
		HookSpecificOutput: hookSpecificOutput{
			HookEventName:            preToolUse,
			PermissionDecision:       "deny",
			PermissionDecisionReason: reason,
		},
	})
	if err != nil {
		return fmt.Errorf("hookio: writing decision: %w", err)
	}
	return nil
}
