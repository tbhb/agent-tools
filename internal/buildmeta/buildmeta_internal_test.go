// SPDX-License-Identifier: Apache-2.0
// Copyright Tony Burns

package buildmeta

import (
	"runtime/debug"
	"testing"

	"github.com/stretchr/testify/assert"
)

// TestResolveVersion drives each branch of the runtime-fallback
// chain so mutation testing finds no surviving conditional flip in
// the init-time logic. The cases pair an ldflags input with a
// hand-rolled readBuildInfo result and assert the resolved version.
func TestResolveVersion(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name           string
		ldflagsVersion string
		readBuildInfo  func() (*debug.BuildInfo, bool)
		want           string
	}{
		{
			name:           "ldflags version wins over runtime fallback",
			ldflagsVersion: "v1.2.3",
			readBuildInfo: func() (*debug.BuildInfo, bool) {
				return &debug.BuildInfo{Main: debug.Module{Version: "v9.9.9"}}, true
			},
			want: "v1.2.3",
		},
		{
			name:           "build info unavailable keeps DEV fallback",
			ldflagsVersion: "DEV",
			readBuildInfo: func() (*debug.BuildInfo, bool) {
				return nil, false
			},
			want: "DEV",
		},
		{
			name:           "build info devel placeholder keeps DEV fallback",
			ldflagsVersion: "DEV",
			readBuildInfo: func() (*debug.BuildInfo, bool) {
				return &debug.BuildInfo{Main: debug.Module{Version: "(devel)"}}, true
			},
			want: "DEV",
		},
		{
			name:           "build info concrete version replaces DEV fallback",
			ldflagsVersion: "DEV",
			readBuildInfo: func() (*debug.BuildInfo, bool) {
				return &debug.BuildInfo{Main: debug.Module{Version: "v0.4.2"}}, true
			},
			want: "v0.4.2",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			got := resolveVersion(tc.ldflagsVersion, tc.readBuildInfo)
			assert.Equal(t, tc.want, got)
		})
	}
}
