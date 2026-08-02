// SPDX-License-Identifier: Apache-2.0
// Copyright Tony Burns

// Command guard-markdown refuses Markdown whose paragraphs span more than
// one line.
//
// One check, three callers. A Claude PreToolUse hook runs it in hook mode,
// reading the tool payload on stdin and answering with an allow or a deny. A
// pre-commit hook hands it paths, as does a repo's verification stack.
//
// See Run in run.go.
package main

import "os"

func main() {
	os.Exit(Run(os.Args[1:], streams{in: os.Stdin, out: os.Stdout, err: os.Stderr}))
}
