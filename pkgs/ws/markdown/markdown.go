// Package markdown renders markdown for a terminal pane: glamour for text
// and code, and pictures and mermaid diagrams as Kitty images.
package markdown

import (
	"bytes"
	"cmp"
	"encoding/json"
	"hash/fnv"
	"image"
	"image/png"
	"regexp"
	"strings"
	"workspace/kitty"

	"github.com/charmbracelet/glamour"
	"github.com/charmbracelet/glamour/ansi"
	"github.com/charmbracelet/glamour/styles"
	"github.com/charmbracelet/lipgloss"
	"github.com/muesli/termenv"
	"github.com/yuin/goldmark"
	"github.com/yuin/goldmark/ast"
	"github.com/yuin/goldmark/extension"
	gmtext "github.com/yuin/goldmark/text"
)

// Options are what rendering needs from the program around it.
type Options struct {
	Dark bool // Catppuccin Mocha, or Latte
	// Style is a glamour style as JSON, which colors everything, code
	// included. Without one, text takes glamour's own style for the mode and
	// code takes Catppuccin's.
	Style    []byte
	Terminal kitty.Terminal // where pictures are drawn, or one line of their description
	// Fetch loads a picture's source, such as a URL or a path.
	Fetch func(src string) (image.Image, error)
	// Mermaid draws a diagram's source, or is nil to keep diagrams as text.
	Mermaid func(src string, dark bool) (image.Image, error)
}

// A Doc is markdown split where a picture stands on a line of its own: text
// for glamour, and pictures and diagrams for the terminal to draw.
type Doc []part

type part struct {
	text string // markdown, in a part with no picture
	alt  string // what the picture shows, drawn where images can't be
	png  []byte // the picture, encoded once as it loads
	size image.Point
	id   kitty.ID
}

var (
	imageLine   = regexp.MustCompile(`^\s*!\[([^\]]*)\]\((\S+?)(?:\s+"[^"]*")?\)\s*$`)
	imgTag      = regexp.MustCompile(`^\s*<img\b[^>]*\bsrc="([^"]+)"[^>]*>\s*$`)
	imgAlt      = regexp.MustCompile(`\balt="([^"]*)"`)
	htmlComment = regexp.MustCompile(`(?s)<!--.*?-->`)
	dim         = lipgloss.NewStyle().Foreground(lipgloss.Color("8"))
)

// A line of markdown is in prose, in a code fence, or in a mermaid fence,
// whose lines become a picture.
type block int

const (
	prose block = iota
	code
	mermaid
)

// step is what a line does in the block it's read in.
type step int

const (
	text        step = iota // goes into the text
	openDiagram             // starts a diagram, and isn't text
	diagram                 // is part of a diagram
	endDiagram              // ends the diagram
)

func (b block) next(line string) (block, step) {
	fence := strings.TrimSpace(line)
	switch {
	case b == mermaid && strings.HasPrefix(fence, "```"):
		return prose, endDiagram
	case b == mermaid:
		return mermaid, diagram
	case b == prose && fence == "```mermaid":
		return mermaid, openDiagram
	case b == prose && strings.HasPrefix(fence, "```"):
		return code, text
	case b == code && fence == "```": // a closing fence names no language
		return prose, text
	}
	return b, text
}

type docBuilder struct {
	doc          Doc
	lines        []string
	diagramLines []string
	o            Options
}

func (db *docBuilder) flush() {
	if len(db.lines) > 0 {
		db.doc = append(db.doc, part{text: joinSoftBreaks(strings.Join(db.lines, "\n"))})
		db.lines = nil
	}
}

func (db *docBuilder) picture(alt, src string, load func() (image.Image, error)) {
	db.flush()
	p := part{alt: alt}
	if img, err := load(); err == nil {
		var data bytes.Buffer
		if png.Encode(&data, img) == nil {
			p.png, p.size = data.Bytes(), img.Bounds().Size()
		}
	}
	h := fnv.New32a()
	_, _ = h.Write([]byte(src))
	p.id = kitty.ID(h.Sum32()&0xffffff | 0x010000) // a 24-bit color, never black
	db.doc = append(db.doc, p)
}

func (db *docBuilder) endDiagram(line string) {
	if db.o.Mermaid == nil {
		db.lines = append(append(append(db.lines, "```mermaid"), db.diagramLines...), line)
	} else {
		src := strings.Join(db.diagramLines, "\n")
		db.picture("mermaid diagram", src, func() (image.Image, error) { return db.o.Mermaid(src, db.o.Dark) })
	}
	db.diagramLines = nil
}

func (db *docBuilder) addImageLine(line string) bool {
	if m := imageLine.FindStringSubmatch(line); m != nil {
		db.picture(m[1], m[2], func() (image.Image, error) { return db.o.Fetch(m[2]) })
		return true
	}
	if m := imgTag.FindStringSubmatch(line); m != nil {
		alt := ""
		if a := imgAlt.FindStringSubmatch(line); a != nil {
			alt = a[1]
		}
		db.picture(alt, m[1], func() (image.Image, error) { return db.o.Fetch(m[1]) })
		return true
	}
	return false
}

// Load splits md and loads its pictures. It belongs off the UI, because
// pictures come over the network and a diagram can take seconds the first
// time. A picture that fails to load keeps only its description.
func Load(md string, o Options) Doc {
	db := docBuilder{o: o}
	// glamour keeps tabs, and the pane widens them to four spaces after the
	// layout, so code lines would run past the edge.
	md = strings.NewReplacer("\r", "", "\t", "    ").Replace(htmlComment.ReplaceAllString(md, ""))
	b := prose
	for line := range strings.SplitSeq(strings.TrimSpace(md), "\n") {
		var s step
		was := b
		b, s = b.next(line)
		switch s {
		case openDiagram:
		case diagram:
			db.diagramLines = append(db.diagramLines, line)
		case endDiagram:
			db.endDiagram(line)
		default:
			if was != prose || b != prose || !db.addImageLine(line) {
				db.lines = append(db.lines, line)
			}
		}
	}
	db.flush()
	return db.doc
}

// glamour joins the lines of a paragraph but keeps each line of a list item
// apart, so a wrapped item reads ragged. joinSoftBreaks puts a space in place
// of each soft line break, as Markdown renders one, and of the next line's
// indent and quote marks. It parses md as glamour does, so it leaves hard
// breaks and code as they are.
func joinSoftBreaks(md string) string {
	src := []byte(md)
	doc := goldmark.New(goldmark.WithExtensions(extension.GFM, extension.DefinitionList)).Parser().Parse(gmtext.NewReader(src))
	var out []byte
	kept := 0
	_ = ast.Walk(doc, func(n ast.Node, entering bool) (ast.WalkStatus, error) {
		t, ok := n.(*ast.Text)
		if !ok || !entering || !t.SoftLineBreak() {
			return ast.WalkContinue, nil
		}
		end, ok := softBreakEnd(src, t.Segment.Stop)
		if !ok {
			return ast.WalkContinue, nil
		}
		out = append(append(out, src[kept:t.Segment.Stop]...), ' ')
		kept = end
		return ast.WalkContinue, nil
	})
	return string(append(out, src[kept:]...))
}

func softBreakEnd(src []byte, stop int) (int, bool) {
	end := stop
	for end < len(src) && (src[end] == ' ' || src[end] == '\t') {
		end++
	}
	if end == len(src) || src[end] != '\n' {
		return 0, false
	}
	end++
	for end < len(src) && strings.IndexByte(" \t>", src[end]) >= 0 {
		end++
	}
	return end, true
}

func resolveStyle(o Options) ansi.StyleConfig {
	var style ansi.StyleConfig
	if o.Style == nil || json.Unmarshal(o.Style, &style) != nil {
		theme := "catppuccin-mocha"
		style = styles.DarkStyleConfig
		if !o.Dark {
			style, theme = styles.LightStyleConfig, "catppuccin-latte"
		}
		// glamour uses a style's own Chroma colors over the theme whenever
		// it has them, and both built-in styles do.
		style.CodeBlock.Theme, style.CodeBlock.Chroma = theme, nil
	}
	zero := uint(0)
	style.Document.Margin, style.CodeBlock.Margin = &zero, &zero
	return style
}

func renderPart(r *glamour.TermRenderer, p part, w int, o Options) []string {
	switch {
	case p.text != "":
		s, err := r.Render(p.text)
		if err != nil {
			s = p.text
		}
		return []string{strings.Trim(s, "\n")}
	case p.png == nil || !o.Terminal.Draws:
		return []string{"", dim.Render("▣ " + cmp.Or(p.alt, "picture")), ""}
	default:
		// A cell is about twice as tall as it is wide, and a picture is
		// never drawn wider than its pixels at 8 a column.
		cols := min(w, max(1, p.size.X/8))
		rows := max(1, min(40, (cols*p.size.Y+p.size.X)/(2*p.size.X)))
		return []string{"", o.Terminal.Image(p.png, p.id, cols, rows) + kitty.Placeholders(p.id, cols, rows), ""}
	}
}

// Render lays the doc out w columns wide. A picture becomes Kitty
// placeholders, with the image sent on its first row, or one line of its
// description where the terminal can't draw images.
func (d Doc) Render(w int, o Options) string {
	style := resolveStyle(o)
	// glamour's code formatter defaults to 256 colors, which shifts the
	// style's.
	r, err := glamour.NewTermRenderer(glamour.WithStyles(style), glamour.WithWordWrap(w), glamour.WithColorProfile(termenv.TrueColor), glamour.WithChromaFormatter("terminal16m"))
	if err != nil {
		return err.Error()
	}
	var out []string
	for _, p := range d {
		out = append(out, renderPart(r, p, w, o)...)
	}
	return strings.Join(out, "\n")
}
