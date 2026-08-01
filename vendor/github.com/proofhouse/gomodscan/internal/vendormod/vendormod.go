// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of Proofhouse

// Package vendormod enumerates the modules a project vendors.
// Both depscan and malscan call [Read] to load the dependency set
// they need to audit, and future scanners under tools/ share the
// parser rather than carrying their own copy.
package vendormod

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

const (
	// scannerInitialBufSize sizes the bufio.Scanner buffer for one
	// vendor/modules.txt line. Most lines fit in 256 bytes, so
	// 64 KiB leaves comfortable headroom. The shift literal avoids
	// an untestable arithmetic-base mutation position; bufio.Scanner
	// grows its buffer up to scannerMaxBufSize regardless.
	scannerInitialBufSize = 1 << 16

	// scannerMaxBufSize caps the buffer at 1 MiB so a malformed
	// line can't make the scanner grow without bound.
	scannerMaxBufSize = 1 << 20

	// plainModuleFields names the two-field form "<path> <version>"
	// that vendor/modules.txt uses for modules without a replace
	// directive.
	plainModuleFields = 2
)

// Module names one entry in vendor/modules.txt after the parser
// resolves any replace directives. Only the fields downstream
// lookups need stay on the struct.
type Module struct {
	Path    string
	Version string
	// Line records the 1-based vendor/modules.txt line carrying this
	// module's "# <path> <version>" declaration. SARIF emission feeds
	// it to the region start line so GitHub Code Scanning anchors each
	// finding on the real file.
	Line int
}

// Read returns the modules declared in modroot/vendor/modules.txt.
// Pass an empty modroot to read from the current working directory.
func Read(modroot string) ([]Module, error) {
	path := filepath.Join(modroot, "vendor", "modules.txt")
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("open %s: %w", path, err)
	}
	defer f.Close()
	mods, err := Parse(f)
	if err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}
	return mods, nil
}

// Parse reads the well-defined vendor/modules.txt format described
// in the [Go vendoring reference]. Lines that begin with "# "
// declare a module and its version, optionally followed by a
// replace directive ("=> path" or "=> path version"). Two leading
// hashes ("## ") flag sub-metadata that the parser ignores. Every
// other line lists package paths inside the most recent module
// and doesn't affect enumeration.
//
// [Go vendoring reference]: https://go.dev/ref/mod#vendoring
func Parse(r io.Reader) ([]Module, error) {
	var mods []Module
	scanner := bufio.NewScanner(r)
	scanner.Buffer(make([]byte, 0, scannerInitialBufSize), scannerMaxBufSize)
	lineNo := 0
	for scanner.Scan() {
		lineNo++
		line := scanner.Text()
		if !strings.HasPrefix(line, "# ") || strings.HasPrefix(line, "## ") {
			continue
		}
		mod, ok := parseLine(strings.TrimPrefix(line, "# "))
		if !ok {
			continue
		}
		mod.Line = lineNo
		mods = append(mods, mod)
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("scan: %w", err)
	}
	return mods, nil
}

// parseLine parses one declaration after the caller strips the
// "# " prefix. Returns a false second return for replaced-to-local
// modules and other shapes the parser can't handle, leaving the
// caller to drop them.
//
// Recognized forms with their resolved Module entry:
//
//	<path> <version>                                       -> (path, version)
//	<path> <version> => <replacement-path> <repl-version>  -> (repl-path, repl-version)
//	<path> => <replacement-path> <replacement-version>     -> (repl-path, repl-version)
//
// Anything else (including replaced-to-local) falls through to
// the trailing return, which yields the drop sentinel. Folding
// the drop case into the trailing return avoids a dedicated
// branch that would read as observationally identical and live
// through mutation testing. The if/else chain rather than a
// switch-true form keeps each predicate inside a statement block
// that Go's coverage profile can attach a count to.
func parseLine(line string) (Module, bool) {
	fields := strings.Fields(line)
	if len(fields) >= 4 && fields[len(fields)-3] == "=>" {
		return Module{Path: fields[len(fields)-2], Version: fields[len(fields)-1]}, true
	}
	if len(fields) == plainModuleFields {
		return Module{Path: fields[0], Version: fields[1]}, true
	}
	return Module{}, false
}
