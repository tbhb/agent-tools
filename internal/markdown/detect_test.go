// SPDX-License-Identifier: Apache-2.0
// Copyright Tony Burns

package markdown_test

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/tbhb/agent-tools/internal/markdown"
)

// wrapped is five lines, so its four breaks clear MinEvidence and the report
// is willing to name a cause. A shorter sample remains a violation, but it
// reports no cause. See the thin-evidence case in TestCause.
const wrapped = "This paragraph has been hard-wrapped by an agent at roughly column\n" +
	"seventy-two, which is exactly the behavior this hook exists to\n" +
	"refuse before it can ever reach the disk in the first place, and\n" +
	"it runs on long enough to give the sweep something to work with\n" +
	"and to clear the evidence floor the report needs to name a cause.\n"

const clean = "A single-line paragraph, exactly as the convention requires.\n"

func TestParagraphs(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name  string
		input string
		want  int // number of violating runs
	}{
		{"single line is not a run", clean, 0},
		{"adjacent prose lines form a run", "alpha beta\ngamma delta\n", 1},
		{"blank line separates runs", "one two\nthree four\n\nfive six\nseven\n", 2},
		{"empty document", "", 0},
		{"fenced code is never a run", "```py\nx = 1\ny = 2\n```\n", 0},
		{"tilde fence is never a run", "~~~\nx = 1\ny = 2\n~~~\n", 0},
		{"unterminated fence swallows the rest", "```\nstill code\nmore code\n", 0},
		{"front matter is skipped", "---\ntitle: a\ntags:\n  - one\n---\n\n" + clean, 0},
		{"toml front matter is skipped", "+++\na = 1\nb = 2\n+++\n\n" + clean, 0},
		{"unterminated front matter is content", "---\nalpha beta\ngamma delta\n", 1},
		{"heading closes a run", "# Heading\n# Another\n", 0},
		{"table rows close a run", "| a | b |\n| c | d |\n", 0},
		{"html block closes a run", "<div>\n<span>\n", 0},
		{"link reference definitions close a run", "[a]: http://x\n[b]: http://y\n", 0},
		{"thematic breaks close a run", "---\n***\n", 0},
		{"indented code outside a paragraph", "    code one\n    code two\n", 0},
		{"indented continuation inside a paragraph", "- an item that runs on\n    and on\n", 1},
		{"new list item starts a new run", "- first item\n- second item\n", 0},
		{"wrapped list item is a run", "- an item that carries on\n  onto a second line\n", 1},
		{"ordered list item marker", "1. first item\n2. second item\n", 0},
		{"two-space break closes a run", "a line ending in two spaces  \nnext line\n", 0},
		{"backslash break closes a run", "a line ending in a backslash\\\nnext line\n", 0},
		{"crlf is normalized", "alpha beta\r\ngamma delta\r\n", 1},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			assert.Len(t, markdown.Paragraphs(tc.input), tc.want)
		})
	}
}

func TestParagraphBounds(t *testing.T) {
	t.Parallel()

	found := markdown.Paragraphs("# T\n\nalpha beta\ngamma delta\nepsilon\n")
	require.Len(t, found, 1)
	assert.Equal(t, 3, found[0].Start)
	assert.Equal(t, 5, found[0].End())
}

func TestStripPrefix(t *testing.T) {
	t.Parallel()

	cases := []struct{ line, prefix, rest string }{
		{"plain text", "", "plain text"},
		{"- an item", "- ", "an item"},
		{"1. an item", "1. ", "an item"},
		{"> quoted", "> ", "quoted"},
		{"> - quoted item", "> - ", "quoted item"},
	}

	for _, tc := range cases {
		t.Run(tc.line, func(t *testing.T) {
			t.Parallel()
			prefix, rest := markdown.StripPrefix(tc.line)
			assert.Equal(t, tc.prefix, prefix)
			assert.Equal(t, tc.rest, rest)
		})
	}
}

func TestInferWidth(t *testing.T) {
	t.Parallel()

	t.Run("no breaks infers nothing", func(t *testing.T) {
		t.Parallel()
		width, count := markdown.InferWidth(nil)
		assert.Zero(t, width)
		assert.Zero(t, count)
	})

	t.Run("break outside the candidate range is ignored", func(t *testing.T) {
		t.Parallel()
		// Ends at column 5 with a two-character next word: no width in
		// [MinWidth, MaxWidth] explains it.
		width, count := markdown.InferWidth([]markdown.Break{{End: 5, Word: 2}})
		assert.Zero(t, width)
		assert.Zero(t, count)
	})

	t.Run("agreeing breaks pick the shared column", func(t *testing.T) {
		t.Parallel()
		width, count := markdown.InferWidth([]markdown.Break{
			{End: 68, Word: 6},
			{End: 70, Word: 4},
		})
		assert.Equal(t, 2, count)
		assert.Equal(t, 70, width)
	})
}

func TestBreakExplainedBy(t *testing.T) {
	t.Parallel()

	b := markdown.Break{End: 68, Word: 6}
	assert.True(t, b.ExplainedBy(68), "lower bound")
	assert.True(t, b.ExplainedBy(74), "upper bound")
	assert.False(t, b.ExplainedBy(67), "below the line's own end")
	assert.False(t, b.ExplainedBy(75), "next word would have fit")
}

func TestBreaksSkipsBlankContinuation(t *testing.T) {
	t.Parallel()

	// A run whose second line carries no words yields no measurable break.
	got := markdown.Breaks([]markdown.Paragraph{{Start: 1, Lines: []string{"alpha", "   "}}})
	assert.Empty(t, got)
}

func TestBreaksExpandsTabs(t *testing.T) {
	t.Parallel()

	got := markdown.Breaks([]markdown.Paragraph{{Start: 1, Lines: []string{"\tab", "next"}}})
	require.Len(t, got, 1)
	// One tab advances to column 8, then two characters.
	assert.Equal(t, 10, got[0].End)
}

func TestCause(t *testing.T) {
	t.Parallel()

	t.Run("width wrapped names the column", func(t *testing.T) {
		t.Parallel()
		r := markdown.Analyze(wrapped)
		assert.True(t, r.Wrapped())
		assert.Contains(t, r.Cause(), "hard-wrapped at column")
	})

	t.Run("sentence per line is named semantic", func(t *testing.T) {
		t.Parallel()
		r := markdown.Analyze("Short one.\n" +
			"This second sentence is considerably longer than the first was.\n" +
			"Tiny.\n" +
			"Another middling sentence goes here.\n" +
			"And now a really quite long closing sentence to finish it off.\n" +
			"End.\n")
		assert.False(t, r.Wrapped())
		assert.True(t, r.Semantic())
		assert.Equal(t, "broken one sentence per line", r.Cause())
	})

	t.Run("thin evidence names no cause", func(t *testing.T) {
		t.Parallel()
		r := markdown.Analyze("alpha beta gamma\ndelta epsilon zeta\n")
		assert.False(t, r.Wrapped())
		assert.False(t, r.Semantic())
		assert.Equal(t, "split across multiple lines", r.Cause())
	})

	t.Run("clean document has no breaks", func(t *testing.T) {
		t.Parallel()
		r := markdown.Analyze(clean)
		assert.True(t, r.OK())
		assert.Zero(t, r.Total)
		assert.False(t, r.Wrapped())
		assert.False(t, r.Semantic())
	})
}

func TestUnwrap(t *testing.T) {
	t.Parallel()

	cases := []struct{ name, input, want string }{
		{"clean text unchanged", clean, clean},
		{"paragraph joined", "alpha beta\ngamma delta\n", "alpha beta gamma delta\n"},
		{"list marker preserved", "- alpha beta\n  gamma delta\n", "- alpha beta gamma delta\n"},
		{"quote marker preserved", "> alpha beta\n> gamma delta\n", "> alpha beta gamma delta\n"},
		{"missing trailing newline not invented", "alpha beta\ngamma delta", "alpha beta gamma delta"},
		{
			"surrounding structure survives",
			"# Title\n\nalpha beta\ngamma delta\n\n```\ncode\n```\n",
			"# Title\n\nalpha beta gamma delta\n\n```\ncode\n```\n",
		},
		{"indentation preserved", "  alpha beta\n  gamma delta\n", "  alpha beta gamma delta\n"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			assert.Equal(t, tc.want, markdown.Unwrap(tc.input))
		})
	}
}

func TestUnwrapIsIdempotentAndClean(t *testing.T) {
	t.Parallel()

	once := markdown.Unwrap(wrapped)
	assert.True(t, markdown.Analyze(once).OK(), "result passes a second check")
	assert.Equal(t, once, markdown.Unwrap(once), "fixing twice changes nothing")
}

// TestUnwrapRoundTrip is the invariant worth pinning: a paragraph wrapped at
// any plausible column is both flagged and restored exactly.
func TestUnwrapRoundTrip(t *testing.T) {
	t.Parallel()

	words := strings.Fields("the quick brown fox jumps over a lazy dog while " +
		"several other creatures look on with mild interest and considerable " +
		"patience until the whole scene finally resolves itself completely")
	original := strings.Join(words, " ")

	for width := markdown.MinWidth; width <= markdown.MaxWidth; width++ {
		got := markdown.Unwrap(fill(words, width) + "\n")
		assert.Equal(t, original+"\n", got, "width %d", width)
	}
}

func TestDescribe(t *testing.T) {
	t.Parallel()

	lines := markdown.Describe("a.md", markdown.Analyze(wrapped))
	require.Len(t, lines, 1)
	assert.Contains(t, lines[0], "a.md:1: error: check-markdown:")
	assert.Contains(t, lines[0], "join lines 1-5 into one line")
}

func TestDenyReason(t *testing.T) {
	t.Parallel()

	reason := markdown.DenyReason("a.md", markdown.Analyze(wrapped))
	assert.Contains(t, reason, "a.md is hard-wrapped at column")
	assert.Contains(t, reason, "never hard-wrapped")
	assert.Contains(t, reason, "1-5")
}

func TestIsMarkdown(t *testing.T) {
	t.Parallel()

	cases := map[string]bool{
		"a.md": true, "a.markdown": true, "A.MD": true,
		"dir/b.Md": true, "a.go": false, "a": false, "a.mdx": false,
	}
	for name, want := range cases {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			assert.Equal(t, want, markdown.IsMarkdown(name))
		})
	}
}

// fill wraps words at the given column, the way a hard-wrapping editor would.
func fill(words []string, width int) string {
	var b strings.Builder
	col := 0
	for i, w := range words {
		switch {
		case i == 0:
			b.WriteString(w)
			col = len(w)
		case col+1+len(w) > width:
			b.WriteString("\n" + w)
			col = len(w)
		default:
			b.WriteString(" " + w)
			col += 1 + len(w)
		}
	}
	return b.String()
}
