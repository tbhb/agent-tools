// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of Proofhouse

// Package osv provides a minimal client for the OSV.dev v1 API
// documented in the [OSV.dev API reference]. The malscan tool uses
// it to retrieve vulnerability records for each vendored module and
// filter for the malicious-package advisories published under the
// MAL- ID prefix.
//
// The client wraps POST /v1/query and decodes the [Vulnerability]
// subset of the [OSV schema]. Other endpoints (querybatch,
// vulns/{id}) stay out of scope.
//
// Field shapes mirror the upstream JSON-schema field names rather
// than the protobuf-generated Go types in the [google/osv.dev]
// repository, so the API contract stays explicit here without a
// transitive dependency on that module.
//
// [OSV.dev API reference]: https://google.github.io/osv.dev/api/
// [OSV schema]: https://ossf.github.io/osv-schema/
// [google/osv.dev]: https://github.com/google/osv.dev
package osv

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"time"
)

const (
	// DefaultBaseURL points at the public OSV.dev v1 host. Tests
	// override via [Client.BaseURL].
	DefaultBaseURL = "https://api.osv.dev"

	// DefaultUserAgent identifies gomodscan traffic to OSV.dev. A
	// descriptive value lets the upstream operator tell these
	// requests apart from a generic Go HTTP client.
	DefaultUserAgent = "gomodscan/1 (+https://github.com/proofhouse/gomodscan)"

	// defaultTimeout caps each per-module query. Most OSV responses
	// complete in under a second; thirty seconds leaves headroom for
	// slow links without letting a hung connection stall the scan.
	defaultTimeout = 30 * time.Second
)

// ErrUnexpectedStatus reports that OSV.dev returned an HTTP status
// outside the contract (anything other than 200). The wrapped
// message records the request URL and the status code so the caller
// can decide whether to retry or surface the failure. OSV returns
// 200 with an empty vulns array for any package, including ones
// it doesn't recognize, so no separate not-found sentinel applies.
var ErrUnexpectedStatus = errors.New("unexpected status from osv.dev")

// defaultHTTPClient backs every [Client] value that doesn't override
// [Client.HTTPClient]. One shared client (and one shared transport)
// lets the underlying connection pool serve every module lookup,
// which avoids a fresh TLS handshake per query.
//
//nolint:gochecknoglobals // intentional process-wide singleton for connection pooling.
var defaultHTTPClient = &http.Client{Timeout: defaultTimeout}

// Package locates a single module within an OSV ecosystem. For Go
// modules, set Ecosystem to "Go" and Name to the module path (such
// as github.com/spf13/cobra).
type Package struct {
	Name      string `json:"name"`
	Ecosystem string `json:"ecosystem"`
}

// Vulnerability mirrors the subset of the OSV record shape malscan
// needs. The full schema carries many more fields (affected ranges,
// references, severity); malscan only inspects the ID prefix and
// surfaces summary text when present.
type Vulnerability struct {
	ID        string   `json:"id"`
	Aliases   []string `json:"aliases,omitempty"`
	Summary   string   `json:"summary,omitempty"`
	Details   string   `json:"details,omitempty"`
	Modified  string   `json:"modified,omitempty"`
	Published string   `json:"published,omitempty"`
}

// queryRequest matches the JSON body shape POST /v1/query accepts.
// The upstream schema treats the version field as optional, but
// malscan always supplies it so OSV can filter for advisories that
// actually cover the pinned release.
type queryRequest struct {
	Version string  `json:"version"`
	Package Package `json:"package"`
}

// queryResponse wraps the JSON body shape POST /v1/query returns.
type queryResponse struct {
	Vulns []Vulnerability `json:"vulns"`
}

// Client posts version-and-package queries against the OSV /v1/query
// endpoint. The zero value targets the public host with a 30 s
// timeout. Tests inject an in-memory server through BaseURL.
type Client struct {
	BaseURL    string
	HTTPClient *http.Client
	UserAgent  string
}

func (c *Client) baseURL() string {
	if c.BaseURL != "" {
		return c.BaseURL
	}
	return DefaultBaseURL
}

func (c *Client) httpClient() *http.Client {
	if c.HTTPClient != nil {
		return c.HTTPClient
	}
	return defaultHTTPClient
}

func (c *Client) userAgent() string {
	if c.UserAgent != "" {
		return c.UserAgent
	}
	return DefaultUserAgent
}

// Query returns every [Vulnerability] OSV.dev knows for the given
// package at the given version. An empty slice means OSV has no
// record covering that release, the common state for well-behaved
// modules. OSV.dev returns 200 with an empty vulns array for
// unknown packages, so no separate not-found path applies.
func (c *Client) Query(ctx context.Context, pkg Package, version string) ([]Vulnerability, error) {
	reqURL, err := c.buildURL()
	if err != nil {
		return nil, err
	}

	body, err := json.Marshal(queryRequest{Version: version, Package: pkg})
	if err != nil {
		return nil, fmt.Errorf("marshal request for %s: %w", pkg.Name, err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, reqURL, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("build request for %s: %w", pkg.Name, err)
	}
	req.Header.Set("User-Agent", c.userAgent())
	req.Header.Set("Accept", "application/json")
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient().Do(req)
	if err != nil {
		return nil, fmt.Errorf("POST %s: %w", reqURL, err)
	}
	defer resp.Body.Close()

	switch resp.StatusCode {
	case http.StatusOK:
		var qr queryResponse
		if decErr := json.NewDecoder(resp.Body).Decode(&qr); decErr != nil {
			return nil, fmt.Errorf("decode %s: %w", pkg.Name, decErr)
		}
		return qr.Vulns, nil
	default:
		return nil, fmt.Errorf("%w: POST %s: status %d", ErrUnexpectedStatus, reqURL, resp.StatusCode)
	}
}

func (c *Client) buildURL() (string, error) {
	base, err := url.Parse(c.baseURL())
	if err != nil {
		return "", fmt.Errorf("parse base URL %q: %w", c.baseURL(), err)
	}
	return base.JoinPath("v1", "query").String(), nil
}
