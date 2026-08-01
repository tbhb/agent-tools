// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of Proofhouse

// Package pkgsite provides a minimal client for the public pkg.go.dev
// /v1beta API documented at https://go.dev/blog/pkgsite-api. The
// depscan tool uses it to retrieve per-version deprecation and
// retraction status for each vendored module.
//
// The client wraps GET /v1beta/versions/{module}, decodes the
// [ModuleVersion] records, and walks the nextPageToken chain so the
// caller sees the full version list. Other v1beta endpoints
// (package, search, vulns) stay out of scope.
//
// Field shapes mirror golang/pkgsite's
// cmd/internal/pkgsite-cli/client/types_gen.go, the reference CLI
// from the announcement blog post. The struct duplicates those
// fields rather than importing the internal package, so the API
// contract stays explicit here.
package pkgsite

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"time"
)

const (
	// DefaultBaseURL points at the public pkg.go.dev v1beta host.
	// Tests override via [Client.BaseURL].
	DefaultBaseURL = "https://pkg.go.dev"

	// DefaultUserAgent identifies gomodscan traffic to pkg.go.dev. The
	// reference pkgsite-cli client sets a similar self-describing
	// header. A descriptive value lets the upstream operator tell
	// these requests apart from a generic Go HTTP client.
	DefaultUserAgent = "gomodscan/1 (+https://github.com/proofhouse/gomodscan)"

	// defaultPageLimit caps items per page. The API enforces its
	// own ceiling. This value bounds the response size for modules
	// with hundreds of tagged versions.
	defaultPageLimit = 200

	// defaultTimeout matches the per-request budget the reference
	// pkgsite-cli uses.
	defaultTimeout = 30 * time.Second
)

// ErrNotFound reports that pkg.go.dev doesn't recognize the module.
// Private modules, modules replaced to a local path, and modules
// never indexed surface as HTTP 404. Callers typically skip them
// rather than treating the result as a failure.
var ErrNotFound = errors.New("module not indexed on pkg.go.dev")

// ErrUnexpectedStatus reports that pkg.go.dev returned an HTTP
// status outside the contract (neither 200 nor 404). The wrapped
// message records the request URL and the status code so the
// caller can decide whether to retry or surface the failure.
var ErrUnexpectedStatus = errors.New("unexpected status from pkg.go.dev")

// defaultHTTPClient backs every [Client] value that doesn't override
// [Client.HTTPClient]. One shared client (and one shared transport)
// lets the underlying connection pool serve every module lookup,
// which avoids a fresh TLS handshake per page.
//
//nolint:gochecknoglobals // intentional process-wide singleton for connection pooling.
var defaultHTTPClient = &http.Client{Timeout: defaultTimeout}

// ModuleVersion mirrors the entry shape returned by
// /v1beta/versions/{module}. Field names match the JSON keys the
// upstream OpenAPI spec documents.
type ModuleVersion struct {
	ModulePath        string    `json:"modulePath"`
	Version           string    `json:"version"`
	CommitTime        time.Time `json:"commitTime"`
	IsRedistributable bool      `json:"isRedistributable"`
	HasGoMod          bool      `json:"hasGoMod"`
	LatestVersion     string    `json:"latestVersion"`
	Deprecated        bool      `json:"deprecated"`
	DeprecationReason string    `json:"deprecationReason"`
	Retracted         bool      `json:"retracted"`
	RetractionReason  string    `json:"retractionReason"`
}

// Client fetches module-version metadata from a pkg.go.dev v1beta
// server. The zero value targets the public host with a 30 s
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

// page wraps the paginated response shape the API returns.
type page struct {
	Items         []ModuleVersion `json:"items"`
	Total         int             `json:"total"`
	NextPageToken string          `json:"nextPageToken,omitempty"`
}

// Versions returns every ModuleVersion record pkg.go.dev knows for
// the given module path, walking the nextPageToken chain until the
// API signals exhaustion. Returns ErrNotFound (wrapped) when the
// API responds 404.
func (c *Client) Versions(ctx context.Context, module string) ([]ModuleVersion, error) {
	var all []ModuleVersion
	token := ""
	for {
		p, err := c.fetchPage(ctx, module, token)
		if err != nil {
			return nil, err
		}
		all = append(all, p.Items...)
		if p.NextPageToken == "" {
			return all, nil
		}
		token = p.NextPageToken
	}
}

func (c *Client) fetchPage(ctx context.Context, module, token string) (*page, error) {
	reqURL, err := c.buildURL(module, token)
	if err != nil {
		return nil, err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, reqURL, nil)
	if err != nil {
		return nil, fmt.Errorf("build request for %s: %w", module, err)
	}
	req.Header.Set("User-Agent", c.userAgent())
	req.Header.Set("Accept", "application/json")

	resp, err := c.httpClient().Do(req)
	if err != nil {
		return nil, fmt.Errorf("GET %s: %w", reqURL, err)
	}
	defer resp.Body.Close()

	switch resp.StatusCode {
	case http.StatusOK:
		var p page
		if decErr := json.NewDecoder(resp.Body).Decode(&p); decErr != nil {
			return nil, fmt.Errorf("decode %s: %w", module, decErr)
		}
		return &p, nil
	case http.StatusNotFound:
		return nil, fmt.Errorf("%w: %s", ErrNotFound, module)
	default:
		return nil, fmt.Errorf("%w: GET %s: status %d", ErrUnexpectedStatus, reqURL, resp.StatusCode)
	}
}

func (c *Client) buildURL(module, token string) (string, error) {
	base, err := url.Parse(c.baseURL())
	if err != nil {
		return "", fmt.Errorf("parse base URL %q: %w", c.baseURL(), err)
	}
	u := base.JoinPath("v1beta", "versions", module)
	q := u.Query()
	q.Set("limit", strconv.Itoa(defaultPageLimit))
	if token != "" {
		q.Set("token", token)
	}
	u.RawQuery = q.Encode()
	return u.String(), nil
}
