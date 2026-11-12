// Package markdown renders markdown for a terminal pane: glamour for text
// and code, and pictures and mermaid diagrams as Kitty images.
package markdown

import (
	"bytes"
	"cmp"
	"hash/fnv"
	"image"
	"image/png"
	"regexp"
	"strings"

	"github.com/charmbracelet/glamour"
	"github.com/charmbracelet/glamour/styles"
	"github.com/charmbracelet/lipgloss"
	"github.com/muesli/termenv"

	"workspace/kitty"
)

// Options are what rendering needs from the program around it.
type Options struct {
	Dark     bool           // Catppuccin Mocha, or Latte
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

// Load splits md and loads its pictures. It belongs off the UI, because
// pictures come over the network and a diagram can take seconds the first
// time. A picture that fails to load keeps only its description.
func Load(md string, o Options) Doc {
	var d Doc
	var lines, diagramLines []string
	flush := func() {
		if len(lines) > 0 {
			d = append(d, part{text: strings.Join(lines, "\n")})
			lines = nil
		}
	}
	picture := func(alt, src string, load func() (image.Image, error)) {
		flush()
		p := part{alt: alt}
		if img, err := load(); err == nil {
			var data bytes.Buffer
			if png.Encode(&data, img) == nil {
				p.png, p.size = data.Bytes(), img.Bounds().Size()
			}
		}
		h := fnv.New32a()
		h.Write([]byte(src))
		p.id = kitty.ID(h.Sum32()&0xffffff | 0x010000) // a 24-bit color, never black
		d = append(d, p)
	}
	fetch := func(src string) func() (image.Image, error) {
		return func() (image.Image, error) { return o.Fetch(src) }
	}
	// glamour keeps tabs, and the pane widens them to four spaces after the
	// layout, so code lines would run past the edge.
	md = strings.NewReplacer("\r", "", "\t", "    ").Replace(htmlComment.ReplaceAllString(md, ""))
	b := prose
	for line := range strings.SplitSeq(strings.TrimSpace(md), "\n") {
		var s step
		was := b
		b, s = b.next(line)
		switch {
		case s == openDiagram:
		case s == diagram:
			diagramLines = append(diagramLines, line)
		case s == endDiagram && o.Mermaid == nil:
			lines = append(append(append(lines, "```mermaid"), diagramLines...), line)
			diagramLines = nil
		case s == endDiagram:
			src := strings.Join(diagramLines, "\n")
			picture("mermaid diagram", src, func() (image.Image, error) { return o.Mermaid(src, o.Dark) })
			diagramLines = nil
		case was == prose && b == prose && imageLine.MatchString(line):
			m := imageLine.FindStringSubmatch(line)
			picture(m[1], m[2], fetch(m[2]))
		case was == prose && b == prose && imgTag.MatchString(line):
			src, alt := imgTag.FindStringSubmatch(line)[1], ""
			if a := imgAlt.FindStringSubmatch(line); a != nil {
				alt = a[1]
			}
			picture(alt, src, fetch(src))
		default:
			lines = append(lines, line)
		}
	}
	flush()
	return d
}

// Render lays the doc out w columns wide. A picture becomes Kitty
// placeholders, with the image sent on its first row, or one line of its
// description where the terminal can't draw images.
func (d Doc) Render(w int, o Options) string {
	style, theme := styles.DarkStyleConfig, "catppuccin-mocha"
	if !o.Dark {
		style, theme = styles.LightStyleConfig, "catppuccin-latte"
	}
	zero := uint(0)
	style.Document.Margin, style.CodeBlock.Margin, style.CodeBlock.Theme = &zero, &zero, theme
	r, err := glamour.NewTermRenderer(glamour.WithStyles(style), glamour.WithWordWrap(w), glamour.WithColorProfile(termenv.TrueColor))
	if err != nil {
		return err.Error()
	}
	var out []string
	for _, p := range d {
		switch {
		case p.text != "":
			s, err := r.Render(p.text)
			if err != nil {
				s = p.text
			}
			out = append(out, strings.Trim(s, "\n"))
		case p.png == nil || !o.Terminal.Draws:
			out = append(out, "", dim.Render("▣ "+cmp.Or(p.alt, "picture")), "")
		default:
			// A cell is about twice as tall as it is wide, and a picture is
			// never drawn wider than its pixels at 8 a column.
			cols := min(w, max(1, p.size.X/8))
			rows := max(1, min(40, (cols*p.size.Y+p.size.X)/(2*p.size.X)))
			out = append(out, "", o.Terminal.Image(p.png, p.id, cols, rows)+kitty.Placeholders(p.id, cols, rows), "")
		}
	}
	return strings.Join(out, "\n")
}
