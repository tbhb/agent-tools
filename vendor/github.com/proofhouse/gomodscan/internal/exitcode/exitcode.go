// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of Proofhouse

// Package exitcode defines the exit-code convention every
// findings-reporting scanner under tools/ follows. Wrapping the
// three integers in a named package lets reviewers grep one place
// to confirm the contract and keeps drift between scanners out of
// the picture.
package exitcode

const (
	// OK signals that no findings surfaced and the tool ran to
	// completion.
	OK = 0

	// Findings signals that at least one finding surfaced. The tool
	// itself ran to completion; the non-zero exit tells the caller
	// to review the output before proceeding.
	Findings = 1

	// ToolFailure signals that the tool itself failed (network
	// error, parse error, missing inputs, etc.) and couldn't list
	// findings. Callers should retry or escalate.
	ToolFailure = 2
)
