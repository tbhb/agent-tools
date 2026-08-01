// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of Proofhouse

// Command gomodscan scans the modules a Go project vendors and reports
// two supply chain concerns in a single pass: dependencies that
// pkg.go.dev marks as retracted at the pinned version or deprecated at
// their latest version (S2C2F SCA-3), and dependencies that the OSV
// malicious-package registry flags as malware (S2C2F ING-3).
//
// Usage: gomodscan [-modroot dir] [-format text|sarif] [-version]
//
// gomodscan reads vendor/modules.txt under -modroot (defaults to the
// current working directory) and enumerates the vendored module set.
// For each module it queries pkg.go.dev /v1beta/versions/{module} for
// deprecation and retraction status, and the OSV /v1/query endpoint for
// malicious-package advisories under the MAL- ID prefix. Modules
// replaced to a local path fall outside both registries and get
// skipped.
//
// The -format flag selects the finding emitter. Text output (the
// default) follows the unified shape documented in the [findings]
// package. SARIF output emits a v2.1.0 report suitable for ingestion by
// GitHub Code Scanning.
//
// [findings]: https://pkg.go.dev/github.com/proofhouse/gomodscan/internal/findings
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/proofhouse/gomodscan/internal/buildmeta"
	"github.com/proofhouse/gomodscan/internal/exitcode"
	"github.com/proofhouse/gomodscan/internal/findings"
	"github.com/proofhouse/gomodscan/internal/osv"
	"github.com/proofhouse/gomodscan/internal/pkgsite"
	"github.com/proofhouse/gomodscan/internal/vendormod"
)

const (
	toolName = "gomodscan"

	// vendorModulesPath names the repo-root-relative file each SARIF
	// result points at. gomodscan reads it to list the vendored module
	// set, the physical location GitHub Code Scanning anchors every
	// finding on.
	vendorModulesPath = "vendor/modules.txt"

	// goEcosystem names the Go ecosystem in OSV requests.
	goEcosystem = "Go"

	// maliciousIDPrefix marks advisories that flag a release as
	// malware rather than as a known vulnerability. The OSSF
	// malicious-packages dataset reserves this prefix.
	maliciousIDPrefix = "MAL-"
)

// errUnknownFormat reports that the -format flag carried a value
// outside the {text, sarif} allowlist. The sentinel form supports
// programmatic matching and keeps wrapcheck and err113 quiet.
var errUnknownFormat = errors.New("unknown -format (want text or sarif)")

// versionsClient abstracts the slice of [pkgsite.Client] the deprecated
// scanner needs. The interface keeps run injectable from tests, so the
// table-driven cases that mutation testing relies on don't have to
// stand up a real HTTP transport for every branch.
type versionsClient interface {
	Versions(ctx context.Context, module string) ([]pkgsite.ModuleVersion, error)
}

// vulnsClient abstracts the slice of [osv.Client] the malicious scanner
// needs. Keeping run injectable lets the table-driven cases drive every
// branch through a stub rather than an httptest server.
type vulnsClient interface {
	Query(ctx context.Context, pkg osv.Package, version string) ([]osv.Vulnerability, error)
}

// findingKind enumerates the issue classes gomodscan reports. The
// string value doubles as the SARIF ruleId.
type findingKind string

const (
	kindRetracted  findingKind = "retracted"
	kindDeprecated findingKind = "deprecated"
	kindMalicious  findingKind = "malicious-package"
)

// finding describes a single hit from either scanner. The kind selects
// which fields carry meaning: retracted uses reason; deprecated adds
// latest; malicious-package uses id and summary.
type finding struct {
	kind    findingKind
	module  string
	version string
	line    int
	latest  string
	reason  string
	id      string
	summary string
}

// level maps a finding to its SARIF severity. A malicious-package hit
// names live malware, so it reports at error. A deprecation or
// retraction warns the caller to act, so it reports at warning.
func (f finding) level() findings.Level {
	if f.kind == kindMalicious {
		return findings.LevelError
	}
	return findings.LevelWarning
}

// props returns the property bag for this finding in the shape shared
// by the text and SARIF emitters. Keys match SARIF property names so
// consumers reading either output channel see the same vocabulary.
func (f finding) props() map[string]string {
	if f.kind == kindMalicious {
		p := map[string]string{"id": f.id}
		if f.summary != "" {
			p["summary"] = strings.TrimSpace(f.summary)
		}
		return p
	}
	p := make(map[string]string)
	if f.reason != "" {
		p["reason"] = strings.TrimSpace(f.reason)
	}
	if f.kind == kindDeprecated && f.latest != "" {
		p["latest"] = f.latest
	}
	return p
}

// message returns the prose used as the SARIF result message. The text
// emitter doesn't use it; the unified text format encodes the same
// information through level/rule/properties.
func (f finding) message() string {
	switch f.kind {
	case kindRetracted:
		return fmt.Sprintf("Module retracted at %s. %s", f.version, reasonSentence(f.reason))
	case kindDeprecated:
		return fmt.Sprintf("Module deprecated at latest version %s. %s", f.latest, reasonSentence(f.reason))
	case kindMalicious:
		if f.summary == "" {
			return fmt.Sprintf("OSV malicious-package advisory %s.", f.id)
		}
		return fmt.Sprintf("OSV malicious-package advisory %s: %s.", f.id, strings.TrimSpace(f.summary))
	default:
		return "Unknown finding."
	}
}

func reasonSentence(r string) string {
	if r == "" {
		return "No reason recorded."
	}
	return "Reason: " + strings.TrimSpace(r) + "."
}

func main() {
	os.Exit(realMain(os.Args[1:], os.Stdout, os.Stderr))
}

// realMain wraps the imperative flag-parsing and exit-code wiring in a
// function that the test harness can drive. The split keeps main itself
// trivial enough to verify by inspection and lets mutation testing
// exercise the error-log branch via real arguments and writers rather
// than the exit call.
func realMain(args []string, out, errOut io.Writer) int {
	fs := flag.NewFlagSet(toolName, flag.ContinueOnError)
	fs.SetOutput(errOut)
	modroot := fs.String("modroot", "", "module root to scan (defaults to cwd)")
	format := fs.String("format", "text", "output format: text or sarif")
	showVersion := fs.Bool("version", false, "print version information and exit")
	if err := fs.Parse(args); err != nil {
		return exitcode.ToolFailure
	}

	if *showVersion {
		info := buildmeta.Get()
		fmt.Fprintf(out, "%s %s\ncommit: %s\ndate:   %s\n", toolName, info.Version, info.Commit, info.Date)
		return exitcode.OK
	}

	rc, err := run(context.Background(), *modroot, *format, &pkgsite.Client{}, &osv.Client{}, out, errOut)
	if err != nil {
		fmt.Fprintf(errOut, "%s: %v\n", toolName, err)
	}
	return rc
}

// run reads the vendored module set once and runs both scanners over
// it, accumulating findings in module order (the deprecated check
// before the malicious check for each module). A per-module lookup
// error logs to errOut and drops that scanner's result for that module
// without failing the run; only a failure to read the module set or
// emit the findings returns a tool-failure code.
func run(
	ctx context.Context,
	modroot, format string,
	versions versionsClient,
	vulns vulnsClient,
	out, errOut io.Writer,
) (int, error) {
	mods, err := vendormod.Read(modroot)
	if err != nil {
		return exitcode.ToolFailure, fmt.Errorf("read vendored modules: %w", err)
	}

	var hits []finding
	for _, mod := range mods {
		dep, depErr := evaluateDeprecated(ctx, versions, mod)
		if depErr != nil {
			fmt.Fprintf(errOut, "%s: %s: %v\n", toolName, mod.Path, depErr)
		} else {
			hits = append(hits, dep...)
		}

		mal, malErr := evaluateMalicious(ctx, vulns, mod)
		if malErr != nil {
			fmt.Fprintf(errOut, "%s: %s: %v\n", toolName, mod.Path, malErr)
		} else {
			hits = append(hits, mal...)
		}
	}

	if emitErr := emitFindings(out, format, hits); emitErr != nil {
		return exitcode.ToolFailure, fmt.Errorf("emit findings: %w", emitErr)
	}

	if len(hits) > 0 {
		fmt.Fprintf(errOut, "%s: %d finding(s) across %d module(s)\n", toolName, len(hits), len(mods))
		return exitcode.Findings, nil
	}
	fmt.Fprintf(errOut, "%s: scanned %d module(s), no findings\n", toolName, len(mods))
	return exitcode.OK, nil
}

func emitFindings(out io.Writer, format string, hits []finding) error {
	switch format {
	case "text":
		return emitText(out, hits)
	case "sarif":
		return emitSARIF(out, hits)
	default:
		return fmt.Errorf("%w: %q", errUnknownFormat, format)
	}
}

func emitText(out io.Writer, hits []finding) error {
	for _, f := range hits {
		if err := findings.WriteText(
			out,
			f.level(),
			toolName,
			string(f.kind),
			f.module,
			f.version,
			f.props(),
		); err != nil {
			return fmt.Errorf("emit text finding for %s: %w", f.module, err)
		}
	}
	return nil
}

func emitSARIF(out io.Writer, hits []finding) error {
	run := findings.NewRun(toolName)
	run.AddRule(string(kindRetracted)).
		WithDescription("Module is retracted at the pinned version").
		WithHelpURI("https://go.dev/ref/mod#go-mod-file-retract")
	run.AddRule(string(kindDeprecated)).
		WithDescription("Module is deprecated at its latest version").
		WithHelpURI("https://go.dev/ref/mod#go-mod-file-module-deprecation")
	run.AddRule(string(kindMalicious)).
		WithDescription("Module appears in the OSV malicious-package registry").
		WithHelpURI("https://github.com/ossf/malicious-packages")
	for _, f := range hits {
		findings.AddResult(run, string(f.kind), f.level(), f.message(), f.module, f.version,
			findings.Location{URI: vendorModulesPath, Line: f.line}, f.props())
	}
	if err := findings.WriteSARIF(out, run); err != nil {
		return fmt.Errorf("emit sarif: %w", err)
	}
	return nil
}

// evaluateDeprecated looks up the module on pkg.go.dev and classifies
// its retraction and deprecation status. A not-found result marks the
// module as private, replaced, or not indexed, so the scan skips it.
func evaluateDeprecated(ctx context.Context, client versionsClient, mod vendormod.Module) ([]finding, error) {
	versions, err := client.Versions(ctx, mod.Path)
	if err != nil {
		if errors.Is(err, pkgsite.ErrNotFound) {
			return nil, nil // private, replaced, or not indexed: skip
		}
		return nil, fmt.Errorf("lookup versions: %w", err)
	}
	return collectDeprecated(mod, versions), nil
}

// collectDeprecated walks the version records once and emits one hit
// per concern. Retraction looks at the entry whose version matches the
// vendored pin; deprecation looks at the entry the API names as latest.
// The Go module system stores deprecation on the most recent version's
// go.mod, so any older deprecation flags stay informational rather than
// authoritative.
func collectDeprecated(mod vendormod.Module, versions []pkgsite.ModuleVersion) []finding {
	if len(versions) == 0 {
		return nil
	}
	latest := versions[0].LatestVersion
	var hits []finding
	for _, v := range versions {
		if v.Version == mod.Version && v.Retracted {
			hits = append(hits, finding{
				kind:    kindRetracted,
				module:  mod.Path,
				version: mod.Version,
				line:    mod.Line,
				reason:  v.RetractionReason,
			})
		}
		if v.Version == latest && v.Deprecated {
			hits = append(hits, finding{
				kind:    kindDeprecated,
				module:  mod.Path,
				version: mod.Version,
				line:    mod.Line,
				latest:  latest,
				reason:  v.DeprecationReason,
			})
		}
	}
	return hits
}

// evaluateMalicious queries OSV for the module at its pinned version and
// classifies the response. OSV returns 200 with an empty list for
// unknown packages, so an empty result signals the common clean state,
// not an error.
func evaluateMalicious(ctx context.Context, client vulnsClient, mod vendormod.Module) ([]finding, error) {
	vulns, err := client.Query(ctx, osv.Package{Name: mod.Path, Ecosystem: goEcosystem}, mod.Version)
	if err != nil {
		return nil, fmt.Errorf("lookup vulns: %w", err)
	}
	return collectMalicious(mod, vulns), nil
}

// collectMalicious walks the OSV response and emits one finding per
// advisory whose ID uses the MAL- prefix. Other advisory prefixes
// (GO-, GHSA-, CVE-) describe regular vulnerabilities rather than
// malware reports and belong to the govulncheck recipe.
func collectMalicious(mod vendormod.Module, vulns []osv.Vulnerability) []finding {
	var hits []finding
	for _, v := range vulns {
		if !strings.HasPrefix(v.ID, maliciousIDPrefix) {
			continue
		}
		hits = append(hits, finding{
			kind:    kindMalicious,
			module:  mod.Path,
			version: mod.Version,
			line:    mod.Line,
			id:      v.ID,
			summary: v.Summary,
		})
	}
	return hits
}
