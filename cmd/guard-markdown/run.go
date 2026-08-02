// SPDX-License-Identifier: Apache-2.0
// Copyright Tony Burns

package main

import (
	"errors"
	"fmt"
	"io"
	"os"

	"github.com/spf13/cobra"

	"github.com/tbhb/agent-tools/internal/buildmeta"
	"github.com/tbhb/agent-tools/internal/hookio"
	"github.com/tbhb/agent-tools/internal/markdown"
)

// Exit statuses. A linter that found something isn't a program that
// failed, so findings and errors get distinct codes.
const (
	exitOK       = 0
	exitFindings = 1
	exitError    = 2
)

var (
	// errFindings signals that the check reported violations. Run maps it to
	// exitFindings without printing it, so the findings themselves are the
	// only output a caller has to read.
	errFindings = errors.New("findings")

	// errHookTakesNoPaths rejects mixing the two invocation styles, which
	// would otherwise silently ignore one of them.
	errHookTakesNoPaths = errors.New("--hook reads stdin and takes no paths")
)

// streams gathers the process I/O so tests can drive the command without
// touching the real stdin and stdout.
type streams struct {
	in  io.Reader
	out io.Writer
	err io.Writer
}

// Run executes the command and returns the process exit status.
func Run(args []string, s streams) int {
	cmd := newRootCmd(s)
	cmd.SetArgs(args)

	switch err := cmd.Execute(); {
	case err == nil:
		return exitOK
	case errors.Is(err, errFindings):
		return exitFindings
	default:
		fmt.Fprintln(s.err, "guard-markdown:", err)
		return exitError
	}
}

func newRootCmd(s streams) *cobra.Command {
	var hook, fix bool

	root := &cobra.Command{
		Use:   "guard-markdown [flags] [paths...]",
		Short: "Refuse Markdown whose paragraphs span more than one line",
		Long: "Markdown in tbhb repositories is never hard-wrapped: every paragraph is\n" +
			"a single line and the renderer decides where it breaks.\n\n" +
			"One binary serves three callers. With --hook it reads a Claude\n" +
			"PreToolUse payload on stdin and denies a Write or Edit before wrapped\n" +
			"prose reaches disk. With paths it reports violations and exits nonzero,\n" +
			"which is what pre-commit and the just recipes consume. With --fix it\n" +
			"joins the offending paragraphs in place.\n\n" +
			"A CHANGELOG.md is exempt in every mode. A generator builds it from\n" +
			"commit messages, which are hard-wrapped under their own gate, so the\n" +
			"wrapping arrives with the content and the next release restores it.",
		Version:       buildmeta.Version,
		SilenceUsage:  true,
		SilenceErrors: true,
		RunE: func(_ *cobra.Command, args []string) error {
			if hook {
				if len(args) > 0 {
					return errHookTakesNoPaths
				}
				return runHook(s)
			}
			return runCheck(args, fix, s)
		},
	}

	root.Flags().BoolVar(&hook, "hook", false,
		"read a Claude PreToolUse payload on stdin instead of paths")
	root.Flags().BoolVar(&fix, "fix", false,
		"join wrapped paragraphs in place instead of reporting them")
	root.SetOut(s.out)
	root.SetErr(s.err)
	return root
}

// runHook answers a PreToolUse payload. Every path that can't reach a
// verdict returns nil. A hook must never block a call it failed to parse,
// and it must never block one it holds no opinion about.
func runHook(s streams) error {
	payload, err := hookio.Decode(s.in)
	if err != nil {
		// Deliberate: a payload it failed to read isn't grounds to block a tool
		// call. Failing open is the only safe direction for a gate that sits
		// in front of every Write and Edit.
		return nil //nolint:nilerr // fail open, as the comment explains
	}
	path, content, ok := payload.Resolve(nil)
	if !ok || !markdown.Checked(path) {
		return nil
	}
	report := markdown.Analyze(content)
	if report.OK() {
		return nil
	}
	if denyErr := hookio.Deny(s.out, markdown.DenyReason(path, report)); denyErr != nil {
		return fmt.Errorf("writing hook decision: %w", denyErr)
	}
	return nil
}

// runCheck inspects files on disk, optionally rewriting them.
func runCheck(paths []string, fix bool, s streams) error {
	found := false
	for _, path := range paths {
		if !markdown.Checked(path) {
			continue
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return fmt.Errorf("reading %s: %w", path, err)
		}
		report := markdown.Analyze(string(data))
		if report.OK() {
			continue
		}
		if fix {
			if rewriteErr := rewrite(path, markdown.Unwrap(string(data))); rewriteErr != nil {
				return rewriteErr
			}
			fmt.Fprintf(s.out, "%s: joined %d wrapped paragraphs\n", path, len(report.Paragraphs))
			continue
		}
		found = true
		for _, line := range markdown.Describe(path, report) {
			fmt.Fprintln(s.out, line)
		}
	}
	if found {
		return errFindings
	}
	return nil
}

// rewrite replaces a file's contents, preserving its existing mode rather
// than imposing one.
//
// The path is attacker-controlled only in the sense that it comes from the
// caller's own argv or from pre-commit's staged-file list, which is the whole
// point of a file checker. No boundary exists here for traversal to cross.
func rewrite(path, content string) error {
	info, err := os.Stat(path)
	if err != nil {
		return fmt.Errorf("stat %s: %w", path, err)
	}
	perm := info.Mode().Perm()
	//nolint:gosec // G703: the path is the caller's own argument, as noted.
	if writeErr := os.WriteFile(path, []byte(content), perm); writeErr != nil {
		return fmt.Errorf("writing %s: %w", path, writeErr)
	}
	return nil
}
