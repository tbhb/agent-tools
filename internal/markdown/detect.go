// SPDX-License-Identifier: Apache-2.0
// Copyright Tony Burns

// Package markdown detects hard-wrapped prose in Markdown documents.
//
// Markdown in tbhb repositories is never hard-wrapped. Every paragraph is a
// single line, and the renderer decides where it breaks. Hard wrapping
// belongs to commit messages and to comments in code or config, each of
// which has its own gate. A paragraph spanning two or more lines is the
// violation this package looks for.
//
// To say *why* in the failure message, the analysis also infers the wrap
// column. A break ending at column e whose next word runs n characters is
// explained by wrapping at any width from e to e+n, so every break votes for
// that interval and the column covered by the most intervals wins. Breaks no
// width explains are the author's own, one sentence per line, which the
// message names as semantic rather than width-driven because the fix differs.
//
// That inference needs evidence to be worth stating. Across a handful of
// breaks the two causes are indistinguishable: three sentences that happen to
// end near column 45 fit a wrap at 45 exactly as well as they fit deliberate
// sentence breaks. Below MinEvidence breaks the report names no cause at all.
// The verdict never changes, only the explanation offered for it.
package markdown

import (
	"fmt"
	"path/filepath"
	"regexp"
	"strings"
)

const (
	// MinWidth and MaxWidth bound the candidate wrap columns. Nothing below
	// 40 reads as a deliberate wrap setting, and past 120 the next-word test
	// stops discriminating because almost any break is explained.
	MinWidth = 40
	MaxWidth = 120

	// WrapRatio is the share of breaks the winning width must explain
	// before the report calls a document width-wrapped. Half is
	// deliberately lenient: the distinction only picks the wording of the
	// message, and both verdicts fail the gate.
	WrapRatio = 0.5

	// SemanticRatio is the share of the *unexplained* breaks that must
	// follow sentence-ending punctuation before the report calls a document
	// semantically broken rather than merely multi-line.
	SemanticRatio = 0.7

	// MinRun is the number of lines a run needs before it counts as a
	// wrapped paragraph at all.
	MinRun = 2

	// MinEvidence is the number of breaks needed before the report names
	// a cause. The package comment explains the reason.
	MinEvidence = 4

	// codeIndent is where an indented code block opens, but only outside a
	// paragraph, where the same indent instead continues a list item.
	codeIndent = 4

	// tabWidth matches the column arithmetic a renderer would apply when
	// measuring where a line ended.
	tabWidth = 8

	// deltasPerBreak is how many sweep entries each break contributes, one
	// opening its interval and one closing it. Only a capacity hint.
	deltasPerBreak = 2
)

var (
	// explicitBreak is Markdown's own line break: a line ending in two
	// spaces or a backslash. That's an instruction rather than a wrap, so it
	// closes a run instead of counting as evidence.
	explicitBreak = regexp.MustCompile(`( {2}|\\)$`)

	fence       = regexp.MustCompile("^ {0,3}(`{3,}|~{3,})")
	frontMatter = regexp.MustCompile(`^(-{3}|\+{3})\s*$`)
	listItem    = regexp.MustCompile(`^\s*([-*+]|\d+[.)])\s`)
	quote       = regexp.MustCompile(`^\s*>+\s?`)

	// sentenceEnd marks a line whose author almost surely ended it on purpose.
	sentenceEnd = regexp.MustCompile(`[.!?:;]["')\]]*$`)

	// structural matches lines that are never prose and always close a run.
	// Headings, table rows, raw HTML blocks, link reference definitions, and
	// the thematic break and setext underline family all qualify.
	structural = regexp.MustCompile(
		`^ {0,3}(#|\||<|\[[^\]]+\]:|(-{3,}|\*{3,}|_{3,}|={3,}) *$)`,
	)
)

// Paragraph is a run of adjacent prose lines.
type Paragraph struct {
	// Start is the one-indexed line number of the run's first line.
	Start int
	// Lines holds the run's lines as they appear in the document.
	Lines []string
}

// End reports the one-indexed line number of the run's last line.
func (p Paragraph) End() int { return p.Start + len(p.Lines) - 1 }

// Break is one line break inside a run of prose.
type Break struct {
	// End is the column the line ended at.
	End int
	// Word is the length of the following line's first word.
	Word int
	// Sentence records whether the line ended on sentence punctuation.
	Sentence bool
}

// ExplainedBy reports whether wrapping at width would have forced this
// break, meaning the next word couldn't have fit on the preceding line.
func (b Break) ExplainedBy(width int) bool {
	return b.End <= width && width <= b.End+b.Word
}

// Report is the verdict for one Markdown document.
type Report struct {
	// Paragraphs holds every run of two or more prose lines.
	Paragraphs []Paragraph
	// Width is the wrap column explaining the most breaks, or zero when no
	// candidate width explains any.
	Width int
	// Explained counts the breaks that Width explains.
	Explained int
	// Total counts the breaks examined.
	Total int
	// Sentences counts unexplained breaks following sentence punctuation.
	Sentences int
}

// OK reports whether the document satisfies the one-line-per-paragraph rule.
func (r Report) OK() bool { return len(r.Paragraphs) == 0 }

// Wrapped reports whether the breaks look driven by a wrap column.
func (r Report) Wrapped() bool {
	return r.Width > 0 &&
		r.Total >= MinEvidence &&
		float64(r.Explained)/float64(r.Total) >= WrapRatio
}

// Semantic reports whether the unexplained breaks land after sentence ends.
func (r Report) Semantic() bool {
	unexplained := r.Total - r.Explained
	return r.Total >= MinEvidence &&
		unexplained > 0 &&
		float64(r.Sentences)/float64(unexplained) >= SemanticRatio
}

// Cause names why the lines broke, in a phrase fit for a failure message.
func (r Report) Cause() string {
	switch {
	case r.Wrapped():
		return fmt.Sprintf("hard-wrapped at column %d", r.Width)
	case r.Semantic():
		return "broken one sentence per line"
	default:
		return "split across multiple lines"
	}
}

// splitLines divides text into lines the way a renderer would, dropping the
// empty element a trailing newline would otherwise produce.
func splitLines(text string) []string {
	text = strings.ReplaceAll(text, "\r\n", "\n")
	if text == "" {
		return nil
	}
	lines := strings.Split(text, "\n")
	if lines[len(lines)-1] == "" {
		lines = lines[:len(lines)-1]
	}
	return lines
}

// expandTabs replaces tabs with spaces to the next tab stop, so a measured
// end column matches the one a reader sees.
func expandTabs(s string) string {
	var b strings.Builder
	col := 0
	for _, r := range s {
		if r == '\t' {
			pad := tabWidth - col%tabWidth
			b.WriteString(strings.Repeat(" ", pad))
			col += pad
			continue
		}
		b.WriteRune(r)
		col++
	}
	return b.String()
}

// skipFrontMatter returns the index of the first line after any front matter.
func skipFrontMatter(lines []string) int {
	if len(lines) == 0 || !frontMatter.MatchString(lines[0]) {
		return 0
	}
	closer := strings.TrimSpace(lines[0])
	for i := 1; i < len(lines); i++ {
		if strings.TrimSpace(lines[i]) == closer {
			return i + 1
		}
	}
	return 0
}

// StripPrefix splits a leading block-quote or list marker from a line's
// text, returning the marker and what follows it.
func StripPrefix(line string) (string, string) {
	marker := ""
	if q := quote.FindString(line); q != "" {
		marker = q
	}
	after := line[len(marker):]
	if item := listItem.FindString(after); item != "" {
		marker += item
	}
	return marker, line[len(marker):]
}

// line pairs a document line with its zero-based index.
type line struct {
	index int
	text  string
}

// outsideFences walks the document with fenced code blocks removed. Fence
// bookkeeping gets its own pass so the paragraph scanner never nests run
// accumulation inside code-block state. Each fence line comes back as an
// empty line, which the scanner already treats as a run boundary. Everything
// between a pair of fences disappears.
func outsideFences(lines []string, start int) []line {
	out := make([]line, 0, len(lines))
	open := ""
	for i := start; i < len(lines); i++ {
		text := lines[i]
		if open != "" {
			if strings.HasPrefix(strings.TrimSpace(text), open) {
				open = ""
			}
			continue
		}
		if m := fence.FindStringSubmatch(text); m != nil {
			open = m[1]
			out = append(out, line{index: i, text: ""})
			continue
		}
		out = append(out, line{index: i, text: text})
	}
	return out
}

// closesRun reports whether a line can never continue a paragraph. The inside
// flag says whether a run is currently open, which decides how an indented
// line reads.
func closesRun(text string, inside bool) bool {
	indentedCode := strings.HasPrefix(text, strings.Repeat(" ", codeIndent)) && !inside
	return strings.TrimSpace(text) == "" || structural.MatchString(text) || indentedCode
}

// Paragraphs finds every run of adjacent prose lines. Structural Markdown
// never joins a run, and a new list item always starts one.
func Paragraphs(text string) []Paragraph {
	lines := splitLines(text)
	var found []Paragraph
	var run []string
	start := 0

	closeRun := func() {
		if len(run) >= MinRun {
			found = append(found, Paragraph{Start: start + 1, Lines: append([]string(nil), run...)})
		}
		run = run[:0]
	}

	for _, item := range outsideFences(lines, skipFrontMatter(lines)) {
		if closesRun(item.text, len(run) > 0) {
			closeRun()
			continue
		}
		if listItem.MatchString(item.text) {
			closeRun()
		}
		if len(run) == 0 {
			start = item.index
		}
		run = append(run, item.text)
		if explicitBreak.MatchString(item.text) {
			closeRun()
		}
	}
	closeRun()
	return found
}

// Breaks measures every line break inside the given runs.
func Breaks(found []Paragraph) []Break {
	var measured []Break
	for _, p := range found {
		for i := 0; i+1 < len(p.Lines); i++ {
			_, rest := StripPrefix(p.Lines[i+1])
			words := strings.Fields(rest)
			if len(words) == 0 {
				continue
			}
			text := strings.TrimRight(expandTabs(p.Lines[i]), " \t")
			measured = append(measured, Break{
				End:      len([]rune(text)),
				Word:     len([]rune(words[0])),
				Sentence: sentenceEnd.MatchString(text),
			})
		}
	}
	return measured
}

// InferWidth finds the wrap column explaining the most breaks, sweeping the
// intervals each break votes for. It returns the winning column and how many
// breaks that column explains, or zero for both when nothing is explained.
func InferWidth(measured []Break) (int, int) {
	delta := make(map[int]int, len(measured)*deltasPerBreak)
	for _, b := range measured {
		low := max(b.End, MinWidth)
		high := min(b.End+b.Word, MaxWidth)
		if low > high {
			continue
		}
		delta[low]++
		delta[high+1]--
	}
	width, count, running := 0, 0, 0
	for w := MinWidth; w <= MaxWidth; w++ {
		running += delta[w]
		if running > count {
			count = running
			width = w
		}
	}
	return width, count
}

// Analyze judges one Markdown document.
func Analyze(text string) Report {
	found := Paragraphs(text)
	measured := Breaks(found)
	width, explained := InferWidth(measured)

	sentences := 0
	for _, b := range measured {
		if width == 0 || !b.ExplainedBy(width) {
			if b.Sentence {
				sentences++
			}
		}
	}
	return Report{
		Paragraphs: found,
		Width:      width,
		Explained:  explained,
		Total:      len(measured),
		Sentences:  sentences,
	}
}

// Unwrap joins every wrapped paragraph back into a single line. The first
// line keeps its indentation and any list or quote marker; the rest
// contribute their text alone, joined with single spaces.
func Unwrap(text string) string {
	report := Analyze(text)
	if report.OK() {
		return text
	}
	lines := splitLines(text)
	replaced := make(map[int]string, len(report.Paragraphs))
	dropped := make(map[int]bool)

	for _, p := range report.Paragraphs {
		head := p.Lines[0]
		marker, rest := StripPrefix(head)
		if marker == "" {
			marker = head[:len(head)-len(strings.TrimLeft(head, " \t"))]
		}
		parts := make([]string, 0, len(p.Lines))
		parts = append(parts, strings.TrimSpace(rest))
		for _, l := range p.Lines[1:] {
			_, body := StripPrefix(l)
			parts = append(parts, strings.TrimSpace(body))
		}
		replaced[p.Start-1] = marker + strings.Join(parts, " ")
		for i := p.Start; i < p.End(); i++ {
			dropped[i] = true
		}
	}

	rebuilt := make([]string, 0, len(lines))
	for i, l := range lines {
		if dropped[i] {
			continue
		}
		if r, ok := replaced[i]; ok {
			l = r
		}
		rebuilt = append(rebuilt, l)
	}
	out := strings.Join(rebuilt, "\n")
	if strings.HasSuffix(text, "\n") {
		out += "\n"
	}
	return out
}

// Describe renders one self-contained line per violating paragraph.
func Describe(path string, report Report) []string {
	out := make([]string, 0, len(report.Paragraphs))
	for _, p := range report.Paragraphs {
		out = append(out, fmt.Sprintf(
			"%s:%d: error: guard-markdown: paragraph spans %d lines (%s); join lines %d-%d into one line",
			path, p.Start, len(p.Lines), report.Cause(), p.Start, p.End(),
		))
	}
	return out
}

// DenyReason builds the message shown to an agent when a write is refused.
func DenyReason(path string, report Report) string {
	spans := make([]string, 0, len(report.Paragraphs))
	for _, p := range report.Paragraphs {
		spans = append(spans, fmt.Sprintf("%d-%d", p.Start, p.End()))
	}
	return fmt.Sprintf(
		"%s is %s. Markdown in this repository is never hard-wrapped: write "+
			"each paragraph as one long line and let the renderer wrap it. "+
			"Rewrite these line ranges as a single line each: %s.",
		path, report.Cause(), strings.Join(spans, ", "),
	)
}

// IsMarkdown reports whether a path names a Markdown document.
func IsMarkdown(path string) bool {
	lower := strings.ToLower(path)
	return strings.HasSuffix(lower, ".md") || strings.HasSuffix(lower, ".markdown")
}

// generatedChangelog is the one document this check never judges. A
// changelog generator writes it from commit messages, which are hard-wrapped
// under their own gate, so the wrapping arrives with the content and no
// author is in a position to unwrap it. Unwrapping it by hand only holds
// until the next release regenerates the file.
//
// The match is exact, on the base name alone.
const generatedChangelog = "CHANGELOG.md"

// Checked reports whether this check judges the document at path. Every
// caller asks this one question, so the hook, the file check, and the fixer
// can't come to different answers about the same path.
func Checked(path string) bool {
	return IsMarkdown(path) && filepath.Base(path) != generatedChangelog
}
