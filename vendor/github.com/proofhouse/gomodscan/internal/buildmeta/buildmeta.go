// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of Proofhouse

// Package buildmeta carries build-time information injected via ldflags, with
// a fallback that consults the runtime/debug build info when no ldflags apply
// (such as go install directly from source).
package buildmeta

import "runtime/debug"

// devFallback holds the placeholder version stamped when no ldflags
// and no runtime build info apply. resolveVersion treats it as a
// signal to consult runtime/debug rather than as a real version.
const devFallback = "DEV"

// Build-time variables. The Justfile and goreleaser config both set these via
// -ldflags "-X github.com/proofhouse/gomodscan/internal/buildmeta.<Var>=<value>".
// The defaults below apply when the build passes no ldflags.
//
//nolint:gochecknoglobals // ldflags -X can only patch package-level vars
var (
	// Version holds the semantic version of the build. Set via ldflags, or
	// resolved from the runtime/debug build info at init time.
	Version = devFallback

	// Commit holds the short git SHA of the build.
	Commit = ""

	// Date holds the build date in calendar form, like 2026-05-26.
	Date = ""
)

// Info bundles build metadata for callers that want a struct rather than
// the package-level vars.
type Info struct {
	Version string
	Commit  string
	Date    string
}

// Get returns the current build metadata.
func Get() Info {
	return Info{Version: Version, Commit: Commit, Date: Date}
}

//nolint:gochecknoinits // runtime/debug fallback runs once at process start
func init() {
	Version = resolveVersion(Version, debug.ReadBuildInfo)
}

// resolveVersion produces the effective package Version from the
// ldflags-supplied value and a callable that reads the runtime
// build info. When ldflags pinned a non-default version, that
// value wins. With the placeholder fallback in place, the runtime
// build info supplies a module-derived version, except when the
// reader reports the literal (devel) value. That literal leaves
// the placeholder untouched so callers always see a non-empty
// Version.
//
// The function takes readBuildInfo as a parameter so tests can
// drive each branch directly without spawning a child process.
func resolveVersion(ldflagsVersion string, readBuildInfo func() (*debug.BuildInfo, bool)) string {
	if ldflagsVersion != devFallback {
		return ldflagsVersion
	}
	info, ok := readBuildInfo()
	if !ok || info.Main.Version == "(devel)" {
		return ldflagsVersion
	}
	return info.Main.Version
}
